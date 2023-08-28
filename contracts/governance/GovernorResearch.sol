// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./../staking/Staking.sol";

contract GovernorResearch {

    ///*** ERRORS ***///
    error AlreadyActiveProposal();
    error EmptyOptions();
    error IncorrectBlockNumber();
    error IncorrectOption();
    error IncorrectPhase(ProposalStatus);
    error IncorrectSnapshotIndex();
    error InsufficientBalance(uint256 currentDeposit, uint256 requestedAmount);
    error InsufficientVotingRights(uint256 currentRights, uint256 votesGiven);
    error TokensStillLocked(uint256 voteLockTimeStamp, uint256 currentTimeStamp);
    error ProposalLifeTimePassed();
    error ProposalInexistent();
    error QuorumNotReached();
    error Unauthorized(address user);
    error VoteLock();
    error WrongToken();

    ///*** STRUCTS ***///
    struct Proposal {
        uint256                     startBlockNum;
        uint256                     endTimeStamp;
        ProposalStatus              status; 
        string                      details; 
        uint256                     votesFor;
        uint256                     votesAgainst;
        uint256                     votesAbstain;
        uint256                     totalVotes;        
    }

    ///*** GOVERNANCE PARAMETERS ***///
    uint256 public proposalLifeTime;
    uint256 public quorum;
    uint256 public voteLockTime;

    ///*** STORAGE & MAPPINGS ***///
    address                                         public      stakingAddress;
    uint256                                         private     _proposalIndex;
    address                                         public      po;
    NftLike                                         public      poToken;
    uint8                                           public      poLive;
    mapping(address => uint8)                       public      wards;
    mapping(uint256 => Proposal)                    private     proposals;
    mapping(uint256 => mapping(address => uint8))   private     voted;

    ///*** ENUMERATOR ***///
    enum ProposalStatus {
        Active, Scheduled, Executed, Cancelled 
    }

    enum Vote {
        No, Yes
    }

    ///*** MODIFIER ***///
    modifier dao() {
        if(wards[msg.sender] != 1) revert Unauthorized(msg.sender);
        _;
    }

    /*** EVENTS ***/
    event RelyOn(address indexed _user);
    event Denied(address indexed _user);
    event Proposed(uint256 indexed _id, string _details);
    event Voted(uint256 indexed _id, Vote indexed _vote, uint256 _amount);
    event Scheduled(uint256 indexed _id);
    event Executed(uint256 indexed _id);
    event Cancelled(uint256 indexed _id);


    constructor(
        address stakingAddress_,
        address po_
    ) {
        wards[msg.sender] = 1;
        stakingAddress = stakingAddress_;
        poToken = NftLike(po_);
    }

    /**
     * @dev returns the total amount of staked SCI and DON tokens
     */
    function getTotalStaked() public returns (uint256) {
        IStaking staking = IStaking(stakingAddress);
        return staking.getTotalStaked();
    }

    ///*** EXTERNAL FUNCTIONS ***///

    /**
     * @dev sets the staking address
     */
    function setStakingAddress(address _newStakingAddress) external dao {
        stakingAddress = _newStakingAddress;
    }

    /**
     * @dev sets the participation phase to live
     * @param _status the status of the participation phase, must be 1 to activate
     */
    function setPoPhase(uint8 _status) external dao {
        poLive = _status;
    }

    /**
     * @dev sets the PO token address
     */
    function setPoAddress(address po_) external dao {
        po = po_;
    }

    /**
     * @dev returns if user has voted for a given proposal
     * @param _id the proposal id
     */
    function getVoted(uint256 _id) external view returns (uint8) {
        return voted[_id][msg.sender];
    }

    /**
     * @dev returns the proposal index 
     */
    function getProposalIndex() external view returns (uint256) {
        return _proposalIndex;
    }

    /**
     * @dev returns proposal information
     * @param _id the index of the proposal of interest
     */
    function getProposalInfo(uint256 _id) external view returns (
        uint256,
        uint256,
        ProposalStatus,
        string memory,
        uint256,
        uint256,
        uint256
    ) {
        if(_id > _proposalIndex || _id < 1) revert ProposalInexistent();
        return (
            proposals[_id].startBlockNum,
            proposals[_id].endTimeStamp,
            proposals[_id].status,
            proposals[_id].details,
            proposals[_id].votesFor,
            proposals[_id].votesAgainst,
            proposals[_id].totalVotes
        );
    }

    /**
     * @dev adds a gov
     * @param _user the user that is eligible to become a gov
     */
    function addGov(
        address _user
        ) external dao {
        wards[_user] = 1;
        emit RelyOn(_user);
    }

    /**
     * @dev removes a gov
     * @param _user the user that will be removed as a gov
     */
    function removeGov(
        address _user
        ) external dao {
        if(wards[_user] != 1) {
            revert Unauthorized(msg.sender);
        }
        delete wards[_user];
        emit Denied(_user);
    }

    /**
     * @dev sets the governance parameters given data
     * @param _param the parameter of interest
     * @param _data the data assigned to the parameter
     */
    function govParams(
        bytes32 _param, 
        uint256 _data
        ) external dao {
        if(_param == "proposalLifeTime") proposalLifeTime = _data;
        if(_param == "quorum") quorum = _data;                     
        if(_param == "voteLockTime") voteLockTime = _data;          
    }


    /**
     * @dev creates a proposal with three different research projects
     *      at least one option needs to be proposed
     * @param _proposalDetails #1 of the three proposed research projects

     */
    function propose(
            string memory _proposalDetails
        ) external dao returns (uint256) {

        //Initiate and specify each parameter of the proposal
        Proposal memory proposal = Proposal(
            block.number,
            block.timestamp + proposalLifeTime,
            ProposalStatus.Active,
            _proposalDetails,
            0,
            0,
            0,
            0
        );

        //increment proposal index
        _proposalIndex += 1;

        //store proposal at the given index
        proposals[_proposalIndex] = proposal;

        //emit Proposed event
        emit Proposed(_proposalIndex, _proposalDetails);

        return _proposalIndex;
    }

    /**
     * @dev vote for an of option of a given proposal 
     *      using the rights from the most recent snapshot
     * @param _id the index of the proposal
     * @param _user the address of the voting users
     * @param _votes the amount of votes given to the chosen research project
     */
    function vote(
        uint256 _id, 
        address _user,  
        Vote _vote, 
        uint256 _votes) external {
        
        if (msg.sender != _user) revert Unauthorized(msg.sender);

        IStaking staking = IStaking(stakingAddress);
        
        //check if proposal exists
        if(_id > _proposalIndex || _id < 1) revert ProposalInexistent();
        
        //check if proposal is still active
        if(proposals[_id].status != ProposalStatus.Active) revert IncorrectPhase(proposals[_id].status); 
        
        //check if proposal life time has not passed
        if(block.timestamp > proposals[_id].endTimeStamp) revert ProposalLifeTimePassed();

        //get latest voting rights
        uint256 _votingRights = staking.getLatestUserRights(_user);

        //check if user has enough voting rights
        if(_votes > _votingRights) revert InsufficientVotingRights(_votingRights, _votes);

        //check if user already voted for this proposal
        if(voted[_id][_user] == 1) revert VoteLock();
        
        //vote for, against or abstain
        if(_vote == Vote.Yes) {
            proposals[_id].votesFor += _votes;

        } else if(_vote == Vote.No) {
            proposals[_id].votesAgainst += _votes;
        }

        //add to the total votes
        proposals[_id].totalVotes += _votes;

        //set user as voted for proposal
        voted[_id][_user] = 1;

        //mint a participation token if live
        if (poLive == 1) {
            poToken.mint(_user);
        }
        staking.voted(_user, block.timestamp + voteLockTime);

        //emit Voted events
        emit Voted(_id, _vote, _votes);
    }

    /**
     * @dev finalizes the voting phase
     * @param _id the index of the proposal of interest
     */
    function finalizeVoting(
        uint256 _id
        ) external dao {
        if(_id > _proposalIndex || _id < 1) revert ProposalInexistent();
        if (proposals[_id].totalVotes < quorum) revert QuorumNotReached();
        if (proposals[_id].status != ProposalStatus.Active) revert IncorrectPhase(proposals[_id].status);
        proposals[_id].status = ProposalStatus.Scheduled;
        emit Scheduled(_id);
    }

    /**
     * @dev executes the proposal
     * @param _id the index of the proposal of interest
     */
    function executeProposal(
        uint256 _id
        ) external dao {
        if(_id > _proposalIndex || _id < 1) revert ProposalInexistent();
        if (proposals[_id].status != ProposalStatus.Scheduled) revert IncorrectPhase(proposals[_id].status);
        proposals[_id].status = ProposalStatus.Executed;
        emit Executed(_id);
    }
    
    /**
     * @dev cancels the proposal
     * @param _id the index of the proposal of interest
     */
    function cancelProposal(
        uint256 _id
        ) external dao {
        if(_id > _proposalIndex || _id < 1) revert ProposalInexistent();
        proposals[_id].status = ProposalStatus.Cancelled;
        emit Cancelled(_id);
    }
}