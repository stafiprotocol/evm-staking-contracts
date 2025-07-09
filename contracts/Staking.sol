pragma solidity 0.8.19;

// SPDX-License-Identifier: GPL-3.0-only
import "./base/Ownable.sol";
import "./base/Types.sol";
import "./base/PoolLib.sol";
import "./base/UserLib.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract Staking is Initializable, UUPSUpgradeable, Ownable {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.UintSet;
    using PoolLib for PoolInfo;
    using UserLib for UserInfo;

    uint256 public constant MIN_STAKE_AMOUNT = 1e9;
    uint256 public constant UNSTAKE_TIMES_LIMIT = 100;

    PoolInfo[] public poolInfo;

    // pid => user address => info
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    // pid => unstakeIndex => info
    mapping(uint256 => mapping(uint256 => UnstakeInfo)) public unstakeAtIndex;

    // pid => user address => set
    mapping(uint256 => mapping(address => EnumerableSet.UintSet)) unstakesOfUser;

    event Stake(address indexed user, uint256 indexed pid, uint256 amount);
    event Unstake(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Claim(address indexed user, uint256 indexed pid, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() external initializer {
        _initOwner(msg.sender);
    }

    function _authorizeUpgrade(address _newImplementation) internal override onlyOwner {}

    // ------------ getter ------------

    function version() external view returns (uint8) {
        return _getInitializedVersion();
    }

    function getUserClaimableReward(uint256 _pid, address _user) public view returns (uint256) {
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo memory user = userInfo[_pid][_user];
        uint256 rewardPerShare = pool.rewardPerShare;
        if (block.timestamp > pool.lastRewardTimestamp && pool.totalStake > 0) {
            uint256 reward = pool.getPoolReward();
            rewardPerShare += reward * 1e12 / pool.totalStake;
        }
        return user.amount * rewardPerShare / 1e12 - user.rewardDebt;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function getUnstakeIndexListOf(uint256 _pid, address _staker) public view returns (uint256[] memory) {
        return unstakesOfUser[_pid][_staker].values();
    }

    function getUserInfo(uint256 _pid, address _staker) public view returns (UserInfo memory) {
        return userInfo[_pid][_staker];
    }

    function getPoolInfo(uint256 _pid) public view returns (PoolInfo memory) {
        return poolInfo[_pid];
    }

    // ------------ pool creater ------------

    function createPool(
        IERC20 _stakeToken,
        uint256 _rewardRate,
        uint256 _totalReward,
        uint256 _unbondingSeconds,
        RewardAlgorithm _rewardAlgorithm
    ) public {
        _stakeToken.safeTransferFrom(address(msg.sender), address(this), _totalReward);

        poolInfo.push(
            PoolInfo({
                admin: msg.sender,
                stakeToken: _stakeToken,
                minStakeAmount: 0,
                rewardRate: _rewardRate,
                totalStake: 0,
                rewardAlgorithm: _rewardAlgorithm,
                totalReward: _totalReward,
                undistributedReward: _totalReward,
                lastRewardTimestamp: 0,
                rewardPerShare: 0,
                unbondingSeconds: _unbondingSeconds,
                nextUnstakeIndex: 0
            })
        );
    }

    function addRewards(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (pool.admin != msg.sender) revert CallerNotAllowed();

        pool.updatePool();

        pool.stakeToken.safeTransferFrom(address(msg.sender), address(this), _amount);

        pool.totalReward += _amount;
        pool.undistributedReward += _amount;
    }

    function updateMinStakeAmount(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (pool.admin != msg.sender) revert CallerNotAllowed();

        pool.minStakeAmount = _amount;
    }

    function updateUnbondingSeconds(uint256 _pid, uint256 _unbondingSeconds) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (pool.admin != msg.sender) revert CallerNotAllowed();

        pool.unbondingSeconds = _unbondingSeconds;
    }

    function updateRewardRate(uint256 _pid, uint256 _rewardRate, RewardAlgorithm _rewardAlgorithm) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (pool.admin != msg.sender) revert CallerNotAllowed();
        pool.updatePool();

        pool.rewardRate = _rewardRate;
        pool.rewardAlgorithm = _rewardAlgorithm;
    }

    // ------------ staker ------------

    function stake(uint256 _pid, uint256 _amount) public {
        if (_amount < MIN_STAKE_AMOUNT) revert AmountNotMatch();

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        pool.stakeToken.safeTransferFrom(address(msg.sender), address(this), _amount);

        pool.updatePool();

        user.updateReward(pool.rewardPerShare);

        user.amount += _amount;
        pool.totalStake += _amount;

        user.updateRewardDebt(pool.rewardPerShare);

        emit Stake(msg.sender, _pid, _amount);
    }

    function unstake(uint256 _pid, uint256 _amount) public {
        if (unstakesOfUser[_pid][msg.sender].length() >= UNSTAKE_TIMES_LIMIT) revert UnstakeTimesExceedLimit();

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        if (_amount == 0 || user.amount < _amount) revert AmountNotMatch();

        pool.updatePool();

        user.updateReward(pool.rewardPerShare);

        user.amount -= _amount;
        pool.totalStake -= _amount;

        user.updateRewardDebt(pool.rewardPerShare);

        // unstake info
        uint256 willUseUnstakeIndex = pool.nextUnstakeIndex;
        pool.nextUnstakeIndex = willUseUnstakeIndex + 1;

        unstakeAtIndex[_pid][willUseUnstakeIndex] =
            UnstakeInfo({amount: _amount, withdrawableTimestamp: pool.unbondingSeconds + block.timestamp});
        unstakesOfUser[_pid][msg.sender].add(willUseUnstakeIndex);

        emit Unstake(msg.sender, _pid, _amount);
    }

    function withdraw(uint256 _pid) public {
        uint256 totalWithdrawAmount;
        uint256[] memory unstakeIndexList = unstakesOfUser[_pid][msg.sender].values();

        PoolInfo memory pool = poolInfo[_pid];
        for (uint256 i = 0; i < unstakeIndexList.length; ++i) {
            UnstakeInfo memory unstakeInfo = unstakeAtIndex[_pid][unstakeIndexList[i]];
            if (unstakeInfo.withdrawableTimestamp > block.timestamp) {
                continue;
            }
            if (!unstakesOfUser[_pid][msg.sender].remove(unstakeIndexList[i])) revert AlreadyWithdrawed();
            totalWithdrawAmount += unstakeInfo.amount;

            emit Withdraw(msg.sender, _pid, unstakeInfo.amount);
        }

        if (totalWithdrawAmount > 0) {
            IERC20(pool.stakeToken).safeTransfer(msg.sender, totalWithdrawAmount);
        }
    }

    function claim(uint256 _pid, bool restake) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        pool.updatePool();

        user.updateReward(pool.rewardPerShare);

        uint256 claimAmount = user.reward;
        user.reward = 0;

        if (claimAmount > 0) {
            if (restake) {
                pool.totalStake += claimAmount;
                user.amount += claimAmount;

                user.updateRewardDebt(pool.rewardPerShare);
            } else {
                IERC20(pool.stakeToken).safeTransfer(msg.sender, claimAmount);
            }

            emit Claim(msg.sender, _pid, claimAmount);
        }
    }
}
