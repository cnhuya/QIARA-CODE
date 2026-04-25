// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract EpochManager {
    uint256 public immutable GENESIS_TIMESTAMP;
    uint256 public immutable EPOCH_DURATION;

    constructor(uint256 _genesisTimestamp, uint256 _epochDuration) {
        require(_genesisTimestamp <= block.timestamp, "Genesis must be in past");
        require(_epochDuration > 0, "Duration cannot be zero");
        
        GENESIS_TIMESTAMP = _genesisTimestamp;
        EPOCH_DURATION = _epochDuration;
    }

    /**
     * @notice Calculates the current epoch based on the current block timestamp.
     */
    function getCurrentEpoch() public view returns (uint256) {
        if (block.timestamp < GENESIS_TIMESTAMP) return 0;
        return (block.timestamp - GENESIS_TIMESTAMP) / EPOCH_DURATION;
    }

    /**
     * @notice Returns the exact second an epoch ends.
     */
    function getEpochEndTime(uint256 epoch) public view returns (uint256) {
        return GENESIS_TIMESTAMP + ((epoch + 1) * EPOCH_DURATION);
    }

    /**
     * @notice Checks if a specific epoch has technically "finished".
     */
    function isEpochOver(uint256 epoch) public view returns (bool) {
        return block.timestamp >= getEpochEndTime(epoch);
    }
}