// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./../interface/IParticipation.sol";
import "./../interface/IStaking.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import "../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";

contract GovernorOperations is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    ///*** ERRORS ***///
    error AlreadyActiveProposal();
    error ContractTerminated(uint256 blockNumber);
    error EmptyOptions();
    error IncorrectCoinValue();
    error IncorrectBlockNumber();
    error IncorrectPaymentOption();
    error IncorrectCurrency();
    error IncorrectPhase(ProposalStatus);
    error IncorrectSnapshotIndex();
    error InsufficientBalance(uint256 balance, uint256 requiredBalance);
    error InsufficientVotingRights(uint256 currentRights, uint256 votesGiven);
    error InvalidInputForExecutable();
    error InvalidInputForNonExecutable();
    error InvalidInfo();
    error TokensStillLocked(uint256 voteLockStamp, uint256 currentStamp);
    error ProposalIsNotExecutable();
    error ProposalLifeTimePassed();
    error ProposalOngoing(uint256 currentBlock, uint256 endBlock);
    error ProposalInexistent();
    error QuorumNotReached();
    error Unauthorized(address user);
    error VoteLock();
    error WrongToken();
    error WrongInput();

    ///*** STRUCTS ***///
    struct Proposal {
        uint256 startBlockNum;
        uint256 endTimeStamp;
        ProposalStatus status;
        ProjectInfo details;
        uint256 votesFor;
        uint256 votesAgainst;
        uint256 totalVotes;
    }

    struct ProjectInfo {
        string info; //IPFS link
        address receivingWallet; //wallet address to send funds to
        Payment payment;
        uint256 amount; //amount of usdc or coin
        uint256 amountSci; //amount of sci token
        bool executable;
    }

    ///*** TOKEN ***///
    IParticipation private _po;

    ///*** GOVERNANCE PARAMETERS ***///
    uint256 public proposalLifeTime;
    uint256 public quorum;
    uint256 public voteLockTime;

    ///*** KEY ADDRESSES ***///
    address public stakingAddress;
    address public treasuryWallet;
    address public donationWallet;
    address public usdc;
    address public sci;

    ///*** STORAGE & MAPPINGS ***///
    uint8 public poLive;
    uint256 public opThreshold;
    uint256 private _operationsProposalIndex;
    bytes32 public constant OPERATIONS_ROLE = keccak256("OPERATIONS_ROLE");
    bool public terminated = false;
    mapping(uint256 => Proposal) private operationsProposals;
    mapping(uint256 => mapping(address => uint8)) private votedOperations;

    ///*** ENUMERATORS ***///
    enum ProposalStatus {
        Active,
        Scheduled,
        Executed,
        Completed, //Completed status only for proposals that cannot be executed
        Cancelled
    }

    enum Payment {
        Usdc,
        Sci,
        Coin,
        SciUsdc
    }

    ///*** MODIFIER ***///
    modifier notTerminated() {
        if (terminated) revert ContractTerminated(block.number);
        _;
    }

    /*** EVENTS ***/
    event Proposed(uint256 indexed id, ProjectInfo details);
    event Voted(uint256 indexed id, bool indexed support, uint256 amount);
    event Scheduled(uint256 indexed id, bool indexed research);
    event Executed(uint256 indexed id, bool indexed donated, uint256 amount);
    event Completed(uint256 indexed id);
    event Cancelled(uint256 indexed id);
    event Terminated(address admin, uint256 blockNumber);

    constructor(
        address stakingAddress_,
        address treasuryWallet_,
        address donationWallet_,
        address usdc_,
        address sci_
    ) {
        stakingAddress = stakingAddress_;
        treasuryWallet = treasuryWallet_;
        donationWallet = donationWallet_;
        usdc = usdc_;
        sci = sci_;

        opThreshold = 100e18;

        proposalLifeTime = 2 weeks;
        quorum = (IERC20(sci).totalSupply() / 100) * 3; //3% of circulating supply
        voteLockTime = 2 weeks;

        _grantRole(DEFAULT_ADMIN_ROLE, treasuryWallet_);
        _grantRole(DEFAULT_ADMIN_ROLE, donationWallet_);

        _grantRole(OPERATIONS_ROLE, treasuryWallet_);
        _setRoleAdmin(OPERATIONS_ROLE, DEFAULT_ADMIN_ROLE);
    }

    ///*** EXTERNAL FUNCTIONS ***///

    /**
     * @dev sets the threshold for DD and non-DD members to propose
     */
    function setStakedSciThreshold(
        uint256 thresholdOpMember
    ) external notTerminated onlyRole(DEFAULT_ADMIN_ROLE) {
        opThreshold = thresholdOpMember;
    }

    /**
     * @dev allows the DAO to add a member to the Due Diligence Crew
     * @param member the address of the member that will be added to the DD crew
     */
    function addOperationsMember(
        address member
    ) external notTerminated onlyRole(DEFAULT_ADMIN_ROLE) {
        IStaking staking = IStaking(stakingAddress);
        if (staking.getStakedSci(member) > opThreshold) {
            grantRole(OPERATIONS_ROLE, member);
        } else {
            revert InsufficientBalance(
                staking.getStakedSci(member),
                opThreshold
            );
        }
    }

    /**
     * @dev allows the DAO to add a member to the Due Diligence Crew
     * @param member the address of the member that will be added to the DD crew
     */
    function removeOperationsMember(
        address member
    ) external notTerminated onlyRole(DEFAULT_ADMIN_ROLE) {
        revokeRole(OPERATIONS_ROLE, member);
    }

    /**
     * @dev sets the treasury wallet address
     */
    function setTreasuryWallet(
        address newTreasuryWallet
    ) external notTerminated onlyRole(DEFAULT_ADMIN_ROLE) {
        treasuryWallet = newTreasuryWallet;
    }

    /**
     * @dev sets the donation wallet address
     */
    function setDonationWallet(
        address newDonationWallet
    ) external notTerminated onlyRole(DEFAULT_ADMIN_ROLE) {
        donationWallet = newDonationWallet;
    }

    /**
     * @dev sets the staking address
     */
    function setStakingAddress(
        address _newStakingAddress
    ) external notTerminated onlyRole(DEFAULT_ADMIN_ROLE) {
        stakingAddress = _newStakingAddress;
    }

    /**
     * @dev sets the participation phase to live
     * @param _status the status of the participation phase, must be 1 to activate
     */
    function setPoPhase(
        uint8 _status
    ) external notTerminated onlyRole(DEFAULT_ADMIN_ROLE) {
        poLive = _status;
    }

    /**
     * @dev sets the PO token address and interface
     */
    function setPoToken(
        address po_
    ) external notTerminated onlyRole(DEFAULT_ADMIN_ROLE) {
        _po = IParticipation(po_);
    }

    /**
     * @dev sets the governance parameters given data
     * @param _param the parameter of interest
     * @param _data the data assigned to the parameter
     */
    function govParams(
        bytes32 _param,
        uint256 _data
    ) external notTerminated onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_param == "proposalLifeTime") proposalLifeTime = _data;
        if (_param == "quorum") quorum = _data;
        if (_param == "voteLockTime") voteLockTime = _data;
    }

    /**
     * @dev proposes a change in DAO operations
     *      at least one option needs to be proposed
     * @param info ipfs hash of project proposal
     * @param receivingWallet the address of the party receiving funds if proposal passed
     * @param amountUsdc the amount of USDC
     * @param amountCoin the amount of Coin
     * @param amountSci the amount of SCI tokens
     */
    function proposeOperation(
        string memory info,
        address receivingWallet,
        uint256 amountUsdc, //6 decimals
        uint256 amountCoin, //18 decimals
        uint256 amountSci, //18 decimals
        bool executable
    ) external notTerminated nonReentrant returns (uint256) {
        if (bytes(info).length == 0) {
            revert InvalidInfo();
        }

        if (executable) {
            if (
                receivingWallet == address(0) ||
                !((amountUsdc > 0 && amountCoin == 0 && (amountSci >= 0)) ||
                    (amountCoin > 0 && amountUsdc == 0 && amountSci == 0) ||
                    (amountSci > 0 && amountCoin == 0 && (amountUsdc >= 0)))
            ) {
                revert InvalidInputForExecutable();
            }
        } else {
            if (
                receivingWallet != address(0) ||
                amountUsdc != 0 ||
                amountCoin != 0 ||
                amountSci != 0
            ) {
                revert InvalidInputForNonExecutable();
            }
        }

        IStaking staking = IStaking(stakingAddress);

        if (staking.getStakedSci(_msgSender()) < opThreshold)
            revert InsufficientBalance(
                staking.getStakedSci(_msgSender()),
                opThreshold
            );

        // if (staking.pr)

        Payment payment;
        uint256 amount;
        uint256 sciAmount;
        if (executable) {
            uint8 paymentOptions = (amountUsdc > 0 ? 1 : 0) +
                (amountCoin > 0 ? 1 : 0) +
                (amountSci > 0 ? 1 : 0);

            if (paymentOptions == 1) {
                if (amountUsdc > 0) {
                    amount = amountUsdc;
                    payment = Payment.Usdc;
                } else if (amountCoin > 0) {
                    amount = amountCoin;
                    payment = Payment.Coin;
                } else if (amountSci > 0) {
                    sciAmount = amountSci;
                    payment = Payment.Sci;
                }
            } else if (paymentOptions == 2 && amountUsdc > 0 && amountSci > 0) {
                amount = amountUsdc;
                sciAmount = amountSci;
                payment = Payment.SciUsdc;
            } else {
                revert IncorrectPaymentOption();
            }
        }

        ProjectInfo memory projectInfo = ProjectInfo(
            info,
            receivingWallet,
            payment,
            amount,
            sciAmount,
            executable
        );

        //Initiate and specify each parameter of the proposal
        Proposal memory proposal = Proposal(
            block.number,
            block.timestamp + proposalLifeTime,
            ProposalStatus.Active,
            projectInfo,
            0,
            0,
            0
        );

        //increment proposal index
        _operationsProposalIndex += 1;

        //store proposal at the given index
        operationsProposals[_operationsProposalIndex] = proposal;

        //emit Proposed event
        emit Proposed(_operationsProposalIndex, projectInfo);

        return _operationsProposalIndex;
    }

    /**
     * @dev vote for an of option of a given proposal
     *      using the rights from the most recent snapshot
     * @param id the index of the proposal
     * @param user the address of the voting users
     * @param votes the amount of votes given to the chosen research project
     */
    function voteOnOperations(
        uint256 id,
        address user,
        bool support,
        uint256 votes
    ) external notTerminated nonReentrant {
        if (_msgSender() != user) revert Unauthorized(_msgSender());

        IStaking staking = IStaking(stakingAddress);

        //check if proposal exists
        if (id > _operationsProposalIndex || id < 1)
            revert ProposalInexistent();

        //check if proposal is still active
        if (operationsProposals[id].status != ProposalStatus.Active)
            revert IncorrectPhase(operationsProposals[id].status);

        //check if proposal life time has not passed
        if (block.timestamp > operationsProposals[id].endTimeStamp)
            revert ProposalLifeTimePassed();

        //get latest voting rights
        uint256 _votingRights = staking.getLatestUserRights(user);

        //check if user has enough voting rights
        if (votes > _votingRights)
            revert InsufficientVotingRights(_votingRights, votes);

        //check if user already voted for this proposal
        if (votedOperations[id][user] == 1) revert VoteLock();

        //vote for or against
        if (support) {
            operationsProposals[id].votesFor += votes;
        } else {
            operationsProposals[id].votesAgainst += votes;
        }

        //add to the total votes
        operationsProposals[id].totalVotes += votes;

        //set user as voted for proposal
        votedOperations[id][user] = 1;

        //set the lock time in the staking contract
        staking.votedOperations(user, block.timestamp + voteLockTime);

        //mint a participation token if live
        if (poLive == 1) {
            _po.mint(user);
        }

        //emit Voted events
        emit Voted(id, support, votes);
    }

    /**
     * @dev finalizes the voting phase for a research proposal
     * @param id the index of the proposal of interest
     */
    function finalizeVotingOperationsProposal(
        uint256 id
    ) external notTerminated {
        if (id > _operationsProposalIndex || id < 1)
            revert ProposalInexistent();

        if (block.timestamp < operationsProposals[id].endTimeStamp)
            revert ProposalOngoing(
                block.timestamp,
                operationsProposals[id].endTimeStamp
            );

        if (operationsProposals[id].status != ProposalStatus.Active)
            revert IncorrectPhase(operationsProposals[id].status);

        if (operationsProposals[id].totalVotes < quorum)
            revert QuorumNotReached();

        operationsProposals[id].status = ProposalStatus.Scheduled;

        emit Scheduled(id, false);
    }

    /**
     * @dev executes the proposal using a token or coin - Operation's crew's choice
     * @param id the index of the proposal of interest
     */
    function executeOperationsProposal(
        uint256 id
    ) external payable notTerminated nonReentrant {
        //check if proposal exists
        if (id > _operationsProposalIndex || id < 1)
            revert ProposalInexistent();

        if (operationsProposals[id].details.executable) {
            //check if proposal has finalized voting
            if (operationsProposals[id].status != ProposalStatus.Scheduled)
                revert IncorrectPhase(operationsProposals[id].status);

            address receivingWallet = operationsProposals[id]
                .details
                .receivingWallet;

            uint256 amount = operationsProposals[id].details.amount;
            uint256 amountSci = operationsProposals[id].details.amountSci;

            Payment payment = operationsProposals[id].details.payment;
            if (payment == Payment.Usdc || payment == Payment.SciUsdc) {
                transferToken(
                    IERC20(usdc),
                    treasuryWallet,
                    receivingWallet,
                    amount
                );
            }
            if (payment == Payment.Sci || payment == Payment.SciUsdc) {
                transferToken(
                    IERC20(sci),
                    treasuryWallet,
                    receivingWallet,
                    amountSci
                );
            }
            if (payment == Payment.Coin) {
                transferCoin(treasuryWallet, receivingWallet, amount);
            }

            operationsProposals[id].status = ProposalStatus.Executed;

            emit Executed(id, false, amount);
        } else {
            revert ProposalIsNotExecutable();
        }
    }

    function completeOperationsProposal(
        uint256 id
    ) external notTerminated onlyRole(OPERATIONS_ROLE) {
        if (id > _operationsProposalIndex || id < 1)
            revert ProposalInexistent();

        if (operationsProposals[id].status != ProposalStatus.Scheduled)
            revert IncorrectPhase(operationsProposals[id].status);

        operationsProposals[id].status = ProposalStatus.Completed;

        emit Completed(id);
    }

    /**
     * @dev cancels the proposal
     * @param id the index of the proposal of interest
     */
    function cancelOperationsProposal(
        uint256 id
    ) external notTerminated onlyRole(OPERATIONS_ROLE) {
        if (id > _operationsProposalIndex || id < 1)
            revert ProposalInexistent();

        if (operationsProposals[id].status != ProposalStatus.Active)
            revert IncorrectPhase(operationsProposals[id].status);

        operationsProposals[id].status = ProposalStatus.Cancelled;

        emit Cancelled(id);
    }

    function getPoToken() external view returns (address) {
        return address(_po);
    }

    /**
     * @dev returns if user has voted for a given proposal
     * @param id the proposal id
     */
    function getVotedOperations(uint256 id) external view returns (uint8) {
        return votedOperations[id][_msgSender()];
    }

    /**
     * @dev returns the operations proposal index
     */
    function getOperationsProposalIndex() external view returns (uint256) {
        return _operationsProposalIndex;
    }

    /**
     * @dev returns proposal information
     * @param id the index of the proposal of interest
     */
    function getOperationsProposalInfo(
        uint256 id
    )
        external
        view
        returns (uint256, uint256, ProposalStatus, uint256, uint256, uint256)
    {
        if (id > _operationsProposalIndex || id < 1)
            revert ProposalInexistent();
        return (
            operationsProposals[id].startBlockNum,
            operationsProposals[id].endTimeStamp,
            operationsProposals[id].status,
            operationsProposals[id].votesFor,
            operationsProposals[id].votesAgainst,
            operationsProposals[id].totalVotes
        );
    }

    /**
     * @dev returns operations project info information
     * @param id the index of the proposal of interest
     */
    function getOperationsProposalProjectInfo(
        uint256 id
    ) external view returns (string memory, address, Payment, uint256) {
        if (id > _operationsProposalIndex || id < 1)
            revert ProposalInexistent();
        return (
            operationsProposals[id].details.info,
            operationsProposals[id].details.receivingWallet,
            operationsProposals[id].details.payment,
            operationsProposals[id].details.amount
        );
    }

    /**
     * @dev terminates the governance and staking smart contracts
     */
    function terminateOperations()
        external
        notTerminated
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        IStaking staking = IStaking(stakingAddress);
        staking.terminateOperations(_msgSender());
        terminated = true;
        emit Terminated(_msgSender(), block.number);
    }

    /**
     * @dev Transfers ERC20 tokens from one address to another.
     *      Uses the safeTransferFrom function from the SafeERC20 library
     *      to securely transfer tokens.
     * @param token The ERC20 token to be transferred.
     * @param from The address from which the tokens will be transferred.
     * @param to The address to which the tokens will be transferred.
     * @param amount The amount of tokens to transfer.
     */
    function transferToken(
        IERC20 token,
        address from,
        address to,
        uint256 amount
    ) internal {
        if (amount > 0) {
            token.safeTransferFrom(from, to, amount);
        }
    }

    /**
     * @dev Transfers ETH coin from one address to another.
     *      Requires that the function caller is the same as the 'from' address.
     *      Reverts if the transferred amount does not match the provided value
     *      or if the sender is unauthorized.
     * @param from The address from which the coins will be transferred. Must match the message sender.
     * @param to The address to which the coins will be transferred.
     * @param amount The amount of coins to transfer.
     */
    function transferCoin(address from, address to, uint256 amount) internal {
        if (_msgSender() != from) revert Unauthorized(_msgSender());
        if (msg.value == 0 || msg.value != amount) revert IncorrectCoinValue();
        (bool sent, ) = to.call{value: msg.value}("");
        require(sent, "Failed to transfer");
    }
}
