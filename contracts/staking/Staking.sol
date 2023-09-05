// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IStaking} from "contracts/interface/IStaking.sol";
import {IDonation} from "contracts/interface/IDonation.sol";
import {IParticipation} from "contracts/interface/IParticipation.sol";

interface AccountBoundTokenLike {
    function push(address, uint256) external;
    function pull(address, uint256) external;
}

contract Staking is IStaking, ReentrancyGuard {

    ///*** ERRORS ***///
    error CannotClaim();
    error IncorrectBlockNumber();
    error IncorrectSnapshotIndex();
    error InsufficientBalance(uint256 currentDeposit, uint256 requestedAmount);
    error NotGovernanceContract(address govAddress);
    error TokensStillLocked(uint256 voteLockEndStamp, uint256 currentTimeStamp);
    error Unauthorized(address user);
    error VoteLock();
    error WrongToken();


    ///*** TOKENS ***//
    address                 private             _po;
    address                 private immutable   _sci;
    address                 private immutable   _don;
    IParticipation          public              poToken;
    IERC20                  public  immutable   sciToken;
    IDonation               public  immutable   donToken;

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
    uint256                                         private     totStaked;
    mapping(address => uint8)                       public      wards;
    mapping(address => User)                        public      users;
    uint256                                         public      numerator;          //numerator
    uint256                                         public      denominator;          //denominator
    address                                         public      govRes;
    address                                         public      govOps;

    ///*** MODIFIER ***///
    modifier dao() {
        if(wards[msg.sender] != 1) revert Unauthorized(msg.sender);
        _;
    }

    modifier gov() {
        require(msg.sender == govRes || msg.sender == govOps, "Not a gov contract");
        _;
    }

    /*** EVENTS ***/
    event RelyOn(address indexed user);
    event Denied(address indexed user);
    event Locked(address indexed token, address indexed user, uint256 amount, uint256 votes);
    event Freed(address indexed token, address indexed user, uint256 amount, uint256 remainingVotes);
    event VoteLockTimeUpdated(address user, uint256 voteLockEndTime);

    constructor(
        address po,
        address sci,
        address don,
        address _dao
    ) {
        poToken       = IParticipation(po);
        sciToken      = IERC20(sci); //implement safeERC20
        donToken      = IDonation(don);

        _po = po;
        _sci = sci;
        _don = don;

        numerator = 10;
        denominator = 10;

        wards[_dao] = 1;
    }

    ///*** INTERNAL FUNCTIONS ***///
    /**
     * @dev a snaphshot of the current voting rights of a given user
     * @param user the address that is being snapshotted
     */
    function snapshot(
        address user
        ) internal {
        uint256 index = users[user].amtSnapshots;
        if (index > 0 && users[user].snapshots[index].atBlock == block.number) {
            users[user].snapshots[index].rights = users[user].votingRights;
        } else {
            users[user].amtSnapshots = index += 1;
            users[user].snapshots[index] = Snapshot(block.number, users[user].votingRights);
        }
    }

    /**
     * @dev calculate the votes for users that have donated e.g. amount * 12/10  
     * @param amount of deposited DON tokens that will be multiplied with n / d
     */
    function calcVotes(
        uint256 amount
    ) internal view returns (uint256 votingPower) {
        return votingPower = amount * numerator / denominator;
    }

    /**
    *@dev   Using this function, a given amount will be turned into an array.
    *       This array will be used in ERC1155's batch mint function. 
    *@param amount is the amount provided that will be turned into an array.
    */
    function turnAmountIntoArray(uint256 amount) internal pure returns (uint256[] memory tokenAmounts) {
        tokenAmounts = new uint[](amount);
        for (uint256 i = 0; i < amount;) {
            tokenAmounts[i] = i + 1;
            unchecked {
                i++;
            }
        }
    }

    function turnUserIntoArray(address user, uint256 amountOfTokens) internal pure returns (address[] memory addressArray) {
        addressArray = new address[](amountOfTokens);
        for (uint256 i = 0; i < amountOfTokens;) {
            addressArray[i] = user;
            unchecked {
                i++;
            }
        }
    }
    
    ///*** EXTERNAL FUNCTIONS ***///

    /**
     * @dev Return the voting rights of a user at a certain snapshot
     * @param user the user address 
     * @param snapshotIndex the index of the snapshots the user has
     * @param blockNum the highest block.number at which the user rights will be retrieved
     */
    function getUserRights(
        address user, 
        uint256 snapshotIndex, 
        uint256 blockNum
        ) public view returns (uint256) {
        uint256 index = users[user].amtSnapshots;
        if (snapshotIndex > index) revert IncorrectSnapshotIndex();
        Snapshot memory snap = users[user].snapshots[snapshotIndex];
        if (snap.atBlock > blockNum) revert IncorrectBlockNumber();
        return snap.rights;
    }

    function getLatestUserRights(
        address user  
    ) external view returns (uint256) {
        uint256 latestSnapshot = users[user].amtSnapshots;
        return getUserRights(user, latestSnapshot, block.number);
    }

    /**
     * @dev returns the total amount of staked SCI and DON tokens
     */
    function getTotalStaked() external view returns (uint256) {
        return totStaked;
    }

    /**
     * @dev sets the address of the research funding governance smart contract
     */
    function setGovRes(address newGovRes) external dao {
        govRes = newGovRes;
    }

    /**
     * @dev sets the address of the operations funding governance smart contract
     */
    function setGovOps(address newGovOps) external dao {
        govOps = newGovOps;
    }

    /**
     * @dev set the numerator and denominator us
     */
    function setNandD(uint256 n, uint256 d) external dao {
        numerator = n;
        denominator = d;
    }

    /**
     * @dev adds a gov
     * @param user the user that is eligible to become a gov
     */
    function addGov(address user) external dao {
        wards[user] = 1;
        emit RelyOn(user);
    }

    /**
     * @dev removes a gov
     * @param user the user that will be removed as a gov
     */
    function removeGov(address user) external dao {
        if(wards[user] != 1) {
            revert Unauthorized(msg.sender);
        }
        delete wards[user];
        emit Denied(user);
    }

    /**
     * @dev locks a given amount of SCI or DON tokens
     * @param src the address of the token needs to be locked: SCI or DON
     * @param user the user that wants to lock tokens
     * @param amount the amount of tokens that will be locked
     */
    function lock(
        address src, 
        address user, 
        uint256 amount
        ) external nonReentrant {
        if (msg.sender != user) revert Unauthorized(msg.sender);

        if (src == _don) {
            
            //Retrieve DON tokens from wallet
            donToken.push(user, amount);

            //add to total staked amount
            totStaked += amount;

            //Adds amount of deposited DON tokens
            users[user].stakedDon += amount;

            //in this case the amount deposited in DON tokens is equal to voting rights
            users[user].votingRights += amount;

            //emit event
            emit Locked(_don, user, amount, amount);
            
        } else if (src == _sci) {
            //Retrieve SCI tokens from user wallet but user needs to approve transfer first 
            sciToken.transferFrom(user, address(this), amount);

            //add to total staked amount
            totStaked += amount;

            //Adds amount of deposited SCI tokens
            users[user].stakedSci += amount;

            //SCI holders get more votes per locked token 
            //based on amount of DON tokens in circulation
            uint256 votes = calcVotes(amount);

            //calculated votes are added as voting rights
            users[user].votingRights = votes;

            emit Locked(_sci, user, amount, votes);

        } else {
            //Revert if the wrong token is chosen
            revert WrongToken();
        }

        //snapshot of voting rights
        snapshot(user);
    }

    /**
     * @dev frees locked tokens after voteLockEnd has passed
     * @param src the address of the token that will be freed
     * @param user the user's address holding SCI or DON tokens
     * @param amount the amount of tokens that will be freed
     */
    function free(
        address src, 
        address user,
        uint256 amount
        ) external nonReentrant {
        if (msg.sender != user) revert Unauthorized(msg.sender);

        if(users[user].voteLockEnd > block.timestamp) revert TokensStillLocked(users[user].voteLockEnd, block.timestamp);

        if (src == _don) {
            //check if amount is lower than deposited DON tokens 
            if(users[user].stakedDon < amount) revert InsufficientBalance(users[user].stakedDon, amount);
            
            //pulls DON tokens from gov to user's wallet
            donToken.pull(user, amount);
            
            //update total staked
            totStaked -= amount;

            //Removes the amount of deposited DON tokens
            users[user].stakedDon -= amount;
            
            //removes amount from voting rights
            users[user].votingRights -= amount;

            //emit event
            emit Freed(_don, user, amount, amount);

        } else if (src == _sci) {
            //check if amount is lower than deposited SCI tokens 
            if(users[user].stakedSci < amount) revert InsufficientBalance(users[user].stakedSci, amount);

            //return SCI tokens
            sciToken.transfer(user, amount);

            //deduct amount from total staked
            totStaked -= amount;

            //remove amount from deposited amount
            users[user].stakedSci -= amount;

            //recalculates the votes based on the remaining deposited amount
            uint256 votes = calcVotes(users[user].stakedSci);

            //add new amount of votes as rights
            users[user].votingRights = votes;

            emit Freed(_sci, user, amount, votes);

        } else {
            revert WrongToken();
        }

        //make a new snapshot
        snapshot(user);
    }

    /**
     * @dev lets users stake their PO NFTs
     * @param user the user that wants to stake PO tokens
     */
    function stakePo(
        address user, 
        uint256 amount,
        uint256[] memory ids
    ) external nonReentrant {
        for (uint256 i = 0; i < amount; i++) {
            if (
                poToken.balanceOfBatch(turnUserIntoArray(user, ids.length), ids)[i] < 1
                && users[user].stakedPo < amount
            ) revert InsufficientBalance(users[user].stakedPo, amount);
        }
        //Retrieve PO token from user wallet 
        poToken.push(
            user,  
            turnAmountIntoArray(amount), 
            ids
        );

        //update staked PO balance
        users[user].stakedPo += amount;
        
        //emit locked event
        emit Locked(_po, user, amount, 0);
    }

    function unstakePo(
        address user, 
        uint256 amount,
        uint256[] memory ids
    ) external nonReentrant {

        //Retrieve PO token from user wallet 
        poToken.pull(
            user,  
            turnAmountIntoArray(amount), 
            ids
        );
        //update staked PO balance
        users[user].stakedPo -= amount; 

        emit Freed(_po, user, amount, 0);  
    }

    /**
     * @dev is called by gov contract upon voting
     * @param user the user's address holding SCI or DON tokens
     * @param voteLockEnd the block number where the vote lock ends
     */ 
    function voted(
        address user,
        uint256 voteLockEnd
    ) external gov returns (bool) {
        if(users[user].voteLockEnd < voteLockEnd) {
            users[user].voteLockEnd = voteLockEnd;
        }
        emit VoteLockTimeUpdated(user, voteLockEnd);
        return true;
    }
}