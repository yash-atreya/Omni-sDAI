// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@uma/core/contracts/optimistic-oracle-v3/implementation/ClaimData.sol";
import "@uma/core/contracts/optimistic-oracle-v3/interfaces/OptimisticOracleV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract DataAsserter {
    using SafeERC20 for IERC20;

    IERC20 public immutable defaultCurrency;
    OptimisticOracleV3Interface public immutable oo;
    uint64 public constant assertionLiveness = 30; // 30 seconds.
    bytes32 public immutable defaultIdentifier;
    address public immutable scrollSavingsDai;

    struct DepositToVaultAssertion {
        bytes32 depositId; // The txn hash of the deposit.
        address depositor;
        uint256 amount;
        address asserter; // The address that made the assertion.
        bool resolved; // Whether the assertion has been resolved.
    }

    struct DepositFillAssertion {
        bytes32 fillHash; // The hash returned by the FillerPool.
        address filler; // Relayer that filled the request.
        address fillToken; // The L2 address of the token that was used to fill the request. eg. If Dai was used, then this is the address of L2 Dai.
        uint256 amount; // The amount of the token that was used to fill the request.
        address fillFor; // The address for whom the request was filled.
        uint256 receivedShares; // The amount of sDai shares received when request was filled.
        bool resolved; // Whether the assertion has been resolved.
        address asserter; // The address that made the assertion.
    }

    mapping(bytes32 => DepositFillAssertion) public fillAssertionsData;
    mapping(address => mapping(address => uint256)) public reimbursements; // Relayer -> L2Token -> Amount

    event DepositFillAsserted(bytes32 indexed fillHash, address indexed asserter, bytes32 indexed assertionId);
    event DepositFillAssertionResolved(bytes32 indexed fillHash, address indexed asserter, bytes32 indexed assertionId);

    mapping(bytes32 => DepositToVaultAssertion) public assertionsData;

    event DepositToVaultAsserted(address indexed depositor, uint256 indexed amount, bytes32 indexed assertionId);

    event DepositToVaultAssertionResolved(
        bytes32 indexed depositId, address indexed asserter, bytes32 indexed assertionId
    );

    constructor(address _defaultCurrency, address _optimisticOracleV3, address _scrollSavingsDai) {
        defaultCurrency = IERC20(_defaultCurrency);
        oo = OptimisticOracleV3Interface(_optimisticOracleV3);
        defaultIdentifier = oo.defaultIdentifier();
        scrollSavingsDai = _scrollSavingsDai;
    }

    function assertDepositFill(
        address _filler,
        bytes32 _fillHash,
        address _fillToken,
        uint256 _amount,
        address _fillFor,
        uint256 _receivedShares
    ) public returns (bytes32 assertionId) {
        address _asserter = msg.sender;
        uint256 bond = oo.getMinimumBond(address(defaultCurrency));
        defaultCurrency.safeTransferFrom(msg.sender, address(this), bond);
        defaultCurrency.safeApprove(address(oo), bond);

        assertionId = oo.assertTruth(
            abi.encodePacked(
                "0x",
                ClaimData.toUtf8BytesAddress(_asserter),
                " asserting in the DataAsserter contract at 0x",
                ClaimData.toUtf8BytesAddress(address(this)),
                " that the deposit request with fillHash: 0x",
                ClaimData.toUtf8Bytes(_fillHash),
                " initiated by depositor 0x",
                ClaimData.toUtf8BytesAddress(_fillFor),
                " has been filled by relayer 0x",
                ClaimData.toUtf8BytesAddress(_filler),
                " receiving ",
                ClaimData.toUtf8BytesUint(_receivedShares),
                " shares of sDai is valid."
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

        fillAssertionsData[assertionId] =
            DepositFillAssertion(_fillHash, _filler, _fillToken, _amount, _fillFor, _receivedShares, false, _asserter);
        emit DepositFillAsserted(_fillHash, _asserter, assertionId);
        return assertionId;
    }

    // OptimisticOracleV3 resolve callback.
    function assertionResolvedCallback(bytes32 assertionId, bool assertedTruthfully) public {
        require(msg.sender == address(oo));
        // If the assertion was true, then the data assertion is resolved.
        if (assertedTruthfully) {
            assertionsData[assertionId].resolved = true;
            DepositFillAssertion memory fillDataAssertion = fillAssertionsData[assertionId];
            emit DepositFillAssertionResolved(fillDataAssertion.fillHash, fillDataAssertion.filler, assertionId);
            // Mint `amount` of wrapped sDAI to the depositor on scroll.
            (bool success,) = scrollSavingsDai.call(
                abi.encodeWithSignature(
                    "mint(address,uint256)", fillDataAssertion.fillFor, fillDataAssertion.receivedShares
                )
            );
            require(success, "Failed to mint Wrapped sDai shares to depositor on Scroll.");
            reimbursements[fillDataAssertion.filler][fillDataAssertion.fillToken] += fillDataAssertion.amount;
        } else {
            delete assertionsData[assertionId];
            // TODO: Refund deposited wDai back to user if assertion was false.
        }
    }

    function getReimbursementAmount(address _relayer, address _l2token) public view returns (uint256) {
        return reimbursements[_relayer][_l2token];
    }
    // function withdrawToL1(address _l2token) public {
    //     uint256 amount = reimbursements[msg.sender][_l2token];
    //     require(amount > 0, "No reimbursements available.");
    //     reimbursements[msg.sender][_l2token] = 0;
    //     // Withdraw `amount` through native bridge to L1.
    //     (bool success,) = scrollSavingsDai.call(
    //         abi.encodeWithSignature("withdraw(address,uint256)", _l2token, amount)
    //     );
    // }

    // TODO: Disputed Callback
    // This OptimisticOracleV3 callback function needs to be defined so the OOv3 doesn't revert when it tries to call it.
    // function assertionDisputedCallback(bytes32 assertionId) public {}
}
