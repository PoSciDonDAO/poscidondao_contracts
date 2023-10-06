// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./../interface/IParticipation.sol";
import "./../interface/IStaking.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import "../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";

contract Governor is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    ///*** ERRORS ***///
    error AlreadyActiveProposal();
    error EmptyOptions();
    error IncorrectEthValue();
    error IncorrectBlockNumber();
    error IncorrectOption();
    error IncorrectCurrency();
    error IncorrectPhase(Proposalstatus);
    error IncorrectSnapshotIndex();
    error InsufficientBalance(uint256 balance, uint256 requiredBalance);
    error InsufficientVotingRights(uint256 currentRights, uint256 votesGiven);
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
        Proposalstatus status;
        ProjectInfo details;
        uint256 votesFor;
        uint256 votesAgainst;
        uint256 totalVotes;
    }

    struct ProjectInfo {
        string info; //IPFS link
        address receivingWallet; //wallet address to send funds to
        uint256 amount; //amount of funds
    }

    ///*** TOKEN ***///
    IParticipation private _po;

    ///*** GOVERNANCE PARAMETERS ***///
    uint256 public proposalLifeTime;
    uint256 public quorum;
    uint256 public voteLockTime;

    ///*** STORAGE & MAPPINGS ***///
    address public stakingAddress;
    address public treasuryWallet;
    address public donationWallet;
    address public usdc;
    uint8 public poLive;
    uint256 public ddThreshold;
    uint256 public memberThreshold;
    uint256 private _researchProposalIndex;
    uint256 private _operationsProposalIndex;
    bytes32 public constant DUE_DILIGENCE_ROLE =
        keccak256("DUE_DILIGENCE_ROLE");
    mapping(uint256 => Proposal) private researchProposals;
    mapping(uint256 => Proposal) private operationsProposals;
    mapping(uint256 => mapping(address => uint8)) private votedResearch;
    mapping(uint256 => mapping(address => uint8)) private votedOperations;

    ///*** ENUMERATORS ***///
    enum Proposalstatus {
        Active,
        Scheduled,
        Executed,
        Cancelled
    }

    /*** EVENTS ***/
    event Proposed(uint256 indexed id, ProjectInfo details);
    event Voted(uint256 indexed id, bool indexed support, uint256 amount);
    event Scheduled(uint256 indexed id, bool indexed research);
    event Executed(uint256 indexed id, bool indexed donated, uint256 amount);
    event Cancelled(uint256 indexed id);

    constructor(
        address stakingAddress_,
        address treasuryWallet_,
        address donationWallet_,
        address usdc_
    ) {
        stakingAddress = stakingAddress_;
        treasuryWallet = treasuryWallet_;
        donationWallet = donationWallet_;
        usdc = usdc_;

        ddThreshold = 1000e18;
        memberThreshold = 100e18;

        _setupRole(DEFAULT_ADMIN_ROLE, treasuryWallet_);
        _setupRole(DEFAULT_ADMIN_ROLE, donationWallet_);
        _setupRole(DUE_DILIGENCE_ROLE, _msgSender());
        _setRoleAdmin(DUE_DILIGENCE_ROLE, DEFAULT_ADMIN_ROLE);
    }

    ///*** EXTERNAL FUNCTIONS ***///

    /**
     * @dev sets the threshold for DD and non-DD members to propose
     */
    function setStakedSciThreshold(
        uint256 thresholdDD,
        uint256 thresholdMember
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        ddThreshold = thresholdDD;
        memberThreshold = thresholdMember;
    }

    /**
     * @dev allows the DAO to add a member to the Due Diligence Crew
     * @param member the address of the member that will be added to the DD crew
     */
    function addDueDiligenceMember(
        address member
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IStaking staking = IStaking(stakingAddress);
        if (staking.getStakedSci(member) > memberThreshold) {
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
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        revokeRole(DUE_DILIGENCE_ROLE, member);
    }

    /**
     * @dev sets the treasury wallet address
     */
    function setTreasuryWallet(
        address newTreasuryWallet
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        treasuryWallet = newTreasuryWallet;
    }

    /**
     * @dev sets the donation wallet address
     */
    function setDonationWallet(
        address newDonationWallet
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        donationWallet = newDonationWallet;
    }

    /**
     * @dev sets the staking address
     */
    function setStakingAddress(
        address _newStakingAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        stakingAddress = _newStakingAddress;
    }

    /**
     * @dev sets the participation phase to live
     * @param _status the status of the participation phase, must be 1 to activate
     */
    function setPoPhase(uint8 _status) external onlyRole(DEFAULT_ADMIN_ROLE) {
        poLive = _status;
    }

    /**
     * @dev sets the PO token address and interface
     */
    function setPoToken(address po_) external onlyRole(DEFAULT_ADMIN_ROLE) {
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
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_param == "proposalLifeTime") proposalLifeTime = _data;
        if (_param == "quorum") quorum = _data;
        if (_param == "voteLockTime") voteLockTime = _data;
    }

    /**
     * @dev proposes a research project in need of funding
     *      at least one option needs to be proposed
     * @param info ipfs hash of project proposal
     * @param wallet the address of the research group receiving funds if proposal passed
     * @param amount the amount of funding in usdc; should be 0 if _amountEth > 0
     */
    function proposeResearch(
        string memory info,
        address wallet,
        uint256 amount
    ) external onlyRole(DUE_DILIGENCE_ROLE) returns (uint256) {

        IStaking staking = IStaking(stakingAddress);

        if (staking.getStakedSci(_msgSender()) < ddThreshold) 
            revert InsufficientBalance(staking.getStakedSci(_msgSender()), ddThreshold);

        ProjectInfo memory projectInfo = ProjectInfo(
            info,
            wallet,
            amount
        );
        //Initiate and specify each parameter of the proposal
        Proposal memory proposal = Proposal(
            block.number,
            block.timestamp + proposalLifeTime,
            Proposalstatus.Active,
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
     * @dev proposes a change in DAO operations
     *      at least one option needs to be proposed
     * @param info ipfs hash of project proposal
     * @param wallet the address of the research group receiving funds if proposal passed
     * @param amount the amount of funding
     */
    function proposeOperation(
        string memory info,
        address wallet,
        uint256 amount
    ) external returns (uint256) {

        IStaking staking = IStaking(stakingAddress);

        if (staking.getStakedSci(_msgSender()) < memberThreshold) 
            revert InsufficientBalance(staking.getStakedSci(_msgSender()), memberThreshold);

        ProjectInfo memory projectInfo = ProjectInfo(
            info,
            wallet,
            amount
        );
        //Initiate and specify each parameter of the proposal
        Proposal memory proposal = Proposal(
            block.number,
            block.timestamp + proposalLifeTime,
            Proposalstatus.Active,
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
     */
    function voteOnResearch(
        uint256 id,
        address user,
        bool support
    ) external onlyRole(DUE_DILIGENCE_ROLE) {
        if (msg.sender != user) revert Unauthorized(msg.sender);

        IStaking staking = IStaking(stakingAddress);

        if (staking.getStakedSci(user) < memberThreshold)
            revert InsufficientBalance(staking.getStakedSci(user), memberThreshold);

        //check if proposal exists
        if (id > _researchProposalIndex || id < 1) revert ProposalInexistent();

        //check if proposal is still active
        if (researchProposals[id].status != Proposalstatus.Active)
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
        staking.voted(user, block.timestamp + voteLockTime);

        //emit Voted events
        emit Voted(id, support, 1);
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
    ) external {
        if (msg.sender != user) revert Unauthorized(msg.sender);

        IStaking staking = IStaking(stakingAddress);

        //check if proposal exists
        if (id > _operationsProposalIndex || id < 1)
            revert ProposalInexistent();

        //check if proposal is still active
        if (operationsProposals[id].status != Proposalstatus.Active)
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

        //vote for, against or abstain
        if (support) {
            operationsProposals[id].votesFor += votes;
        } else {
            operationsProposals[id].votesAgainst += votes;
        }

        //add to the total votes
        operationsProposals[id].totalVotes += votes;

        //set user as voted for proposal
        votedOperations[id][user] = 1;

        //mint a participation token if live
        if (poLive == 1) {
            _po.mint(user);
        }

        //set the lock time in the staking contract
        staking.voted(user, block.timestamp + voteLockTime);

        //emit Voted events
        emit Voted(id, support, votes);
    }

    /**
     * @dev finalizes the voting phase for a research proposal
     * @param id the index of the proposal of interest
     */
    function finalizeVotingResearchProposal(
        uint256 id
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (id > _researchProposalIndex || id < 1) revert ProposalInexistent();

        if (researchProposals[id].status != Proposalstatus.Active)
            revert IncorrectPhase(researchProposals[id].status);

        if (block.timestamp < researchProposals[id].endTimeStamp)
            revert ProposalOngoing(
                block.timestamp,
                researchProposals[id].endTimeStamp
            );

        researchProposals[id].status = Proposalstatus.Scheduled;

        emit Scheduled(id, true);
    }

    /**
     * @dev finalizes the voting phase for a research proposal
     * @param id the index of the proposal of interest
     */
    function finalizeVotingOperationsProposal(
        uint256 id
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (id > _operationsProposalIndex || id < 1)
            revert ProposalInexistent();

        if (operationsProposals[id].totalVotes < quorum)
            revert QuorumNotReached();

        if (operationsProposals[id].status != Proposalstatus.Active)
            revert IncorrectPhase(operationsProposals[id].status);

        if (block.timestamp < operationsProposals[id].endTimeStamp)
            revert ProposalOngoing(
                block.timestamp,
                operationsProposals[id].endTimeStamp
            );

        operationsProposals[id].status = Proposalstatus.Scheduled;

        emit Scheduled(id, false);
    }

    /**
     * @dev executes the proposal using USDC
     * @param id the index of the proposal of interest
     * @param donated set to true if funds are derived from the donation wallet
     * @param token set to true if USDC is sent to the receiving wallet
     *              set to false if a coin is sent to the receiving wallet
     */
    function executeResearchProposal(
        uint256 id,
        bool donated,
        bool token
    ) external payable nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        //check if proposal exists
        if (id > _researchProposalIndex || id < 1) revert ProposalInexistent();
        //check if proposal has finalized voting
        if (researchProposals[id].status != Proposalstatus.Scheduled)
            revert IncorrectPhase(researchProposals[id].status);

        address receivingWallet = researchProposals[id].details.receivingWallet;

        uint256 amount = researchProposals[id].details.amount;

        if (donated) {
            if (token) {
                IERC20(usdc).safeTransferFrom(
                    donationWallet,
                    receivingWallet,
                    amount
                );
            } else {
                if (_msgSender() != donationWallet)
                    revert Unauthorized(_msgSender());
                if (msg.value == 0 || msg.value != amount)
                    revert IncorrectEthValue();
                (bool sent, ) = payable(receivingWallet).call{value: msg.value}(
                    ""
                );
                require(sent, "Failed to transfer");
            }
        } else {
            if (token) {
                IERC20(usdc).safeTransferFrom(
                    treasuryWallet,
                    receivingWallet,
                    amount
                );
            } else {
                if (_msgSender() != treasuryWallet)
                    revert Unauthorized(_msgSender());
                if (msg.value == 0 || msg.value != amount)
                    revert IncorrectEthValue();
                (bool sent, ) = payable(receivingWallet).call{value: msg.value}(
                    ""
                );
                require(sent, "Failed to transfer");
            }

            researchProposals[id].status = Proposalstatus.Executed;

            emit Executed(id, donated, amount);
        }
    }

    /**
     * @dev executes the proposal using USDC
     * @param id the index of the proposal of interest
     * @param donated set to true if funds are derived from the donation wallet
     * @param token set to true if USDC is sent to the receiving wallet
     *              set to false if a coin is sent to the receiving wallet
     */
    function executeOperationsProposal(
        uint256 id,
        bool donated,
        bool token
    ) external payable nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        //check if proposal exists
        if (id > _operationsProposalIndex || id < 1)
            revert ProposalInexistent();
        //check if proposal has finalized voting
        if (operationsProposals[id].status != Proposalstatus.Scheduled)
            revert IncorrectPhase(operationsProposals[id].status);

        address receivingWallet = operationsProposals[id]
            .details
            .receivingWallet;

        uint256 amount = operationsProposals[id].details.amount;

        if (donated) {
            if (token) {
                IERC20(usdc).safeTransferFrom(
                    donationWallet,
                    receivingWallet,
                    amount
                );
            } else {
                if (_msgSender() != donationWallet)
                    revert Unauthorized(_msgSender());
                if (msg.value == 0 || msg.value != amount)
                    revert IncorrectEthValue();
                (bool sent, ) = payable(receivingWallet).call{value: msg.value}(
                    ""
                );
                require(sent, "Failed to transfer");
            }
        } else {
            if (token) {
                IERC20(usdc).safeTransferFrom(
                    treasuryWallet,
                    receivingWallet,
                    amount
                );
            } else {
                if (_msgSender() != treasuryWallet)
                    revert Unauthorized(_msgSender());
                if (msg.value == 0 || msg.value != amount)
                    revert IncorrectEthValue();
                (bool sent, ) = payable(receivingWallet).call{value: msg.value}(
                    ""
                );
                require(sent, "Failed to transfer");
            }

            operationsProposals[id].status = Proposalstatus.Executed;

            emit Executed(id, donated, amount);
        }
    }

    /**
     * @dev cancels the proposal
     * @param id the index of the proposal of interest
     */
    function cancelResearchProposal(
        uint256 id
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (id > _researchProposalIndex || id < 1) revert ProposalInexistent();

        if (researchProposals[id].status != Proposalstatus.Active)
            revert IncorrectPhase(researchProposals[id].status);

        researchProposals[id].status = Proposalstatus.Cancelled;

        emit Cancelled(id);
    }

    /**
     * @dev cancels the proposal
     * @param id the index of the proposal of interest
     */
    function cancelOperationsProposal(
        uint256 id
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (id > _operationsProposalIndex || id < 1)
            revert ProposalInexistent();

        if (operationsProposals[id].status != Proposalstatus.Active)
            revert IncorrectPhase(operationsProposals[id].status);

        operationsProposals[id].status = Proposalstatus.Cancelled;

        emit Cancelled(id);
    }

    /**
     * @dev returns if user has voted for a given proposal
     * @param id the proposal id
     */
    function getVotedResearch(uint256 id) external view returns (uint8) {
        return votedResearch[id][msg.sender];
    }

    /**
     * @dev returns if user has voted for a given proposal
     * @param id the proposal id
     */
    function getVotedOperations(uint256 id) external view returns (uint8) {
        return votedOperations[id][msg.sender];
    }

    /**
     * @dev returns the proposal index
     */
    function getResearchProposalIndex() external view returns (uint256) {
        return _researchProposalIndex;
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
    function getResearchProposalInfo(
        uint256 id
    )
        external
        view
        returns (uint256, uint256, Proposalstatus, uint256, uint256, uint256)
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
     * @dev returns proposal information
     * @param id the index of the proposal of interest
     */
    function getOperationsProposalInfo(
        uint256 id
    )
        external
        view
        returns (uint256, uint256, Proposalstatus, uint256, uint256, uint256)
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

    function getProposalResearchProjectInfo(
        uint256 id
    ) external view returns (string memory, address, uint256) {
        if (id > _operationsProposalIndex || id < 1)
            revert ProposalInexistent();
        return (
            operationsProposals[id].details.info,
            operationsProposals[id].details.receivingWallet,
            operationsProposals[id].details.amount
        );
    }
}
