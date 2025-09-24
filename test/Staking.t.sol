// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {StakingRewards, IERC20} from "../src/StakingRewards.sol";
import {MockERC20} from "../src/MockErc20.sol";

contract StakingTest is Test {
    StakingRewards staking;
    MockERC20 stakingToken;
    MockERC20 rewardToken;

    address owner = makeAddr("owner");
    address bob = makeAddr("bob");
    address dso = makeAddr("dso");

    function setUp() public {
        vm.startPrank(owner);
        stakingToken = new MockERC20();
        rewardToken = new MockERC20();
        staking = new StakingRewards(
            address(stakingToken),
            address(rewardToken)
        );
        vm.stopPrank();
    }

    function test_alwaysPass() public {
        assertEq(staking.owner(), owner, "Wrong owner set");
        assertEq(
            address(staking.stakingToken()),
            address(stakingToken),
            "Wrong staking token address"
        );
        assertEq(
            address(staking.rewardsToken()),
            address(rewardToken),
            "Wrong reward token address"
        );

        assertTrue(true);
    }

    function test_cannot_stake_amount0() public {
        deal(address(stakingToken), bob, 10e18);
        // start prank to assume user is making subsequent calls
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(
            address(staking),
            type(uint256).max
        );

        // we are expecting a revert if we deposit/stake zero
        vm.expectRevert("amount = 0");
        staking.stake(0);
        vm.stopPrank();
    }

    function test_can_stake_successfully() public {
        deal(address(stakingToken), bob, 10e18);
        // start prank to assume user is making subsequent calls
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(
            address(staking),
            type(uint256).max
        );
        uint256 _totalSupplyBeforeStaking = staking.totalSupply();
        staking.stake(5e18);
        assertEq(staking.balanceOf(bob), 5e18, "Amounts do not match");
        assertEq(
            staking.totalSupply(),
            _totalSupplyBeforeStaking + 5e18,
            "totalsupply didnt update correctly"
        );
    }

    function test_cannot_withdraw_amount0() public {
        vm.prank(bob);
        vm.expectRevert("amount = 0");
        staking.withdraw(0);
    }

    function test_can_withdraw_deposited_amount() public {
        test_can_stake_successfully();

        uint256 userStakebefore = staking.balanceOf(bob);
        uint256 totalSupplyBefore = staking.totalSupply();
        staking.withdraw(2e18);
        assertEq(
            staking.balanceOf(bob),
            userStakebefore - 2e18,
            "Balance didnt update correctly"
        );
        assertLt(
            staking.totalSupply(),
            totalSupplyBefore,
            "total supply didnt update correctly"
        );
        vm.stopPrank();
    }

    function test_reward_per_token() public {}

    function test_notify_Rewards() public {
        // check that it reverts if non owner tried to set duration
        vm.expectRevert("not authorized");
        staking.setRewardsDuration(1 weeks);

        // simulate owner calls setReward successfully
        vm.prank(owner);
        staking.setRewardsDuration(1 weeks);
        assertEq(staking.duration(), 1 weeks, "duration not updated correctly");
        // log block.timestamp
        console.log("current time", block.timestamp);
        // move time foward
        vm.warp(block.timestamp + 200);
        // notify rewards
        deal(address(rewardToken), owner, 100 ether);
        vm.startPrank(owner);
        IERC20(address(rewardToken)).transfer(address(staking), 100 ether);

        // trigger revert
        vm.expectRevert("reward rate = 0");
        staking.notifyRewardAmount(1);

        // trigger second revert
        vm.expectRevert("reward amount > balance");
        staking.notifyRewardAmount(200 ether);

        // trigger first type of flow success
        staking.notifyRewardAmount(100 ether);
        assertEq(staking.rewardRate(), uint256(100 ether) / uint256(1 weeks));
        assertEq(
            staking.finishAt(),
            uint256(block.timestamp) + uint256(1 weeks)
        );
        assertEq(staking.updatedAt(), block.timestamp);

        // trigger setRewards distribution revert
        vm.expectRevert("reward duration not finished");
        staking.setRewardsDuration(1 weeks);
    }

    function test_finshat_notifyRewards() public {
        // 1. Set duration
        vm.prank(owner);
        staking.setRewardsDuration(2 weeks);
        assertEq(staking.duration(), 2 weeks, "duration not updated");

        // 2. Fund the contract with reward tokens
        deal(address(rewardToken), owner, 200 ether);

        // 3. First notify to start reward distribution
        vm.startPrank(owner);
        rewardToken.transfer(address(staking), 100 ether);
        staking.notifyRewardAmount(100 ether); // sets initial rewardRate and finishAt

        uint256 firstRewardRate = staking.rewardRate();
        uint256 firstFinishAt = staking.finishAt();

        // 4. Fast forward time (but not past finishAt)
        vm.warp(block.timestamp + 1 weeks); // halfway through

        // 5. Transfer more tokens to the staking contract
        rewardToken.transfer(address(staking), 100 ether);

        // 6. Capture expected values before calling
        uint256 timeLeft = firstFinishAt - block.timestamp;
        uint256 remainingRewards = timeLeft * firstRewardRate;
        uint256 expectedRewardRate = (100 ether + remainingRewards) /
            staking.duration();

        // 7. Call notifyRewardAmount again
        staking.notifyRewardAmount(100 ether); // hits second branch

        // 8. Assertions
        assertApproxEqAbs(
            staking.rewardRate(),
            expectedRewardRate,
            1,
            "rewardRate mismatch"
        );
        assertEq(
            staking.finishAt(),
            block.timestamp + staking.duration(),
            "finishAt incorrect"
        );
        assertEq(staking.updatedAt(), block.timestamp, "updatedAt incorrect");

        vm.stopPrank();
    }

    function test_get_Rewards() public {
        vm.prank(owner);
        staking.setRewardsDuration(1 weeks);
        assertEq(staking.duration(), 1 weeks, "duration not updated correctly");
        // log block.timestamp
        console.log("current time", block.timestamp);
        // move time foward
        vm.warp(block.timestamp + 200);
        // notify rewards
        deal(address(rewardToken), owner, 100 ether);
        vm.startPrank(owner);
        IERC20(address(rewardToken)).transfer(address(staking), 100 ether);

        staking.notifyRewardAmount(100 ether);
        vm.stopPrank();

        test_can_stake_successfully();

        uint256 userStakebefore = staking.balanceOf(bob);
        uint256 totalSupplyBefore = staking.totalSupply();

        vm.warp(block.timestamp + 20000);

        staking.withdraw(2e18);
        assertEq(
            staking.balanceOf(bob),
            userStakebefore - 2e18,
            "Balance didnt update correctly"
        );
        assertLt(
            staking.totalSupply(),
            totalSupplyBefore,
            "total supply didnt update correctly"
        );
        uint256 bobEarning = staking.earned(bob);
        staking.getReward();

        assertGt(rewardToken.balanceOf(bob), 0, "No Rewards");
        assertEq(rewardToken.balanceOf(bob), bobEarning, "I no sabi");

        vm.stopPrank();
    }


        function test_lastTimeRewardApplicable_beforeFinish() public {
        vm.prank(owner);
        staking.setRewardsDuration(1 weeks);

        // Fund and notify reward
        deal(address(rewardToken), owner, 100 ether);
        vm.startPrank(owner);
        rewardToken.transfer(address(staking), 100 ether);
        staking.notifyRewardAmount(100 ether);
        vm.stopPrank();

        uint256 finishAt = staking.finishAt();
        uint256 current = block.timestamp;

        // Case: block.timestamp < finishAt
        assertEq(staking.lastTimeRewardApplicable(), current);
    }

    function test_lastTimeRewardApplicable_afterFinish() public {
        vm.prank(owner);
        staking.setRewardsDuration(1 weeks);

        deal(address(rewardToken), owner, 100 ether);
        vm.startPrank(owner);
        rewardToken.transfer(address(staking), 100 ether);
        staking.notifyRewardAmount(100 ether);
        vm.stopPrank();

        uint256 finishAt = staking.finishAt();

        // warp past finishAt
        vm.warp(finishAt + 10);

        // Case: block.timestamp > finishAt
        assertEq(staking.lastTimeRewardApplicable(), finishAt);
    }

}
