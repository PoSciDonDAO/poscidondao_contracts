// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./../interface/IStaking.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import "../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";

contract GovernorResearch is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    ///*** ERRORS ***///
    error AlreadyActiveProposal();
    error ContractTerminated(uint256 blockNumber);
    error EmptyOptions();
    error IncorrectCoinValue();
    error IncorrectBlockNumber();
    error IncorrectPaymentOption();
    error IncorrectPhase(ProposalStatus);
    error IncorrectSnapshotIndex();
    error InsufficientBalance(uint256 balance, uint256 requiredBalance);
    error InvalidInput();
    error TokensStillLocked(uint256 voteLockStamp, uint256 currentStamp);
    error ProposalLifeTimePassed();
    error ProposalOngoing(uint256 currentBlock, uint256 endBlock);
    error ProposalInexistent();
    error QuorumNotReached();
    error Unauthorized(address user);
    error VoteLock();
    error WrongToken();

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
    uint256 public ddThreshold;
    uint256 private _researchProposalIndex;
    bytes32 public constant DUE_DILIGENCE_ROLE =
        keccak256("DUE_DILIGENCE_ROLE");
    bool public terminated = false;
    mapping(uint256 => Proposal) private researchProposals;
    mapping(uint256 => mapping(address => uint8)) private votedResearch;

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

        ddThreshold = 1000e18;

        proposalLifeTime = 4 weeks;
        quorum = 1;
        voteLockTime = 2 weeks;

        _grantRole(DEFAULT_ADMIN_ROLE, treasuryWallet_);
        _grantRole(DEFAULT_ADMIN_ROLE, donationWallet_);

        _grantRole(DUE_DILIGENCE_ROLE, treasuryWallet_);
        _setRoleAdmin(DUE_DILIGENCE_ROLE, DEFAULT_ADMIN_ROLE);
    }

    ///*** EXTERNAL FUNCTIONS ***///

    /**
     * @dev sets the threshold for DD and non-DD members to propose
     */
    function setStakedSciThreshold(
        uint256 thresholdDDMember
    ) external notTerminated onlyRole(DEFAULT_ADMIN_ROLE) {
        ddThreshold = thresholdDDMember;
    }

    /**
     * @dev allows the DAO to add a member to the Due Diligence Crew
     * @param member the address of the member that will be added to the DD crew
     */
    function addDueDiligenceMember(
        address member
    ) external notTerminated onlyRole(DEFAULT_ADMIN_ROLE) {
        IStaking staking = IStaking(stakingAddress);
        if (staking.getStakedSci(member) > ddThreshold) {
            grantRole(DUE_DILIGENCE_ROLE, member);
        } else {
            revert InsufficientBalance(staking.getStakedSci(member), 1000e18);
        }
    }

    /**
     * @dev allows the DAO to add a member to the Due Diligence Crew
     * @param member the address of the member that will be added to the DD crew
     */
    function removeDueDiligenceMember(
        address member
    ) external notTerminated onlyRole(DEFAULT_ADMIN_ROLE) {
        revokeRole(DUE_DILIGENCE_ROLE, member);
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
     * @dev proposes a research project in need of funding
     *      at least one option needs to be proposed
     * @param info ipfs hash of project proposal
     * @param receivingWallet the address of the research group receiving funds if proposal passed
     * @param amountUsdc the amount of USDC
     * @param amountCoin the amount of Coin
     * @param amountSci the amount of SCI tokens
     */
    function proposeResearch(
        string memory info,
        address receivingWallet,
        uint256 amountUsdc, //6 decimals
        uint256 amountCoin, //18 decimals
        uint256 amountSci //18 decimals
    )
        external
        nonReentrant
        notTerminated
        onlyRole(DUE_DILIGENCE_ROLE)
        returns (uint256)
    {
        if (
            bytes(info).length == 0 ||
            receivingWallet == address(0) ||
            (amountUsdc > 0 ? 1 : 0) +
                (amountCoin > 0 ? 1 : 0) +
                (amountSci > 0 ? 1 : 0) !=
            1
        ) {
            revert InvalidInput();
        }

        IStaking staking = IStaking(stakingAddress);

        if (staking.getStakedSci(_msgSender()) < ddThreshold)
            revert InsufficientBalance(
                staking.getStakedSci(_msgSender()),
                ddThreshold
            );

        Payment payment;
        uint256 amount;
        uint256 sciAmount;

        if (amountUsdc > 0) {
            amount = amountUsdc;
            payment = Payment.Usdc;
        } else if (amountCoin > 0) {
            amount = amountCoin;
            payment = Payment.Coin;
        } else if (amountUsdc > 0 && amountSci > 0) {
            amount = amountUsdc;
            sciAmount = amountSci;
            payment = Payment.SciUsdc;
        } else {
            revert IncorrectPaymentOption();
        }

        ProjectInfo memory projectInfo = ProjectInfo(
            info,
            receivingWallet,
            payment,
            amount,
            amountSci,
            true
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
        _researchProposalIndex += 1;

        //store proposal at the given index
        researchProposals[_researchProposalIndex] = proposal;

        //emit Proposed event
        emit Proposed(_researchProposalIndex, projectInfo);

        return _researchProposalIndex;
    }

    /**
     * @dev vote for an of option of a given proposal
     *      using the rights from the most recent snapshot
     * @param id the index of the proposal
     * @param user the address of the voting users
     */
    function voteOnResearch(
        uint256 id,
        address user,
        bool support
    ) external notTerminated nonReentrant onlyRole(DUE_DILIGENCE_ROLE) {
        if (_msgSender() != user) revert Unauthorized(_msgSender());

        IStaking staking = IStaking(stakingAddress);

        if (staking.getStakedSci(user) < ddThreshold)
            revert InsufficientBalance(staking.getStakedSci(user), ddThreshold);

        //check if proposal exists
        if (id > _researchProposalIndex || id < 1) revert ProposalInexistent();

        //check if proposal is still active
        if (researchProposals[id].status != ProposalStatus.Active)
            revert IncorrectPhase(researchProposals[id].status);

        //check if proposal life time has not passed
        if (block.timestamp > researchProposals[id].endTimeStamp)
            revert ProposalLifeTimePassed();

        //check if user already voted for this proposal
        if (votedResearch[id][user] == 1) revert VoteLock();

        //vote for, against or abstain
        if (support) {
            researchProposals[id].votesFor += 1;
        } else {
            researchProposals[id].votesAgainst += 1;
        }

        //add to the total votes
        researchProposals[id].totalVotes += 1;

        //set user as voted for proposal
        votedResearch[id][user] = 1;

        //set the lock time in the staking contract
        staking.votedResearch(user, block.timestamp + voteLockTime);

        //emit Voted events
        emit Voted(id, support, 1);
    }

    /**
     * @dev finalizes the voting phase for a research proposal
     * @param id the index of the proposal of interest
     */
    function finalizeVotingResearchProposal(
        uint256 id
    ) external notTerminated onlyRole(DUE_DILIGENCE_ROLE) {
        if (id > _researchProposalIndex || id < 1) revert ProposalInexistent();

        if (researchProposals[id].status != ProposalStatus.Active)
            revert IncorrectPhase(researchProposals[id].status);

        if (block.timestamp < researchProposals[id].endTimeStamp)
            revert ProposalOngoing(
                block.timestamp,
                researchProposals[id].endTimeStamp
            );

        researchProposals[id].status = ProposalStatus.Scheduled;

        emit Scheduled(id, true);
    }

    /**
     * @dev executes the proposal using USDC
     * @param id the index of the proposal of interest
     * @param donated set to true if funds are derived from the donation wallet
     */
    function executeResearchProposal(
        uint256 id,
        bool donated
    ) external payable notTerminated nonReentrant onlyRole(DUE_DILIGENCE_ROLE) {
        // Check if proposal exists and has finalized voting
        if (id > _researchProposalIndex || id < 1) revert ProposalInexistent();
        if (researchProposals[id].status != ProposalStatus.Scheduled)
            revert IncorrectPhase(researchProposals[id].status);

        // Extract proposal details
        address receivingWallet = researchProposals[id].details.receivingWallet;
        uint256 amount = researchProposals[id].details.amount;
        uint256 amountSci = researchProposals[id].details.amountSci;
        Payment payment = researchProposals[id].details.payment;

        // Determine the source wallet based on the 'donated' flag
        address sourceWallet = donated ? donationWallet : treasuryWallet;

        // Transfer funds based on payment type
        if (payment == Payment.Usdc || payment == Payment.SciUsdc) {
            transferToken(IERC20(usdc), sourceWallet, receivingWallet, amount);
        }
        if (payment == Payment.Sci || payment == Payment.SciUsdc) {
            transferToken(
                IERC20(sci),
                sourceWallet,
                receivingWallet,
                amountSci
            );
        }
        if (payment == Payment.Coin) {
            transferCoin(sourceWallet, receivingWallet, amount);
        }

        researchProposals[id].status = ProposalStatus.Executed;
        emit Executed(id, donated, amount);
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

    /**
     * @dev cancels the proposal
     * @param id the index of the proposal of interest
     */
    function cancelResearchProposal(
        uint256 id
    ) external notTerminated onlyRole(DUE_DILIGENCE_ROLE) {
        if (id > _researchProposalIndex || id < 1) revert ProposalInexistent();

        if (researchProposals[id].status != ProposalStatus.Active)
            revert IncorrectPhase(researchProposals[id].status);

        researchProposals[id].status = ProposalStatus.Cancelled;

        emit Cancelled(id);
    }

    /**
     * @dev returns if user has voted for a given proposal
     * @param id the proposal id
     */
    function getVotedResearch(uint256 id) external view returns (uint8) {
        return votedResearch[id][_msgSender()];
    }

    /**
     * @dev returns the proposal index
     */
    function getResearchProposalIndex() external view returns (uint256) {
        return _researchProposalIndex;
    }

    /**
     * @dev returns proposal information
     * @param id the index of the proposal of interest
     */
    function getResearchProposalInfo(
        uint256 id
    )
        external
        view
        returns (uint256, uint256, ProposalStatus, uint256, uint256, uint256)
    {
        if (id > _researchProposalIndex || id < 1) revert ProposalInexistent();
        return (
            researchProposals[id].startBlockNum,
            researchProposals[id].endTimeStamp,
            researchProposals[id].status,
            researchProposals[id].votesFor,
            researchProposals[id].votesAgainst,
            researchProposals[id].totalVotes
        );
    }

    /**
     * @dev returns research project info information
     * @param id the index of the proposal of interest
     */
    function getResearchProposalProjectInfo(
        uint256 id
    ) external view returns (string memory, address, Payment, uint256) {
        if (id > _researchProposalIndex || id < 1) revert ProposalInexistent();
        return (
            researchProposals[id].details.info,
            researchProposals[id].details.receivingWallet,
            researchProposals[id].details.payment,
            researchProposals[id].details.amount
        );
    }

    /**
     * @dev terminates the governance and staking smart contracts
     */
    function terminateResearch()
        external
        notTerminated
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        IStaking staking = IStaking(stakingAddress);
        staking.terminateResearch(_msgSender());
        terminated = true;
        emit Terminated(_msgSender(), block.number);
    }
}
