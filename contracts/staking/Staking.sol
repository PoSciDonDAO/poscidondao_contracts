// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "contracts/staking/IStaking.sol";

interface AccountBoundTokenLike {
    function push(address, uint256) external;
    function pull(address, uint256) external;
}

interface TokenLike {
    function transferFrom(address, address, uint256) external;
    function transfer(address, uint256) external;
}

interface NftLike {
    function safeBatchTransferFrom(address, address, uint256[] memory, uint256[] memory, bytes memory) external ;
}

contract Staking is IStaking, ReentrancyGuard {

    ///*** ERRORS ***///
    error CannotClaim();
    error IncorrectBlockNumber();
    error IncorrectSnapshotIndex();
    error InsufficientBalance(uint256 currentDeposit, uint256 requestedAmount);
    error NotGovernanceContract(address);
    error TokensStillLocked(uint256 voteLockEndStamp, uint256 currentTimeStamp);
    error Unauthorized(address user);
    error VoteLock();
    error WrongToken();


    ///*** TOKENS ***//
    address                 private             _po;
    address                 private immutable   _sci;
    address                 private immutable   _don;
    NftLike                 public              poToken;
    TokenLike               public  immutable   sciToken;
    AccountBoundTokenLike   public  immutable   donToken;

    ///*** STRUCTS ***///
    struct User {
        uint256                      stakedPo;      //PO deposited
        uint256                      stakedSci;     //SCI deposited
        uint256                      stakedDon;     //DON deposited
        uint256                      votingRights;  //Voting rights   
        uint256                      voteLockEnd;   //Time before tokens can be unlocked during voting
        uint256                      amtSnapshots;  //Amount of snapshots
        mapping(uint256 => Snapshot) snapshots;     //Index => snapshot
    } 

    struct Snapshot {
        uint256 atBlock;
        uint256 rights;
    }

    ///*** STORAGE & MAPPINGS ***///
    uint256                                         private     _totStaked;
    mapping(address => uint8)                       public      wards;
    mapping(address => User)                        public      users;
    uint256                                         public      n; //numerator
    uint256                                         public      d; //denominator
    address                                         public      govRes;
    address                                         public      govOps;

    ///*** MODIFIER ***///
    modifier dao() {
        if(wards[msg.sender] != 1) revert Unauthorized(msg.sender);
        _;
    }

    modifier gov() {
        if(msg.sender != govRes || msg.sender != govOps) revert NotGovernanceContract(msg.sender);
        _;
    }

    /*** EVENTS ***/
    event RelyOn(address indexed user);
    event Denied(address indexed user);
    event Locked(address indexed token, address indexed user, uint256 amount, uint256 votes);
    event Freed(address indexed token, address indexed user, uint256 amount, uint256 remainingVotes);

    constructor(
        address po_,
        address sci_,
        address don_,
        address dao_
    ) {
        poToken       = NftLike(po_);
        sciToken      = TokenLike(sci_);
        donToken      = AccountBoundTokenLike(don_);

        _po = po_;
        _sci = sci_;
        _don = don_;

        n = 10;
        d = 10;

        wards[dao_] = 1;
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
            users[_user].snapshots[index].rights = users[_user].votingRights;
        } else {
            users[_user].amtSnapshots += 1;
            users[_user].snapshots[index] = Snapshot(block.number, users[_user].votingRights);
        }
    }

    /**
     * @dev calculate the votes for users that have donated e.g. amount * 12/10  
     * @param _amount of deposited DON tokens that will be multiplied with n / d
     */
    function _calcVotes(
        uint256 _amount
    ) internal view returns (uint256 votingPower) {
        return votingPower = _amount * n / d;
    }

    /**
    *@dev   Using this function, a given amount will be turned into an array.
    *       This array will be used in ERC1155's batch mint function. 
    *@param _amount is the amount provided that will be turned into an array.
    */
    function _turnAmountIntoArray(uint256 _amount) internal pure returns (uint256[] memory tokenAmounts) {
        tokenAmounts = new uint[](_amount);
        for (uint256 i = 0; i < _amount;) {
            tokenAmounts[i] = i + 1;
            unchecked {
                i++;
            }
        }
    }

    ///*** PUBLIC FUNCTIONS ***///
    
    /**
     * @dev Return the voting rights of a user at a certain snapshot
     * @param _user the user address 
     * @param _snapshotIndex the index of the snapshots the user has
     * @param _blockNum the highest block.number at which the user rights will be retrieved
     */
    function getUserRights(
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

    ///*** EXTERNAL FUNCTIONS ***///

    /**
     * @dev returns snapshot information
     * @param _user the snapshotted user
     * @param _snapshotNum the snapshot number
     */
    function getSnapshot(address _user, uint256 _snapshotNum ) external view returns (uint256, uint256) {
        return (
            users[_user].snapshots[_snapshotNum].atBlock, 
            users[_user].snapshots[_snapshotNum].rights
        );
    }

    /**
     * @dev returns the total amount of staked SCI and DON tokens
     */
    function getTotalStaked() external view returns (uint256) {
        return _totStaked;
    }

    /**
     * @dev sets the address of the governance smart contract
     */
    function setGovRes(address _newGovRes) external dao {
        govRes = _newGovRes;
    }

    /**
     * @dev sets the address of the governance smart contract
     */
    function setGovOps(address _newGovOps) external dao {
        govOps = _newGovOps;
    }

    /**
     * @dev set the numerator and denominator us
     */
    function setNandD(uint256 _n, uint256 _d) external dao {
        n = _n;
        d = _d;
    }

    /**
     * @dev adds a gov
     * @param _user the user that is eligible to become a gov
     */
    function addGov(address _user) external dao {
        wards[_user] = 1;
        emit RelyOn(_user);
    }

    /**
     * @dev removes a gov
     * @param _user the user that will be removed as a gov
     */
    function removeGov(address _user) external dao {
        if(wards[_user] != 1) {
            revert Unauthorized(msg.sender);
        }
        delete wards[_user];
        emit Denied(_user);
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
        ) external nonReentrant {
        if (msg.sender != _user) revert Unauthorized(msg.sender);

        if (_src == _don) {
            
            //Retrieve DON tokens from wallet
            donToken.push(_user, _amount);

            //add to total staked amount
            _totStaked += _amount;

            //Adds amount of deposited DON tokens
            users[_user].stakedDon += _amount;

            //in this case the amount deposited in DON tokens is equal to voting rights
            users[_user].votingRights += _amount;

            //emit event
            emit Locked(_don, _user, _amount, _amount);
            
        } else if (_src == _sci) {
            //Retrieve SCI tokens from user wallet but user needs to approve transfer first 
            sciToken.transferFrom(_user, address(this), _amount);

            //add to total staked amount
            _totStaked += _amount;

            //Adds amount of deposited SCI tokens
            users[_user].stakedSci += _amount;

            //SCI holders get more votes per locked token 
            //based on amount of DON tokens in circulation
            uint256 _votes = _calcVotes(_amount);

            //calculated votes are added as voting rights
            users[_user].votingRights = _votes;

            emit Locked(_sci, _user, _amount, _votes);

        } else {
            //Revert if the wrong token is chosen
            revert WrongToken();
        }

        //snapshot of voting rights
        _snapshot(_user);
    }

    /**
     * @dev frees locked tokens after voteLockEnd has passed
     * @param _src the address of the token that will be freed
     * @param _user the user's address holding SCI or DON tokens
     * @param _amount the amount of tokens that will be freed
     */
    function free(
        address _src, 
        address _user, 
        uint256 _amount
        ) external nonReentrant {
        if (msg.sender != _user) revert Unauthorized(msg.sender);
        if(users[_user].voteLockEnd > block.timestamp) revert TokensStillLocked(users[_user].voteLockEnd, block.timestamp);

        if (_src == _don) {
            //check if amount is lower than deposited DON tokens 
            if(users[_user].stakedDon < _amount) revert InsufficientBalance(users[_user].stakedDon, _amount);
            
            //pulls DON tokens from gov to user's wallet
            donToken.pull(_user, _amount);
            
            //update total staked
            _totStaked -= _amount;

            //Removes the amount of deposited DON tokens
            users[_user].stakedDon -= _amount;
            
            //removes amount from voting rights
            users[_user].votingRights -= _amount;

            //emit event
            emit Freed(_don, _user, _amount, _amount);

        } else if (_src == _sci) {
            //check if amount is lower than deposited SCI tokens 
            if(users[_user].stakedSci < _amount) revert InsufficientBalance(users[_user].stakedSci, _amount);

            //return SCI tokens
            sciToken.transfer(_user, _amount);

            //deduct amount from total staked
            _totStaked -= _amount;

            //remove amount from deposited amount
            users[_user].stakedSci -= _amount;

            //recalculates the votes based on the remaining deposited amount
            uint256 _votes = _calcVotes(users[_user].stakedSci);

            //add new amount of votes as rights
            users[_user].votingRights = _votes;

            emit Freed(_sci, _user, _amount, _votes);

        } else {
            revert WrongToken();
        }

        //make a new snapshot
        _snapshot(_user);
    }

    /**
     * @dev lets users stake their PO NFTs
     * @param _user the user that wants to stake PO tokens
     */
    function stakePO(
        address _user, 
        uint256 _amount,
        uint256[] memory _ids
    ) external nonReentrant {
        //Retrieve PO token from user wallet 
        //but user needs to confirm ERC1155's approve all first
        poToken.safeBatchTransferFrom(
            _user, 
            address(this), 
            _turnAmountIntoArray(_amount), 
            _ids, 
            "0x0"
        );

        //update staked PO balance
        users[_user].stakedPo += _amount;
        
        //emit locked event
        emit Locked(_po, _user, _amount, 0);
    }

    /**
     * @dev is called by gov contract upon voting
     * @param _user the user's address holding SCI or DON tokens
     * @param _voteLockEnd the block number where the vote lock ends
     */ 
    function voted(
        address _user,
        uint256 _voteLockEnd
    ) external gov returns (bool) {
        if(users[_user].voteLockEnd < _voteLockEnd) {
            users[_user].voteLockEnd = _voteLockEnd;
        }

        return true;
    }
}