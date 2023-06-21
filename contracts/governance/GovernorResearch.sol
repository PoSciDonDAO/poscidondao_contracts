// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface AccountBoundTokenLike {
    function push(address, address, uint256) external returns (bool);
    function pull(address, address, uint256) external returns (bool);
}

interface TokenLike {
    function transferFrom(address, address, uint256) external;
    function transfer(address, uint256) external;
}

interface SemiFungibleTokenLike {
    function mint(address) external;
}

contract GovernorResearch {

    ///*** ERRORS ***///
    error AlreadyActiveProposal();
    error EmptyOptions();
    error IncorrectBlockNumber();
    error IncorrectOption();
    error IncorrectPhase(ProposalStatus);
    error IncorrectSnapshot();
    error IncorrectSnapshotIndex();
    error InsufficientBalance(uint256 currentDeposit, uint256 requestedAmount);
    error InsufficientRights(uint256 currentRights, uint256 votesGiven);
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
        bytes32                     option1;
        bytes32                     option2;
        bytes32                     option3;
        uint256                     votesOpt1;
        uint256                     votesOpt2;
        uint256                     votesOpt3;
        uint256                     totalVotes;        
    }

    struct User {
        uint256                      depositsSci;   //SCI deposited
        uint256                      depositsDon;   //DON deposited
        uint256                      rights;        //Voting rights
        uint256                      voteLockTime;  //Time before tokens can be unlocked during voting
        uint256                      amtSnapshots;  //Amount of snapshots
        mapping(uint256 => Snapshot) snapshots;     //Index => snapshot
    } 

    struct Snapshot {
        uint256 atBlock;
        uint256 rights;
    }

    ///*** GOVERNANCE PARAMETERS ***///
    uint256 public proposalLifeTime;
    uint256 public quorum;
    uint256 public voteLockTime;

    ///*** TOKENS ***//
    address                 private             po;
    address                 private immutable   sci;
    address                 private immutable   don;
    SemiFungibleTokenLike   public              poToken;
    TokenLike               public  immutable   sciToken;
    AccountBoundTokenLike   public  immutable   donToken;

    ///*** STORAGE & MAPPINGS ***///
    uint256                                         private     _proposalIndex;
    uint256                                         private     _totStaked;
    uint8                                           public      poLive;
    mapping(address => uint8)                       public      govs;
    mapping(address => User)                        public      users;
    mapping(uint256 => Proposal)                    public      proposals;
    mapping(uint256 => mapping(address => uint8))   private     voted;

    ///*** ENUMERATOR ***///
    enum ProposalStatus {
        active, scheduled, executed, cancelled 
    }

    ///*** MODIFIER ***///
    modifier dao() {
        if(govs[msg.sender] != 1) revert Unauthorized(msg.sender);
        _;
    }

    /*** EVENTS ***/
    event RelyOn(address indexed user);
    event Denied(address indexed user);
    event Locked(address indexed user, address indexed gov, uint256 deposit, uint256 votes);
    event Freed(address indexed gov, address indexed user, uint256 amount, uint256 remainingVotes);
    event Proposed(uint256 indexed id, bytes32 option1, bytes32 option2, bytes32 option3);
    event Voted(uint256 indexed id, uint256 snapshotIndex, bytes32 option, uint256 amount);
    event Scheduled(uint256 indexed id);
    event Executed(uint256 indexed id);
    event Cancelled(uint256 indexed id);


    constructor(
        address govSci_,
        address govDon_
    ) {
        sciToken      = TokenLike(govSci_);
        donToken      = AccountBoundTokenLike(govDon_);

        sci = govSci_;
        don = govDon_;

        govs[msg.sender] = 1;
    }

    ///*** INTERNAL FUNCTIONS ***///
    /**
     * @dev a snaphshot of the current voting rights of a given user
     * @param _user the address that is being snapshotted
     */
    function _snapshot(
        address _user
        ) internal {
        uint256 index = users[_user].amtSnapshots;
        if (index > 0 && users[_user].snapshots[index].atBlock == block.number) {
            users[_user].snapshots[index].rights = users[_user].rights;
        } else {
            index += 1;
            users[_user].amtSnapshots += index;
            users[_user].snapshots[index] = Snapshot(block.number, users[_user].rights);
        }
    }

    /**
     * @dev Return the voting rights of a user at a certain snapshot
     * @param _user the user address 
     * @param _snapshotIndex the index of the snapshots the user has
     * @param _blockNum the highest block.number at which the user rights will be retrieved
     */
    function _getUserRights(
        address _user, 
        uint256 _snapshotIndex, 
        uint256 _blockNum
        ) public view returns (uint256) {
        uint256 index = users[_user].amtSnapshots;
        if (_snapshotIndex > index) revert IncorrectSnapshotIndex();
        Snapshot memory snapshot = users[_user].snapshots[_snapshotIndex];
        if (snapshot.atBlock > _blockNum) revert IncorrectBlockNumber();
        return snapshot.rights;
    }

    /**
     * @dev calculate the votes for users that have donated e.g. amount * 12/10  
     * @param _amount of deposited DON tokens that will be multiplied with a/b
     * @param _n numerator of the ratio
     * @param _d denominator of the ratio
     */
    function _calcVotes(
        uint256 _amount, 
        uint256 _n, 
        uint256 _d
        ) internal pure returns (uint256 votingPower) {
        return votingPower = _amount * _n / _d;
    }

    ///*** EXTERNAL FUNCTIONS ***///

    /**
     * @dev sets the PO token address and interface
     * @param _poToken the address of the participation token
     */
    function setPoToken(
        address _poToken
        ) external dao {
        po = _poToken;
        poToken = SemiFungibleTokenLike(_poToken);
    }

    /**
     * @dev sets the participation phase to live
     * @param _status the status of the participation phase, must be 1 to activate
     */
    function setPoPhase(
        uint8 _status
        ) external dao {
        poLive = _status;
    }

    /**
     * @dev returns if user has voted for a given proposal
     * @param _id the proposal id
     */
    function getDidVote(
        uint256 _id
        ) external view returns (uint8) {
        return voted[_id][msg.sender];
    }

    /**
     * @dev returns the proposal index 
     */
    function getProposalIndex() external view returns (uint256) {
        return _proposalIndex;
    }

    /**
     * @dev returns the PO token address
     */
    function getPoToken() external view returns (address) {
        return po;
    }

    /**
     * @dev returns the SCI token address
     */
    function getSciToken() external view returns (address) {
        return sci;
    }

    /**
     * @dev returns the DON token address
     */
    function getDonToken() external view returns (address) {
        return don;
    }

    /**
     * @dev returns the total staked 
     */
    function getTotalStaked() external view returns (uint256) {
        return _totStaked;
    }

    /**
     * @dev adds a gov
     * @param _user the user that is eligible to become a gov
     */
    function addGov(
        address _user
        ) external dao {
        govs[_user] = 1;
        emit RelyOn(_user);
    }

    /**
     * @dev removes a gov
     * @param _user the user that will be removed as a gov
     */
    function removeGov(
        address _user
        ) external dao {
        if(govs[_user] != 1) {
            revert Unauthorized(msg.sender);
        }
        delete govs[_user];
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
     * @dev locks a given amount of SCI or DON tokens
     * @param _src the address of the token needs to be locked: SCI or DON
     * @param _user the user that wants to lock tokens
     * @param _amount the amount of tokens that will be locked
     */
    function lock(
        address _src, 
        address _user, 
        uint256 _amount
        ) external {
        if (_src == don) {
            
            //Retrieve DON tokens from wallet
            donToken.push(_user, address(this), _amount);

            //add to total staked amount
            _totStaked += _amount;

            //Adds amount of deposited DON tokens
            users[_user].depositsDon += _amount;

            //DON holders get 20% more votes per locked token
            uint256 _votes = _calcVotes(_amount, 12, 10);

            //calculated votes are added as voting rights
            users[_user].rights = _votes;

            //snapshot of voting rights and 
            _snapshot(_user);

            //emit event
            emit Locked(don, _user, _amount, _votes);
            
        } else if (_src == sci) {
            //Retrieve SCI tokens from wallet
            sciToken.transferFrom(_user, address(this), _amount);

            //add to total staked amount
            _totStaked += _amount;

            //Adds amount of deposited SCI tokens
            users[_user].depositsSci += _amount;

            //in this case the amount deposited in SCI tokens is equal to voting rights
            users[_user].rights += _amount;

            //snapshot of the recent deposit
            _snapshot(_user);

            emit Locked(sci, _user, _amount, _amount);

        } else {
            //Revert if the wrong token is chosen
            revert WrongToken();
        }
    }
    
    /**
     * @dev frees locked tokens after voteLockTime has passed
     * @param _src the address of the token that will be freed
     * @param _user the user's address holding SCI or DON tokens
     * @param _amount the amount of tokens that will be freed
     */
    function free(
        address _src, 
        address _user, 
        uint256 _amount
        ) external {
        if(users[_user].voteLockTime > block.timestamp) revert TokensStillLocked(users[_user].voteLockTime, block.timestamp);

        if (_src == don) {
            //check if amount is lower than deposited DON tokens 
            if(users[_user].depositsDon < _amount) revert InsufficientBalance(users[_user].depositsDon, _amount);
            
            //pulls DON tokens from gov to user's wallet
            donToken.pull(address(this), _user, _amount);
            
            //update total staked
            _totStaked -= _amount;

            //Removes the amount of deposited DON tokens
            users[_user].depositsDon -= _amount;

            //recalculates the votes based on the remaining deposited amount
            uint256 _votes = _calcVotes(users[_user].depositsDon, 12, 10);

            //add new amount of votes as rights
            users[_user].rights = _votes;

            //make a new snapshot
            _snapshot(_user);

            //emit event
            emit Freed(don, _user, _amount, _votes);

        } else if (_src == sci) {
            //check if amount is lower than deposited SCI tokens 
            if(users[_user].depositsSci < _amount) revert InsufficientBalance(users[_user].depositsSci, _amount);

            //return SCI tokens
            sciToken.transfer(_user, _amount);

            //deduct amount from total staked
            _totStaked -= _amount;

            //remove amount from deposited amount
            users[_user].depositsSci -= _amount;

            //removes amount from voting rights
            users[_user].rights -= _amount;

            //snapshot updated deposits and voting rights
            _snapshot(_user);

            emit Freed(sci, _user, _amount, users[_user].rights);

        } else {
            revert WrongToken();
        }
    }

    /**
     * @dev creates a proposal with three different research projects
     *      at least one option needs to be proposed
     * @param _option1 #1 of the three proposed research projects
     * @param _option2 #2 of the three proposed research projects
     * @param _option3 #3 of the three proposed research projects
     */
    function propose(
        bytes32 _option1, 
        bytes32 _option2, 
        bytes32 _option3
        ) external dao returns (uint256) {
        //check if at least one project has been proposed
        if (_option1 == "" && _option2 == "" && _option3 == "") revert EmptyOptions();

        //specify each parameter of the proposal
        Proposal memory proposal = Proposal(
            block.number,
            block.timestamp + proposalLifeTime,
            ProposalStatus.active,
            _option1,
            _option2,
            _option3,
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
        emit Proposed(_proposalIndex, _option1, _option2, _option3);

        return _proposalIndex;
    }

    /**
     * @dev vote for an of option of a given proposal 
     *      using the rights from the most recent snapshot
     * @param _id the index of the proposal
     * @param _user the address of the voting user
     * @param _snapshotIndex the index of the latest snapshot of the user
     * @param _option the chosen research project
     * @param _votes the amount of votes given to the chosen research project
     */
    function vote(
        uint256 _id, 
        address _user, 
        uint256 _snapshotIndex, 
        bytes32 _option, 
        uint256 _votes) external {
        //check if proposal exists
        if(_id > _proposalIndex || _id < 1) revert ProposalInexistent();
        //check if proposal is still active
        if(proposals[_id].status != ProposalStatus.active) revert IncorrectPhase(proposals[_id].status); 
        //check if proposal life time has not passed
        if(block.timestamp > proposals[_id].endTimeStamp) revert ProposalLifeTimePassed();
        
        //check if user already voted for this proposal
        if(voted[_id][_user] == 1) revert VoteLock();
        
        //check userVotingRights
        if(_getUserRights(_user, _snapshotIndex, proposals[_id].startBlockNum) < _votes
        ) revert InsufficientRights(users[_user].snapshots[_snapshotIndex].rights, _votes);

        //add votes to the chosen option
        if (_option == proposals[_id].option1) {
            proposals[_id].votesOpt1 += _votes;
        } else if (_option == proposals[_id].option2) {
            proposals[_id].votesOpt2 += _votes;
        } else if (_option == proposals[_id].option3) {
            proposals[_id].votesOpt3 += _votes;
        } else {
            revert IncorrectOption();
        }

        //add to the total votes
        proposals[_id].totalVotes += _votes;

        //set the voting lock time
        users[_user].voteLockTime += (block.timestamp + voteLockTime);

        //set as voted
        voted[_id][_user] = 1;

        //mint a participation token if live
        if (poLive == 1) {
            poToken.mint(_user);
        }

        //emit Voted events
        emit Voted(_id, _snapshotIndex, _option, _votes);
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
        if (proposals[_id].status != ProposalStatus.active) revert IncorrectPhase(proposals[_id].status);
        proposals[_id].status = ProposalStatus.scheduled;
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
        if (proposals[_id].status != ProposalStatus.scheduled) revert IncorrectPhase(proposals[_id].status);
        proposals[_id].status = ProposalStatus.executed;
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
        proposals[_id].status = ProposalStatus.cancelled;
        emit Cancelled(_id);
    }
}