// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

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
    error CannotBeZero();
    error CannotBeZeroAddress();
    error CannotClaim();
    error CannotDelegateToAnotherDelegator();
    error CannotDelegateToContract();
    error CannotDelegateDuringEmergency();
    error CannotUndelegateBeforePeriodElapsed();
    error DelegateeAlreadyAdded(address delegate);
    error DelegateeNotAllowListed(address delegate);
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
        address delegatee; //Address of the delegatee
        uint256 delegationTime; // Last delegation timestamp
        uint256 undelegationTime; // Last undelegation timestamp
        address previousDelegatee; //Last delegatee the user delegated to
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
    IGovernorExecution _govExec;
    uint256 private _totLocked;
    uint256 private _totDelegated;
    uint256 private _delegateeThreshold;
    uint256 public constant TOTAL_SUPPLY_SCI = 18910000e18; //never changes
    uint256 private _minDelegationPeriod;

    mapping(address => User) public users;
    mapping(address => bool) private _delegates;

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
        if (!_govExec.hasRole(EXECUTOR_ROLE, msg.sender)) {
            revert Unauthorized(msg.sender);
        }
        _;
    }

    /*** EVENTS ***/
    event AdminSet(address indexed user, address indexed newAddress);
    event Delegated(
        address indexed owner,
        address indexed oldDelegatee,
        address indexed newDelegateee,
        uint256 delegatedAmount
    );
    event DelegateAdded(address indexed delegate);
    event DelegateRemoved(address indexed delegate);
    event DelegateThresholdUpdated();
    event EmergencySet(bool indexed emergency, uint256 timestamp);
    event Freed(address indexed user, address indexed asset, uint256 amount);
    event GovExecSet(address indexed user, address indexed newAddress);
    event GovOpsSet(address indexed user, address indexed newAddress);
    event GovResSet(address indexed user, address indexed newAddress);
    event Locked(address indexed user, address indexed asset, uint256 amount);
    event MinDelegationPeriodSet(uint256 newPeriod, uint256 timestamp);
    event ProposeLockEndTimeUpdated(address user, uint256 proposeLockEndTime);

    event Snapshotted(
        address indexed owner,
        uint256 votingRights,
        uint256 indexed blockNumber
    );
    event VoteCooldownPeriodSet(uint256 newPeriod, uint256 timestamp);
    event VoteLockEndTimeUpdated(address user, uint256 voteLockEndTime);

    constructor(address admin_, address sci_) {
        if (admin_ == address(0) || sci_ == address(0)) {
            revert CannotBeZeroAddress();
        }
        admin = admin_;
        _sci = IERC20(sci_);
        _delegateeThreshold = 50000e18;
        _delegates[address(0)] = true;
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _minDelegationPeriod = 15 minutes;
    }

    ///*** EXTERNAL FUNCTIONS ***///

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
     * @dev sets the number of tokens a user needs to lock to become a delegatee
     * @param newThreshold the new threshold set in number of tokens
     */
    function setDelegateThreshold(
        uint256 newThreshold
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _delegateeThreshold = newThreshold;
        emit DelegateThresholdUpdated();
    }

    /**
     * @dev adds an address to the delegate whitelist if tokens have been locked
     * @param newDelegatee Address to be added to the whitelist
     */
    function addDelegatee(address newDelegatee) external onlyExecutor {
        if (_delegates[newDelegatee]) {
            revert DelegateeAlreadyAdded(newDelegatee);
        }
        if (
            users[newDelegatee].lockedSci < _delegateeThreshold &&
            newDelegatee != address(0)
        )
            revert InsufficientBalance(
                users[newDelegatee].lockedSci,
                _delegateeThreshold
            );
        _delegates[newDelegatee] = true;
        emit DelegateAdded(newDelegatee);
    }

    /**
     * @dev removes an address from the delegate whitelist
     * @param formerDelegatee Address to be removed from the whitelist
     */
    function removeDelegatee(address formerDelegatee) external onlyExecutor {
        if (!_delegates[formerDelegatee]) {
            revert DelegateeNotAllowListed(formerDelegatee);
        }
        _delegates[formerDelegatee] = false;
        emit DelegateRemoved(formerDelegatee);
    }

    /**
     * @dev sets the GovernorExecution address
     */
    function setGovExec(
        address newGovernorAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _govExec = IGovernorExecution(newGovernorAddress);
        emit GovExecSet(msg.sender, newGovernorAddress);
    }

    /**
     * @dev sets the address of the operations governance smart contract
     */
    function setGovOps(
        address newGovOps
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        govOpsContract = newGovOps;
        emit GovOpsSet(msg.sender, newGovOps);
    }

    /**
     * @dev sets the address of the operations governance smart contract
     */
    function setGovRes(
        address newGovRes
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        govResContract = newGovRes;
        emit GovResSet(msg.sender, newGovRes);
    }

    /**
     * @dev sets the minimum delegation period.
     * @param newPeriod The new minimum delegation period in seconds.
     */
    function setMinDelegationPeriod(
        uint256 newPeriod
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _minDelegationPeriod = newPeriod;
        emit MinDelegationPeriodSet(newPeriod, block.timestamp);
    }

    /**
     * @dev _delegates the owner's voting rights
     * @param newDelegatee user that will receive the delegated voting rights
     */
    function delegate(address newDelegatee) external nonReentrant {
        address owner = msg.sender;
        address oldDelegate = users[owner].delegatee;
        uint256 lockedSci = users[owner].lockedSci;

        if (emergency && newDelegatee != address(0)) {
            revert CannotDelegateDuringEmergency();
        }

        if (newDelegatee != address(0) && !_delegates[newDelegatee]) {
            revert DelegateeNotAllowListed(newDelegatee);
        }

        if (owner == newDelegatee) revert SelfDelegationNotAllowed();

        if (oldDelegate == newDelegatee) revert AlreadyDelegated();

        if (lockedSci == 0 && newDelegatee != address(0)) {
            revert NoVotingPowerToDelegate();
        }

        if (users[newDelegatee].delegatee != address(0)) {
            revert CannotDelegateToAnotherDelegator();
        }

        if (oldDelegate != address(0)) {
            if (
                !emergency &&
                block.timestamp <
                users[owner].delegationTime + _minDelegationPeriod
            ) {
                revert CannotUndelegateBeforePeriodElapsed();
            }

            users[owner].voteLockEnd = Math.max(
                users[owner].voteLockEnd,
                users[oldDelegate].voteLockEnd
            );
            emit VoteLockEndTimeUpdated(owner, users[owner].voteLockEnd);

            users[oldDelegate].votingRights -= lockedSci;

            _snapshot(oldDelegate, users[oldDelegate].votingRights);

            users[owner].votingRights += lockedSci;

            _snapshot(owner, users[owner].votingRights);

            _totDelegated -= lockedSci;

            users[owner].previousDelegatee = oldDelegate;

            users[owner].undelegationTime = block.timestamp;
        }

        if (newDelegatee != address(0)) {
            users[newDelegatee].votingRights += lockedSci;

            _snapshot(newDelegatee, users[newDelegatee].votingRights);

            users[owner].votingRights = 0;

            _snapshot(owner, users[owner].votingRights);

            _totDelegated += lockedSci;

            users[owner].delegatee = newDelegatee;

            users[owner].delegationTime = block.timestamp;

            users[owner].voteLockEnd = Math.max(
                users[owner].delegationTime + _minDelegationPeriod,
                users[owner].voteLockEnd
            );
            emit VoteLockEndTimeUpdated(owner, users[owner].voteLockEnd);
        } else {
            users[owner].delegatee = address(0);

            users[owner].previousDelegatee = oldDelegate;

            users[owner].undelegationTime = block.timestamp;
        }

        emit Delegated(owner, oldDelegate, newDelegatee, lockedSci);
    }

    /**
     * @dev locks a given amount of SCI tokens
     * @param amount the amount of tokens that will be locked
     */
    function lock(uint256 amount) external nonReentrant {
        if (amount == 0) {
            revert CannotBeZero();
        }

        users[msg.sender].lockedSci += amount;

        _totLocked += amount;

        address delegated = users[msg.sender].delegatee;
        if (delegated != address(0)) {
            users[delegated].votingRights += amount;

            _snapshot(delegated, users[delegated].votingRights);

            _totDelegated += amount;

            users[msg.sender].delegationTime = block.timestamp;
        } else {
            users[msg.sender].votingRights += amount;

            _snapshot(msg.sender, users[msg.sender].votingRights);
        }

        IERC20(_sci).safeTransferFrom(msg.sender, address(this), amount);

        emit Locked(msg.sender, address(_sci), amount);
    }

    /**
     * @dev frees locked tokens after vote or proposal lock end has passed
     * @param amount the amount of tokens that will be freed
     */
    function free(uint256 amount) external nonReentrant {
        if (
            (users[msg.sender].voteLockEnd > block.timestamp ||
                users[msg.sender].proposeLockEnd > block.timestamp) &&
            !emergency
        ) {
            revert TokensStillLocked(
                users[msg.sender].voteLockEnd,
                block.timestamp
            );
        }

        if (amount == 0) {
            revert CannotBeZero();
        }

        if (users[msg.sender].lockedSci < amount) {
            revert InsufficientBalance(users[msg.sender].lockedSci, amount);
        }

        users[msg.sender].lockedSci -= amount;

        IERC20(_sci).safeTransfer(msg.sender, amount);

        if (_totLocked < amount) {
            revert InsufficientBalance(_totLocked, amount);
        }

        _totLocked -= amount;

        address delegated = users[msg.sender].delegatee;
        if (delegated != address(0)) {
            if (users[delegated].votingRights < amount) {
                revert InsufficientBalance(
                    users[delegated].votingRights,
                    amount
                );
            }
            users[delegated].votingRights -= amount;

            _snapshot(delegated, users[delegated].votingRights);

            if (_totDelegated < amount) {
                revert InsufficientBalance(
                    users[delegated].votingRights,
                    amount
                );
            }
            _totDelegated -= amount;

            if (users[msg.sender].lockedSci == 0) {
                users[msg.sender].previousDelegatee = users[msg.sender]
                    .delegatee;
                users[msg.sender].undelegationTime = block.timestamp;
                users[msg.sender].delegatee = address(0);
            }
        } else {
            if (users[msg.sender].votingRights < amount) {
                revert InsufficientBalance(
                    users[msg.sender].votingRights,
                    amount
                );
            }
            users[msg.sender].votingRights -= amount;

            _snapshot(msg.sender, users[msg.sender].votingRights);
        }

        emit Freed(msg.sender, address(_sci), amount);
    }

    /**
     * @dev toggles the `emergency` state, which overrides vote and propose locks.
     */
    function setEmergency() external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
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
     * @dev Retrieves the delegatee of a given delegator.
     * @param delegator The address of the delegator.
     * @return address The address of the delegatee or address(0) if no delegation exists.
     */
    function getCurrentDelegatee(
        address delegator
    ) external view returns (address) {
        return users[delegator].delegatee;
    }

    /**
     * @dev returns the previous delegatee of a given delegator.
     * @param delegator The address of the delegator.
     * @return address The address of the delegatee or address(0) if no delegation exists.
     */
    function getPreviousDelegatee(
        address delegator
    ) external view returns (address) {
        return users[delegator].previousDelegatee;
    }

    /**
     * @dev returns the previous delegatee of a given delegator.
     * @param delegator The address of the delegator.
     * @return address The address of the previous delegatee or address(0) if no delegation has ever existed.
     */
    function getUndelegationTime(
        address delegator
    ) external view returns (uint256) {
        return users[delegator].undelegationTime;
    }

    /**
     * @dev returns the time at which the delegator delegated their voting power.
     * @param delegator The address of the delegator.
     */
    function getDelegationTime(
        address delegator
    ) external view returns (uint256) {
        return users[delegator].delegationTime;
    }

    /**
     * @dev returns the current minimum delegation period.
     */
    function getMinDelegationPeriod() external view returns (uint256) {
        return _minDelegationPeriod;
    }

    /**
     * @dev returns the time at which the delegator can undelegate their voting power.
     * @param delegator The address of the delegator.
     */
    function getDelegationEndtime(
        address delegator
    ) external view returns (uint256) {
        return users[delegator].delegationTime + _minDelegationPeriod;
    }

    /**
     * @dev returns the current threshold to become a delegate.
     */
    function getDelegateThreshold() external view returns (uint256) {
        return _delegateeThreshold;
    }

    /**
     * @dev returns true if address is a DAO-elected delegate
     */
    function getDelegate(address delegateAddress) external view returns (bool) {
        return _delegates[delegateAddress];
    }

    /**
     * @dev returns the SCI token contract address
     */
    function getSciAddress() external view returns (address) {
        return address(_sci);
    }

    /**
     * @dev returns the total amount of locked SCI tokens
     */
    function getTotalLockedSci() external view returns (uint256) {
        return _totLocked;
    }

    /**
     * @dev returns the total amount of delegated SCI tokens
     */
    function getTotalDelegated() external view returns (uint256) {
        return _totDelegated;
    }

    /**
     * @dev returns the amount of locked SCI tokens of a given user
     */
    function getLockedSci(address user) external view returns (uint256) {
        return users[user].lockedSci;
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
