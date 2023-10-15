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
    DataAsserter public dataAsserter;
    // bytes32 dataId = bytes32("dataId");
    // bytes32 correctData = bytes32("correctData");
    // bytes32 incorrectData = bytes32("incorrectData");

    uint256 mainnetFork;
    uint256 scrollFork;

    ScrollSavingsDai public scrollSavingsDai;
    ERC20 scrollDai;
    ERC20 mainnetDai;
    address liquidityProvider = address(0x1234325);
    SavingsDai savingsDai = SavingsDai(address(0x83F20F44975D03b1b09e64809B757c47f942BEeA));
    TokenPool daiPool;

    event Deposited(address indexed depositor, uint256 indexed amount);
    event DepositAsserted(address indexed depositor, uint256 indexed amount, bytes32 indexed assertionId);
    event DepositAssertionResolved(bytes32 indexed depositId, address indexed asserter, bytes32 indexed assertionId);
    event LiquidityAdded(address indexed provider, uint256 indexed amount);
    event LiquidityRemoved(address indexed provider, uint256 indexed amount);

    function setUp() public {
        mainnetFork = vm.createFork(vm.envString("MAINNET_RPC"));
        scrollFork = vm.createFork(vm.envString("SCROLL_RPC"));
        vm.selectFork(mainnetFork);
        _commonSetup();
        dataAsserter = new DataAsserter(address(defaultCurrency), address(optimisticOracleV3));
        console.log("DataAsserter deployed at address: %s on fork_id %s", address(dataAsserter), vm.activeFork());
        mainnetDai = new ERC20("DAI", "DAI");
        daiPool = new TokenPool(address(mainnetDai), address(0x123), address(dataAsserter));
        console.log("TokenPool deployed at address: %s on fork_id %s", address(daiPool), vm.activeFork());
        deal(address(mainnetDai), liquidityProvider, 1000);

        vm.selectFork(scrollFork);
        scrollDai = new ERC20("ScrollDAI", "sclDAI");
        scrollSavingsDai = new ScrollSavingsDai(address(scrollDai));
        console.log(
            "ScrollSavingsDai deployed at address: %s on fork_id %s", address(scrollSavingsDai), vm.activeFork()
        );

        // Deal
        deal(address(scrollDai), address(this), 1000);
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
        return dataAsserter.assertDepositOnScroll(depositId, depositor, amount, asserter);
    }

    function test_settleAssertion() public {
        bytes32 assertionId = test_depositAndAssert();

        // Settle the assertion
        vm.selectFork(mainnetFork);
        timer.setCurrentTime(timer.getCurrentTime() + 30 seconds);
        vm.expectEmit(true, true, true, true);
        emit DepositAssertionResolved(bytes32("txn-hash-of-deposit-on-scroll"), address(this), assertionId);
        optimisticOracleV3.settleAssertion(assertionId);
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

    function test_depositInVaultAfterSettlement() public {}

    // TODO: Handle Disputes
}
