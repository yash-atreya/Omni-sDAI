// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.16;

import "forge-std/console.sol";
import "./common/CommonOptimisticOracleV3Test.sol";
import "../src/Goerli/DataAsserterGoerli.sol";
import "../src/Scroll/ScrollSavingsDai.sol";
import "../src/Goerli/TokenPool.sol";
import "../src/SavingsDai.sol"; // Mainnet contract
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DepositFlowTest is CommonOptimisticOracleV3Test {
    // Contract Instances

    // Mainnet/Goerli
    DataAsserter public dataAsserter;
    ERC20 mainnetDai = ERC20(address(0x6B175474E89094C44Da98b954EedeAC495271d0F)); // DAI on Mainnet
    SavingsDai savingsDai = SavingsDai(address(0x83F20F44975D03b1b09e64809B757c47f942BEeA)); // SavingsDai on Mainnet
    TokenPool daiPool; // Dai liquidity pool - used to mint sDAI on mainnet.

    // Scroll
    ERC20 scrollDai; // Scroll doesn't have bridged DAI.
    ScrollSavingsDai public scrollSavingsDai; // Scroll SavingsDai - Representation of SavingsDai from

    // Forks
    uint256 mainnetFork;
    uint256 scrollFork;

    // Dummy Accounts
    address liquidityProvider = address(0x1234325); // Provides liquidity to TokenPool (daiPool)

    // Events
    event Deposited(address indexed depositor, uint256 indexed amount);
    event DepositAsserted(address indexed depositor, uint256 indexed amount, bytes32 indexed assertionId);
    event DepositAssertionResolved(bytes32 indexed depositId, address indexed asserter, bytes32 indexed assertionId);
    event LiquidityAdded(address indexed provider, uint256 indexed amount);
    event LiquidityRemoved(address indexed provider, uint256 indexed amount);

    function setUp() public {
        // Create Forks
        mainnetFork = vm.createFork(vm.envString("MAINNET_RPC"));
        scrollFork = vm.createFork(vm.envString("SCROLL_RPC"));

        // Deploy Oracle and DataAsserter on Mainnet/Goerli
        vm.selectFork(mainnetFork);
        _commonSetup();
        daiPool = new TokenPool(address(mainnetDai), address(savingsDai));
        console.log("TokenPool deployed at address: ", address(daiPool), " on fork_id: ", vm.activeFork());
        dataAsserter = new DataAsserter(address(defaultCurrency), address(optimisticOracleV3), address(daiPool));
        console.log("DataAsserter deployed at address: ", address(dataAsserter), " on fork_id: ", vm.activeFork());
        daiPool.setDataAsserter(address(dataAsserter)); // Set DataAsserter on TokenPool

        // Deploy ScrollSavingsDai on Scroll
        vm.selectFork(scrollFork);
        scrollDai = new ERC20("ScrollDAI", "sclDAI"); // Scroll doesn't have bridged DAI. Create our own.
        scrollSavingsDai = new ScrollSavingsDai(address(scrollDai));
        console.log(
            "ScrollSavingsDai deployed at address: ", address(scrollSavingsDai), " on fork_id: ", vm.activeFork()
        );

        // Deal
        deal(address(scrollDai), address(this), 1000);
        vm.selectFork(mainnetFork);
        deal(address(mainnetDai), liquidityProvider, 1000);
    }

    function test_depositOnScroll() public {
        // Approve ScrollSavingsDai to spend DAI
        vm.selectFork(scrollFork);
        scrollDai.approve(address(scrollSavingsDai), 100);
        assertEq(scrollDai.allowance(address(this), address(scrollSavingsDai)), 100);
        vm.expectEmit(true, true, false, true);
        emit Deposited(address(this), 100);
        scrollSavingsDai.deposit(100);
    }

    /**
     * @notice Test the deposit and assert flow
     * @dev Depositor needs to approve ScrollSavingsDai to spend DAI before depositing
     * @dev Asserter needs to approve DataAsserterGoerli to spend the bond before asserting
     */
    function test_depositAndAssert() public returns (bytes32) {
        // @dev Approve ScrollSavingsDai to spend DAI
        vm.selectFork(scrollFork);
        scrollDai.approve(address(scrollSavingsDai), 100);

        // Deposit 100 Dai
        vm.expectEmit(true, true, false, true);
        emit Deposited(address(this), 100);
        scrollSavingsDai.deposit(100);

        // Assert that the data is correct
        vm.selectFork(mainnetFork);
        bytes32 depositId = bytes32("txn-hash-of-deposit-on-scroll");
        address depositor = address(this);
        uint256 amount = 100;
        address asserter = address(this);
        defaultCurrency.allocateTo(asserter, optimisticOracleV3.getMinimumBond(address(defaultCurrency))); // Give the asserter some money for the bond

        // @dev: Asserter needs to approve DataAsserterGoerli to spend the bond
        defaultCurrency.approve(address(dataAsserter), optimisticOracleV3.getMinimumBond(address(defaultCurrency)));
        assertEq(
            defaultCurrency.allowance(asserter, address(dataAsserter)),
            optimisticOracleV3.getMinimumBond(address(defaultCurrency))
        );

        vm.expectEmit(true, true, false, true);
        emit DepositAsserted(depositor, amount, bytes32(0));
        return dataAsserter.assertDeposit(depositId, depositor, amount, asserter);
    }

    // TOKEN POOL TESTS
    function test_addLiquidity() public {
        // Approve TokenPool to spend DAI
        vm.selectFork(mainnetFork);
        vm.startPrank(liquidityProvider);
        mainnetDai.approve(address(daiPool), 100);
        assertEq(mainnetDai.allowance(liquidityProvider, address(daiPool)), 100);

        // Add liquidity
        vm.expectEmit(true, true, false, true);
        emit LiquidityAdded(liquidityProvider, 100);
        daiPool.addLiquidity(100);
        vm.stopPrank();
        assertEq(daiPool.totalDaiBalance(), 100);
        assertEq(daiPool.daiBalances(liquidityProvider), 100);
    }

    function test_removeLiquidity() public {
        test_addLiquidity();
        assertEq(mainnetDai.balanceOf(liquidityProvider), 900);

        // Remove liquidity
        vm.expectEmit(true, true, false, true);
        emit LiquidityRemoved(liquidityProvider, 100); // liquidityProvider is address(this)
        vm.prank(liquidityProvider);
        daiPool.removeLiquidity(100);
        assertEq(daiPool.totalDaiBalance(), 0);
        assertEq(daiPool.daiBalances(liquidityProvider), 0);
        assertEq(mainnetDai.balanceOf(liquidityProvider), 1000);
    }
    /**
     * @notice Tests the depositDaiToVault function from TokenPool called by callback when assertion is resolved/settled.
     */

    function test_depositInVaultAfterSettlement() public {
        // Call approveSavingsDai on TokenPool to approve SavingsDai to spend DAI
        vm.selectFork(mainnetFork);
        daiPool.approveSavingsDai(type(uint256).max); // Max approval

        // Add liquidity
        test_addLiquidity();
        assertEq(daiPool.totalDaiBalance(), 100);

        // Deposit, Assert and Settle on Scroll
        uint256 previewShares = savingsDai.previewDeposit(100);
        _settleAssertion();
        assertEq(savingsDai.balanceOf(address(daiPool)), previewShares);
    }

    function _settleAssertion() internal {
        bytes32 assertionId = test_depositAndAssert();

        // Settle the assertion
        vm.selectFork(mainnetFork);
        timer.setCurrentTime(timer.getCurrentTime() + 30 seconds);
        vm.expectEmit(true, true, true, true);
        emit DepositAssertionResolved(bytes32("txn-hash-of-deposit-on-scroll"), address(this), assertionId);
        optimisticOracleV3.settleAssertion(assertionId);
    }
    // TODO: Handle Disputes
}
