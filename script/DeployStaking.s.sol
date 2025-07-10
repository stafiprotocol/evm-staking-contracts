// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import {Staking} from "../contracts/Staking.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// export PRIVATE_KEY=0xXXXXX
// forge script script/DeployStaking.s.sol --rpc-url https://evmrpc-testnet.0g.ai --broadcast

contract DeployStakingScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        // deploy logic contracts
        address stakingLogic = address(new Staking());

        // deploy proxy contracts
        address stakingProxy = address(new ERC1967Proxy(stakingLogic, ""));

        Staking staking = Staking(payable(stakingProxy));

        // initialize proxy contract
        staking.initialize();

        console.log("Staking Proxy deployed at:", address(stakingProxy));

        vm.stopBroadcast();
    }
}
