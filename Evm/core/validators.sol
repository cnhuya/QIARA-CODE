// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IEpochManager {
    function getCurrentEpoch() external view returns (uint256);
}

contract IValidators {
    uint256 public activeRoot;
    uint256 public pendingRoot;

    // --- Struct to queue sequential updates [1] ---
    struct PendingUpdate {
        address validator;
        bool isRemoval;
    }

    // --- Address Lists & Update Queue ---
    address[] public activeAddresses;
    PendingUpdate[] public pendingUpdates; // Replaced pendingAddresses [1]

    // --- Epoch Tracking ---
    IEpochManager public epochManager;
    uint256 public lastProcessedEpoch; 

    address public authorizedContract;
    address public owner;

    // --- Events ---
    event AuthorizedContractUpdated(address indexed newAddress);
    event EpochManagerUpdated(address indexed newManager);
    event AddressAddedToPending(address indexed user, bool isRemoval, uint256 epoch);
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

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }
    modifier onlyAuthorized() {
        require(msg.sender == authorizedContract, "Not authorized");
        _;
    }

    // --- Logic ---
    
    function addPendingAddress(address _user, bool isRemoval) external onlyAuthorized {
        _checkAndHandleEpochRollover();

        // Push structured update to the queue [1]
        pendingUpdates.push(PendingUpdate({
            validator: _user,
            isRemoval: isRemoval
        }));

        emit AddressAddedToPending(_user, isRemoval, lastProcessedEpoch);
    }

    function _checkAndHandleEpochRollover() internal {
        uint256 currentEpoch = epochManager.getCurrentEpoch();

        // If time has moved into a new epoch compared to what we last saw
        if (currentEpoch > lastProcessedEpoch) {
            uint256 len = pendingUpdates.length;

            // Process updates sequentially in FIFO order [1]
            for (uint256 i = 0; i < len; i++) {
                PendingUpdate memory update = pendingUpdates[i];
                if (update.isRemoval) {
                    _removeActiveAddress(update.validator); // [1]
                } else {
                    _addActiveAddress(update.validator); // [1]
                }
            }

            // Clear pending updates for the new epoch [1]
            delete pendingUpdates;

            // Update the marker
            lastProcessedEpoch = currentEpoch;

            emit ListsRolledOver(currentEpoch, activeAddresses.length);
        }
    }

    // --- Internal Helpers for State Manipulation ---

    /// Deduplicates and appens a validator to the active set [1]
    function _addActiveAddress(address _user) internal {
        uint256 len = activeAddresses.length;
        for (uint256 i = 0; i < len; i++) {
            if (activeAddresses[i] == _user) {
                return; // Already present, skip
            }
        }
        activeAddresses.push(_user);
    }

    /// Gas-efficient swap-and-pop removal from the active set [1]
    function _removeActiveAddress(address _user) internal {
        uint256 len = activeAddresses.length;
        for (uint256 i = 0; i < len; i++) {
            if (activeAddresses[i] == _user) {
                // Swap target element with the last element of the array, then pop [1]
                activeAddresses[i] = activeAddresses[activeAddresses.length - 1];
                activeAddresses.pop();
                return;
            }
        }
    }

    // --- ADMIN FUNCTION ---
    function addActiveAddressDirect(address _user) external onlyOwner {
        _addActiveAddress(_user);
    }

    // --- Helpers / Views ---
    function getActiveAddresses() external view returns (address[] memory) {
        return activeAddresses;
    }

    /// Returns the raw PendingUpdate structs queue [1]
    function getPendingUpdates() external view returns (PendingUpdate[] memory) {
        return pendingUpdates;
    }

    /// Backwards compatibility helper: extracts just the addresses from pending queue [1]
    function getPendingAddresses() external view returns (address[] memory) {
        uint256 len = pendingUpdates.length;
        address[] memory addresses = new address[](len);
        for (uint256 i = 0; i < len; i++) {
            addresses[i] = pendingUpdates[i].validator;
        }
        return addresses;
    }

    function checkSystemEpoch() public view returns (uint256) {
        return epochManager.getCurrentEpoch();
    }
}