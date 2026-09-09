// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IQiaraVerifier {
    function verifyProof(uint256[8] calldata proof, uint256[4] calldata input) external view;
}

interface IValidators {
    function getActiveAddresses() external view returns (address[] memory);
}

interface IQiaraVariables {
    function getActiveVariable(string calldata header, string calldata name) external view returns (bytes memory);
}

interface IEpochManager {
    function getCurrentEpoch() external view returns (uint256);
}


struct FeeConfig {
        uint256 currentEpoch;
        uint256 currentFeeRate;   // Effective rate for current epoch
        uint256 baseFeeRate;      // BURN_FEE (e.g. 500 = 0.0005%)
        uint256 increasePerEpoch; // BURN_INCREASE (e.g. 250 = 0.00025% per epoch)
        uint256 minFeeAmount;     // BURN_FEE_MINIMAL (scaled to 9 decimals)
        uint256 maxFeeRate;       // BURN_FEE_MAXIMAL (0 if uncapped)
        uint256 feeDenominator;   // 100_000_000 (1_000_000 = 1%)
    }

contract Qiara is ERC20, Ownable {
    uint256 public constant FEE_DENOMINATOR = 100_000_000; // 1_000_000 = 1% | 250 = 0.00025%

    IQiaraVerifier   public immutable verifier;
    IValidators      public immutable validatorsRegistry;
    IQiaraVariables  public immutable variablesRegistry;
    IEpochManager    public immutable epochManager;

    string  public variableHeader;
    address public feeRecipient; // address(0) = burn directly

    mapping(uint256 => bool) public usedNullifiers;
    mapping(address => bool) public isFeeExempt;

    event ZkMint(address indexed to, uint256 amount, uint256 nonce, uint256 nullifier);
    event FeeExemptUpdated(address indexed account, bool exempt);
    event FeeRecipientUpdated(address indexed newRecipient);
    event VariableHeaderUpdated(string newHeader);

    error InvalidProof();
    error ReplayAttack();
    error WrongChain();
    error InvalidSignatures();
    error UnauthorizedValidator();
    error DuplicateSignature();
    error UnauthorizedWhitelistAdmin();
    error InsufficientValidators();

    constructor(
        address _verifier,
        address _validatorsRegistry,
        address _variablesRegistry,
        address _epochManager,
        string memory _variableHeader,
        address _feeRecipient
    ) ERC20("Qiara", "Qiara") Ownable(msg.sender) {
        verifier           = IQiaraVerifier(_verifier);
        validatorsRegistry = IValidators(_validatorsRegistry);
        variablesRegistry  = IQiaraVariables(_variablesRegistry);
        epochManager       = IEpochManager(_epochManager);
        variableHeader     = bytes(_variableHeader).length > 0 ? _variableHeader : "QiaraToken";
        feeRecipient       = _feeRecipient; // address(0) burns tokens

        isFeeExempt[msg.sender]   = true;
        isFeeExempt[address(this)] = true;

        _mint(msg.sender, 1_000_000 * 10 ** 9);
    }

    function decimals() public pure override returns (uint8) {
        return 9;
    }

    // --- ZK Minting ---

    function zkMint(
        uint256[8] calldata proof,
        uint256[4] calldata pubSignals,
        bytes calldata signatures
    ) external {
        verifier.verifyProof(proof, pubSignals);

        uint256 packed = pubSignals[3];
        uint256 amount = packed & 0xFFFFFFFFFFFFFFFF;
        uint256 chainId = (packed >> 64) & 0xFFFFFFFF;
        uint256 nonce = (packed >> 96) & 0xFFFFFFFF;

        if (chainId != block.chainid) revert WrongChain();

        uint256 nullifier = uint256(keccak256(abi.encodePacked(
            pubSignals[0], pubSignals[1], pubSignals[2], pubSignals[3]
        )));

        if (usedNullifiers[nullifier]) revert ReplayAttack();
        usedNullifiers[nullifier] = true;

        _verifySignatures(bytes32(nullifier), signatures);

        address user = address(uint160(pubSignals[2]));
        _mint(user, amount);

        emit ZkMint(user, amount, nonce, nullifier);
    }

    // --- Dynamic Burn Fee & Whitelist ---

    function _readU64(string memory name) internal view returns (uint64 val) {
        bytes memory data = variablesRegistry.getActiveVariable(variableHeader, name);
        if (data.length == 8) {
            assembly { val := shr(192, mload(add(data, 32))) }
        } else if (data.length == 32) {
            assembly { val := mload(add(data, 32)) }
        }
    }

    /// @notice Calculates dynamic burn fee with epoch escalation and min/max clamps
    function calculateTransferFee(uint256 value) public view returns (uint256) {
        uint256 baseRate = _readU64("BURN_FEE"); // e.g. 500 = 0.0005%
        if (baseRate == 0) return 0;

        uint256 increase = _readU64("BURN_INCREASE"); // e.g. 250 = 0.00025% per epoch
        uint256 epoch = epochManager.getCurrentEpoch();
        uint256 rate = baseRate + (increase * epoch);

        // Maximum fee rate clamp (if BURN_FEE_MAXIMAL is registered)
        uint256 maxRate = _readU64("BURN_FEE_MAXIMAL");
        if (maxRate > 0 && rate > maxRate) {
            rate = maxRate;
        } else if (rate > FEE_DENOMINATOR) {
            rate = FEE_DENOMINATOR;
        }

        uint256 fee = (value * rate) / FEE_DENOMINATOR;

        // Minimum fee clamp: 100 units at 6 decimals = 0.0001 token -> scaled to 9 decimals (* 1000)
        uint256 rawMin = _readU64("BURN_FEE_MINIMAL");
        if (rawMin > 0) {
            uint256 minFee = rawMin >= 100_000 ? rawMin : rawMin * 1000;
            if (fee < minFee) fee = minFee;
        }

        return fee > value ? value : fee;
    }

    function getWhitelistAdmin() public view returns (address admin) {
        bytes memory data = variablesRegistry.getActiveVariable(variableHeader, "WHITELIST_ADMIN");
        if (data.length == 20) {
            assembly { admin := shr(96, mload(add(data, 32))) }
        } else if (data.length == 32) {
            admin = abi.decode(data, (address));
        }
        return admin == address(0) ? owner() : admin;
    }

    function setFeeExempt(address account, bool exempt) external {
        if (msg.sender != getWhitelistAdmin() && msg.sender != owner()) {
            revert UnauthorizedWhitelistAdmin();
        }
        isFeeExempt[account] = exempt;
        emit FeeExemptUpdated(account, exempt);
    }

    // --- ERC20 Transfer Hook ---

    function _update(address from, address to, uint256 value) internal virtual override {
        if (from == address(0) || to == address(0) || isFeeExempt[from] || isFeeExempt[to]) {
            super._update(from, to, value);
            return;
        }

        uint256 fee = calculateTransferFee(value);
        if (fee > 0) {
            super._update(from, feeRecipient, fee); // address(0) burns tokens
            unchecked { value -= fee; }
        }

        super._update(from, to, value);
    }

    // --- Internal Helpers ---


    function _readU8(string memory name) internal view returns (uint8) {
        bytes memory data = variablesRegistry.getActiveVariable(variableHeader, name);
        if (data.length == 0) {
            data = variablesRegistry.getActiveVariable("QiaraValidators", name);
        }
        if (data.length == 1) return uint8(data[0]);
        if (data.length == 32) return uint8(uint256(bytes32(data)));
        return 0;
    }

    function _verifySignatures(bytes32 messageHash, bytes calldata signatures) internal view {
        uint256 numSigs = signatures.length / 65;
        if (numSigs == 0 || signatures.length % 65 != 0) revert InvalidSignatures();

        // Enforce dynamic validator quorum
        uint256 minValidators = _readU8("MINIMUM_UNIQUE_VALIDATORS");
        if (numSigs < minValidators) revert InsufficientValidators();

        bytes32 ethSignedHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );

        address[] memory activeValidators = validatorsRegistry.getActiveAddresses();
        address lastSigner = address(0);

        for (uint256 i = 0; i < numSigs; i++) {
            bytes32 r;
            bytes32 s;
            uint8 v;
            assembly {
                let offset := add(signatures.offset, mul(i, 65))
                r := calldataload(offset)
                s := calldataload(add(offset, 32))
                v := byte(0, calldataload(add(offset, 64)))
            }

            address signer = ecrecover(ethSignedHash, v, r, s);
            // Strictly ascending ensures each signature is from a UNIQUE validator
            if (signer <= lastSigner) revert DuplicateSignature();
            lastSigner = signer;

            bool isAuthorized = false;
            for (uint256 j = 0; j < activeValidators.length; j++) {
                if (activeValidators[j] == signer) {
                    isAuthorized = true;
                    break;
                }
            }
            if (!isAuthorized) revert UnauthorizedValidator();
        }
    }


    /// @notice Full transparency view returning all active fee mechanics and current rates
    function getFeeConfig() external view returns (FeeConfig memory cfg) {
        cfg.currentEpoch     = epochManager.getCurrentEpoch();
        cfg.baseFeeRate      = _readU64("BURN_FEE");
        cfg.increasePerEpoch = _readU64("BURN_INCREASE");
        cfg.maxFeeRate       = _readU64("BURN_FEE_MAXIMAL");
        cfg.feeDenominator   = FEE_DENOMINATOR;

        uint256 rawMin = _readU64("BURN_FEE_MINIMAL");
        cfg.minFeeAmount = rawMin >= 100_000 ? rawMin : rawMin * 1000;

        uint256 rate = cfg.baseFeeRate + (cfg.increasePerEpoch * cfg.currentEpoch);
        if (cfg.maxFeeRate > 0 && rate > cfg.maxFeeRate) {
            rate = cfg.maxFeeRate;
        } else if (rate > FEE_DENOMINATOR) {
            rate = FEE_DENOMINATOR;
        }
        cfg.currentFeeRate = rate;
    }

    // --- Admin Setters ---

    function setFeeRecipient(address _newRecipient) external onlyOwner {
        feeRecipient = _newRecipient;
        emit FeeRecipientUpdated(_newRecipient);
    }

    function setVariableHeader(string calldata _newHeader) external onlyOwner {
        variableHeader = _newHeader;
        emit VariableHeaderUpdated(_newHeader);
    }
}