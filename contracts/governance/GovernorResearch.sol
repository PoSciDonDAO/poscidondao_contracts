// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./../interface/IParticipation.sol";
import "./../interface/IStaking.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

contract GovernorResearch {
    using SafeERC20 for IERC20;

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
        ProjectInfo                 details; 
        uint256                     votesFor;
        uint256                     votesAgainst;
        uint256                     totalVotes;        
    }

    struct ProjectInfo {
        string                      info; //IPFS link
        address                     researchWallet; //wallet address to send funds to
        uint256                     amountUsdc; //amount of funds in Usdc
        uint256                     amountEth; //amount of funds in Eth
    }

    ///*** GOVERNANCE PARAMETERS ***///
    uint256 public proposalLifeTime;
    uint256 public quorum;
    uint256 public voteLockTime;

    ///*** STORAGE & MAPPINGS ***///
    address                                         public      stakingAddress;
    address                                         public      treasuryWallet;
    address                                         public      usdc;
    uint256                                         private     _proposalIndex;
    address                                         public      po;
    IParticipation                                  public      poToken;
    uint8                                           public      poLive;
    mapping(address => uint8)                       public      wards;
    mapping(uint256 => Proposal)                    private     proposals;
    mapping(uint256 => mapping(address => uint8))   private     voted;

    ///*** ENUMERATORS ***///
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
    event Proposed(uint256 indexed id, ProjectInfo _details);
    event Voted(uint256 indexed id, Vote indexed _vote, uint256 _amount);
    event Scheduled(uint256 indexed id);
    event Executed(uint256 indexed id);
    event Cancelled(uint256 indexed id);


    constructor(
        address stakingAddress_,
        address treasuryWallet_,
        address usdc_
    ) {
        stakingAddress = stakingAddress_;
        treasuryWallet = treasuryWallet_;
        usdc = usdc_;


        wards[msg.sender] = 1;
        wards[treasuryWallet_] = 1;
        emit RelyOn(msg.sender);
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
     * @dev sets the PO token address and interface
     */
    function setPoToken(address po_) external dao {
        po = po_;
        poToken = IParticipation(po_);
    }

    /**
     * @dev adds a gov
     * @param _user the user that is eligible to become a gov
     */
    function addWard(address _user) external dao {
        wards[_user] = 1;
        emit RelyOn(_user);
    }

    /**
     * @dev removes a gov
     * @param _user the user that will be removed as a gov
     */
    function removeWard(address _user) external dao {
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
     * @param _info ipfs hash of project proposal
     * @param _wallet the address of the research group receiving funds if proposal passed
     * @param _amountUsdc the amount of funding in usdc; should be 0 if _amountEth > 0
     * @param _amountEth the amount of funding in Eth; should be 0 if _amountUsdc > 0
     */
    function propose(
            string memory _info,
            address _wallet,
            uint256 _amountUsdc,
            uint256 _amountEth
        ) external dao returns (uint256) {
        ProjectInfo memory _projectInfo = ProjectInfo(
            _info,
            _wallet,
            _amountUsdc,
            _amountEth
        );
        //Initiate and specify each parameter of the proposal
        Proposal memory _proposal = Proposal(
            block.number,
            block.timestamp + proposalLifeTime,
            ProposalStatus.Active,
            _projectInfo,
            0,
            0,
            0
        );

        //increment proposal index
        _proposalIndex += 1;

        //store proposal at the given index
        proposals[_proposalIndex] = _proposal;

        //emit Proposed event
        emit Proposed(_proposalIndex, _projectInfo);

        return _proposalIndex;
    }

    /**
     * @dev vote for an of option of a given proposal 
     *      using the rights from the most recent snapshot
     * @param id the index of the proposal
     * @param _user the address of the voting users
     * @param _votes the amount of votes given to the chosen research project
     */
    function vote(
        uint256 id, 
        address _user,  
        Vote _vote, 
        uint256 _votes) external {
        
        if (msg.sender != _user) revert Unauthorized(msg.sender);

        IStaking staking = IStaking(stakingAddress);
        
        //check if proposal exists
        if(id > _proposalIndex || id < 1) revert ProposalInexistent();
        
        //check if proposal is still active
        if(proposals[id].status != ProposalStatus.Active) revert IncorrectPhase(proposals[id].status); 
        
        //check if proposal life time has not passed
        if(block.timestamp > proposals[id].endTimeStamp) revert ProposalLifeTimePassed();

        //get latest voting rights
        uint256 _votingRights = staking.getLatestUserRights(_user);

        //check if user has enough voting rights
        if(_votes > _votingRights) revert InsufficientVotingRights(_votingRights, _votes);

        //check if user already voted for this proposal
        if(voted[id][_user] == 1) revert VoteLock();
        
        //vote for, against or abstain
        if(_vote == Vote.Yes) {
            proposals[id].votesFor += _votes;

        } else if(_vote == Vote.No) {
            proposals[id].votesAgainst += _votes;
        }

        //add to the total votes
        proposals[id].totalVotes += _votes;

        //set user as voted for proposal
        voted[id][_user] = 1;

        //mint a participation token if live
        if (poLive == 1) {
            poToken.mint(_user);
        }
        staking.voted(_user, block.timestamp + voteLockTime);

        //emit Voted events
        emit Voted(id, _vote, _votes);
    }

    /**
     * @dev finalizes the voting phase
     * @param id the index of the proposal of interest
     */
    function finalizeVoting(uint256 id) external dao {
        if(id > _proposalIndex || id < 1) revert ProposalInexistent();
        if(proposals[id].totalVotes < quorum) revert QuorumNotReached();
        if(proposals[id].status != ProposalStatus.Active) revert IncorrectPhase(proposals[id].status);
        proposals[id].status = ProposalStatus.Scheduled;
        emit Scheduled(id);
    }

    /**
     * @dev executes the proposal
     * @param id the index of the proposal of interest
     */
    function executeProposal(uint256 id) external payable dao {

        if(id > _proposalIndex || id < 1) revert ProposalInexistent();

        if(proposals[id].status != ProposalStatus.Scheduled) revert IncorrectPhase(proposals[id].status);

        if(proposals[id].details.amountUsdc > 0) {
            IERC20(usdc).safeTransferFrom(treasuryWallet, proposals[id].details.researchWallet, proposals[id].details.amountUsdc);
        
        } else if(proposals[id].details.amountEth > 0) {
            address _researchWallet = proposals[id].details.researchWallet;
            (bool sent,) = _researchWallet.call{value: proposals[id].details.amountEth}("");
            require(sent);
        }
        
        proposals[id].status = ProposalStatus.Executed;
        
        emit Executed(id);
    }
    
    /**
     * @dev cancels the proposal
     * @param id the index of the proposal of interest
     */
    function cancelProposal(uint256 id) external dao {
        if(id > _proposalIndex || id < 1) revert ProposalInexistent();
        proposals[id].status = ProposalStatus.Cancelled;
        emit Cancelled(id);
    }
    
    /**
     * @dev returns if user has voted for a given proposal
     * @param id the proposal id
     */
    function getVoted(uint256 id) external view returns (uint8) {
        return voted[id][msg.sender];
    }

    /**
     * @dev returns the proposal index 
     */
    function getProposalIndex() external view returns (uint256) {
        return _proposalIndex;
    }

    /**
     * @dev returns proposal information
     * @param id the index of the proposal of interest
     */
    function getProposalInfo(uint256 id) external view returns (
        uint256,
        uint256,
        ProposalStatus,
        uint256,
        uint256,
        uint256
    ) {
        if(id > _proposalIndex || id < 1) revert ProposalInexistent();
        return (
            proposals[id].startBlockNum,
            proposals[id].endTimeStamp,
            proposals[id].status,
            proposals[id].votesFor,
            proposals[id].votesAgainst,
            proposals[id].totalVotes
        );
    }

    function getProposalProjectInfo(uint256 id) external view returns (
        string memory,
        address,
        uint256,
        uint256
    ) {
        if(id > _proposalIndex || id < 1) revert ProposalInexistent();
        return (
            proposals[id].details.info,
            proposals[id].details.researchWallet,
            proposals[id].details.amountUsdc,
            proposals[id].details.amountEth
        );
    }
}