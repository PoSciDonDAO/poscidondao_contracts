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
    error IncorrectBlockNumber();
    error IncorrectSnapshotIndex();
    error InsufficientBalance(uint256 currentDeposit, uint256 requestedAmount);
    error NotGovernanceContract(address govAddress);
    error TokensStillLocked(uint256 voteLockEndStamp, uint256 currentTimeStamp);
    error Unauthorized(address user);
    error UnauthorizedDelegation();
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
        address delegate; //Address of the delegate
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
    address public govContract;

    ///*** MODIFIER ***///
    modifier gov() {
        if (msg.sender != govContract) revert Unauthorized(msg.sender);
        _;
    }

    /*** EVENTS ***/
    event Locked(
        address indexed token,
        address indexed user,
        uint256 amountLocked
    );
    event Freed(
        address indexed token,
        address indexed user,
        uint256 amountFreed
    );
    event Delegated(address indexed owner, address indexed newDelegate);
    event VoteLockTimeUpdated(address user, uint256 voteLockEndTime);

    constructor(address treasuryWallet_, address sci_) {
        _setupRole(DEFAULT_ADMIN_ROLE, treasuryWallet_);

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
    function setGov(address newGov) external onlyRole(DEFAULT_ADMIN_ROLE) {
        govContract = newGov;
    }

    /**
     * @dev delegates the owner's voting rights
     * @param owner the owner of the delegated voting rights
     * @param newDelegate user that will receive the delegated voting rights
     */
    function delegate(address owner, address newDelegate) external {
        address oldDelegate = users[owner].delegate;

        if (oldDelegate == newDelegate) revert AlreadyDelegated();

        //check if function caller can change delegation
        if (
            owner != msg.sender
            // || //owner can change delegates
            // (oldDelegate != msg.sender && newDelegate != address(0)) //delegates can remove delegations from themselves
        ) revert UnauthorizedDelegation();

        users[owner].delegate = newDelegate;

        //update vote unlock time
        if (oldDelegate != address(0)) {
            users[owner].voteLockEnd = Math.max(
                users[owner].voteLockEnd,
                users[oldDelegate].voteLockEnd
            );

            users[oldDelegate].votingRights -= users[owner].votingRights;

            _snapshot(oldDelegate, users[oldDelegate].votingRights);
        }

        //update voting rights for delegate
        if (newDelegate != address(0)) {
            users[newDelegate].votingRights += users[owner].votingRights;

            _snapshot(newDelegate, users[newDelegate].votingRights);
            //update owner's voting power
            users[owner].votingRights = 0;

            _snapshot(owner, users[owner].votingRights);
        }

        emit Delegated(owner, newDelegate);
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

            address delegated = users[user].delegate;
            if (delegated != address(0)) {
                //update voting rights for delegated address
                users[delegated].votingRights += amount;
                //snapshot of delegate's voting rights
                _snapshot(delegated, users[delegated].votingRights);

                emit Locked(address(_sci), user, amount);
            } else {
                //update voting rights for user
                users[user].votingRights += amount;
                //snapshot of voting rights
                _snapshot(user, users[user].votingRights);

                emit Locked(address(_sci), user, amount);
            }
        } else if (src == address(_po)) {
            //retrieve balance of user
            uint256 balance = _po.balanceOf(user);

            //check if user has enough PO tokens
            if (balance < amount) revert InsufficientBalance(balance, amount);

            //Retrieve PO token from user wallet
            _po.push(user, amount);

            //update staked PO balance
            users[user].stakedPo += amount;

            //emit locked event
            emit Locked(address(_po), user, amount);
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

            address delegated = users[user].delegate;
            if (delegated != address(0)) {
                //check if delegate did not vote recently
                if (users[delegated].voteLockEnd <= block.timestamp) {
                    revert TokensStillLocked(
                        block.timestamp,
                        users[delegated].voteLockEnd
                    );
                }

                //remove delegate voting rights
                users[delegated].votingRights -= amount;

                _snapshot(delegated, users[delegated].votingRights);
            } else {
                //add new amount of votes as rights
                users[user].votingRights -= amount;

                //snapshot of voting rights
                _snapshot(user, users[user].votingRights);
            }

            emit Freed(address(_sci), user, amount);
        } else if (src == address(_po)) {
            //check if amount is lower than deposited PO tokens
            if (users[user].stakedPo < amount)
                revert InsufficientBalance(users[user].stakedPo, amount);

            //Retrieve PO token from staking contract
            _po.pull(user, amount);

            //update staked PO balance
            users[user].stakedPo -= amount;

            emit Freed(address(_po), user, amount);
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
    function _snapshot(address user, uint256 votingRights) internal {
        uint256 index = users[user].amtSnapshots;
        if (index > 0 && users[user].snapshots[index].atBlock == block.number) {
            users[user].snapshots[index].rights = votingRights;
        } else {
            users[user].amtSnapshots = index += 1;
            users[user].snapshots[index] = Snapshot(block.number, votingRights);
        }
    }
}
