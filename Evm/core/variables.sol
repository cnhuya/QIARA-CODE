// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IEpochManager {
    function getCurrentEpoch() external view returns (uint256);
}

contract QiaraVariables {
    struct VariableEntry {
        string header;
        string name;
        bytes data;
    }

    // --- State Variables ---
    uint256 public activeRoot;
    uint256 public pendingRoot;

    // --- Epoch Tracking ---
    IEpochManager public epochManager;
    uint256 public lastProcessedEpoch; 

    address public authorizedContract;
    address public owner;

    // --- List Logic (Similar to Validators) ---
    // These store the actual data intended for the next state update
    VariableEntry[] public pendingVariables;
    mapping(string => mapping(string => bytes)) private _activeData;

    // --- Events ---
    event AuthorizedContractUpdated(address indexed newAddress);
    event EpochManagerUpdated(address indexed newManager);
    event VariableQueued(string indexed header, string indexed name, uint256 epoch);
    event VariablesFinalized(uint256 indexed epoch, uint256 countMoved, uint256 newRoot);

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

    // --- Epoch & List Logic ---
    function addPendingVariable(string calldata header, string calldata name, bytes calldata data) external onlyAuthorized {
        
        // Check if we've entered a new epoch. 
        // If so, we clear pending (or you could move them to a history log)
        _checkAndHandleEpochRollover();

        pendingVariables.push(VariableEntry(header, name, data));
        emit VariableQueued(header, name, lastProcessedEpoch);
    }

    function _checkAndHandleEpochRollover() internal {
        uint256 currentEpoch = epochManager.getCurrentEpoch();
        
        if (currentEpoch > lastProcessedEpoch) {
            // Clear the pending queue from the previous epoch
            // Users must now prove the state including those variables
            for (uint i = 0; i < pendingVariables.length; i++) {
                VariableEntry memory entry = pendingVariables[i];
                _activeData[entry.header][entry.name] = entry.data;
            }
            
            uint256 count = pendingVariables.length;
            delete pendingVariables;
            emit VariablesFinalized(lastProcessedEpoch, count, activeRoot);
            lastProcessedEpoch = currentEpoch;
        }
    }

    // --- ADMIN FUNCTION ---
    function setActiveVariableDirect(string calldata header,string calldata name,bytes calldata data) external onlyOwner {
        _activeData[header][name] = data;
    }

    // --- Views ---
    function getActiveVariable(string calldata header, string calldata name) external view returns (bytes memory) {
        return _activeData[header][name];
    }
    function getPendingCount() external view returns (uint256) {
        return pendingVariables.length;
    }
}