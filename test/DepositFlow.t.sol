// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.16;

import "forge-std/console.sol";
import "./common/CommonOptimisticOracleV3Test.sol";
import "../src/Goerli/DataAsserter.sol";
import "../src/Scroll/ScrollSavingsDai.sol";
import "../src/SavingsDai.sol"; // Mainnet contract
import "../src/Goerli/FillerPool.sol";
import {DataAsserter as DataAsserterScroll} from "../src/Scroll/DataAsserter.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DepositFlowTest is CommonOptimisticOracleV3Test {
    // Contract Instances

    // Mainnet/Goerli
    DataAsserter public dataAsserter;
    ERC20 mainnetDai = ERC20(address(0x6B175474E89094C44Da98b954EedeAC495271d0F)); // DAI on Mainnet
    SavingsDai savingsDai = SavingsDai(address(0x83F20F44975D03b1b09e64809B757c47f942BEeA)); // SavingsDai on Mainnet
    FillerPool fillerPool; // FillerPool on Mainnet
    // Scroll
    ERC20 scrollDai; // Scroll Sepolia doesn't have bridged DAI. Scroll Mainnet has it. https://github.com/scroll-tech/token-list
    ScrollSavingsDai public scrollSavingsDai; // Scroll SavingsDai - Representation of SavingsDai from
    DataAsserterScroll public dataAsserterScroll; // DataAsserter on Scroll
    // Forks
    uint256 mainnetFork;
    uint256 scrollFork;

    // Dummy Accounts
    address relayer = address(0x1234326); // Relayer
    address depositor = address(0x1234327); // Depositor
    // Events

    // Scroll-SavingsDai Events
    event Deposited(address indexed depositor, uint256 indexed amount);
    // FillerPool Events
    event DepositFilled(address indexed filler, address indexed fillFor, bytes32 indexed fillHash);

    // Scroll-DataAsserter Events
    event DepositFillAsserted(bytes32 indexed fillHash, address indexed asserter, bytes32 indexed assertionId);
    event DepositFillAssertionResolved(bytes32 indexed fillHash, address indexed asserter, bytes32 indexed assertionId);

    function setUp() public {
        // Create Forks
        mainnetFork = vm.createFork(vm.envString("MAINNET_RPC"));
        scrollFork = vm.createFork(vm.envString("SCROLL_RPC"));

        // Deploy Oracle and DataAsserter on Mainnet/Goerli
        vm.selectFork(mainnetFork);
        // Deploy FillerPool on Mainnet
        fillerPool = new FillerPool(address(savingsDai));
        _commonSetup();
        dataAsserter =
        new DataAsserter(address(defaultCurrency), address(optimisticOracleV3), address(savingsDai), address(fillerPool));
        console.log("DataAsserter deployed at address: ", address(dataAsserter), " on fork_id: ", vm.activeFork());

        // Deploy ScrollSavingsDai on Scroll
        vm.selectFork(scrollFork);
        scrollDai = new ERC20("ScrollDAI", "sclDAI"); // Scroll doesn't have bridged DAI. Create our own.

        // Deploy OOv3 and DataAsserter on Scroll
        scrollSavingsDai = new ScrollSavingsDai(address(scrollDai));
        console.log(
            "ScrollSavingsDai deployed at address: ", address(scrollSavingsDai), " on fork_id: ", vm.activeFork()
        );
        _commonSetup();
        dataAsserterScroll =
            new DataAsserterScroll(address(defaultCurrency), address(optimisticOracleV3), address(scrollSavingsDai));
        console.log(
            "DataAsserterScroll deployed at address: ", address(dataAsserterScroll), " on fork_id: ", vm.activeFork()
        );
        scrollSavingsDai.setDataAsserter(address(dataAsserterScroll)); // Set DataAsserter on ScrollSavingsDai
        // Deal
        deal(address(scrollDai), depositor, 1000); // Gives 100 Dai to depositor on Scroll
        vm.selectFork(mainnetFork);
        deal(address(mainnetDai), relayer, 1000);
    }

    function test_depositOnScroll() public {
        // Approve ScrollSavingsDai to spend DAI
        vm.selectFork(scrollFork);
        vm.startPrank(depositor);
        scrollDai.approve(address(scrollSavingsDai), 100);
        assertEq(scrollDai.allowance(depositor, address(scrollSavingsDai)), 100);
        vm.expectEmit(true, true, false, true);
        emit Deposited(depositor, 100);
        scrollSavingsDai.deposit(100);
        vm.stopPrank();
    }

    function test_fillDeposit() public returns (bytes32, uint256) {
        test_depositOnScroll();
        vm.selectFork(mainnetFork);
        // Relay catches the `Deposited` event and fills deposit
        bytes32 depositHash = bytes32("txn-hash-of-deposit-on-scroll");
        uint256 amount = 100;
        address fillFor = depositor;
        address filler = relayer;
        address token = address(mainnetDai);
        uint256 fee = 0;

        uint256 previewedShares = savingsDai.previewDeposit(amount);
        vm.prank(filler);
        mainnetDai.approve(address(fillerPool), amount);
        vm.expectEmit(true, true, false, true);
        emit DepositFilled(filler, fillFor, bytes32(0));
        (bytes32 fillHash, uint256 receivedShares) =
            fillerPool.fillDeposit(depositHash, amount, fillFor, filler, token, fee);
        assertEq(receivedShares, previewedShares);
        assertEq(savingsDai.balanceOf(address(fillerPool)), previewedShares);
        assertEq(mainnetDai.balanceOf(relayer), 900);
        return (fillHash, receivedShares);
    }

    /**
     * @notice In this test, relayer fills the deposit and asserts the fill to Scroll's DataAsserter.
     */
    function test_fillDepositAndAssertFill() public returns (bytes32, bytes32) {
        (bytes32 fillHash, uint256 receivedShares) = test_fillDeposit();
        // Relayer asserts the filled deposit on Scroll
        vm.selectFork(scrollFork);
        address asserter = relayer;
        address filler = relayer;
        address fillFor = depositor;
        address fillToken = address(scrollDai); // Corresponding Represention of fillToken on Scroll.
        uint256 amount = 100;
        defaultCurrency.allocateTo(relayer, optimisticOracleV3.getMinimumBond(address(defaultCurrency))); // Give the asserter some money for the bond
        vm.startPrank(asserter);
        defaultCurrency.approve(
            address(dataAsserterScroll), optimisticOracleV3.getMinimumBond(address(defaultCurrency))
        ); // Asserter needs to approve DataAsserter to spend the bond
        vm.expectEmit(true, true, false, true);
        emit DepositFillAsserted(fillHash, asserter, bytes32(0));
        bytes32 assertionId =
            dataAsserterScroll.assertDepositFill(filler, fillHash, fillToken, amount, fillFor, receivedShares);
        vm.stopPrank();
        return (fillHash, assertionId);
    }

    function test_depositAssertionResolution() public {
        (bytes32 fillHash, bytes32 assertionId) = test_fillDepositAndAssertFill();
        // Settle the assertion
        timer.setCurrentTime(timer.getCurrentTime() + 30 seconds);
        vm.expectEmit(true, true, true, true);
        address asserter = relayer;
        emit DepositFillAssertionResolved(fillHash, asserter, assertionId);
        optimisticOracleV3.settleAssertion(assertionId);
        uint256 totalSupply = scrollSavingsDai.totalSupply();
        assertTrue(scrollSavingsDai.balanceOf(depositor) > 0);
        assertEq(scrollSavingsDai.balanceOf(depositor), totalSupply);
        assertEq(dataAsserterScroll.getReimbursementAmount(relayer, address(scrollDai)), 100);
        console.log("sDai balance of depositor: ", scrollSavingsDai.balanceOf(depositor));
    }

    function test_withdrawRelayerReimbursement() public {
        test_depositAssertionResolution();
        // Withdraw reimbursement
        vm.selectFork(scrollFork);
        vm.startPrank(relayer);
        scrollSavingsDai.withdrawRelayerReimbursement(relayer, address(scrollDai), address(0));
        vm.stopPrank();
        assertEq(scrollDai.balanceOf(relayer), 100);
        assertEq(scrollDai.balanceOf(address(scrollSavingsDai)), 0);
    }
}
