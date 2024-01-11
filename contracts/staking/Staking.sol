// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IStaking} from "contracts/interface/IStaking.sol";
import {IParticipation} from "contracts/interface/IParticipation.sol";
import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import "../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";

contract Staking is IStaking, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    ///*** ERRORS ***///
    error AlreadyDelegated();
    error CannotClaim();
    error ContractsTerminated();
    error IncorrectBlockNumber();
    error IncorrectSnapshotIndex();
    error InsufficientBalance(uint256 currentDeposit, uint256 requestedAmount);
    error NotGovernanceContract();
    error TokensStillLocked(uint256 voteLockEndStamp, uint256 currentTimeStamp);
    error Unauthorized(address user);
    error UnauthorizedDelegation(
        address owner,
        address oldDelegate,
        address newDelegate
    );

    ///*** TOKENS ***//
    IERC20 private _sci;
    IParticipation private _po;

    ///*** STRUCTS ***///
    struct User {
        uint256 stakedPo; //PO deposited
        uint256 stakedSci; //SCI deposited
        uint256 votingRights; //Voting rights for Operation proposals
        uint256 proposalLockEnd; //Time before token unlock after proposing
        uint256 voteLockEnd; //Time before token unlock after voting
        uint256 amtSnapshots; //Amount of snapshots
        address delegate; //Address of the delegate
        mapping(uint256 => Snapshot) snapshots; //Index => snapshot
    }

    struct Snapshot {
        uint256 atBlock;
        uint256 rights;
    }

    ///*** STORAGE & MAPPINGS ***///
    bool public terminatedGovOps = false;
    bool public terminatedGovRes = false;
    address public govOpsContract;
    address public govResContract;
    uint256 private totStaked;
    mapping(address => User) public users;

    ///*** MODIFIERS ***///
    modifier govOps() {
        if (_msgSender() != govOpsContract) revert Unauthorized(_msgSender());
        _;
    }

    modifier govRes() {
        if (_msgSender() != govResContract) revert Unauthorized(_msgSender());
        _;
    }

    modifier notTerminated() {
        if (terminatedGovOps && terminatedGovRes) revert ContractsTerminated();
        _;
    }

    /*** EVENTS ***/
    event Delegated(
        address indexed owner,
        address indexed oldDelegate,
        address indexed newDelegate
    );
    event Freed(
        address indexed token,
        address indexed user,
        uint256 amountFreed
    );
    event Locked(
        address indexed token,
        address indexed user,
        uint256 amountLocked
    );
    event Snapshotted(
        address indexed owner,
        uint256 votingRights,
        uint256 indexed blockNumber
    );
    event Terminated(address admin, uint256 blockNumber);
    event VoteLockTimeUpdated(address user, uint256 voteLockEndTime);

    constructor(address treasuryWallet_, address sci_) {
        _grantRole(DEFAULT_ADMIN_ROLE, treasuryWallet_);

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
     * @dev sets the address of the operations governance smart contract
     */
    function setGovOps(
        address newGovOps
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        govOpsContract = newGovOps;
    }

    /**
     * @dev sets the address of the operations governance smart contract
     */
    function setGovRes(
        address newGovRes
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        govResContract = newGovRes;
    }

    /**
     * @dev delegates the owner's voting rights
     * @param owner the owner of the delegated voting rights
     * @param newDelegate user that will receive the delegated voting rights
     */
    function delegate(
        address owner,
        address newDelegate
    ) external notTerminated {
        address oldDelegate = users[owner].delegate;

        if (oldDelegate == newDelegate) revert AlreadyDelegated();

        //check if function caller can change delegation
        if (
            !(owner == _msgSender() ||
                (oldDelegate == _msgSender() && newDelegate == address(0)))
        ) revert UnauthorizedDelegation(owner, oldDelegate, newDelegate);

        users[owner].delegate = newDelegate;

        //update vote unlock time
        if (oldDelegate != address(0)) {
            users[owner].voteLockEnd = Math.max(
                users[owner].voteLockEnd,
                users[oldDelegate].voteLockEnd
            );

            users[oldDelegate].votingRights -= users[owner].stakedSci;

            _snapshot(oldDelegate, users[oldDelegate].votingRights);

            users[owner].votingRights += users[owner].stakedSci;

            _snapshot(owner, users[owner].votingRights);
        }

        //update voting rights for delegate
        if (newDelegate != address(0)) {
            users[newDelegate].votingRights += users[owner].stakedSci;

            _snapshot(newDelegate, users[newDelegate].votingRights);
            //update owner's voting power
            users[owner].votingRights = 0;

            _snapshot(owner, users[owner].votingRights);
        }

        emit Delegated(owner, oldDelegate, newDelegate);
    }

    /**
     * @dev locks a given amount of SCI tokens
     * @param amount the amount of tokens that will be locked
     */
    function lockSci(uint256 amount) external notTerminated nonReentrant {
        //Retrieve SCI tokens from user wallet but user needs to approve transfer first
        IERC20(_sci).safeTransferFrom(msg.sender, address(this), amount);

        //add to total staked amount
        totStaked += amount;

        //Adds amount of deposited SCI tokens
        users[msg.sender].stakedSci += amount;

        address delegated = users[msg.sender].delegate;
        if (delegated != address(0)) {
            //update voting rights for delegated address
            users[delegated].votingRights += amount;
            //snapshot of delegate's voting rights
            _snapshot(delegated, users[delegated].votingRights);

            emit Locked(address(_sci), msg.sender, amount);
        } else {
            //update voting rights for user
            users[msg.sender].votingRights += amount;
            //snapshot of voting rights
            _snapshot(msg.sender, users[msg.sender].votingRights);

            emit Locked(address(_sci), msg.sender, amount);
        }
    }

    /**
     * @dev locks a given amount PO tokens
     * @param amount the amount of tokens that will be locked
     */
    function lockPo(uint256 amount) external notTerminated nonReentrant {
        //retrieve balance of user
        uint256 balance = _po.balanceOf(msg.sender);

        //check if user has enough PO tokens
        if (balance < amount) revert InsufficientBalance(balance, amount);

        //Retrieve PO token from user wallet
        _po.push(msg.sender, amount);

        //update staked PO balance
        users[msg.sender].stakedPo += amount;

        //emit locked event
        emit Locked(address(_po), msg.sender, amount);
    }

    /**
     * @dev frees locked tokens after voteLockEnd has passed
     * @param amount the amount of tokens that will be freed
     */
    function freeSci(uint256 amount) external nonReentrant {
        if (
            users[msg.sender].voteLockEnd > block.timestamp &&
            !(terminatedGovOps && terminatedGovRes)
        ) {
            revert TokensStillLocked(users[msg.sender].voteLockEnd, block.timestamp);
        } else {
            users[msg.sender].voteLockEnd = 0;
            users[msg.sender].proposalLockEnd = 0;
        }

        //check if amount is lower than deposited SCI tokens
        if (users[msg.sender].stakedSci < amount)
            revert InsufficientBalance(users[msg.sender].stakedSci, amount);

        //return SCI tokens
        IERC20(_sci).safeTransfer(msg.sender, amount);

        //deduct amount from total staked
        totStaked -= amount;

        //remove amount from deposited amount
        users[msg.sender].stakedSci -= amount;

        address delegated = users[msg.sender].delegate;
        if (delegated != address(0)) {
            //check if delegate did not vote recently
            if (
                users[delegated].voteLockEnd > block.timestamp &&
                !(terminatedGovOps && terminatedGovRes)
            ) {
                revert TokensStillLocked(
                    users[delegated].voteLockEnd,
                    block.timestamp
                );
            } else {
                users[delegated].voteLockEnd = 0;
            }

            //remove delegate voting rights
            users[delegated].votingRights -= amount;

            _snapshot(delegated, users[delegated].votingRights);
        } else {
            //add new amount of votes as rights
            users[msg.sender].votingRights -= amount;

            //snapshot of voting rights
            _snapshot(msg.sender, users[msg.sender].votingRights);
        }

        emit Freed(address(_sci), msg.sender, amount);
    }

    /**
     * @dev frees locked tokens after voteLockEnd has passed
     * @param amount the amount of tokens that will be freed
     */
    function freePo(uint256 amount) external nonReentrant {
        //check if amount is lower than deposited PO tokens
        if (users[msg.sender].stakedPo < amount)
            revert InsufficientBalance(users[msg.sender].stakedPo, amount);

        //Retrieve PO token from staking contract
        _po.pull(msg.sender, amount);

        //update staked PO balance
        users[msg.sender].stakedPo -= amount;

        emit Freed(address(_po), msg.sender, amount);
    }

    /**
     * @dev is called by gov contract upon voting
     * @param user the user's address holding SCI tokens
     * @param voteLockEnd the block number where the vote lock ends
     */
    function votedOperations(
        address user,
        uint256 voteLockEnd
    ) external govOps returns (bool) {
        if (users[user].voteLockEnd < voteLockEnd) {
            users[user].voteLockEnd = voteLockEnd;
        }
        emit VoteLockTimeUpdated(user, voteLockEnd);
        return true;
    }

    /**
     * @dev is called by gov contract upon voting
     * @param user the user's address holding SCI tokens
     * @param voteLockEnd the block number where the vote lock ends
     */
    function votedResearch(
        address user,
        uint256 voteLockEnd
    ) external govRes returns (bool) {
        if (users[user].voteLockEnd < voteLockEnd) {
            users[user].voteLockEnd = voteLockEnd;
        }
        emit VoteLockTimeUpdated(user, voteLockEnd);
        return true;
    }

    /**
     * @dev is called by govOps contract upon proposing
     * @param user the user's address holding SCI tokens
     * @param proposalLockEnd the block number where the vote lock ends
     */
    function proposedOperations(
        address user,
        uint256 proposalLockEnd
    ) external govOps returns (bool) {
        if (users[user].proposalLockEnd < proposalLockEnd) {
            users[user].proposalLockEnd = proposalLockEnd;
        }
        emit VoteLockTimeUpdated(user, proposalLockEnd);
        return true;
    }

    /**
     * @dev is called by govOps contract upon proposing
     * @param user the user's address holding SCI tokens
     * @param proposalLockEnd the block number where the vote lock ends
     */
    function proposedResearch(
        address user,
        uint256 proposalLockEnd
    ) external govRes returns (bool) {
        if (users[user].proposalLockEnd < proposalLockEnd) {
            users[user].proposalLockEnd = proposalLockEnd;
        }
        emit VoteLockTimeUpdated(user, proposalLockEnd);
        return true;
    }

    /**
     * @dev terminates the staking smart contract
     */
    function terminateOperations(
        address admin
    ) external govOps notTerminated nonReentrant {
        terminatedGovOps = true;
        emit Terminated(admin, block.number);
    }

    /**
     * @dev terminates the staking smart contract
     */
    function terminateResearch(
        address admin
    ) external govRes notTerminated nonReentrant {
        terminatedGovRes = true;
        emit Terminated(admin, block.number);
    }

    /**
     * @dev return the timestamp where the lock after voting ends
     */
    function getVoteLockEnd(address user) external view returns (uint256) {
        return users[user].voteLockEnd;
    }

    /**
     * @dev return the timestamp where the lock after proposing ends
     */
    function getProposalLockEnd(address user) external view returns (uint256) {
        return users[user].proposalLockEnd;
    }

    /**
     * @dev returns the user rights from the latest taken snapshot
     * @param user the user address
     */
    function getLatestUserRights(address user) external view returns (uint256) {
        uint256 latestSnapshotIndex = users[user].amtSnapshots;
        return getUserRights(user, latestSnapshotIndex, block.number);
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
    function _snapshot(address user, uint256 votingRights) internal {
        uint256 index = users[user].amtSnapshots;
        if (index > 0 && users[user].snapshots[index].atBlock == block.number) {
            users[user].snapshots[index].rights = votingRights;
        } else {
            users[user].amtSnapshots = index += 1;
            users[user].snapshots[index] = Snapshot(block.number, votingRights);
        }
        emit Snapshotted(user, votingRights, block.number);
    }
}
