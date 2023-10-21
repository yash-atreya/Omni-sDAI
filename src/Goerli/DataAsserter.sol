// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@uma/core/contracts/optimistic-oracle-v3/implementation/ClaimData.sol";
import "@uma/core/contracts/optimistic-oracle-v3/interfaces/OptimisticOracleV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// This contract allows assertions on any form of data to be made using the UMA Optimistic Oracle V3 and stores the
// proposed value so that it may be retrieved on chain. The dataId is intended to be an arbitrary value that uniquely
// identifies a specific piece of information in the consuming contract and is replaceable. Similarly, any data
// structure can be used to replace the asserted data.

contract DataAsserter {
    using SafeERC20 for IERC20;

    IERC20 public immutable defaultCurrency; // Oracle's default currency for posting bonds.
    OptimisticOracleV3Interface public immutable oo;
    uint64 public constant assertionLiveness = 30; // 30 seconds.
    bytes32 public immutable defaultIdentifier; // The identifier used by the OptimisticOracleV3. - "ASSERT_TRUTH"
    address public immutable savingsDai; // SavingsDai contract address.
    address public immutable fillerPool; // FillerPool contract address.

    struct DepositAssertion {
        bytes32 depositId; // The txn hash of the deposit.
        address depositor;
        uint256 amount;
        address asserter; // The address that made the assertion.
        bool resolved; // Whether the assertion has been resolved.
    }

    struct WithdrawalAssertion {
        bytes32 withdrawalId; // The txn hash of the withdrawal.
        address withdrawer;
        uint256 amount; // Number of shares to withdraw.
        address asserter; // The address that made the assertion.
        bool resolved; // Whether the assertion has been resolved.
    }

    struct FilledWithdrawalAssertion {
        bytes32 fillHash; // The txn hash of the fill.
        address relayer;
        uint256 amount; // Amount of tokens used to fill.
        address token; // The token used fill and should be reimbursed in.
        address asserter; // The address that made the assertion.
        bool resolved; // Whether the assertion has been resolved.
    }

    mapping(bytes32 => WithdrawalAssertion) public withdrawalAssertionsData;
    mapping(bytes32 => FilledWithdrawalAssertion) public filledWithdrawalAssertionsData;
    mapping(address => mapping(address => uint256)) public reimbursements; // Relayer -> L1Token -> Amount

    event WithdrawalAsserted(address indexed withdrawer, uint256 indexed amount, bytes32 indexed assertionId);
    event WithdrawalAssertionResolved(
        bytes32 indexed withdrawalId, address indexed asserter, bytes32 indexed assertionId
    );

    event FilledWithdrawalAsserted(address indexed relayer, uint256 indexed amount, bytes32 indexed assertionId);
    event FilledWithdrawalAssertionResolved(
        bytes32 indexed fillHash, address indexed asserter, bytes32 indexed assertionId
    );

    constructor(address _defaultCurrency, address _optimisticOracleV3, address _savingsDai, address _fillerPool) {
        defaultCurrency = IERC20(_defaultCurrency);
        oo = OptimisticOracleV3Interface(_optimisticOracleV3);
        defaultIdentifier = oo.defaultIdentifier();
        savingsDai = _savingsDai;
        fillerPool = _fillerPool;
    }

    // For a given assertionId, returns a boolean indicating whether the data is accessible and the data itself.
    // function getData(bytes32 assertionId) public view returns (bool, bytes32) {
    //     if (!assertionsData[assertionId].resolved) return (false, 0);
    //     return (true, assertionsData[assertionId].data);
    // }

    function assertWithdrawal(bytes32 _withdrawalId, address _withdrawer, uint256 _amount, address _asserter)
        public
        returns (bytes32 assertionId)
    {
        _asserter = _asserter == address(0) ? msg.sender : _asserter; // _asserter is the relayer.
        uint256 bond = oo.getMinimumBond(address(defaultCurrency));
        defaultCurrency.safeTransferFrom(msg.sender, address(this), bond);
        defaultCurrency.safeApprove(address(oo), bond);

        assertionId = oo.assertTruth(
            abi.encodePacked(
                "0x",
                ClaimData.toUtf8BytesAddress(_asserter),
                " asserting withdrawal by withdrawer: 0x",
                ClaimData.toUtf8BytesAddress(_withdrawer),
                " with amount: ",
                ClaimData.toUtf8BytesUint(_amount),
                " at timestamp: ",
                ClaimData.toUtf8BytesUint(block.timestamp),
                " in the DataAsserter contract at 0x",
                ClaimData.toUtf8BytesAddress(address(this)),
                " is valid."
            ),
            _asserter,
            address(this),
            address(0), // No sovereign security.
            assertionLiveness,
            defaultCurrency,
            bond,
            defaultIdentifier,
            bytes32(0) // No domain.
        );

        withdrawalAssertionsData[assertionId] =
            WithdrawalAssertion(_withdrawalId, _withdrawer, _amount, _asserter, false);

        emit WithdrawalAsserted(_withdrawer, _amount, assertionId);
    }

    // Assert Filled Withdrawal
    /**
     * @notice Asserts that a withdrawal has been filled for getting reimbursent.
     */
    function assertFilledWithdrawal(
        bytes32 _fillHash,
        address _relayer,
        uint256 _amount,
        address _token,
        address _asserter
    ) public returns (bytes32 assertionId) {
        _asserter = _asserter == address(0) ? msg.sender : _relayer; // _asserter is the relayer.
        uint256 bond = oo.getMinimumBond(address(defaultCurrency));
        defaultCurrency.safeTransferFrom(msg.sender, address(this), bond);
        defaultCurrency.safeApprove(address(oo), bond);

        assertionId = oo.assertTruth(
            abi.encodePacked(
                "0x",
                ClaimData.toUtf8BytesAddress(_asserter),
                " asserting filled withdrawal 0x",
                ClaimData.toUtf8Bytes(_fillHash),
                " by relayer: 0x",
                ClaimData.toUtf8BytesAddress(_relayer),
                " with amount: ",
                ClaimData.toUtf8BytesUint(_amount),
                " at timestamp: ",
                ClaimData.toUtf8BytesUint(block.timestamp),
                " using token 0x",
                ClaimData.toUtf8BytesAddress(_token),
                " in the DataAsserter contract at 0x",
                ClaimData.toUtf8BytesAddress(address(this)),
                " is valid."
            ),
            _asserter,
            address(this),
            address(0), // No sovereign security.
            assertionLiveness,
            defaultCurrency,
            bond,
            defaultIdentifier,
            bytes32(0) // No domain.
        );

        filledWithdrawalAssertionsData[assertionId] =
            FilledWithdrawalAssertion(_fillHash, _relayer, _amount, _token, _asserter, false);

        emit FilledWithdrawalAsserted(_relayer, _amount, assertionId);
    }

    // OptimisticOracleV3 resolve callback.
    function assertionResolvedCallback(bytes32 assertionId, bool assertedTruthfully) public {
        require(msg.sender == address(oo));
        // If the assertion was true, then the data assertion is resolved.
        if (assertedTruthfully) {
            if (_isWithdrawalAssertion(assertionId)) {
                _resolveWithdrawalAssertion(assertionId);
            } else if (_isFillAssertion(assertionId)) {
                _resolveFillAssertion(assertionId);
            }
        } else {
            if (_isWithdrawalAssertion(assertionId)) {
                delete withdrawalAssertionsData[assertionId];
            } else if (_isFillAssertion(assertionId)) {
                delete filledWithdrawalAssertionsData[assertionId];
            }
        }
    }

    function _isWithdrawalAssertion(bytes32 assertionId) internal view returns (bool) {
        if (withdrawalAssertionsData[assertionId].asserter != address(0)) {
            return true;
        } else {
            return false;
        }
    }

    function _resolveWithdrawalAssertion(bytes32 assertionId) internal {
        WithdrawalAssertion memory dataAssertion = withdrawalAssertionsData[assertionId];

        // Deposit `amount` Dai from Pool in sDAI Vault with the receiver as the depositor on scroll.
        // daiPool.depositDaiToVault(dataAssertion.amount, dataAssertion.depositor);
        // Else delete the data assertion if it was false to save gas.
        (bool success,) = savingsDai.call(
            abi.encodeWithSignature(
                "redeem(uint256,address,address)",
                dataAssertion.amount,
                address(fillerPool),
                address(fillerPool) // `receiver` and `owner` are both the FillerPool contract.
            )
        );

        require(success, "Failed to withdraw Dai from sDai Vault to FillerPool.");
        withdrawalAssertionsData[assertionId].resolved = true;
        emit WithdrawalAssertionResolved(dataAssertion.withdrawalId, dataAssertion.asserter, assertionId);
        // Emit event with how much Dai was received after withdrawing from the sDai Vault.
        // Lock that Dai in the filler pool.
        // Ask relayer to fill wDai to the user.
        // Let relayer withdraw the locked Dai from the filler pool.
    }

    function _isFillAssertion(bytes32 assertionId) internal view returns (bool) {
        if (filledWithdrawalAssertionsData[assertionId].asserter != address(0)) {
            return true;
        } else {
            return false;
        }
    }

    function _resolveFillAssertion(bytes32 assertionId) internal {
        FilledWithdrawalAssertion memory dataAssertion = filledWithdrawalAssertionsData[assertionId];

        // Reimburse the relayer in the token used to the fill the withdrawal with `amount`.
        reimbursements[dataAssertion.relayer][dataAssertion.token] += dataAssertion.amount;
        filledWithdrawalAssertionsData[assertionId].resolved = true;
        emit FilledWithdrawalAssertionResolved(dataAssertion.fillHash, dataAssertion.asserter, assertionId);
    }

    function getReimbursementAmount(address _relayer, address _l1token) public view returns (uint256) {
        return reimbursements[_relayer][_l1token];
    }

    // If assertion is disputed, do nothing and wait for resolution.
    // This OptimisticOracleV3 callback function needs to be defined so the OOv3 doesn't revert when it tries to call it.
    // function assertionDisputedCallback(bytes32 assertionId) public {}
}
