// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IEpochManager {
    function getCurrentEpoch() external view returns (uint256);
}

contract QiaraValidators {
    struct TimedStatus {
        bool isActive;          // Baseline active status
        uint256 effectiveEpoch; // Epoch when targetStatus takes effect
        bool targetStatus;      // Status to apply at effectiveEpoch
    }

    uint256 public activeCommitment;
    IEpochManager public epochManager;
    address public authorizedContract;
    address public owner;

    address[] private _allValidators;
    mapping(address => bool) private _isKnown;
    mapping(address => TimedStatus) private _statuses;

    event EpochManagerUpdated(address indexed newManager);
    event AuthorizedContractUpdated(address indexed newAuth);
    event ValidatorStaged(address indexed validator, bool isAdded, uint256 indexed effectiveEpoch, uint256 newCommitment);
    event ValidatorDirectSet(address indexed validator, bool isActive);

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
    function stageValidator(
        address validator,
        bool isRemoval,
        uint256 effectiveEpoch,
        uint256 newCommitment
    ) external onlyAuthorized {
        if (!_isKnown[validator]) {
            _isKnown[validator] = true;
            _allValidators.push(validator);
        }

        TimedStatus storage cur = _statuses[validator];
        uint256 currentEpoch = epochManager.getCurrentEpoch();

        // Auto-promote previous status if already matured
        if (cur.effectiveEpoch != 0 && currentEpoch >= cur.effectiveEpoch) {
            cur.isActive = cur.targetStatus;
        }

        cur.targetStatus = !isRemoval;
        cur.effectiveEpoch = effectiveEpoch;

        activeCommitment = newCommitment;
        emit ValidatorStaged(validator, !isRemoval, effectiveEpoch, newCommitment);
    }

    // --- Admin Direct Fallback ---
    function setActiveValidatorDirect(address validator, bool isActive) external onlyOwner {
        if (!_isKnown[validator]) {
            _isKnown[validator] = true;
            _allValidators.push(validator);
        }

        _statuses[validator] = TimedStatus({
            isActive: isActive,
            effectiveEpoch: 0,
            targetStatus: false
        });

        emit ValidatorDirectSet(validator, isActive);
    }

    // --- View Functions ---

    /// $O(1)$ lookup for signature verification (eliminates nested loops in Delegator)
    function isValidatorActive(address validator) public view returns (bool) {
        TimedStatus memory cur = _statuses[validator];
        if (cur.effectiveEpoch != 0 && epochManager.getCurrentEpoch() >= cur.effectiveEpoch) {
            return cur.targetStatus;
        }
        return cur.isActive;
    }

    /// Returns dynamic list of validators active in the current epoch (zero storage writes)
    function getActiveAddresses() external view returns (address[] memory) {
        uint256 len = _allValidators.length;
        uint256 count = 0;

        for (uint256 i = 0; i < len; i++) {
            if (isValidatorActive(_allValidators[i])) {
                count++;
            }
        }

        address[] memory active = new address[](count);
        uint256 idx = 0;
        for (uint256 i = 0; i < len; i++) {
            address v = _allValidators[i];
            if (isValidatorActive(v)) {
                active[idx++] = v;
            }
        }
        return active;
    }
}