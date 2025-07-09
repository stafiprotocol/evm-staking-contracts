pragma solidity 0.8.19;

// SPDX-License-Identifier: GPL-3.0-only
import "./base/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract Staking is Initializable, UUPSUpgradeable, Ownable {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.UintSet;

    uint256 public constant MIN_STAKE_AMOUNT = 1e9;

    struct UserInfo {
        uint256 amount;
        uint256 reward;
        uint256 rewardDebt;
    }

    struct PoolInfo {
        address admin;
        IERC20 stakeToken;
        uint256 minStakeAmount;
        uint256 rewardRate;
        uint256 totalStake;
        RewardAlgorithm rewardAlgorithm;
        uint256 totalReward;
        uint256 undistributedReward;
        uint256 lastRewardTimestamp;
        uint256 rewardPerShare;
        uint256 unbondingSeconds;
        uint256 nextUnstakeIndex;
    }

    struct UnstakeInfo {
        uint256 amount;
        uint256 withdrawableTimestamp;
    }

    enum RewardAlgorithm {
        FixedPerTokenPerSecond,
        FixedTotalPerSecond
    }

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
            uint256 reward = _getPoolReward(pool);
            rewardPerShare += reward * 1e12 / pool.totalStake;
        }
        return user.amount * rewardPerShare / 1e12 - user.rewardDebt;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function getUnstakeIndexListOf(uint256 _pid, address _staker) public view virtual returns (uint256[] memory) {
        return unstakesOfUser[_pid][_staker].values();
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

        _updatePool(_pid);

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
        _updatePool(_pid);
        PoolInfo storage pool = poolInfo[_pid];
        if (pool.admin != msg.sender) revert CallerNotAllowed();

        pool.rewardRate = _rewardRate;
        pool.rewardAlgorithm = _rewardAlgorithm;
    }

    // ------------ staker ------------

    function stake(uint256 _pid, uint256 _amount) public {
        if (_amount < MIN_STAKE_AMOUNT) revert AmountNotMatch();

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        _updatePool(_pid);

        if (user.amount > 0) {
            uint256 pending = user.amount * pool.rewardPerShare / 1e12 - user.rewardDebt;
            user.reward += pending;
        }

        pool.stakeToken.safeTransferFrom(address(msg.sender), address(this), _amount);

        user.amount += _amount;
        pool.totalStake += _amount;

        user.rewardDebt = user.amount * pool.rewardPerShare / 1e12;

        emit Stake(msg.sender, _pid, _amount);
    }

    function unstake(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        if (_amount == 0 || user.amount < _amount) revert AmountNotMatch();

        _updatePool(_pid);

        uint256 pending = user.amount * pool.rewardPerShare / 1e12 - user.rewardDebt;

        user.reward += pending;
        user.amount -= _amount;
        pool.totalStake -= _amount;
        pool.stakeToken.safeTransfer(address(msg.sender), _amount);

        user.rewardDebt = user.amount * pool.rewardPerShare / 1e12;

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
            totalWithdrawAmount = totalWithdrawAmount + unstakeInfo.amount;

            emit Withdraw(msg.sender, _pid, unstakeInfo.amount);
        }

        if (totalWithdrawAmount > 0) {
            IERC20(pool.stakeToken).safeTransfer(msg.sender, totalWithdrawAmount);
        }
    }

    function claim(uint256 _pid, bool restake) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        _updatePool(_pid);

        if (user.amount > 0) {
            uint256 pending = user.amount * pool.rewardPerShare / 1e12 - user.rewardDebt;
            user.reward += pending;
        }

        if (user.reward > 0) {
            if (restake) {
                user.amount += user.reward;
                user.rewardDebt = user.amount * pool.rewardPerShare / 1e12;
            } else {
                IERC20(pool.stakeToken).safeTransfer(msg.sender, user.reward);
            }

            emit Claim(msg.sender, _pid, user.reward);

            user.reward = 0;
        }
    }

    // ------------ helper ------------
    function _updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardTimestamp) {
            return;
        }
        if (pool.totalStake == 0) {
            pool.lastRewardTimestamp = block.timestamp;
            return;
        }
        uint256 reward = _getPoolReward(pool);

        if (reward > 0) {
            pool.undistributedReward = pool.undistributedReward - reward;
            pool.rewardPerShare += reward * 1e12 / pool.totalStake;
        }
        pool.lastRewardTimestamp = block.timestamp;
    }

    function _safeTransfer(address _token, address _to, uint256 _amount) internal {
        uint256 bal = IERC20(_token).balanceOf(address(this));
        require(bal >= _amount, "balance not enough");
        IERC20(_token).safeTransfer(_to, _amount);
    }

    function _getPoolReward(PoolInfo memory pool) public view returns (uint256) {
        if (pool.rewardAlgorithm == RewardAlgorithm.FixedPerTokenPerSecond) {
            uint256 amount = pool.totalStake * (block.timestamp - pool.lastRewardTimestamp) * pool.rewardRate / 1e18;
            return pool.undistributedReward < amount ? pool.undistributedReward : amount;
        } else if (pool.rewardAlgorithm == RewardAlgorithm.FixedTotalPerSecond) {
            uint256 amount = (block.timestamp - pool.lastRewardTimestamp) * pool.rewardRate;
            return pool.undistributedReward < amount ? pool.undistributedReward : amount;
        } else {
            revert RewardAlgorithmNotSupport();
        }
    }
}
