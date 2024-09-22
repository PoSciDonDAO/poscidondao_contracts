// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import "./../interface/IStaking.sol";
import "./../interface/IGovernorResearch.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import "../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";

contract GovernorResearch is IGovernorResearch, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    ///*** ERRORS ***///
    error CannotCompleteProposalsOfTransactionType();
    error CannotExecuteProposalsOfOtherType();
    error ContractTerminated(uint256 blockNumber);
    error IncorrectCoinValue();
    error IncorrectPaymentOption();
    error IncorrectPhase(ProposalStatus);
    error InsufficientBalance(uint256 balance, uint256 requiredBalance);
    error InvalidInfo();
    error InvalidInputOtherProposal();
    error InvalidInputTransactionProposal();
    error ProposalLifeTimePassed();
    error ProposalOngoing(uint256 id, uint256 currentBlock, uint256 endBlock);
    error ProposalInexistent();
    error QuorumNotReached();
    error Unauthorized(address user);
    error VoteChangeNotAllowedAfterCutOff();
    error VoteChangeWindowExpired();

    ///*** STRUCTS ***///
    struct Proposal {
        uint256 startBlockNum;
        uint256 endTimestamp;
        ProposalStatus status;
        ProjectInfo details;
        uint256 votesFor;
        uint256 votesAgainst;
        uint256 totalVotes;
    }

    struct ProjectInfo {
        string info; //IPFS link
        address targetWallet; //wallet address to send funds to
        Payment payment;
        uint256 amount; //amount of usdc or coin
        uint256 amountSci; //amount of sci token
        ProposalType proposalType; //proposalType option for proposal
    }

    struct UserVoteData {
        bool voted; // Whether the user has voted
        uint256 initialVoteTimestamp; // The timestamp of when the user first voted
        bool previousSupport; // Whether the user supported the last vote
    }

    ///*** GOVERNANCE PARAMETERS ***///
    uint256 public proposalLifeTime;
    uint256 public quorum;
    uint256 public proposeLockTime;
    uint256 public voteLockTime;
    uint256 public voteChangeTime;
    uint256 public voteChangeCutOff;

    ///*** KEY ADDRESSES ***///
    address public govOpsAddress;
    address public stakingAddress;
    address public treasuryWallet;
    address public researchFundingWallet;
    address public usdc;
    address public sci;

    ///*** STORAGE & MAPPINGS ***///
    uint256 public ddThreshold;
    uint256 private _index;
    bytes32 public constant DUE_DILIGENCE_ROLE =
        keccak256("DUE_DILIGENCE_ROLE");
    bool public terminated = false;
    uint256 constant VOTE = 1;
    mapping(uint256 => Proposal) private proposals;
    mapping(address => uint8) private proposedResearch;
    mapping(address => mapping(uint256 => UserVoteData)) private userVoteData;

    ///*** ENUMERATORS ***///

    /**
     * @notice Enumerates the different proposalType options for a proposal.
     */
    enum ProposalType {
        Other,
        Transaction
    }

    /**
     * @notice Enumerates the different states a proposal can be in.
     */
    enum ProposalStatus {
        Active,
        Scheduled,
        Executed,
        Completed, //Completed status only for proposals that cannot be executed
        Cancelled
    }

    /**
     * @notice Enumerates the different payment options for a proposal.
     */
    enum Payment {
        Usdc,
        Sci,
        Coin,
        SciUsdc,
        None
    }

    ///*** MODIFIERS ***///

    /**
     * @notice Ensures operations can only proceed if the contract has not been terminated.
     */
    modifier notTerminated() {
        if (terminated) revert ContractTerminated(block.number);
        _;
    }
    /**
     * @notice Ensures function can only be called by the staking contract.
     */
    modifier onlyStaking() {
        if (msg.sender != stakingAddress) revert Unauthorized(msg.sender);
        _;
    }

    modifier onlyGov() {
        if (!(msg.sender == govOpsAddress)) revert Unauthorized(msg.sender);
        _;
    }

    /*** EVENTS ***/
    event Cancelled(uint256 indexed id);
    event Completed(uint256 indexed id);
    event Executed(uint256 indexed id, uint256 amount);
    event Proposed(
        uint256 indexed id,
        address indexed user,
        ProjectInfo details
    );
    event Voted(
        uint256 indexed id,
        address indexed user,
        bool indexed support,
        uint256 amount
    );
    event Scheduled(uint256 indexed id);
    event Terminated(address admin, uint256 blockNumber);

    constructor(
        address stakingAddress_,
        address treasuryWallet_,
        address researchFundingWallet_,
        address usdc_,
        address sci_ //add list of members for initial DD Crew
    ) {
        stakingAddress = stakingAddress_;
        treasuryWallet = treasuryWallet_;
        researchFundingWallet = researchFundingWallet_;
        usdc = usdc_;
        sci = sci_;

        ddThreshold = 1000e18;

        proposalLifeTime = 15 minutes;
        quorum = 1;
        voteLockTime = 0;
        proposeLockTime = 0;
        voteChangeTime = 1 hours;
        voteChangeCutOff = 3 days;

        _grantRole(DEFAULT_ADMIN_ROLE, treasuryWallet_);

        _grantRole(DUE_DILIGENCE_ROLE, treasuryWallet_);
        _grantRole(DUE_DILIGENCE_ROLE, researchFundingWallet_);

        _setRoleAdmin(DUE_DILIGENCE_ROLE, DEFAULT_ADMIN_ROLE);
    }

    ///*** EXTERNAL FUNCTIONS ***///

    /**
     * @dev terminates the governance smart contract
     */
    function setTerminated() external notTerminated onlyStaking {
        terminated = true;
        emit Terminated(msg.sender, block.number);
    }

    /**
     * @dev sets the threshold for DD members to propose
     */
    function setStakedSciThreshold(
        uint256 thresholdDDMember
    ) external notTerminated onlyRole(DEFAULT_ADMIN_ROLE) {
        ddThreshold = thresholdDDMember;
    }

    /**
     * @dev sets the GovernorOperations contract address
     */
    function setGovOps(
        address newGovOpsAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        govOpsAddress = newGovOpsAddress;
    }

    /**
     * @dev grants Due Diligence role to member
     * @param member the address of the DAO member
     */
    function grantDueDiligenceRole(
        address member
    ) external notTerminated onlyGov {
        IStaking staking = IStaking(stakingAddress);
        _validateStakingRequirements(staking, member);
        _grantRole(DUE_DILIGENCE_ROLE, member);
    }

    /**
     * @dev revokes Due Diligence role to member
     * @param member the address of the DAO member
     */
    function revokeDueDiligenceRole(
        address member
    ) external notTerminated onlyGov {
        _revokeRole(DUE_DILIGENCE_ROLE, member);
    }

    /**
     * @dev checks if user has the DD role
     * @param member the address of the DAO member
     */
    function checkDueDiligenceRole(
        address member
    ) external view returns (bool) {
        return hasRole(DUE_DILIGENCE_ROLE, member);
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
    function setResearchFundingWallet(
        address newresearchFundingWallet
    ) external notTerminated onlyRole(DEFAULT_ADMIN_ROLE) {
        researchFundingWallet = newresearchFundingWallet;
    }

    /**
     * @dev sets the staking address
     */
    function setStakingAddress(
        address newStakingAddress
    ) external notTerminated onlyRole(DEFAULT_ADMIN_ROLE) {
        stakingAddress = newStakingAddress;
    }

    /**
     * @dev sets the governance parameters given data
     * @param param the parameter of interest
     * @param data the data assigned to the parameter
     */
    function setGovParams(
        bytes32 param,
        uint256 data
    ) external notTerminated onlyRole(DEFAULT_ADMIN_ROLE) {
        //the duration of the proposal
        if (param == "proposalLifeTime") proposalLifeTime = data;

        //provide a percentage of the total supply
        if (param == "quorum") quorum = data;

        //the lock time of your tokens after voting
        if (param == "voteLockTime") voteLockTime = data;

        //the lock time of your tokens and ability to propose after proposing
        if (param == "proposeLockTime") proposeLockTime = data;

        //the time for a user to change their vote after their initial vote
        if (param == "voteChangeTime") voteChangeTime = data;

        //the time before the end of the proposal that users can change their votes
        if (param == "voteChangeCutOff") voteChangeCutOff = data;
    }

    /**
     * @dev proposes a research project in need of funding
     *      at least one option needs to be proposed
     * @param info ipfs hash of project proposal
     * @param targetWallet the address of the research group receiving funds if proposal passed
     * @param amountUsdc the amount of USDC
     * @param amountCoin the amount of Coin
     * @param amountSci the amount of SCI tokens
     */
    function propose(
        string memory info,
        address targetWallet,
        uint256 amountUsdc,
        uint256 amountCoin,
        uint256 amountSci,
        ProposalType proposalType
    )
        external
        nonReentrant
        notTerminated
        onlyRole(DUE_DILIGENCE_ROLE)
        returns (uint256)
    {
        _validateInput(
            info,
            targetWallet,
            amountUsdc,
            amountCoin,
            amountSci,
            proposalType
        );

        IStaking staking = IStaking(stakingAddress);
        _validateStakingRequirements(staking, msg.sender);

        (
            Payment payment,
            uint256 amount,
            uint256 sciAmount
        ) = _determinePaymentDetails(
                amountUsdc,
                amountCoin,
                amountSci,
                proposalType
            );

        ProjectInfo memory projectInfo = ProjectInfo(
            info,
            targetWallet,
            payment,
            amount,
            sciAmount,
            proposalType
        );

        uint256 currentIndex = _storeProposal(projectInfo);

        emit Proposed(currentIndex, msg.sender, projectInfo);

        return currentIndex;
    }

    /**
     * @dev vote for an of option of a given proposal
     *      using the rights from the most recent snapshot
     * @param id the index of the proposal
     * @param support true if in support of proposal
     */
    function vote(
        uint256 id,
        bool support
    ) external notTerminated nonReentrant onlyRole(DUE_DILIGENCE_ROLE) {
        _votingChecks(id, msg.sender);

        IStaking staking = IStaking(stakingAddress);

        _validateStakingRequirements(staking, msg.sender);

        _recordVote(id, support);
    }

    /**
     * @dev finalizes the voting phase for a research proposal
     * @param id the index of the proposal of interest
     */
    function finalize(
        uint256 id
    ) external nonReentrant notTerminated onlyRole(DUE_DILIGENCE_ROLE) {
        if (id >= _index) revert ProposalInexistent();

        if (proposals[id].status != ProposalStatus.Active)
            revert IncorrectPhase(proposals[id].status);

        if (block.timestamp < proposals[id].endTimestamp)
            revert ProposalOngoing(
                id,
                block.timestamp,
                proposals[id].endTimestamp
            );
        if (proposals[id].totalVotes < quorum) revert QuorumNotReached();

        proposals[id].status = ProposalStatus.Scheduled;

        emit Scheduled(id);
    }

    /**
     * @dev executes the proposal using USDC
     * @param id the index of the proposal of interest
     */
    function execute(
        uint256 id
    ) external payable notTerminated nonReentrant onlyRole(DUE_DILIGENCE_ROLE) {
        // Check if proposal exists and has finalized voting
        if (id >= _index) revert ProposalInexistent();
        if (proposals[id].status != ProposalStatus.Scheduled)
            revert IncorrectPhase(proposals[id].status);

        if (proposals[id].details.proposalType == ProposalType.Other)
            revert CannotExecuteProposalsOfOtherType();

        // Extract proposal details
        address targetWallet = proposals[id].details.targetWallet;
        uint256 amount = proposals[id].details.amount;
        uint256 amountSci = proposals[id].details.amountSci;
        Payment payment = proposals[id].details.payment;

        // Transfer funds based on payment type
        if (payment == Payment.Usdc || payment == Payment.SciUsdc) {
            _transferToken(
                IERC20(usdc),
                researchFundingWallet,
                targetWallet,
                amount
            );
        }
        if (payment == Payment.Sci || payment == Payment.SciUsdc) {
            _transferToken(
                IERC20(sci),
                researchFundingWallet,
                targetWallet,
                amountSci
            );
        }
        if (payment == Payment.Coin) {
            _transferCoin(researchFundingWallet, targetWallet, amount);
        }

        proposals[id].status = ProposalStatus.Executed;

        emit Executed(id, amount);
    }

    /**
     * @dev completes a non-executable proposal
     * @param id the _index of the proposal of interest
     */
    function complete(
        uint256 id
    ) external nonReentrant notTerminated onlyRole(DUE_DILIGENCE_ROLE) {
        if (id > _index) revert ProposalInexistent();

        if (proposals[id].status != ProposalStatus.Scheduled)
            revert IncorrectPhase(proposals[id].status);

        if ((proposals[id].details.proposalType == ProposalType.Transaction)) {
            revert CannotCompleteProposalsOfTransactionType();
        }

        proposals[id].status = ProposalStatus.Completed;

        emit Completed(id);
    }

    /**
     * @dev cancels the proposal
     * @param id the index of the proposal of interest
     */
    function cancel(
        uint256 id
    ) external nonReentrant onlyRole(DUE_DILIGENCE_ROLE) {
        if (terminated) {
            proposals[id].status = ProposalStatus.Cancelled;

            emit Cancelled(id);
        } else {
            if (id >= _index) revert ProposalInexistent();

            if (proposals[id].status != ProposalStatus.Active)
                revert IncorrectPhase(proposals[id].status);

            if (block.timestamp < proposals[id].endTimestamp)
                revert ProposalOngoing(
                    id,
                    block.timestamp,
                    proposals[id].endTimestamp
                );
            proposals[id].status = ProposalStatus.Cancelled;

            emit Cancelled(id);
        }
    }

    /**
     * @dev returns the proposal index
     */
    function getProposalIndex() external view returns (uint256) {
        return _index;
    }

    /**
     * @dev Retrieves the current governance parameters.
     * @return proposalLifeTime The lifetime of a proposal from its creation to its completion.
     * @return quorum The percentage of votes required for a proposal to be considered valid.
     * @return voteLockTime The duration for which voting on a proposal is open.
     * @return proposeLockTime The lock time before which a new proposal cannot be made.
     * @return voteChangeTime The time window during which a vote can be changed after the initial vote.
     * @return voteChangeCutOff The time before the end of the proposal during which vote changes are no longer allowed.
     */
    function getGovernanceParameters()
        public
        view
        returns (uint256, uint256, uint256, uint256, uint256, uint256)
    {
        return (
            proposalLifeTime,
            quorum,
            voteLockTime,
            proposeLockTime,
            voteChangeTime,
            voteChangeCutOff
        );
    }

    /**
     * @notice Retrieves detailed information about a specific governance proposal.
     * @dev This function returns comprehensive details of a proposal identified by its unique ID. It ensures the proposal exists before fetching the details. If the proposal ID is invalid (greater than the current maximum index), it reverts with `ProposalInexistent`.
     * @param id The unique identifier (index) of the proposal whose information is being requested. This ID is sequentially assigned to proposals as they are created.
     * @return startBlockNum The block number at which the proposal was made. This helps in tracking the proposal's lifecycle and duration.
     * @return endTimeStamp The timestamp (block time) by which the proposal voting must be concluded. After this time, the proposal may be finalized or executed based on its status and outcome.
     * @return status The current status of the proposal, represented as a value from the `ProposalStatus` enum. This status could be Active, Scheduled, Executed, Completed, or Cancelled.
     * @return details A `ProjectInfo` struct containing the proposal's detailed information such as the project description (IPFS link), the receiving wallet, payment options, and the amounts involved.
     * @return votesFor The total number of votes in favor of the proposal. This count helps in determining if the proposal has met quorum requirements and the majority's consensus.
     * @return totalVotes The total number of votes cast for the proposal, including both for and against. This is used to calculate the proposal's overall engagement and participation.
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
            uint256
        )
    {
        if (id > _index) revert ProposalInexistent();
        return (
            proposals[id].startBlockNum,
            proposals[id].endTimestamp,
            proposals[id].status,
            proposals[id].details,
            proposals[id].votesFor,
            proposals[id].totalVotes
        );
    }

    /**
     * @notice Retrieves voting data for a specific user on a specific proposal.
     * @dev This function returns the user's voting data for a proposal identified by its unique ID. It ensures the proposal exists before fetching the data.
     *      If the proposal ID is invalid (greater than the current maximum index), it reverts with `ProposalInexistent`.
     * @param user The address of the user whose voting data is being requested.
     * @param id The unique identifier (index) of the proposal for which the user's voting data is being requested. This ID is sequentially assigned to proposals as they are created.
     * @return voted A boolean indicating whether the user has voted on this proposal. `true` means the user has cast a vote, `false` means they have not.
     * @return initialVoteTimestamp The timestamp of when the user last voted on this proposal. The value represents seconds since Unix epoch (block timestamp).
     * @return previousSupport A boolean indicating whether the user supported the proposal in their last vote. `true` means they supported it, `false` means they opposed it.
     */
    function getUserVoteData(
        address user,
        uint256 id
    ) external view returns (bool, uint256, bool) {
        if (id > _index) revert ProposalInexistent();
        return (
            userVoteData[user][id].voted,
            userVoteData[user][id].initialVoteTimestamp,
            userVoteData[user][id].previousSupport
        );
    }

    ///*** INTERNAL FUNCTIONS ***///

    /**
     * @dev Validates the input parameters for a research proposal.
     * @param info The description or details of the research proposal, expected not to be empty.
     * @param targetWallet The wallet address that will receive funds if the proposal is approved.
     * @param amountUsdc The amount of USDC tokens involved in the proposal (6 decimals).
     * @param amountCoin The amount of Coin tokens involved in the proposal (18 decimals).
     * @param amountSci The amount of SCI tokens involved in the proposal (18 decimals).
     *
     * @notice This function reverts with InvalidInput if the validation fails.
     * Validation fails if 'info' is empty, 'targetWallet' is a zero address,
     * or the payment amounts do not meet the specified criteria.
     */
    function _validateInput(
        string memory info,
        address targetWallet,
        uint256 amountUsdc,
        uint256 amountCoin,
        uint256 amountSci,
        ProposalType proposalType
    ) internal pure {
        if (bytes(info).length == 0) revert InvalidInfo();

        if (proposalType == ProposalType.Transaction) {
            if (
                targetWallet == address(0) ||
                !((amountUsdc > 0 && amountCoin == 0 && amountSci >= 0) ||
                    (amountCoin > 0 && amountUsdc == 0 && amountSci == 0) ||
                    (amountSci > 0 && amountCoin == 0 && amountUsdc >= 0))
            ) {
                revert InvalidInputTransactionProposal();
            }
        } else {
            if (
                amountUsdc > 0 ||
                amountCoin > 0 ||
                amountSci > 0 ||
                targetWallet != address(0)
            ) {
                revert InvalidInputOtherProposal();
            }
        }
    }

    /**
     * @dev Performs common validation checks for all voting actions.
     *      This function validates the existence and status of a proposal, ensures that voting
     *      conditions such as proposal activity and timing constraints are met, and verifies
     *      the signature of the voter where necessary.
     *
     * @param id The index of the proposal on which to vote.
     * @param voter the user that wants to vote on the given proposal id
     *
     *
     */
    function _votingChecks(uint id, address voter) internal view {
        if (id >= _index) revert ProposalInexistent();
        if (proposals[id].status != ProposalStatus.Active)
            revert IncorrectPhase(proposals[id].status);
        if (block.timestamp > proposals[id].endTimestamp)
            revert ProposalLifeTimePassed();
        if (
            userVoteData[voter][id].voted &&
            block.timestamp >= proposals[id].endTimestamp - voteChangeCutOff
        ) revert VoteChangeNotAllowedAfterCutOff();
        if (
            userVoteData[voter][id].voted &&
            block.timestamp >
            userVoteData[voter][id].initialVoteTimestamp + voteChangeTime
        ) {
            revert VoteChangeWindowExpired();
        }
    }

    /**
     * @dev Records a vote on a proposal, updating the vote totals and voter status.
     *      This function is called after all preconditions checked by `_votingChecks` are met.
     *
     * @param id The index of the proposal on which to vote.
     * @param support A boolean indicating whether the vote is in support of (true) or against (false) the proposal.
     */
    function _recordVote(uint id, bool support) internal {
        UserVoteData storage voteData = userVoteData[msg.sender][id];

        // Deduct previous votes if the user has already voted
        if (voteData.voted) {
            if (voteData.previousSupport) {
                proposals[id].votesFor -= VOTE;
            } else {
                proposals[id].votesAgainst -= VOTE;
            }
            proposals[id].totalVotes -= VOTE;
        }

        if (support) {
            proposals[id].votesFor += VOTE;
        } else {
            proposals[id].votesAgainst += VOTE;
        }
        proposals[id].totalVotes += VOTE;

        voteData.voted = true;
        voteData.previousSupport = support;

        if (voteData.initialVoteTimestamp == 0) {
            voteData.initialVoteTimestamp = block.timestamp;
        }

        IStaking(stakingAddress).voted(
            msg.sender,
            block.timestamp + voteLockTime
        );

        emit Voted(id, msg.sender, support, VOTE);
    }

    /**
     * @dev Validates if the proposer meets the staking requirements for proposing research.
     * @param staking The staking contract interface used to check the staked SCI.
     * @param member The address of the member initiating an action.
     *
     * @notice This function reverts with InsufficientBalance if the staked SCI is below the threshold.
     * The staked SCI amount and required threshold are provided in the revert message.
     */
    function _validateStakingRequirements(
        IStaking staking,
        address member
    ) internal view {
        uint256 stakedSci = staking.getStakedSci(member);
        if (stakedSci < ddThreshold) {
            revert InsufficientBalance(stakedSci, ddThreshold);
        }
    }

    /**
     * @dev Determines the payment method and amount for the research proposal.
     * @param amountUsdc Amount of USDC tokens to be used in the proposal.
     * @param amountCoin Amount of Coin tokens to be used in the proposal.
     * @param amountSci Amount of SCI tokens to be used in the proposal.
     * @return payment The determined type of payment from the Payment enum.
     * @return amount The amount of USDC or Coin tokens to be used.
     * @return sciAmount The amount of SCI tokens to be used.
     *
     * @notice This function reverts with IncorrectPaymentOption if the payment options do not meet the criteria.
     * Only one of amountUsdc, amountCoin, or amountSci should be greater than zero, except for a specific combination
     * where SciUsdc is chosen as the payment method.
     */
    function _determinePaymentDetails(
        uint256 amountUsdc,
        uint256 amountCoin,
        uint256 amountSci,
        ProposalType proposalType
    )
        internal
        pure
        returns (Payment payment, uint256 amount, uint256 sciAmount)
    {
        if (proposalType == ProposalType.Other) return (Payment.None, 0, 0);
        uint8 paymentOptions = (amountUsdc > 0 ? 1 : 0) +
            (amountCoin > 0 ? 1 : 0) +
            (amountSci > 0 ? 1 : 0);

        if (paymentOptions == 1) {
            if (amountUsdc > 0) return (Payment.Usdc, amountUsdc, 0);
            if (amountCoin > 0) return (Payment.Coin, amountCoin, 0);
            if (amountSci > 0) return (Payment.Sci, 0, amountSci);
        } else if (paymentOptions == 2 && amountUsdc > 0 && amountSci > 0) {
            return (Payment.SciUsdc, amountUsdc, amountSci);
        } else {
            revert IncorrectPaymentOption();
        }
    }

    /**
     * @dev Stores a new research proposal in the contract's state.
     * @param projectInfo Struct containing information about the project.
     * @return uint256 The index of the newly stored research proposal.
     *
     * @notice The function increments the _index after storing the proposal.
     * The proposal is stored with an Active status and initialized voting counters.
     * The function returns the index at which the new proposal is stored.
     */
    function _storeProposal(
        ProjectInfo memory projectInfo
    ) internal returns (uint256) {
        Proposal memory proposal = Proposal(
            block.number,
            block.timestamp + proposalLifeTime,
            ProposalStatus.Active,
            projectInfo,
            0,
            0,
            0
        );

        uint256 currentIndex = _index++;
        proposals[currentIndex] = proposal;

        return currentIndex;
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
        if (msg.value != amount) revert IncorrectCoinValue();
        (bool sent, ) = to.call{value: msg.value}("");
        require(sent, "Failed to transfer");
    }
}
