// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IEpochManager {
    function getCurrentEpoch() external view returns (uint256);
}

contract IValidators {
    uint256 public activeRoot;
    uint256 public pendingRoot;

    // --- Address Lists ---
    address[] public activeAddresses;
    address[] public pendingAddresses;

    // --- Epoch Tracking ---
    IEpochManager public epochManager;
    uint256 public lastProcessedEpoch; 

    address public authorizedContract;
    address public owner;

    event AuthorizedContractUpdated(address indexed newAddress);
    event EpochManagerUpdated(address indexed newManager);
    event AddressAddedToPending(address indexed user, uint256 epoch);
    event ListsRolledOver(uint256 newEpoch, uint256 countMoved);

    constructor() {
        owner = msg.sender;
    }

    // --- Configuration ---

    function setEpochManager(address _epochManager) external {
        require(msg.sender == owner, "Only owner");
        epochManager = IEpochManager(_epochManager);
        emit EpochManagerUpdated(_epochManager);
    }

    function setAuthorizedContract(address _authAddress) external {
        require(msg.sender == owner, "Only owner");
        authorizedContract = _authAddress;
        emit AuthorizedContractUpdated(_authAddress);
    }

    modifier onlyAuthorized() {
        require(msg.sender == authorizedContract, "Not authorized");
        _;
    }

    // --- Logic ---
    function addPendingAddress(address _user) external onlyAuthorized {
        _checkAndHandleEpochRollover();

        pendingAddresses.push(_user);
        emit AddressAddedToPending(_user, lastProcessedEpoch);
    }

    function _checkAndHandleEpochRollover() internal {
        uint256 currentEpoch = epochManager.getCurrentEpoch();

        // If time has moved into a new epoch compared to what we last saw
        if (currentEpoch > lastProcessedEpoch) {
            
            // 1. Move pending to active
            // Note: In production, consider gas limits if pendingAddresses is huge.
            activeAddresses = pendingAddresses;

            // 2. Clear pending for the new epoch
            delete pendingAddresses;

            // 3. Update the marker
            lastProcessedEpoch = currentEpoch;

            emit ListsRolledOver(currentEpoch, activeAddresses.length);
        }
    }

    // --- Helpers / Views ---

    function getActiveAddresses() external view returns (address[] memory) {
        return activeAddresses;
    }
    function getPendingAddresses() external view returns (address[] memory) {
        return pendingAddresses;
    }
    function checkSystemEpoch() public view returns (uint256) {
        return epochManager.getCurrentEpoch();
    }
}