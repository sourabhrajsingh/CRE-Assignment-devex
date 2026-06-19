// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {PriceSnapshot} from "../src/Snapshot.sol";
import {ISnapshot} from "../src/Snapshot.sol";

/**
 * @dev Test Harness to expose the internal `_processReport` function for unit testing.
 */
contract PriceSnapshotHarness is PriceSnapshot {
    constructor(address _forwarder) PriceSnapshot(_forwarder) {}

    function expose_processReport(bytes calldata report) external {
        _processReport(report);
    }
}

contract PriceSnapshotTest is Test {
    PriceSnapshotHarness public priceSnapshot;
    address public mockForwarder = address(0x123);

    // Re-declaring the event here so forge's vm.expectEmit can match against it
    event SnapshotUpdated(
        string indexed token,
        uint256 price,
        uint256 blockNumber,
        uint256 timestamp
    );

    function setUp() public {
        // Deploy the harness contract instead of the raw contract
        priceSnapshot = new PriceSnapshotHarness(mockForwarder);
    }

    /**
     * @notice Verifies that a valid encoded report correctly updates the state and emits an event.
     */
    function test_ProcessReport_Success() public {
        ISnapshot.Record memory record = ISnapshot.Record({
            token: "ETH",
            price: 3000 * 10**18,
            blockNumber: 1000,
            timestamp: block.timestamp
        });

        // Encode the struct exactly how the CRE workflow would send it
        bytes memory report = abi.encode(record);

        // Expect the SnapshotUpdated event
        vm.expectEmit(true, false, false, true);
        emit SnapshotUpdated("ETH", record.price, record.blockNumber, record.timestamp);

        // Execute
        priceSnapshot.expose_processReport(report);

        // Assert contract state matches the report
        (string memory token, uint256 price, uint256 blockNumber, uint256 timestamp) = priceSnapshot.snapshot("ETH");
        assertEq(token, "ETH");
        assertEq(price, 3000 * 10**18);
        assertEq(blockNumber, 1000);
        assertEq(timestamp, block.timestamp);
    }

    /**
     * @notice Verifies the contract reverts if the token string is empty.
     */
    function test_Revert_InvalidToken() public {
        ISnapshot.Record memory record = ISnapshot.Record({
            token: "",
            price: 3000 * 10**18,
            blockNumber: 1000,
            timestamp: block.timestamp
        });

        bytes memory report = abi.encode(record);

        vm.expectRevert("Invalid token");
        priceSnapshot.expose_processReport(report);
    }

    /**
     * @notice Verifies the contract reverts if the price is zero.
     */
    function test_Revert_InvalidPrice() public {
        ISnapshot.Record memory record = ISnapshot.Record({
            token: "BTC",
            price: 0,
            blockNumber: 1000,
            timestamp: block.timestamp
        });

        bytes memory report = abi.encode(record);

        vm.expectRevert("Invalid price");
        priceSnapshot.expose_processReport(report);
    }

    /**
     * @notice Verifies that submitting a newer report for the same token overwrites the old state.
     */
    function test_UpdateExistingSnapshot() public {
        // First report
        ISnapshot.Record memory firstRecord = ISnapshot.Record({
            token: "LINK",
            price: 15 * 10**18,
            blockNumber: 1000,
            timestamp: block.timestamp
        });
        priceSnapshot.expose_processReport(abi.encode(firstRecord));

        // Second report updating the same token
        ISnapshot.Record memory secondRecord = ISnapshot.Record({
            token: "LINK",
            price: 16 * 10**18,
            blockNumber: 1001,
            timestamp: block.timestamp + 12
        });
        priceSnapshot.expose_processReport(abi.encode(secondRecord));

        // Verify the mapping holds the latest data
        (, uint256 price, uint256 blockNumber, ) = priceSnapshot.snapshot("LINK");
        assertEq(price, 16 * 10**18);
        assertEq(blockNumber, 1001);
    }

    /**
     * @notice Fuzz test to ensure the contract handles a massive variety of valid inputs.
     */
    function testFuzz_ProcessReport(
        string memory randomToken,
        uint256 randomPrice,
        uint256 randomBlock,
        uint256 randomTimestamp
    ) public {
        // Bound the fuzz inputs to satisfy your require statements
        vm.assume(bytes(randomToken).length > 0);
        vm.assume(randomPrice > 0);

        ISnapshot.Record memory record = ISnapshot.Record({
            token: randomToken,
            price: randomPrice,
            blockNumber: randomBlock,
            timestamp: randomTimestamp
        });

        bytes memory report = abi.encode(record);
        priceSnapshot.expose_processReport(report);

        // Verify the state matches the fuzz inputs
        (string memory token, uint256 price, uint256 blockNumber, uint256 timestamp) = priceSnapshot.snapshot(randomToken);
        assertEq(token, randomToken);
        assertEq(price, randomPrice);
        assertEq(blockNumber, randomBlock);
        assertEq(timestamp, randomTimestamp);
    }

    /**
     * @notice Test behavior when an older report arrives AFTER a newer report.
     */
    function test_OutOfOrderReports_OverwritesRegardless() public {
        string memory tokenName = "SOL";
        vm.warp(10000);

        // 1. Submit a NEW report (Block 5000) at current block.timestamp (10,000)
        ISnapshot.Record memory newRecord = ISnapshot.Record({
            token: tokenName,
            price: 150 * 10**18,
            blockNumber: 5000,
            timestamp: block.timestamp
        });
        priceSnapshot.expose_processReport(abi.encode(newRecord));

        // 2. Submit an OLD report (Block 4999) arriving late
        ISnapshot.Record memory oldRecord = ISnapshot.Record({
            token: tokenName,
            price: 145 * 10**18,
            blockNumber: 4999,
            timestamp: block.timestamp - 12
        });
        priceSnapshot.expose_processReport(abi.encode(oldRecord));

        // 3. Assert that the old report effectively overwrote the new one
        (, uint256 price, uint256 blockNumber, ) = priceSnapshot.snapshot(tokenName);
        assertEq(price, 145 * 10**18);
        assertEq(blockNumber, 4999);
    }

    /**
     * @notice Integration test confirming that the ReceiverTemplate's access control
     * works perfectly with the PriceSnapshot logic.
     */
    function test_Integration_OnlyForwarderCanCall() public {
        // 1. Prepare the report payload
        ISnapshot.Record memory record = ISnapshot.Record({
            token: "AVAX",
            price: 30 * 10**18,
            blockNumber: 100,
            timestamp: block.timestamp
        });
        bytes memory report = abi.encode(record);
        bytes memory metadata = "";

        address badActor = makeAddr("bad_actor");

        // 2. Context: An unauthorized user tries to call the public entry point
        vm.prank(badActor);
        vm.expectRevert();
        priceSnapshot.onReport(metadata, report);

        // 3. Context: The authorized forwarder calls the entry point
        vm.prank(mockForwarder);
        priceSnapshot.onReport(metadata, report);

        // 4. Assert that data successfully made it all the way to PriceSnapshot's storage
        (, uint256 price, uint256 blockNumber, ) = priceSnapshot.snapshot("AVAX");
        assertEq(price, 30 * 10**18);
        assertEq(blockNumber, 100);
    }
}
