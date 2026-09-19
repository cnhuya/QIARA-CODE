// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IEpochManager {
    function getCurrentEpoch() external view returns (uint256);
}

contract QiaraVariables {
    struct TimedValue {
        bytes data;
        uint256 effectiveEpoch;
    }

    uint256 public activeCommitment;
    IEpochManager public epochManager;
    address public authorizedContract;
    address public owner;

    // keyHash = keccak256(abi.encodePacked(header, ":", name))
    mapping(bytes32 => bytes) private _activeData;
    mapping(bytes32 => TimedValue) private _pendingData;

    event EpochManagerUpdated(address indexed newManager);
    event AuthorizedContractUpdated(address indexed newAuth);
    event VariableStaged(string header, string name, uint256 indexed effectiveEpoch, uint256 newCommitment);
    event VariableDirectUpdated(string header, string name);

    error Unauthorized();
    error ZeroAddress();

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier onlyAuthorized() {
        if (msg.sender != authorizedContract && msg.sender != owner) revert Unauthorized();
        _;
    }

    constructor(address _epochManager, uint256 _initialCommitment) {
        owner = msg.sender;
        epochManager = IEpochManager(_epochManager);
        activeCommitment = _initialCommitment;
    }

    // --- Configuration ---
    function setEpochManager(address _epochManager) external onlyOwner {
        if (_epochManager == address(0)) revert ZeroAddress();
        epochManager = IEpochManager(_epochManager);
        emit EpochManagerUpdated(_epochManager);
    }

    function setAuthorizedContract(address _authAddress) external onlyOwner {
        if (_authAddress == address(0)) revert ZeroAddress();
        authorizedContract = _authAddress;
        emit AuthorizedContractUpdated(_authAddress);
    }

    // --- State Transition (Called by QiaraZKDelegator) ---
    function stageVariable(string calldata header,string calldata name,bytes calldata data,uint256 effectiveEpoch,uint256 newCommitment) external onlyAuthorized {
        bytes32 keyHash = keccak256(abi.encodePacked(header, ":", name));

        // Auto-promote matured pending value before overwriting
        TimedValue storage cur = _pendingData[keyHash];
        if (cur.effectiveEpoch != 0 && epochManager.getCurrentEpoch() >= cur.effectiveEpoch) {
            _activeData[keyHash] = cur.data;
        }

        _pendingData[keyHash] = TimedValue({
            data: data,
            effectiveEpoch: effectiveEpoch
        });

        activeCommitment = newCommitment;
        emit VariableStaged(header, name, effectiveEpoch, newCommitment);
    }

    // --- Admin Direct Set ---
    function setActiveVariableDirect(string calldata header,string calldata name,bytes calldata data) external onlyOwner {
        bytes32 keyHash = keccak256(abi.encodePacked(header, ":", name));
        _activeData[keyHash] = data;
        delete _pendingData[keyHash];
        emit VariableDirectUpdated(header, name);
    }

    // --- Views ---
    function getActiveVariable(string calldata header, string calldata name) external view returns (bytes memory) {
        bytes32 keyHash = keccak256(abi.encodePacked(header, ":", name));
        TimedValue memory pending = _pendingData[keyHash];

        if (pending.effectiveEpoch != 0 && epochManager.getCurrentEpoch() >= pending.effectiveEpoch) {
            return pending.data;
        }
        return _activeData[keyHash];
    }
}