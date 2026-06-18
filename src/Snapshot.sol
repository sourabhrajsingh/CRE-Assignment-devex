// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import {ReceiverTemplate} from "./ReceiverTemplate.sol";

interface ISnapshot {
    struct Record {
        string token;
        uint256 price;
        uint256 blockNumber;
        uint256 timestamp;
    }
}

contract PriceSnapshot is ReceiverTemplate, ISnapshot {
    // Latest snapshot per token
    mapping(string => Record) public latestSnapshot;

    event SnapshotUpdated(
        string indexed token,
        uint256 price,
        uint256 blockNumber,
        uint256 timestamp
    );

    // Forwarder address required in constructor
    constructor(address _forwarderAddress) ReceiverTemplate(_forwarderAddress) {}

    /**
     * @notice Required by CRE - processes the encoded report from the workflow
     */
    function _processReport(bytes calldata report) internal override {
        Record memory record = abi.decode(report, (Record));

        // Optional forwarder check / validation already handled by ReceiverTemplate
        _storeRecord(record);
    }

    function _storeRecord(Record memory record) internal {

        require(bytes(record.token).length > 0, "Invalid token");
        require(record.price > 0, "Invalid price");

        latestSnapshot[record.token] = record;

        emit SnapshotUpdated(
            record.token,
            record.price,
            record.blockNumber,
            record.timestamp
        );
    }

    // Helper to read latest price
    function snapshot(string calldata tokenString) external view returns (string memory token, uint256 price, uint256 blockNumber, uint256 timestamp) {
        Record memory r = latestSnapshot[tokenString];
        return (r.token, r.price, r.blockNumber, r.timestamp);
    }

}
