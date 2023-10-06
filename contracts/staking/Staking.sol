// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IStaking} from "contracts/interface/IStaking.sol";
import {IParticipation} from "contracts/interface/IParticipation.sol";
import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";

contract Staking is IStaking, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

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
    IERC20 private _sci;
    IParticipation private _po;

    ///*** STRUCTS ***///
    struct User {
        uint256 stakedPo; //PO deposited
        uint256 stakedSci; //SCI deposited
        uint256 votingRights; //Voting rights
        uint256 voteLockEnd; //Time before tokens can be unlocked during voting
        uint256 amtSnapshots; //Amount of snapshots
        mapping(uint256 => Snapshot) snapshots; //Index => snapshot
    }

    struct Snapshot {
        uint256 atBlock;
        uint256 rights;
    }

    ///*** STORAGE & MAPPINGS ***///
    uint256 private totStaked;
    mapping(address => uint8) public wards;
    mapping(address => User) public users;
    uint256 public numerator;
    uint256 public denominator;
    address public govRes;
    address public govOps;
    // bool public discontinued = false;

    ///*** MODIFIER ***///
    modifier gov() {
        if (msg.sender != govRes && msg.sender != govOps)
            revert Unauthorized(msg.sender);
        _;
    }

    /*** EVENTS ***/
    event RelyOn(address indexed user);
    event Denied(address indexed user);
    event Locked(
        address indexed token,
        address indexed user,
        uint256 amount,
        uint256 votes
    );
    event Freed(
        address indexed token,
        address indexed user,
        uint256 amount,
        uint256 remainingVotes
    );
    event VoteLockTimeUpdated(address user, uint256 voteLockEndTime);

    constructor(address sci_) {
        numerator = 10;
        denominator = 10;

        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());

        _sci = IERC20(sci_);
    }

    ///*** EXTERNAL FUNCTIONS ***///

    /**
     * @dev sets the PO token address and interface
     * @param po the address of the participation ($PO) token
     */
    function setPoToken(address po) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _po = IParticipation(po);
    }

    /**
     * @dev sets the sci token address.
     * @param sci the address of the tradable ($SCI) token
     */
    function setSciToken(address sci) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _sci = IERC20(sci);
    }

    /**
     * @dev sets the address of the research funding governance smart contract
     */
    function setGovRes(
        address newGovRes
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        govRes = newGovRes;
    }

    /**
     * @dev sets the address of the operations funding governance smart contract
     */
    function setGovOps(
        address newGovOps
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        govOps = newGovOps;
    }

    /**
     * @dev set the numerator and denominator
     */
    function setNandD(
        uint256 n,
        uint256 d
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        numerator = n;
        denominator = d;
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

        if (src == address(_sci)) {
            //Retrieve SCI tokens from user wallet but user needs to approve transfer first
            IERC20(_sci).safeTransferFrom(user, address(this), amount);

            //add to total staked amount
            totStaked += amount;

            //Adds amount of deposited SCI tokens
            users[user].stakedSci += amount;

            //SCI holders get more votes per locked token
            //based on amount of DON tokens in circulation
            uint256 votes = _calcVotes(amount);

            //calculated votes are added as voting rights
            users[user].votingRights = votes;

            //snapshot of voting rights
            _snapshot(user);

            emit Locked(address(_sci), user, amount, votes);
        } else if (src == address(_po)) {
            //retrieve balance of user
            uint256[] memory balance = _po.getHeldBalance(user);

            //check if user has enough PO tokens
            if (balance.length < amount)
                revert InsufficientBalance(balance.length, amount);

            //Retrieve PO token from user wallet
            _po.push(user, amount);

            //update staked PO balance
            users[user].stakedPo += amount;

            //emit locked event
            emit Locked(address(_po), user, amount, 0);
        } else {
            //Revert if the wrong token is chosen
            revert WrongToken();
        }
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

        if (src == address(_sci) && users[user].voteLockEnd > block.timestamp)
            revert TokensStillLocked(users[user].voteLockEnd, block.timestamp);

        if (src == address(_sci)) {
            //check if amount is lower than deposited SCI tokens
            if (users[user].stakedSci < amount)
                revert InsufficientBalance(users[user].stakedSci, amount);

            //return SCI tokens
            IERC20(_sci).safeTransfer(user, amount);

            //deduct amount from total staked
            totStaked -= amount;

            //remove amount from deposited amount
            users[user].stakedSci -= amount;

            //recalculates the votes based on the remaining deposited amount
            uint256 votes = _calcVotes(users[user].stakedSci);

            //add new amount of votes as rights
            users[user].votingRights = votes;

            //snapshot of voting rights
            _snapshot(user);

            emit Freed(address(_sci), user, amount, votes);
        } else if (src == address(_po)) {
            //check if amount is lower than deposited PO tokens
            if (users[user].stakedPo < amount)
                revert InsufficientBalance(users[user].stakedPo, amount);

            //Retrieve PO token from staking contract
            _po.pull(user, amount);

            //update staked PO balance
            users[user].stakedPo -= amount;

            emit Freed(address(_po), user, amount, 0);
        } else {
            revert WrongToken();
        }
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
        if (users[user].voteLockEnd < voteLockEnd) {
            users[user].voteLockEnd = voteLockEnd;
        }
        emit VoteLockTimeUpdated(user, voteLockEnd);
        return true;
    }

    // function emergencyDiscontinuation() external onlyRole(DEFAULT_ADMIN_ROLE) {

    // }

    /**
     * @dev returns the user rights from the latest taken snapshot
     * @param user the user address
     */
    function getLatestUserRights(address user) external view returns (uint256) {
        uint256 latestSnapshot = users[user].amtSnapshots;
        return getUserRights(user, latestSnapshot, block.number);
    }

    /**
     * @dev returns the address for the Participation (PO) token
     */
    function getPoAddress() external view returns (address) {
        return address(_po);
    }

    /**
     * @dev returns the address for the Participation (PO) token
     */
    function getSciAddress() external view returns (address) {
        return address(_sci);
    }

    /**
     * @dev returns the total amount of staked SCI and DON tokens
     */
    function getTotalStaked() external view returns (uint256) {
        return totStaked;
    }

    /**
     * @dev returns the amount of staked PO tokens of a given user
     */
    function getStakedPo(address user) external view returns (uint256) {
        return users[user].stakedPo;
    }

    /**
     * @dev returns the amount of staked SCI tokens of a given user
     */
    function getStakedSci(address user) external view returns (uint256) {
        return users[user].stakedSci;
    }

    ///*** PUBLIC FUNCTION ***///

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

    ///*** INTERNAL FUNCTIONS ***///

    /**
     * @dev a snaphshot of the current voting rights of a given user
     * @param user the address that is being snapshotted
     */
    function _snapshot(address user) internal {
        uint256 index = users[user].amtSnapshots;
        if (index > 0 && users[user].snapshots[index].atBlock == block.number) {
            users[user].snapshots[index].rights = users[user].votingRights;
        } else {
            users[user].amtSnapshots = index += 1;
            users[user].snapshots[index] = Snapshot(
                block.number,
                users[user].votingRights
            );
        }
    }

    /**
     * @dev calculate the votes for users that have donated e.g. amount * 12/10
     * @param amount of deposited DON tokens that will be multiplied with n / d
     */
    function _calcVotes(
        uint256 amount
    ) internal view returns (uint256 votingPower) {
        return votingPower = (amount * numerator) / denominator;
    }
}
