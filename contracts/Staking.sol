pragma solidity 0.8.19;

// SPDX-License-Identifier: GPL-3.0-only
import "./base/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract Staking is Initializable, UUPSUpgradeable, Ownable {
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 amount;
        uint256 reward;
        uint256 rewardDebt;
    }

    struct PoolInfo {
        IERC20 stakeToken;
        uint256 rewardRate;
        uint256 totalStake;
        uint256 totalReward;
        uint256 undistributedReward;
        uint256 lastRewardTimestamp;
        uint256 rewardPerShare;
        uint256 unbondingSeconds;
    }

    PoolInfo[] public poolInfo;
    // pid => user address => info
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() external initializer {
        _initOwner(msg.sender);
    }

    receive() external payable {}

    function _authorizeUpgrade(address _newImplementation) internal override onlyOwner {}

    // ------------ getter ------------

    function version() external view returns (uint8) {
        return _getInitializedVersion();
    }

    // ------------ user ------------

    function createPool(IERC20 _stakeToken, uint256 _rewardRate, uint256 _totalReward, uint256 _unbondingSeconds)
        public
    {
        _stakeToken.safeTransferFrom(address(msg.sender), address(this), _totalReward);

        poolInfo.push(
            PoolInfo({
                stakeToken: _stakeToken,
                rewardRate: _rewardRate,
                totalStake: 0,
                totalReward: _totalReward,
                undistributedReward: _totalReward,
                lastRewardTimestamp: 0,
                rewardPerShare: 0,
                unbondingSeconds: _unbondingSeconds
            })
        );
    }

    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardTimestamp) {
            return;
        }
        if (pool.totalStake == 0) {
            pool.lastRewardTimestamp = block.timestamp;
            return;
        }
        uint256 reward =
            getPoolReward(pool.lastRewardTimestamp, block.timestamp, pool.rewardRate, pool.undistributedReward);

        if (reward > 0) {
            pool.undistributedReward = pool.undistributedReward - reward;
            pool.rewardPerShare += reward * 1e12 / pool.totalStake;
        }
        pool.lastRewardTimestamp = block.timestamp;
    }

    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        updatePool(_pid);

        if (user.amount > 0) {
            uint256 pending = user.amount * pool.rewardPerShare / 1e12 - user.rewardDebt;
            if (pending > 0) {
                user.reward += pending;
            }
        }
        if (_amount > 0) {
            pool.stakeToken.safeTransferFrom(address(msg.sender), address(this), _amount);

            user.amount += _amount;
            pool.totalStake += _amount;
        }

        user.rewardDebt = user.amount * pool.rewardPerShare / 1e12;

        emit Deposit(msg.sender, _pid, _amount);
    }

    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        require(_amount > 0 && user.amount >= _amount, "withdraw: not good");

        updatePool(_pid);

        uint256 pending = user.amount * pool.rewardPerShare / 1e12 - user.rewardDebt;
        if (pending > 0) {
            user.reward += pending;
        }
        if (_amount > 0) {
            user.amount -= _amount;
            pool.totalStake -= _amount;
            pool.stakeToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount * pool.rewardPerShare / 1e12;

        emit Withdraw(msg.sender, _pid, _amount);
    }

    function claimReward(uint256 _pid) public {
        deposit(_pid, 0);
    }

    function _safeTransfer(address _token, address _to, uint256 _amount) internal {
        uint256 bal = IERC20(_token).balanceOf(address(this));
        require(bal >= _amount, "balance not enough");
        IERC20(_token).safeTransfer(_to, _amount);
    }

    function getPoolReward(uint256 _from, uint256 _to, uint256 _rewardRate, uint256 _undistributedReward)
        public
        pure
        returns (uint256)
    {
        uint256 amount = (_to - _from) * _rewardRate;
        return _undistributedReward < amount ? _undistributedReward : amount;
    }

    function getUserClaimableReward(uint256 _pid, address _user) public view returns (uint256) {
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo memory user = userInfo[_pid][_user];
        uint256 rewardPerShare = pool.rewardPerShare;
        if (block.timestamp > pool.lastRewardTimestamp && pool.totalStake > 0) {
            uint256 reward =
                getPoolReward(pool.lastRewardTimestamp, block.timestamp, pool.rewardRate, pool.undistributedReward);
            rewardPerShare += reward * 1e12 / pool.totalStake;
        }
        return user.amount * rewardPerShare / 1e12 - user.rewardDebt;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }
}
