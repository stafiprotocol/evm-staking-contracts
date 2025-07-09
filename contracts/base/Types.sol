// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

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
