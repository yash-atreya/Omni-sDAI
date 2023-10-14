// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.16;

import "forge-std/console.sol";
import "./common/CommonOptimisticOracleV3Test.sol";
import "../src/Goerli/DataAsserterGoerli.sol";
import "../src/Scroll/ScrollSavingsDai.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DepositFlowTest is CommonOptimisticOracleV3Test {
    DataAsserterGoerli public dataAsserterGoerli;
    // bytes32 dataId = bytes32("dataId");
    // bytes32 correctData = bytes32("correctData");
    // bytes32 incorrectData = bytes32("incorrectData");

    uint256 mainnetFork;
    uint256 scrollFork;

    ScrollSavingsDai public scrollSavingsDai;
    ERC20 dai;

    event Deposited(address indexed depositor, uint256 indexed amount);
    event DataAsserted(bytes32 indexed dataId, bytes32 data, address indexed asserter, bytes32 indexed assertionId);

    function setUp() public {
        mainnetFork = vm.createFork(vm.envString("MAINNET_RPC"));
        scrollFork = vm.createFork(vm.envString("SCROLL_RPC"));
        vm.selectFork(mainnetFork);
        _commonSetup();
        dataAsserterGoerli = new DataAsserterGoerli(address(defaultCurrency), address(optimisticOracleV3));
        console.log("DAGoerli deployed at address: %s on fork_id %s", address(dataAsserterGoerli), vm.activeFork());

        vm.selectFork(scrollFork);
        dai = new ERC20("DAI", "DAI");
        scrollSavingsDai = new ScrollSavingsDai(address(dai));
        console.log(
            "ScrollSavingsDai deployed at address: %s on fork_id %s", address(scrollSavingsDai), vm.activeFork()
        );

        // Deal
        deal(address(dai), address(this), 1000);
    }

    function test_depositOnScroll() public {
        // Approve ScrollSavingsDai to spend DAI
        vm.selectFork(scrollFork);
        dai.approve(address(scrollSavingsDai), 100);
        assertEq(dai.allowance(address(this), address(scrollSavingsDai)), 100);
        vm.expectEmit(true, true, false, true);
        emit Deposited(address(this), 100);
        scrollSavingsDai.deposit(100);
    }

    /**
     * @notice Test the deposit and assert flow
     * @dev Depositor needs to approve ScrollSavingsDai to spend DAI before depositing
     * @dev Asserter needs to approve DataAsserterGoerli to spend the bond before asserting
     */
    function test_depositAndAssert() public {
        // @dev Approve ScrollSavingsDai to spend DAI
        vm.selectFork(scrollFork);
        dai.approve(address(scrollSavingsDai), 100);

        // Deposit 100 Dai
        vm.expectEmit(true, true, false, true);
        emit Deposited(address(this), 100);
        scrollSavingsDai.deposit(100);

        // Assert that the data is correct
        vm.selectFork(mainnetFork);
        bytes32 dataId = bytes32("dataId-DepositOnScroll");
        bytes32 data = bytes32("Deposited(address(this), 100)");
        address asserter = address(this);
        defaultCurrency.allocateTo(asserter, optimisticOracleV3.getMinimumBond(address(defaultCurrency))); // Give the asserter some money for the bond

        // @dev: Asserter needs to approve DataAsserterGoerli to spend the bond
        defaultCurrency.approve(
            address(dataAsserterGoerli), optimisticOracleV3.getMinimumBond(address(defaultCurrency))
        );
        assertEq(
            defaultCurrency.allowance(asserter, address(dataAsserterGoerli)),
            optimisticOracleV3.getMinimumBond(address(defaultCurrency))
        );

        vm.expectEmit(true, true, false, true);
        emit DataAsserted(dataId, data, asserter, bytes32(0));
        dataAsserterGoerli.assertDepositOnScroll(dataId, data, asserter);
    }
}
