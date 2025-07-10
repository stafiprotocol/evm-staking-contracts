// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";

// export PRIVATE_KEY=0xXXXXX
// export STAKING=0xXXXXX
// forge script script/DeployTestToken.s.sol --rpc-url https://evmrpc-testnet.0g.ai --broadcast
contract DeployPresetTokenAndApprove is Script {
    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address stakingAddress = vm.envAddress("STAKING");
        vm.startBroadcast(privateKey);

        address deployer = vm.addr(privateKey);

        ERC20PresetMinterPauser token = new ERC20PresetMinterPauser("TestToken", "TT");
        console.log("Preset Token deployed at:", address(token));

        uint256 mintAmount = 1_000_000 ether;
        token.mint(deployer, mintAmount);
        console.log("Minted", mintAmount / 1 ether, "tokens to deployer");

        uint256 approveAmount = 100_000 ether;
        token.approve(stakingAddress, approveAmount);
        console.log("Approved", approveAmount / 1 ether, "tokens to staking");

        vm.stopBroadcast();
    }
}
