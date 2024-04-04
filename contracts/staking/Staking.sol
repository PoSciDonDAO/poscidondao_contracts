// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

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
    error CannotDelegateToAnotherDelegator();
    error CannotDelegateToContract();
    error ContractsTerminated();
    error DelegateAlreadyAdded(address delegate);
    error DelegateNotAllowListed(address delegate);
    error IncorrectBlockNumber();
    error IncorrectSnapshotIndex();
    error InsufficientBalance(uint256 currentDeposit, uint256 requestedAmount);
    error NoVotingPowerToDelegate();
    error SelfDelegationNotAllowed();
    error TokensStillLocked(uint256 voteLockEndStamp, uint256 currentTimeStamp);
    error Unauthorized(address user);

    ///*** TOKEN ***//
    IERC20 private _sci;

    ///*** STRUCTS ***///
    struct User {
        uint256 lockedSci; //SCI deposited
        uint256 votingRights; //Voting rights for operation proposals
        uint256 proposeLockEnd; //Time before token unlock after proposing
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
    bool public terminated = false;
    bool public terminatedOperations = false;
    bool public terminatedResearchFunding = false;
    address public govOpsContract;
    address public govResContract;
    uint256 private totStaked;
    uint256 private totDelegated;
    uint256 public delegateThreshold;
    mapping(address => User) public users;
    mapping(address => bool) private delegates;

    ///*** MODIFIERS ***///
    modifier gov() {
        if (!(msg.sender == govOpsContract || msg.sender == govResContract))
            revert Unauthorized(msg.sender);
        _;
    }

    modifier notTerminated() {
        if (terminated) revert ContractsTerminated();
        _;
    }

    /*** EVENTS ***/
    event DelegateAdded(address indexed delegate);
    event DelegateRemoved(address indexed delegate);
    event Delegated(
        address indexed owner,
        address indexed oldDelegate,
        address indexed newDelegate,
        uint256 delegatedAmount
    );
    event Freed(
        address indexed user,
        uint256 amountFreed
    );
    event Locked(
        address indexed user,
        uint256 amountLocked
    );
    event Snapshotted(
        address indexed owner,
        uint256 votingRights,
        uint256 indexed blockNumber
    );
    event Terminated(address admin, uint256 blockNumber);
    event TerminatedByGovernance(
        address govContract,
        address admin,
        uint256 blockNumber
    );
    event VoteLockEndTimeUpdated(address user, uint256 voteLockEndTime);
    event ProposeLockEndTimeUpdated(address user, uint256 proposeLockEndTime);

    constructor(address treasuryWallet_, address sci_) {
        _grantRole(DEFAULT_ADMIN_ROLE, treasuryWallet_);
        _sci = IERC20(sci_);
        delegateThreshold = 100e18;
        delegates[address(0)] = true;
    }

    ///*** EXTERNAL FUNCTIONS ***///

    /**
     * @dev sets the sci token address.
     * @param sci the address of the tradable ($SCI) token
     */
    function setSciToken(address sci) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _sci = IERC20(sci);
    }

    /**
     * @dev sets the amount of staked sci tokens needed to become a delegate
     * @param newThreshold the new threshold to become a delegate
     */
    function setDelegateThreshold(
        uint256 newThreshold
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        delegateThreshold = newThreshold;
    }

    /**
     * @dev Adds an address to the delegate whitelist if tokens have been staked
     * @param newDelegate Address to be added to the whitelist
     */
    function addDelegate(
        address newDelegate
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (delegates[newDelegate]) {
            revert DelegateAlreadyAdded(newDelegate);
        }
        if (
            users[newDelegate].lockedSci < delegateThreshold &&
            newDelegate != address(0)
        )
            revert InsufficientBalance(
                users[newDelegate].lockedSci,
                delegateThreshold
            );
        delegates[newDelegate] = true;
        emit DelegateAdded(newDelegate);
    }

    /**
     * @dev Removes an address from the delegate whitelist
     * @param formerDelegate Address to be removed from the whitelist
     */
    function removeDelegate(
        address formerDelegate
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!delegates[formerDelegate]) {
            revert DelegateNotAllowListed(formerDelegate);
        }
        delegates[formerDelegate] = false;
        emit DelegateRemoved(formerDelegate);
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
     * @param newDelegate user that will receive the delegated voting rights
     */
    function delegate(address newDelegate) external nonReentrant notTerminated {
        address owner = msg.sender;
        address oldDelegate = users[owner].delegate;
        uint256 lockedSci = users[owner].lockedSci;

        if (newDelegate != address(0) && !delegates[newDelegate])
            revert DelegateNotAllowListed(newDelegate);

        if (owner == newDelegate) revert SelfDelegationNotAllowed();

        if (oldDelegate == newDelegate) revert AlreadyDelegated();

        if (lockedSci == 0 && newDelegate != address(0))
            revert NoVotingPowerToDelegate();

        if (users[newDelegate].delegate != address(0)) {
            revert CannotDelegateToAnotherDelegator();
        }

        if (oldDelegate != address(0)) {
            users[owner].voteLockEnd = Math.max(
                users[owner].voteLockEnd,
                users[oldDelegate].voteLockEnd
            );

            users[oldDelegate].votingRights -= users[owner].lockedSci;

            _snapshot(oldDelegate, users[oldDelegate].votingRights);

            users[owner].votingRights += users[owner].lockedSci;

            _snapshot(owner, users[owner].votingRights);

            totDelegated -= lockedSci;
        }

        if (newDelegate != address(0)) {
            users[newDelegate].votingRights += users[owner].lockedSci;

            _snapshot(newDelegate, users[newDelegate].votingRights);

            users[owner].votingRights = 0;

            _snapshot(owner, users[owner].votingRights);

            totDelegated += lockedSci;

            users[owner].delegate = newDelegate;
        } else {
            users[owner].delegate = address(0);
        }

        emit Delegated(owner, oldDelegate, newDelegate, lockedSci);
    }

    /**
     * @dev locks a given amount of SCI tokens
     * @param amount the amount of tokens that will be locked
     */
    function lock(uint256 amount) external nonReentrant notTerminated {
        //Retrieve SCI tokens from user wallet but user needs to approve transfer first
        IERC20(_sci).safeTransferFrom(msg.sender, address(this), amount);

        //add to total staked amount
        totStaked += amount;

        //Adds amount of deposited SCI tokens
        users[msg.sender].lockedSci += amount;

        address delegated = users[msg.sender].delegate;
        if (delegated != address(0)) {
            users[delegated].votingRights += amount;

            _snapshot(delegated, users[delegated].votingRights);

            totDelegated += amount;
        } else {
            //update voting rights for user
            users[msg.sender].votingRights += amount;
            //snapshot of voting rights
            _snapshot(msg.sender, users[msg.sender].votingRights);
        }

        emit Locked(msg.sender, amount);
    }

    /**
     * @dev frees locked tokens after vote or proposal lock end has passed
     * @param amount the amount of tokens that will be freed
     */
    function free(uint256 amount) external nonReentrant {
        if (
            (users[msg.sender].voteLockEnd > block.timestamp ||
                users[msg.sender].proposeLockEnd > block.timestamp) &&
            !(terminated)
        ) {
            revert TokensStillLocked(
                users[msg.sender].voteLockEnd,
                block.timestamp
            );
        } else {
            users[msg.sender].voteLockEnd = 0;
            users[msg.sender].proposeLockEnd = 0;
        }

        //return SCI tokens
        IERC20(_sci).safeTransfer(msg.sender, amount);

        //deduct amount from total staked
        totStaked -= amount;

        //remove amount from deposited amount
        users[msg.sender].lockedSci -= amount;

        address delegated = users[msg.sender].delegate;
        if (delegated != address(0)) {
            if (
                users[delegated].voteLockEnd > block.timestamp && !(terminated)
            ) {
                revert TokensStillLocked(
                    users[delegated].voteLockEnd,
                    block.timestamp
                );
            } else {
                users[delegated].voteLockEnd = 0;
            }

            users[delegated].votingRights -= amount;

            _snapshot(delegated, users[delegated].votingRights);

            totDelegated -= amount;

            if (users[msg.sender].lockedSci == 0) {
                users[msg.sender].delegate = address(0);
            }
        } else {
            users[msg.sender].votingRights -= amount;

            _snapshot(msg.sender, users[msg.sender].votingRights);
        }

        emit Freed(msg.sender, amount);
    }

    /**
     * @dev is called by gov contracts upon voting
     * @param user the user's address holding SCI tokens
     * @param voteLockEnd the block number where the vote lock ends
     */
    function voted(
        address user,
        uint256 voteLockEnd
    ) external gov returns (bool) {
        if (users[user].voteLockEnd < voteLockEnd) {
            users[user].voteLockEnd = voteLockEnd;
        }
        emit VoteLockEndTimeUpdated(user, voteLockEnd);
        return true;
    }

    /**
     * @dev is called by gov contracts upon proposing
     * @param user the user's address holding SCI tokens
     * @param proposeLockEnd the block number where the vote lock ends
     */
    function proposed(
        address user,
        uint256 proposeLockEnd
    ) external gov returns (bool) {
        if (users[user].proposeLockEnd < proposeLockEnd) {
            users[user].proposeLockEnd = proposeLockEnd;
        }
        emit ProposeLockEndTimeUpdated(user, proposeLockEnd);
        return true;
    }

    /**
     * @dev initiates termination by operations or research funding governance contracts
     */
    function terminateByGovernance(
        address terminator
    ) external gov nonReentrant notTerminated {
        if (msg.sender == govOpsContract) {
            terminatedOperations = true;

            emit TerminatedByGovernance(
                govOpsContract,
                terminator,
                block.number
            );
        } else if (msg.sender == govResContract) {
            terminatedResearchFunding = true;

            emit TerminatedByGovernance(
                govResContract,
                terminator,
                block.number
            );
        }
    }

    /**
     * @dev terminates the staking smart contract
     */
    function terminate(address terminator) external {
        if (terminatedOperations && terminatedResearchFunding) {
            terminated = true;
            emit Terminated(terminator, block.number);
        }
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
    function getSciAddress() external view returns (address) {
        return address(_sci);
    }

    /**
     * @dev returns the total amount of staked SCI tokens
     */
    function getTotalStaked() external view returns (uint256) {
        return totStaked;
    }

    /**
     * @dev returns the total amount of delegated SCI tokens
     */
    function getTotalDelegated() external view returns (uint256) {
        return totDelegated;
    }

    /**
     * @dev returns the amount of staked SCI tokens of a given user
     */
    function getStakedSci(address user) external view returns (uint256) {
        return users[user].lockedSci;
    }

    /**
     * @dev returns true if address is a delegate
     */
    function getDelegate(address delegateAddress) external view returns (bool) {
        return delegates[delegateAddress];
    }

    /**
     * @dev returns the propose lock end time
     */
    function getProposeLockEndTime(
        address user
    ) external view returns (uint256) {
        return users[user].proposeLockEnd;
    }

    /**
     * @dev returns the vote lock end time
     */
    function getVoteLockEndTime(address user) external view returns (uint256) {
        return users[user].voteLockEnd;
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
