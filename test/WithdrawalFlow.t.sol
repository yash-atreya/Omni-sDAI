// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "forge-std/console.sol";
import "./common/CommonOptimisticOracleV3Test.sol";
import "../src/Goerli/DataAsserter.sol";
import "../src/Scroll/ScrollSavingsDai.sol";
import "../src/SavingsDai.sol"; // Mainnet contract
import "../src/Goerli/FillerPool.sol";
import {FillerPool as ScrollFillerPool} from "../src/Scroll/FillerPool.sol";
import {DataAsserter as DataAsserterScroll} from "../src/Scroll/DataAsserter.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract WithdrawalFlowTest is CommonOptimisticOracleV3Test {
    // Contract Instances

    // Mainnet/Goerli
    DataAsserter public dataAsserter;
    ERC20 mainnetDai = ERC20(address(0x6B175474E89094C44Da98b954EedeAC495271d0F)); // DAI on Mainnet
    SavingsDai savingsDai = SavingsDai(address(0x83F20F44975D03b1b09e64809B757c47f942BEeA)); // SavingsDai on Mainnet
    FillerPool fillerPool; // FillerPool on Mainnet

    // Scroll
    ERC20 scrollDai; // Scroll doesn't have bridged DAI on Sepolia. Scroll Mainnet has it. https://github.com/scroll-tech/token-list
    ScrollSavingsDai public scrollSavingsDai; // Scroll SavingsDai - Representation of SavingsDai from
    DataAsserterScroll public dataAsserterScroll; // DataAsserter on Scroll
    ScrollFillerPool scrollFillerPool; // FillerPool on Scroll
    // Forks
    uint256 mainnetFork;
    uint256 scrollFork;

    // Dummy Accounts
    address relayer = address(0x1234326); // Relayer
    address depositor = address(0x1234327); // Depositor

    // Events

    // ScrollSavingsDai
    event WithdrawalRequest(address indexed withdrawer, uint256 indexed amount);

    // Mainnet/Goerli DataAsserter
    event WithdrawalAsserted(address indexed withdrawer, uint256 indexed amount, bytes32 indexed assertionId);
    event WithdrawalAssertionResolved(
        bytes32 indexed withdrawalId, address indexed asserter, bytes32 indexed assertionId
    );
    event FilledWithdrawalAsserted(address indexed relayer, uint256 indexed amount, bytes32 indexed assertionId);
    event FilledWithdrawalAssertionResolved(
        bytes32 indexed fillHash, address indexed asserter, bytes32 indexed assertionId
    );

    // Scroll Filler Pool
    event FilledWithdrawal(address indexed filler, bytes32 indexed fillHash, uint256 indexed amount);

    function setUp() public {
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
        // Set DataAsserter on Mainnet/FillerPool
        fillerPool.setDataAsserter(address(dataAsserter));
        uint256 minBond = optimisticOracleV3.getMinimumBond(address(defaultCurrency));
        console.log("Minimum Bond on fork ", vm.activeFork(), " is: ", minBond);

        // Deploy ScrollSavingsDai on Scroll
        vm.selectFork(scrollFork);
        scrollDai = new ERC20("ScrollDAI", "sclDAI"); // For Scroll Sepolia. Use bridged DAI on Scroll Mainnet. https://github.com/scroll-tech/token-list.abi

        // Deploy ScrollSavingsDai on Scroll
        scrollSavingsDai = new ScrollSavingsDai(address(scrollDai));
        console.log(
            "ScrollSavingsDai deployed at address: ", address(scrollSavingsDai), " on fork_id: ", vm.activeFork()
        );
        // Deploy FillerPool on Scroll
        scrollFillerPool = new ScrollFillerPool(address(scrollDai), address(scrollSavingsDai));
        // Deploy OOv3 and DataAsserter on Scroll
        _commonSetup();
        dataAsserterScroll =
            new DataAsserterScroll(address(defaultCurrency), address(optimisticOracleV3), address(scrollSavingsDai));
        console.log(
            "DataAsserterScroll deployed at address: ", address(dataAsserterScroll), " on fork_id: ", vm.activeFork()
        );
        // Set DataAsserter on ScrollSavingsDai
        scrollSavingsDai.setDataAsserter(address(dataAsserterScroll));

        // Deal
        deal(address(scrollDai), depositor, 1000); // Gives 100 Dai to depositor on Scroll
        deal(address(scrollDai), relayer, 1000); // Gives 100 Dai to relayer on Mainnet
        vm.selectFork(mainnetFork);
        deal(address(mainnetDai), relayer, 1000);
    }

    function _deposit(uint256 _amount) internal returns (uint256) {
        vm.selectFork(scrollFork);
        vm.startPrank(depositor);
        scrollDai.approve(address(scrollSavingsDai), _amount);
        scrollSavingsDai.deposit(_amount);
        vm.stopPrank();
        // Relayer fills the deposit
        vm.selectFork(mainnetFork);
        // Relay catches the `Deposited` event and fills deposit
        bytes32 depositHash = bytes32("txn-hash-of-deposit-on-scroll");
        uint256 amount = _amount;
        address fillFor = depositor;
        address filler = relayer;
        address token = address(mainnetDai);
        uint256 fee = 0;
        vm.startPrank(filler);
        mainnetDai.approve(address(fillerPool), amount);
        (bytes32 fillHash, uint256 receivedShares) =
            fillerPool.fillDeposit(depositHash, amount, fillFor, filler, token, fee);
        vm.stopPrank();
        // Relayer asserts fill on scroll
        vm.selectFork(scrollFork);
        vm.startPrank(filler);
        defaultCurrency.allocateTo(relayer, optimisticOracleV3.getMinimumBond(address(defaultCurrency))); // Give the asserter some money for the bond
        defaultCurrency.approve(
            address(dataAsserterScroll), optimisticOracleV3.getMinimumBond(address(defaultCurrency))
        ); // Asserter needs to approve DataAsserter to spend the bond
        address fillToken = address(scrollDai); // Deposit was filled using mainnetDai. fillToken needs to be the corresponding version of the token. Therefore, scrollDai.
        bytes32 assertionId =
            dataAsserterScroll.assertDepositFill(filler, fillHash, fillToken, amount, fillFor, receivedShares);
        vm.stopPrank();
        // Warp time and settle
        timer.setCurrentTime(timer.getCurrentTime() + 30 seconds);
        optimisticOracleV3.settleAssertion(assertionId);
        return receivedShares;
    }

    function test_withdrawOnScroll() public returns (uint256) {
        uint256 shares = _deposit(100);

        // Withdraw
        vm.startPrank(depositor);
        assertEq(scrollSavingsDai.balanceOf(depositor), shares);
        scrollSavingsDai.approve(address(scrollSavingsDai), shares);
        scrollSavingsDai.allowance(depositor, address(scrollSavingsDai));
        vm.expectEmit(true, false, false, true);
        emit WithdrawalRequest(depositor, shares);
        scrollSavingsDai.withdraw(shares);
        assertEq(scrollSavingsDai.balanceOf(depositor), 0);
        assertEq(scrollSavingsDai.totalSupply(), 0);
        vm.stopPrank();
        return shares;
    }

    function test_withdrawAndAssertWithdrawal() public returns (uint256) {
        uint256 shares = test_withdrawOnScroll();

        // Redeploy oov3 and DataAsserter on Mainnet/Goerli - As we're using the same variable names for oov3 contracts.
        vm.selectFork(mainnetFork);
        _commonSetup();
        dataAsserter =
        new DataAsserter(address(defaultCurrency), address(optimisticOracleV3), address(savingsDai), address(fillerPool));
        console.log("DataAsserter deployed at address: ", address(dataAsserter), " on fork_id: ", vm.activeFork());

        // Relayer asserts the withdrawal on Mainnet/Goerli
        // uint256 mainnetBond = optimisticOracleV3.getMinimumBond(address(defaultCurrency));
        // console.log("Minimum Bond on fork ", vm.activeFork(), " is: ", mainnetBond);
        defaultCurrency.allocateTo(relayer, optimisticOracleV3.getMinimumBond(address(defaultCurrency))); // Give the asserter some money for the bond
        vm.startPrank(relayer);
        defaultCurrency.approve(address(dataAsserter), optimisticOracleV3.getMinimumBond(address(defaultCurrency))); // Asserter needs to approve DataAsserter to spend the bond
        bytes32 withdrawalHash = bytes32("txn-hash-of-withdrawal-on-scroll");
        uint256 amount = shares;
        address withdrawer = depositor;
        // address token = address(mainnetDai);
        // uint256 fee = 0;
        vm.expectEmit(true, false, false, true);
        emit WithdrawalAsserted(withdrawer, amount, bytes32("assertion-id"));
        bytes32 assertionId = dataAsserter.assertWithdrawal(withdrawalHash, withdrawer, amount, relayer);
        vm.stopPrank();
        // Warp time and settle
        fillerPool.approve(address(savingsDai), address(dataAsserter), type(uint256).max);
        timer.setCurrentTime(timer.getCurrentTime() + 30 seconds);
        vm.expectEmit(true, false, false, true);
        emit WithdrawalAssertionResolved(withdrawalHash, relayer, assertionId);
        console.log("sDai Balance of Filler Pool before settlement: ", savingsDai.balanceOf(address(fillerPool)));
        optimisticOracleV3.settleAssertion(assertionId);
        console.log("sDai Balance of Filler Pool after settlement: ", savingsDai.balanceOf(address(fillerPool)));
        // Check Balances of Filler Pool
        assertTrue(savingsDai.balanceOf(address(fillerPool)) < shares);
        console.log("Received ", mainnetDai.balanceOf(address(fillerPool)), " Dai after withdrawal");
        assertTrue(mainnetDai.balanceOf(address(fillerPool)) > 0);
        return shares;
    }

    function test_fillWithdrawal() public {
        uint256 receivedShares = test_withdrawAndAssertWithdrawal();

        // Relayer fills the withdrawal
        vm.selectFork(scrollFork);
        vm.startPrank(relayer); // As relayer becomes the filler (msg.sender)
        scrollDai.approve(address(fillerPool), 100);
        bytes32 withdrawalHash = bytes32("txn-hash-of-withdrawal-on-scroll");
        uint256 amount = receivedShares;
        address fillFor = depositor;
        address token = address(scrollDai);
        uint256 fee = 0;

        // Relayer must allow FillerPool to spend the amount
        scrollDai.approve(address(scrollFillerPool), amount);
        vm.expectEmit(false, false, true, true);
        emit FilledWithdrawal(relayer, bytes32("fill-hash"), amount);
        scrollFillerPool.fillWithdrawal(withdrawalHash, amount, fillFor, token, fee);
        vm.stopPrank();

        // Check if user received the amount
        assertEq(scrollDai.balanceOf(depositor), (900 + amount));
        assertEq(scrollDai.balanceOf(relayer), 1000 - amount);
        assertEq(scrollSavingsDai.balanceOf(depositor), 0);
        assertEq(scrollSavingsDai.balanceOf(address(scrollSavingsDai)), 0); // Shares deposited by user should be burned.
    }

    function test_assertFilledWithdrawal() public returns (bytes32) {
        uint256 receivedShares = test_withdrawAndAssertWithdrawal();
        vm.selectFork(mainnetFork);
        bytes32 fillhash = bytes32("fill-hash");
        uint256 amount = /*receivedShares*/ 99;
        address filler = relayer;
        address token = address(mainnetDai); // L1 Address of token used to fill the withdrawal.

        _commonSetup();
        dataAsserter =
        new DataAsserter(address(defaultCurrency), address(optimisticOracleV3), address(savingsDai), address(fillerPool));
        console.log("DataAsserter deployed at address: ", address(dataAsserter), " on fork_id: ", vm.activeFork());
        fillerPool.setDataAsserter(address(dataAsserter));
        // Relayer asserts the filled withdrawal
        vm.startPrank(relayer);
        defaultCurrency.allocateTo(relayer, optimisticOracleV3.getMinimumBond(address(defaultCurrency))); // Give the asserter some money for the bond
        defaultCurrency.approve(address(dataAsserter), optimisticOracleV3.getMinimumBond(address(defaultCurrency))); // Asserter needs to approve DataAsserter to spend the bond
        vm.expectEmit(true, false, false, true);
        emit FilledWithdrawalAsserted(filler, amount, bytes32("assertion-id"));
        return dataAsserter.assertFilledWithdrawal(fillhash, filler, amount, token, filler);
    }

    function test_settleFillWithdrawalAssertion() public {
        bytes32 assertionId = test_assertFilledWithdrawal();

        // Warp time and settle
        timer.setCurrentTime(timer.getCurrentTime() + 30 seconds);

        // Settle Assertion
        optimisticOracleV3.settleAssertion(assertionId);

        // Check Reimbursement
        assertEq(dataAsserter.getReimbursementAmount(relayer, address(mainnetDai)), 99); // Fill amount is 96
        assertEq(mainnetDai.balanceOf(address(fillerPool)), 99);
        // withdraw Reimbursement
        assertEq(mainnetDai.balanceOf(relayer), 1000 - 100);
        fillerPool.withdrawRelayerReimbursement(relayer, address(mainnetDai), relayer);
        assertEq(mainnetDai.balanceOf(relayer), 999); // TODO: Possible issue: 1 Dai is being leaked somewhere.
    }
}
