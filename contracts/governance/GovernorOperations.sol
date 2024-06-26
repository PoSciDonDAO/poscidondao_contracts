// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import "./../interface/IParticipation.sol";
import "./../interface/IStaking.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20Burnable} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import "../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "./SybilResistance.sol";

contract GovernorOperations is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    ///*** ERRORS ***///
    error ContractTerminated(uint256 blockNumber);
    error IncorrectCoinValue();
    error IncorrectPaymentOption();
    error IncorrectPhase(ProposalStatus);
    error InexistentOrInvalidSBT();
    error InsufficientBalance(uint256 balance, uint256 requiredBalance);
    error InsufficientVotingRights(uint256 currentRights, uint256 votesGiven);
    error InvalidInputForExecutable();
    error InvalidInputForNonExecutable();
    error InvalidInfo();
    error InvalidVotesInput();
    error TokensStillLocked(uint256 voteLockStamp, uint256 currentStamp);
    error ProposalIsNotExecutable();
    error ProposalLifeTimePassed();
    error ProposeLock();
    error ProposalOngoing(uint256 id, uint256 currentBlock, uint256 endBlock);
    error ProposalInexistent();
    error QuorumNotReached(uint256 id, uint256 totalVotes, uint256 quorum);
    error QuorumReached();
    error Unauthorized(address user);
    error VoteLock();

    ///*** STRUCTS ***///
    struct Proposal {
        uint256 startBlockNum;
        uint256 endTimeStamp;
        ProposalStatus status;
        ProjectInfo details;
        uint256 votesFor;
        uint256 votesAgainst;
        uint256 totalVotes;
        bool quadraticVoting;
    }

    struct ProjectInfo {
        string info; //IPFS link
        address receivingWallet; //wallet address to send funds to
        Payment payment;
        uint256 amount; //amount of usdc or coin
        uint256 amountSci; //amount of sci token
        bool executable;
    }

    ///*** INTERFACE ***///
    IParticipation private po;

    ///*** GOVERNANCE PARAMETERS ***///
    uint256 public proposalLifeTime;
    uint256 public quorum;
    uint256 public proposeLockTime;
    uint256 public voteLockTime;

    ///*** KEY ADDRESSES ***///
    address public stakingAddress;
    address public treasuryWallet;
    address public usdc;
    address public sci;

    ///*** STORAGE & MAPPINGS ***///
    Hub private hub;
    uint256 public opThreshold;
    uint256 private index;
    uint256 public totBurnedForTermination;
    uint256 public terminationThreshold;
    bool public terminated = false;
    mapping(uint256 => Proposal) private proposals;
    mapping(uint256 => mapping(address => bool)) private voted;

    ///*** ENUMERATORS ***///
    enum ProposalStatus {
        Active,
        Scheduled,
        Executed,
        Completed, //Completed status only for proposals that cannot be executed
        Cancelled
    }

    enum Payment {
        None,
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
    event BurnedForTermination(address owner, uint256 amount);
    event Proposed(uint256 indexed id, address proposer, ProjectInfo details);
    event Voted(
        uint256 indexed id,
        address indexed voter,
        bool indexed support,
        uint256 amount
    );
    event Scheduled(uint256 indexed id);
    event Executed(uint256 indexed id, bool indexed donated, uint256 amount);
    event Completed(uint256 indexed id);
    event Cancelled(uint256 indexed id);
    event Terminated(address admin, uint256 blockNumber);

    constructor(
        address stakingAddress_,
        address treasuryWallet_,
        address usdc_,
        address sci_,
        address po_,
        address hubAddress_
    ) {
        stakingAddress = stakingAddress_;
        treasuryWallet = treasuryWallet_;
        usdc = usdc_;
        sci = sci_;
        po = IParticipation(po_);
        hub = Hub(hubAddress_);
        opThreshold = 100e18;
        terminationThreshold = (IERC20(sci).totalSupply() / 10000) * 5100;

        proposalLifeTime = 15 minutes; //testing
        quorum = (IERC20(sci).totalSupply() / 10000) * 300; //3% of circulating supply
        voteLockTime = 0; //testing
        proposeLockTime = 0; //testing

        _grantRole(DEFAULT_ADMIN_ROLE, treasuryWallet_);
    }

    ///*** EXTERNAL FUNCTIONS ***///

    /**
     * @dev sets the Hub address
     */
    function setHubAddress(
        address hubAddress
    ) external notTerminated onlyRole(DEFAULT_ADMIN_ROLE) {
        hub = Hub(hubAddress);
    }

    /**
     * @dev sets the threshold for members to propose
     */
    function setStakedSciThreshold(
        uint256 thresholdOpMember
    ) external notTerminated onlyRole(DEFAULT_ADMIN_ROLE) {
        opThreshold = thresholdOpMember;
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
     * @dev sets the staking address
     */
    function setStakingAddress(
        address _newStakingAddress
    ) external notTerminated onlyRole(DEFAULT_ADMIN_ROLE) {
        stakingAddress = _newStakingAddress;
    }

    /**
     * @dev sets the PO token address and interface
     */
    function setPoToken(
        address po_
    ) external notTerminated onlyRole(DEFAULT_ADMIN_ROLE) {
        po = IParticipation(po_);
    }

    /**
     * @dev sets the governance parameters given data
     * @param param the parameter of interest
     * @param data the data assigned to the parameter
     */
    function govParams(
        bytes32 param,
        uint256 data
    ) external notTerminated onlyRole(DEFAULT_ADMIN_ROLE) {
        //the duration of the proposal
        if (param == "proposalLifeTime") proposalLifeTime = data;

        //the amount of tokens needed to pass a proposal
        //provide a percentage of the total supply
        if (param == "quorum") quorum = data;

        //the lock time of your tokens after voting
        if (param == "voteLockTime") voteLockTime = data;

        //the lock time of your tokens and ability to propose after proposing
        if (param == "proposeLockTime") proposeLockTime = data;

        //the amount of tokens that need to be burned to terminate DAO operations governance
        if(param == "terminationThreshold") terminationThreshold = data;
    }

    /**
     * @dev Proposes a change in DAO operations. At least one option needs to be proposed.
     * @param info IPFS hash of project proposal.
     * @param receivingWallet Address of the party receiving funds if proposal passes.
     * @param amountUsdc Amount of USDC.
     * @param amountCoin Amount of Coin.
     * @param amountSci Amount of SCI tokens.
     * @param executable Whether the proposal is executable.
     * @param quadraticVoting Whether quadratic voting is enabled for the proposal.
     * @return uint256 Index of the newly created proposal.
     */
    function propose(
        string memory info,
        address receivingWallet,
        uint256 amountUsdc,
        uint256 amountCoin,
        uint256 amountSci,
        bool executable,
        bool quadraticVoting
    ) external nonReentrant notTerminated returns (uint256) {
        validateInput(
            info,
            receivingWallet,
            amountUsdc,
            amountCoin,
            amountSci,
            executable
        );

        IStaking staking = IStaking(stakingAddress);

        validateStakingRequirements(staking, msg.sender);

        (
            Payment payment,
            uint256 amount,
            uint256 sciAmount
        ) = determinePaymentDetails(
                amountUsdc,
                amountCoin,
                amountSci,
                executable
            );

        ProjectInfo memory projectInfo = ProjectInfo(
            info,
            receivingWallet,
            payment,
            amount,
            sciAmount,
            executable
        );

        uint256 currentIndex = storeProposal(
            projectInfo,
            quadraticVoting,
            staking
        );

        emit Proposed(currentIndex, msg.sender, projectInfo);

        return currentIndex;
    }

    /**
     * @dev vote for an option of a given proposal
     *      using the rights from the most recent snapshot
     * @param id the index of the proposal
     * @param support user's choice to support a proposal or not
     * @param votes the amount of votes
     * @param circuitId the identifier of holonym v3's zkp circuit
     */
    function vote(
        uint256 id,
        bool support,
        uint256 votes,
        bytes32 circuitId
    ) external nonReentrant notTerminated {
        //check if proposal exists
        if (id >= index) revert ProposalInexistent();

        //check if proposal is still active
        if (proposals[id].status != ProposalStatus.Active)
            revert IncorrectPhase(proposals[id].status);

        //check if proposal life time has not passed
        if (block.timestamp > proposals[id].endTimeStamp)
            revert ProposalLifeTimePassed();

        //check if user already voted for this proposal
        if (voted[id][msg.sender] == true) revert VoteLock();

        if (votes == 0) revert InvalidVotesInput();

        if (proposals[id].quadraticVoting) {
            SBT memory sbt = hub.getSBT(msg.sender, circuitId);
            //getSBT reverts because there is no Hub.sol on optimism or polygon testnet
            if (sbt.publicValues.length == 0 && block.timestamp > sbt.expiry) {
                revert InexistentOrInvalidSBT();
            }
        }

        IStaking staking = IStaking(stakingAddress);

        uint256 votingRights = staking.getLatestUserRights(msg.sender);

        if (votes > votingRights)
            revert InsufficientVotingRights(votingRights, votes);

        uint256 actualVotes;

        if (proposals[id].quadraticVoting) {
            actualVotes = _sqrt(votes);
        } else {
            actualVotes = votes;
        }

        if (support) {
            proposals[id].votesFor += actualVotes;
        } else {
            proposals[id].votesAgainst += actualVotes;
        }

        proposals[id].totalVotes += actualVotes;

        voted[id][msg.sender] = true;

        staking.voted(msg.sender, block.timestamp + voteLockTime);

        po.mint(msg.sender);

        emit Voted(id, msg.sender, support, actualVotes);
    }

    /**
     * @dev finalizes the voting phase for an operations proposal
     * @param id the index of the proposal of interest
     */
    function finalize(uint256 id) external notTerminated {
        if (id >= index) revert ProposalInexistent();

        if (block.timestamp < proposals[id].endTimeStamp)
            revert ProposalOngoing(
                id,
                block.timestamp,
                proposals[id].endTimeStamp
            );

        if (proposals[id].status != ProposalStatus.Active)
            revert IncorrectPhase(proposals[id].status);

        if (
            (!proposals[id].quadraticVoting &&
                proposals[id].totalVotes < quorum) ||
            (proposals[id].quadraticVoting &&
                proposals[id].totalVotes < _sqrt(quorum))
        ) {
            revert QuorumNotReached(
                id,
                proposals[id].totalVotes,
                proposals[id].quadraticVoting ? _sqrt(quorum) : quorum
            );
        }

        proposals[id].status = ProposalStatus.Scheduled;

        emit Scheduled(id);
    }

    /**
     * @dev executes the proposal using a token or coin - Operation's crew's choice
     * @param id the index of the proposal of interest
     */
    function execute(
        uint256 id
    ) external payable nonReentrant notTerminated onlyRole(DEFAULT_ADMIN_ROLE) {
        //check if proposal exists
        if (id >= index) revert ProposalInexistent();

        if (proposals[id].details.executable) {
            //check if proposal has finalized voting
            if (proposals[id].status != ProposalStatus.Scheduled)
                revert IncorrectPhase(proposals[id].status);

            address receivingWallet = proposals[id].details.receivingWallet;

            uint256 amount = proposals[id].details.amount;
            uint256 amountSci = proposals[id].details.amountSci;

            Payment payment = proposals[id].details.payment;
            if (payment == Payment.Usdc || payment == Payment.SciUsdc) {
                _transferToken(
                    IERC20(usdc),
                    treasuryWallet,
                    receivingWallet,
                    amount
                );
            }
            if (payment == Payment.Sci || payment == Payment.SciUsdc) {
                _transferToken(
                    IERC20(sci),
                    treasuryWallet,
                    receivingWallet,
                    amountSci
                );
            }
            if (payment == Payment.Coin) {
                _transferCoin(treasuryWallet, receivingWallet, amount); //only treasury wallet can execute this proposal
            }

            proposals[id].status = ProposalStatus.Executed;

            emit Executed(id, false, amount);
        } else {
            revert ProposalIsNotExecutable();
        }
    }

    function complete(
        uint256 id
    ) external notTerminated onlyRole(DEFAULT_ADMIN_ROLE) {
        if (id > index) revert ProposalInexistent();

        if (proposals[id].status != ProposalStatus.Scheduled)
            revert IncorrectPhase(proposals[id].status);

        proposals[id].status = ProposalStatus.Completed;

        emit Completed(id);
    }

    /**
     * @dev cancels the proposal
     * @param id the index of the proposal of interest
     */
    function cancel(uint256 id) external notTerminated {
        if (id >= index) revert ProposalInexistent();

        if (proposals[id].status != ProposalStatus.Active)
            revert IncorrectPhase(proposals[id].status);

        if (block.timestamp < proposals[id].endTimeStamp)
            revert ProposalOngoing(
                id,
                block.timestamp,
                proposals[id].endTimeStamp
            );
        proposals[id].status = ProposalStatus.Cancelled;

        emit Cancelled(id);
    }

    /**
     * @dev locks a given amount of SCI tokens for termination
     * @param amount the amount of tokens that will be locked
     */
    function burnForTerminatingOperations(
        uint256 amount
    ) external nonReentrant notTerminated {

        ERC20Burnable(sci).burnFrom(msg.sender, amount);

        totBurnedForTermination += amount;

        emit BurnedForTermination(msg.sender, amount);
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
        if (totBurnedForTermination > terminationThreshold) {
            IStaking staking = IStaking(stakingAddress);
            staking.terminate(msg.sender);
            terminated = true;
            emit Terminated(msg.sender, block.number);
        }
    }

    /**
     * @dev returns the PO token address
     */
    function getPoToken() external view returns (address) {
        return address(po);
    }

    /**
     * @dev returns if user has voted for a given proposal
     * @param id the proposal id
     */
    function getVoted(uint256 id) external view returns (bool) {
        if (id >= index) revert ProposalInexistent();
        return voted[id][msg.sender];
    }

    /**
     * @dev returns the operations proposal index
     */
    function getProposalIndex() external view returns (uint256) {
        return index;
    }

    /**
     * @dev returns proposal information
     * @param id the index of the proposal of interest
     */
    function getProposalInfo(
        uint256 id
    )
        external
        view
        returns (
            uint256,
            uint256,
            ProposalStatus,
            ProjectInfo memory,
            uint256,
            uint256,
            bool
        )
    {
        if (id > index) revert ProposalInexistent();
        return (
            proposals[id].startBlockNum,
            proposals[id].endTimeStamp,
            proposals[id].status,
            proposals[id].details,
            proposals[id].votesFor,
            proposals[id].totalVotes,
            proposals[id].quadraticVoting
        );
    }

    ///*** INTERNAL FUNCTIONS ***///

    /**
     * @dev Validates input parameters for an operation proposal.
     * @param info Description or details of the operation proposal.
     * @param receivingWallet Wallet address to receive funds if the proposal is approved.
     * @param amountUsdc Amount of USDC involved in the proposal.
     * @param amountCoin Amount of Coin involved in the proposal.
     * @param amountSci Amount of SCI tokens involved in the proposal.
     * @param executable Boolean indicating whether the proposal is executable.
     *
     * @notice Reverts with InvalidInfo if the info is empty.
     * Reverts with InvalidInputForExecutable or InvalidInputForNonExecutable
     * based on the executable flag and the validity of payment amounts and receiving wallet.
     */
    function validateInput(
        string memory info,
        address receivingWallet,
        uint256 amountUsdc,
        uint256 amountCoin,
        uint256 amountSci,
        bool executable
    ) internal pure {
        if (bytes(info).length == 0) revert InvalidInfo();

        if (executable) {
            if (
                receivingWallet == address(0) ||
                !((amountUsdc > 0 && amountCoin == 0 && amountSci >= 0) ||
                    (amountCoin > 0 && amountUsdc == 0 && amountSci == 0) ||
                    (amountSci > 0 && amountCoin == 0 && amountUsdc >= 0))
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
    }

    /**
     * @dev Checks if the proposer satisfies the staking requirements for proposal submission.
     * @param staking The staking contract interface to check staked amounts.
     * @param proposer Address of the user making the proposal.
     *
     * @notice Reverts with InsufficientBalance if the staked amount is below the required threshold.
     * Reverts with ProposalLock if the proposer's tokens are locked due to a recent proposal.
     */
    function validateStakingRequirements(
        IStaking staking,
        address proposer
    ) internal view {
        if (staking.getStakedSci(proposer) < opThreshold)
            revert InsufficientBalance(
                staking.getStakedSci(proposer),
                opThreshold
            );

        if (staking.getProposeLockEndTime(proposer) > block.timestamp)
            revert ProposeLock();
    }

    /**
     * @dev Determines and returns the payment type and amounts for an operation proposal.
     * @param amountUsdc Amount of USDC involved in the proposal.
     * @param amountCoin Amount of Coin involved in the proposal.
     * @param amountSci Amount of SCI tokens involved in the proposal.
     * @param executable Boolean flag indicating whether the proposal is executable.
     * @return payment The determined payment method from the Payment enum.
     * @return amount The amount of USDC or Coin to be used.
     * @return sciAmount The amount of SCI tokens to be used.
     *
     * @notice Reverts with IncorrectPaymentOption if the payment method is not valid.
     * The method is determined based on the non-zero amounts of USDC, Coin, and SCI tokens.
     */
    function determinePaymentDetails(
        uint256 amountUsdc,
        uint256 amountCoin,
        uint256 amountSci,
        bool executable
    )
        internal
        pure
        returns (Payment payment, uint256 amount, uint256 sciAmount)
    {
        if (!executable) return (Payment.None, 0, 0); // Default for non-executable, adjust as needed

        uint8 paymentOptions = (amountUsdc > 0 ? 1 : 0) +
            (amountCoin > 0 ? 1 : 0) +
            (amountSci > 0 ? 1 : 0);

        if (paymentOptions == 1) {
            if (amountUsdc > 0) return (Payment.Usdc, amountUsdc, 0);
            if (amountCoin > 0) return (Payment.Coin, amountCoin, 0);
            if (amountSci > 0) return (Payment.Sci, 0, amountSci);
        } else if (paymentOptions == 2 && amountUsdc > 0 && amountSci > 0) {
            return (Payment.SciUsdc, amountUsdc, amountSci);
        }

        revert IncorrectPaymentOption();
    }

    /**
     * @dev Stores a new operation proposal in the contract's state and updates staking.
     * @param projectInfo Struct containing detailed information about the project.
     * @param quadraticVoting Boolean indicating if quadratic voting is enabled for this proposal.
     * @param staking The staking contract interface used for updating the proposer's status.
     * @return uint256 The index where the new proposal is stored.
     *
     * @notice The function increments the operations proposal index after storing.
     * It also updates the staking contract to reflect the new proposal.
     */
    function storeProposal(
        ProjectInfo memory projectInfo,
        bool quadraticVoting,
        IStaking staking
    ) internal returns (uint256) {
        Proposal memory proposal = Proposal(
            block.number,
            block.timestamp + proposalLifeTime,
            ProposalStatus.Active,
            projectInfo,
            0,
            0,
            0,
            quadraticVoting
        );

        uint256 currentIndex = index++;
        proposals[currentIndex] = proposal;

        staking.proposed(msg.sender, block.timestamp + proposeLockTime);

        return currentIndex;
    }

    /**
     * @dev calculates the square root of given x 
            adjusted for values with 18 decimals
     */
    function _sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0; // Return 0 for 0 input

        // Normalize x by dividing by 1e18
        uint256 normalizedX = x / 1e18;

        uint256 z = (normalizedX + 1) / 2;
        y = normalizedX;
        while (z < y) {
            y = z;
            z = (normalizedX / z + z) / 2;
        }

        // Convert the result back to wei scale by multiplying with 1e18
        return y * 1e18;
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
    function _transferToken(
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
    function _transferCoin(address from, address to, uint256 amount) internal {
        if (msg.sender != from) revert Unauthorized(msg.sender);
        if (msg.value == 0 || msg.value != amount) revert IncorrectCoinValue();
        (bool sent, ) = to.call{value: msg.value}("");
        require(sent, "Failed to transfer");
    }
}
