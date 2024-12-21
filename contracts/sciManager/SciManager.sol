// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import "../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISciManager} from "contracts/interfaces/ISciManager.sol";
import "../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import "./../interfaces/IGovernorExecution.sol";
import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";

/**
 * @title SciManager
 * @dev Manages SCI token operations including locking and unlocking tokens and delegating voting power.
 */
contract SciManager is ISciManager, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    ///*** ERRORS ***///
    error AlreadyDelegated();
    error CannotBeZeroAddress();
    error CannotClaim();
    error CannotDelegateToAnotherDelegator();
    error CannotDelegateToContract();
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
    IERC20 private sci;

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
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    bool public emergency = false;
    address public admin;
    address public govOpsContract;
    address public govResContract;
    IGovernorExecution govExec;
    uint256 private totLocked;
    uint256 private totDelegated;
    uint256 public delegateThreshold;
    uint256 public constant TOTAL_SUPPLY_SCI = 18910000e18;
    mapping(address => User) public users;
    mapping(address => bool) private delegates;

    ///*** MODIFIERS ***///
    modifier onlyGov() {
        if (!(msg.sender == govOpsContract || msg.sender == govResContract))
            revert Unauthorized(msg.sender);
        _;
    }

    /**
     * @dev Modifier to check if the caller has the `EXECUTOR_ROLE` in `GovernorExecutor`.
     */
    modifier onlyExecutor() {
        if (!govExec.hasRole(EXECUTOR_ROLE, msg.sender)) {
            revert Unauthorized(msg.sender);
        }
        _;
    }

    /*** EVENTS ***/
    event AdminSet(address indexed user, address indexed newAddress);
    event Delegated(
        address indexed owner,
        address indexed oldDelegate,
        address indexed newDelegate,
        uint256 delegatedAmount
    );
    event DelegateAdded(address indexed delegate);
    event DelegateRemoved(address indexed delegate);
    event DelegateThresholdUpdated();
    event EmergencySet(bool indexed emergency, uint256 timestamp);
    event Freed(address indexed user, address indexed asset, uint256 amount);
    event Locked(address indexed user, address indexed asset, uint256 amount);
    event SetGovOps(address indexed user, address indexed newAddress);
    event SetGovRes(address indexed user, address indexed newAddress);


    event GovExecAddressSet(
        address indexed user,
        address indexed newAddress
    );
    event Snapshotted(
        address indexed owner,
        uint256 votingRights,
        uint256 indexed blockNumber
    );
    event VoteLockEndTimeUpdated(address user, uint256 voteLockEndTime);
    event ProposeLockEndTimeUpdated(address user, uint256 proposeLockEndTime);

    constructor(address admin_, address sci_) {
        if (admin_ == address(0) || sci_ == address(0)) {
            revert CannotBeZeroAddress();
        }
        admin = admin_;
        sci = IERC20(sci_);
        delegateThreshold = 50000e18;
        delegates[address(0)] = true;
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
    }

    ///*** EXTERNAL FUNCTIONS ***///

    /**
     * @dev sets the GovernorExecution address
     */
    function setGovExec(
        address newGovernorAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        govExec = IGovernorExecution(newGovernorAddress);
        emit GovExecAddressSet(msg.sender, newGovernorAddress);
    }

    /**
     * @dev Updates the treasury wallet address and transfers admin role.
     * @param newAdmin The address to be set as the new treasury wallet.
     */
    function setAdmin(address newAdmin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        address oldAdmin = admin;
        admin = newAdmin;
        _grantRole(DEFAULT_ADMIN_ROLE, newAdmin);
        _revokeRole(DEFAULT_ADMIN_ROLE, oldAdmin);
        emit AdminSet(oldAdmin, newAdmin);
    }

    /**
     * @dev sets the amount of burned sci tokens needed terminate the DAO
     * @param newThreshold the new threshold to terminate the DAO, precision = 10000
     */
    function setDelegateThreshold(
        uint256 newThreshold
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        delegateThreshold = newThreshold;
        emit DelegateThresholdUpdated();
    }

    /**
     * @dev Adds an address to the delegate whitelist if tokens have been locked
     * @param newDelegate Address to be added to the whitelist
     */
    function addDelegate(address newDelegate) external onlyExecutor {
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
    function removeDelegate(address formerDelegate) external onlyExecutor {
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
        emit SetGovOps(msg.sender, newGovOps);
    }

    /**
     * @dev sets the address of the operations governance smart contract
     */
    function setGovRes(
        address newGovRes
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        govResContract = newGovRes;
        emit SetGovRes(msg.sender, newGovRes);
    }

    /**
     * @dev delegates the owner's voting rights
     * @param newDelegate user that will receive the delegated voting rights
     */
    function delegate(address newDelegate) external nonReentrant {
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
    function lock(uint256 amount) external nonReentrant {
        //Retrieve SCI tokens from user wallet but user needs to approve transfer first
        IERC20(sci).safeTransferFrom(msg.sender, address(this), amount);

        //add to total locked amount
        totLocked += amount;

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

        emit Locked(msg.sender, address(sci), amount);
    }

    /**
     * @dev frees locked tokens after vote or proposal lock end has passed
     * @param amount the amount of tokens that will be freed
     */
    function free(uint256 amount) external nonReentrant {
        if (
            (users[msg.sender].voteLockEnd > block.timestamp ||
                users[msg.sender].proposeLockEnd > block.timestamp) && !emergency
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
        IERC20(sci).safeTransfer(msg.sender, amount);

        //deduct amount from total locked
        totLocked -= amount;

        //remove amount from deposited amount
        users[msg.sender].lockedSci -= amount;

        address delegated = users[msg.sender].delegate;
        if (delegated != address(0)) {
            if (
                users[delegated].voteLockEnd > block.timestamp
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

        emit Freed(msg.sender, address(sci), amount);
    }

    /**
     * @dev Toggles the `emergency` state, which overrides vote and propose locks.
     */
    function setEmergency() external onlyRole(DEFAULT_ADMIN_ROLE) {
        emergency = !emergency;
        emit EmergencySet(emergency, block.timestamp);
    }

    /**
     * @dev is called by gov contracts upon voting
     * @param user the user's address holding SCI tokens
     * @param voteLockEnd the block number where the vote lock ends
     */
    function voted(
        address user,
        uint256 voteLockEnd
    ) external onlyGov returns (bool) {
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
    ) external onlyGov returns (bool) {
        if (users[user].proposeLockEnd < proposeLockEnd) {
            users[user].proposeLockEnd = proposeLockEnd;
        }
        emit ProposeLockEndTimeUpdated(user, proposeLockEnd);
        return true;
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
     * @dev returns the SCI token contract address
     */
    function getSciAddress() external view returns (address) {
        return address(sci);
    }

    /**
     * @dev returns the total amount of locked SCI tokens
     */
    function getTotalLockedSci() external view returns (uint256) {
        return totLocked;
    }

    /**
     * @dev returns the total amount of delegated SCI tokens
     */
    function getTotalDelegated() external view returns (uint256) {
        return totDelegated;
    }

    /**
     * @dev returns the amount of locked SCI tokens of a given user
     */
    function getLockedSci(address user) external view returns (uint256) {
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
    function getProposeLockEnd(address user) external view returns (uint256) {
        return users[user].proposeLockEnd;
    }

    /**
     * @dev returns the vote lock end time
     */
    function getVoteLockEnd(address user) external view returns (uint256) {
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
