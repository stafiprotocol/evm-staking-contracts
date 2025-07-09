// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.19;

import "./Types.sol";
import "./Errors.sol";

library PoolLib {
    function updatePool(PoolInfo storage self) internal {
        if (block.timestamp <= self.lastRewardTimestamp) {
            return;
        }
        if (self.totalStake == 0) {
            self.lastRewardTimestamp = block.timestamp;
            return;
        }
        uint256 reward = PoolLib.getPoolRewardWithStorage(self);

        if (reward > 0) {
            self.undistributedReward = self.undistributedReward - reward;
            self.rewardPerShare += reward * 1e12 / self.totalStake;
        }
        self.lastRewardTimestamp = block.timestamp;
    }

    function getPoolRewardWithStorage(PoolInfo storage self) internal view returns (uint256) {
        if (self.rewardAlgorithm == RewardAlgorithm.FixedPerTokenPerSecond) {
            uint256 amount = self.totalStake * (block.timestamp - self.lastRewardTimestamp) * self.rewardRate / 1e18;
            return self.undistributedReward < amount ? self.undistributedReward : amount;
        } else if (self.rewardAlgorithm == RewardAlgorithm.FixedTotalPerSecond) {
            uint256 amount = (block.timestamp - self.lastRewardTimestamp) * self.rewardRate;
            return self.undistributedReward < amount ? self.undistributedReward : amount;
        } else {
            revert Errors.RewardAlgorithmNotSupport();
        }
    }

    function getPoolReward(PoolInfo memory self) internal view returns (uint256) {
        if (self.rewardAlgorithm == RewardAlgorithm.FixedPerTokenPerSecond) {
            uint256 amount = self.totalStake * (block.timestamp - self.lastRewardTimestamp) * self.rewardRate / 1e18;
            return self.undistributedReward < amount ? self.undistributedReward : amount;
        } else if (self.rewardAlgorithm == RewardAlgorithm.FixedTotalPerSecond) {
            uint256 amount = (block.timestamp - self.lastRewardTimestamp) * self.rewardRate;
            return self.undistributedReward < amount ? self.undistributedReward : amount;
        } else {
            revert Errors.RewardAlgorithmNotSupport();
        }
    }
}
