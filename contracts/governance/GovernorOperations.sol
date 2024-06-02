// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import "./../interface/IPo.sol";
import "./../interface/IStaking.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20Burnable} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import "../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";

/**
 * @title GovernorOperations
 * @dev Implements DAO governance functionalities including proposing, voting, and executing proposals.
 * It integrates with external contracts for staking validation and participation rewards.
 */
contract GovernorOperations is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    ///*** ERRORS ***///
    error CannotVoteOnQVProposals();
    error ContractTerminated(uint256 blockNumber);
    error ExecutableProposalsCannotBeCompleted();
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
        uint256 endTimestamp;
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
    IPo private po;

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
    address private signer;
    // address public recoveredAddress;

    ///*** STORAGE & MAPPINGS ***///
    uint256 public opThreshold;
    uint256 private _index;
    bool public terminated = false;
    mapping(uint256 => Proposal) private proposals;
    mapping(uint256 => mapping(address => bool)) private voted;

    ///*** ENUMERATORS ***///

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

    /*** EVENTS ***/
    event Cancelled(uint256 indexed id);
    event Completed(uint256 indexed id);
    event Executed(uint256 indexed id, bool indexed donated, uint256 amount);
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
        address usdc_,
        address sci_,
        address po_,
        address signer_
    ) {
        stakingAddress = stakingAddress_;
        treasuryWallet = treasuryWallet_;
        usdc = usdc_;
        sci = sci_;
        po = IPo(po_);
        signer = signer_;
        opThreshold = 100e18;
        proposalLifeTime = 7 days; //testing
        quorum = (IERC20(sci).totalSupply() / 10000) * 300; //3% of circulating supply
        voteLockTime = 0; //testing
        proposeLockTime = 0; //testing

        _grantRole(DEFAULT_ADMIN_ROLE, treasuryWallet_);
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
        address newStakingAddress
    ) external notTerminated onlyRole(DEFAULT_ADMIN_ROLE) {
        stakingAddress = newStakingAddress;
    }

    /**
     * @dev sets the signer address
     */
    function setSigner(
        address newSigner
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        signer = newSigner;
    }

    /**
     * @dev sets the PO token address and interface
     */
    function setPoToken(
        address po_
    ) external notTerminated onlyRole(DEFAULT_ADMIN_ROLE) {
        po = IPo(po_);
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

        //the amount of tokens needed to pass a proposal
        //provide a percentage of the total supply
        if (param == "quorum") quorum = data;

        //the lock time of your tokens after voting
        if (param == "voteLockTime") voteLockTime = data;

        //the lock time of your tokens and ability to propose after proposing
        if (param == "proposeLockTime") proposeLockTime = data;
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
        _validateInput(
            info,
            receivingWallet,
            amountUsdc,
            amountCoin,
            amountSci,
            executable
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

        uint256 currentIndex = _storeProposal(
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
     * @param id the _index of the proposal
     * @param support user's choice to support a proposal or not
     * @param votes the amount of votes
     */
    function voteStandard(
        uint id,
        bool support,
        uint votes
    ) external nonReentrant notTerminated {
        _commonVotingChecks(id, votes);

        if (proposals[id].quadraticVoting) revert CannotVoteOnQVProposals();

        uint256 votingRights = IStaking(stakingAddress).getLatestUserRights(
            msg.sender
        );
        if (votes > votingRights)
            revert InsufficientVotingRights(votingRights, votes);

        _recordVote(id, support, votes);
    }

    function voteQV(
        uint id,
        bool support,
        uint votes,
        bool isUnique,
        bytes memory signature
    ) external nonReentrant notTerminated {
        _commonVotingChecks(id, votes);
        _uniquenessCheck(id, msg.sender, isUnique, signature);

        uint256 votingRights = IStaking(stakingAddress).getLatestUserRights(
            msg.sender
        );
        if (votes > votingRights)
            revert InsufficientVotingRights(votingRights, votes);

        uint256 actualVotes = _sqrt(votes);
        _recordVote(id, support, actualVotes);
    }

    /**
     * @dev finalizes the voting phase for an operations proposal
     * @param id the _index of the proposal of interest
     */
    function finalize(uint256 id) external nonReentrant notTerminated {
        if (id >= _index) revert ProposalInexistent();

        if (block.timestamp < proposals[id].endTimestamp)
            revert ProposalOngoing(
                id,
                block.timestamp,
                proposals[id].endTimestamp
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
     * @param id the _index of the proposal of interest
     */
    function execute(
        uint256 id
    ) external payable nonReentrant notTerminated onlyRole(DEFAULT_ADMIN_ROLE) {
        //check if proposal exists
        if (id >= _index) revert ProposalInexistent();

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

    /**
     * @dev completes a non-executable proposal
     * @param id the _index of the proposal of interest
     */
    function complete(
        uint256 id
    ) external nonReentrant notTerminated onlyRole(DEFAULT_ADMIN_ROLE) {
        if (id > _index) revert ProposalInexistent();

        if (proposals[id].status != ProposalStatus.Scheduled)
            revert IncorrectPhase(proposals[id].status);

        if (proposals[id].details.executable) {
            revert ExecutableProposalsCannotBeCompleted();
        }

        proposals[id].status = ProposalStatus.Completed;

        emit Completed(id);
    }

    /**
     * @dev cancels the proposal
     * @param id the _index of the proposal of interest
     */
    function cancel(uint256 id) external nonReentrant {
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
        if (id >= _index) revert ProposalInexistent();
        return voted[id][msg.sender];
    }

    /**
     * @dev returns the operations proposal _index
     */
    function getProposalIndex() external view returns (uint256) {
        return _index;
    }

    /**
     * @dev returns the signer address
     */
    function getSigner()
        external
        view
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (address)
    {
        return signer;
    }

    /**
     * @dev Retrieves the current governance parameters.
     * @return proposalLifeTime The lifetime of a proposal from its creation to its completion.
     * @return quorum The percentage of votes required for a proposal to be considered valid.
     * @return proposeLockTime The lock time before which a new proposal cannot be made.
     * @return voteLockTime The duration for which voting on a proposal is open.
     */
    function getGovernanceParameters()
        public
        view
        returns (uint256, uint256, uint256, uint256)
    {
        return (
            proposalLifeTime,
            quorum,
            voteLockTime,
            proposeLockTime
        );
    }

    /**
     * @notice Retrieves detailed information about a specific governance proposal.
     * @dev This function returns comprehensive details of a proposal identified by its unique ID. It ensures the proposal exists before fetching the details. If the proposal ID is invalid (greater than the current maximum index), it reverts with `ProposalInexistent`.
     * @param id The unique identifier (index) of the proposal whose information is being requested. This ID is sequentially assigned to proposals as they are created.
     * @return startBlockNum The block number at which the proposal was made. This helps in tracking the proposal's lifecycle and duration.
     * @return endTimestamp The timestamp (block time) by which the proposal voting must be concluded. After this time, the proposal may be finalized or executed based on its status and outcome.
     * @return status The current status of the proposal, represented as a value from the `ProposalStatus` enum. This status could be Active, Scheduled, Executed, Completed, or Cancelled.
     * @return details A `ProjectInfo` struct containing the proposal's detailed information such as the project description (IPFS link), the receiving wallet, payment options, and the amounts involved.
     * @return votesFor The total number of votes in favor of the proposal. This count helps in determining if the proposal has met quorum requirements and the majority's consensus.
     * @return totalVotes The total number of votes cast for the proposal, including both for and against. This is used to calculate the proposal's overall engagement and participation.
     * @return quadraticVoting A boolean indicating whether the proposal uses quadratic voting for determining its outcome. Quadratic voting allows for a more nuanced expression of preference and consensus among voters.
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
        if (id > _index) revert ProposalInexistent();
        return (
            proposals[id].startBlockNum,
            proposals[id].endTimestamp,
            proposals[id].status,
            proposals[id].details,
            proposals[id].votesFor,
            proposals[id].totalVotes,
            proposals[id].quadraticVoting
        );
    }

    ///*** INTERNAL FUNCTIONS ***///
    /**
     * @dev Performs common validation checks for all voting actions.
     *      This function validates the existence and status of a proposal, ensures that voting
     *      conditions such as proposal activity and timing constraints are met, and verifies
     *      the signature of the voter where necessary.
     *
     * @param id The index of the proposal on which to vote.
     * @param votes The number of votes the user wishes to cast.
     *
     *
     */
    function _commonVotingChecks(uint id, uint votes) internal view {
        if (id >= _index) revert ProposalInexistent();
        if (proposals[id].status != ProposalStatus.Active)
            revert IncorrectPhase(proposals[id].status);
        if (block.timestamp > proposals[id].endTimestamp)
            revert ProposalLifeTimePassed();
        if (voted[id][msg.sender]) revert VoteLock();
        if (votes == 0) revert InvalidVotesInput();
    }

    /**
     * @dev Performs validation checks for quadratic voting actions.
     *      This function validates the presence of Holonym's SBT in the user's account
     *      to ensure the account is unique.
     *
     * @param id The index of the proposal on which to vote.
     * @param isUnique The status of the uniqueness of the account casting the vote.
     * @param signature The signature of the data related to the account's uniqueness.
     *
     *
     */
    function _uniquenessCheck(
        uint256 id,
        address user,
        bool isUnique,
        bytes memory signature
    ) internal view {
        if (proposals[id].quadraticVoting) {
            bool verified = _verify(user, isUnique, signature);
            require(verified, "Invalid signature");
            require(isUnique, "User does not have a valid SBT");
        }
    }

    /**
     * @dev Calculates a keccak256 hash for the given parameters.
     * @param user The user's Ethereum address.
     * @param isUnique Boolean flag representing whether the user's status is unique.
     * @return The calculated keccak256 hash.
     */
    function _getMessageHash(
        address user,
        bool isUnique
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(user, isUnique));
    }

    /**
     * @dev Calculates the Ethereum specific prefixed hash of a given message hash.
     * @param _messageHash The original hash of the message data.
     * @return The Ethereum-specific signed version of the input hash.
     */
    function _getEthSignedMessageHash(
        bytes32 _messageHash
    ) internal pure returns (bytes32) {
        /*
        Signature is produced by signing a keccak256 hash with the following format:
        "\x19Ethereum Signed Message\n" + len(msg) + msg
        */
        return
            keccak256(
                abi.encodePacked(
                    "\x19Ethereum Signed Message:\n32",
                    _messageHash
                )
            );
    }

    /**
     * @dev Verifies if a given signature is valid for the specified user and uniqueness.
     * @param user The address of the user to verify.
     * @param isUnique Boolean flag to check along with the user address.
     * @param signature The signature to verify.
     * @return True if the signature is valid, false otherwise.
     */
    function _verify(
        address user,
        bool isUnique,
        bytes memory signature
    ) internal view returns (bool) {
        bytes32 messageHash = _getMessageHash(user, isUnique);
        bytes32 ethSignedMessageHash = _getEthSignedMessageHash(messageHash);

        return _recoverSigner(ethSignedMessageHash, signature) == signer;
    }

    /**
     * @dev Recovers the signer address from a given hash and signature.
     * @param _ethSignedMessageHash The hash of the message that was signed.
     * @param _signature The signature from which to recover the signer address.
     * @return The address of the signer.
     */
    function _recoverSigner(
        bytes32 _ethSignedMessageHash,
        bytes memory _signature
    ) internal pure returns (address) {
        (bytes32 r, bytes32 s, uint8 v) = _splitSignature(_signature);

        return ecrecover(_ethSignedMessageHash, v, r, s);
    }

    /**
     * @dev Splits a signature into its r, s, and v components.
     * @param sig The full ECDSA signature.
     * @return r The 32-byte R component of the signature.
     * @return s The 32-byte S component of the signature.
     * @return v The recovery byte, V.
     */
    function _splitSignature(
        bytes memory sig
    ) internal pure returns (bytes32 r, bytes32 s, uint8 v) {
        require(sig.length == 65, "invalid signature length");
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
    }

    /**
     * @dev Records a vote on a proposal, updating the vote totals and voter status.
     *      This function is called after all preconditions checked by `_commonVotingChecks` are met.
     *
     * @param id The index of the proposal on which to vote.
     * @param support A boolean indicating whether the vote is in support of (true) or against (false) the proposal.
     * @param actualVotes The effective number of votes to record, which may be adjusted for voting type, such as quadratic.
     */
    function _recordVote(uint id, bool support, uint actualVotes) internal {
        if (support) {
            proposals[id].votesFor += actualVotes;
        } else {
            proposals[id].votesAgainst += actualVotes;
        }
        proposals[id].totalVotes += actualVotes;

        voted[id][msg.sender] = true;

        IStaking(stakingAddress).voted(
            msg.sender,
            block.timestamp + voteLockTime
        );
        po.mint(msg.sender);
        emit Voted(id, msg.sender, support, actualVotes);
    }

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
    function _validateInput(
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
    function _validateStakingRequirements(
        IStaking staking,
        address proposer
    ) internal view {
        if (staking.getStakedSci(proposer) < opThreshold)
            revert InsufficientBalance(
                staking.getStakedSci(proposer),
                opThreshold
            );

        if (staking.getProposeLockEnd(proposer) > block.timestamp)
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
    function _determinePaymentDetails(
        uint256 amountUsdc,
        uint256 amountCoin,
        uint256 amountSci,
        bool executable
    )
        internal
        pure
        returns (Payment payment, uint256 amount, uint256 sciAmount)
    {
        if (!executable) return (Payment.None, 0, 0);

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
        // revert("Incorrect payment option");
    }

    /**
     * @dev Stores a new operation proposal in the contract's state and updates staking.
     * @param projectInfo Struct containing detailed information about the project.
     * @param quadraticVoting Boolean indicating if quadratic voting is enabled for this proposal.
     * @param staking The staking contract interface used for updating the proposer's status.
     * @return uint256 The _index where the new proposal is stored.
     *
     * @notice The function increments the operations proposal _index after storing.
     * It also updates the staking contract to reflect the new proposal.
     */
    function _storeProposal(
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

        uint256 currentIndex = _index++;
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
