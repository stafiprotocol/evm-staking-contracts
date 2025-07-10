// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Test, console, Vm} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../contracts/Staking.sol";

contract StakingTest is Test {
    address public owner = vm.addr(1);

    Staking public staking;

    function setUp() public {
        // deploy logic contracts
        address stakingLogic = address(new Staking());

        // deploy proxy contracts
        address stakingProxy = address(new ERC1967Proxy(stakingLogic, ""));

        staking = Staking(payable(stakingProxy));

        // initialize proxy contract
        staking.initialize();
    }

    // forge test
    function testVersion() public {
        assertEq(staking.version(), 1);
    }
}
