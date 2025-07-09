// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.19;

import "./Types.sol";
import "./Errors.sol";

library UserLib {
    function updateReward(UserInfo storage self, uint256 _rewardPerShare) internal {
        if (self.amount > 0) {
            self.reward += self.amount * _rewardPerShare / 1e12 - self.rewardDebt;
        }
    }

    function updateRewardDebt(UserInfo storage self, uint256 _rewardPerShare) internal {
        self.rewardDebt = self.amount * _rewardPerShare / 1e12;
    }
}
