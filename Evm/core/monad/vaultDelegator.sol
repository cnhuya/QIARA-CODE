// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

interface IBalanceVerifier {
    function verifyProof(uint[2] calldata _pA, uint[2][2] calldata _pB, uint[2] calldata _pC, uint[8] calldata _pubSignals) external view returns (bool);
}
interface IVariableVerifier {
    function verifyProof(uint[2] calldata _pA, uint[2][2] calldata _pB, uint[2] calldata _pC, uint[8] calldata _pubSignals) external view returns (bool);
}
interface IValidatorVerifier {
    function verifyProof(uint[2] calldata _pA, uint[2][2] calldata _pB, uint[2] calldata _pC, uint[6] calldata _pubSignals) external view returns (bool);
}

interface IQiaraVault {
    function grantWithdrawalPermission(address user, string memory assetName, uint256 amount, uint256 nullifier) external;
}

interface IVariables {
    function addPendingVariable(string calldata header, string calldata name, bytes calldata data) external;
    function getActiveVariable(string calldata header, string calldata name) external view returns (bytes memory);
}
interface IValidators{
    function addPendingAddress(address _user) external;
    function getActiveAddresses() external view returns (address[] memory);
}

contract QiaraZKDelegator is Ownable {
    IBalanceVerifier public immutable balance_verifier;
    IVariableVerifier public immutable variable_verifier;
    IValidatorVerifier public immutable validator_verifier;
    IVariables public immutable variablesRegistry;
    IValidators public immutable validatorsRegistry;
    
    // Mapping to prevent replay attacks
    mapping(uint256 => bool) public usedNullifiers;

    constructor(address _balance_verifier,address _variable_verifier,address _validator_verifier, address _variablesRegistry, address _validatorsRegistry) Ownable(msg.sender) {
        balance_verifier = IBalanceVerifier(_balance_verifier);
        variable_verifier = IVariableVerifier(_variable_verifier);
        validator_verifier = IValidatorVerifier(_validator_verifier);
        variablesRegistry = IVariables(_variablesRegistry);
        validatorsRegistry = IValidators(_validatorsRegistry);
    }

    function processZkWithdraw(uint[2] calldata _pA, uint[2][2] calldata _pB, uint[2] calldata _pC, uint[8] calldata _pubSignals, address[] calldata validators, bytes calldata _signatures) external {
        // 1. Verify ZK Proof
        require(balance_verifier.verifyProof(_pA, _pB, _pC, _pubSignals), "Invalid ZK Proof");

        (uint256 amount, address vaultAddr, string memory storageName) =_prepareWithdrawal(_pubSignals);

        // 5. Replay Protection (Using SHA256)
        uint256 userL = _pubSignals[3];
        uint256 userH = _pubSignals[4];
        uint256 nullifier = _calculateNullifier8(_pubSignals);
        _verifyAllSignatures(bytes32(nullifier), validators, _signatures);
        require(!usedNullifiers[nullifier], "Replay attack detected");
        usedNullifiers[nullifier] = true;

        // 6. User Address Reconstruction
        address user = address(uint160((userH << 128) | userL));

        // 7. Final Call
        IQiaraVault(vaultAddr).grantWithdrawalPermission(user, storageName, amount, nullifier);
    }
    function processZkVariable(uint[2] calldata _pA, uint[2][2] calldata _pB, uint[2] calldata _pC, uint[8] calldata _pubSignals, address[] calldata validators, bytes calldata _signatures) external {
        // 1. Verify ZK Proof
        require(variable_verifier.verifyProof(_pA, _pB, _pC, _pubSignals), "Invalid ZK Proof");




        uint256 chainID = _pubSignals[5];
        require(chainID == block.chainid, "Wrong destination chain");

        // 3. Convert Field Values to Strings
        string memory variableName = fieldToString(_pubSignals[3]);
        string memory variableHeader = fieldToString(_pubSignals[2]);
        bytes memory variableValue = fieldToBytes(_pubSignals[4]);

        // 4. Replay Protection (Using SHA256)
        uint256 nullifier = _calculateNullifier8(_pubSignals);
        _verifyAllSignatures(bytes32(nullifier), validators, _signatures);
        require(!usedNullifiers[nullifier], "Replay attack detected");
        usedNullifiers[nullifier] = true;

        // 7. Final Call
        variablesRegistry.addPendingVariable(variableHeader, variableName, variableValue);
    }
    function processZkValidator(uint[2] calldata _pA, uint[2][2] calldata _pB, uint[2] calldata _pC, uint[6] calldata _pubSignals, address[] calldata validators, bytes calldata _signatures) external {
        // 1. Verify ZK Proof
        require(validator_verifier.verifyProof(_pA, _pB, _pC, _pubSignals), "Invalid ZK Proof");

        uint256 chainID = _pubSignals[4];
        require(chainID == block.chainid, "Wrong destination chain");

        // 4. Replay Protection (Using SHA256)
        uint256 nullifier = _calculateNullifier6(_pubSignals);
        _verifyAllSignatures(bytes32(nullifier), validators, _signatures);
        require(!usedNullifiers[nullifier], "Replay attack detected");
        usedNullifiers[nullifier] = true;

        address validator = fieldToAddress(_pubSignals[5]);

        // 7. Final Call
        validatorsRegistry.addPendingAddress(validator);
    }

    // Dont hash the last pub signal, that contains the pubkey of the validator, which would result in all nulifiers being unique, leading to never reaching needed quarum
    function _calculateNullifier8(uint256[8] calldata _pubSignals) internal pure returns (uint256) {
        // abi.encodePacked concatenates all values into a raw byte stream.
        // Hashing the entire array ensures that if ANY signal changes, the nullifier changes.
        bytes32 hash = keccak256(abi.encodePacked(
            _pubSignals[0],
            _pubSignals[1],
            _pubSignals[2],
            _pubSignals[3],
            _pubSignals[4],
            _pubSignals[5],
            _pubSignals[6]
           //_pubSignals[7],
        ));

        return uint256(hash);
    }
    // Dont hash the last pub signal, that contains the pubkey of the validator, which would result in all nulifiers being unique, leading to never reaching needed quarum
    function _calculateNullifier6(uint256[6] calldata _pubSignals) internal pure returns (uint256) {
        // abi.encodePacked concatenates all values into a raw byte stream.
        // Hashing the entire array ensures that if ANY signal changes, the nullifier changes.
        bytes32 hash = keccak256(abi.encodePacked(
            _pubSignals[0],
            _pubSignals[1],
            _pubSignals[2],
            _pubSignals[3],
            _pubSignals[4]
            //_pubSignals[5],
        ));

        return uint256(hash);
    }

    function _prepareWithdrawal(uint[8] calldata _pubSignals) internal view returns (uint256 amount, address vaultAddr, string memory storageName){
        uint256 packed = _pubSignals[7];
        uint256 chainID = packed & 0xFFFFFFFF;
        amount = (packed >> 32) & 0xFFFFFFFFFFFFFFFF;

        require(chainID == block.chainid, "Wrong destination chain");

        storageName = fieldToString(_pubSignals[5]);
        string memory providerName = fieldToString(_pubSignals[6]);

        string memory vaultKey = string(abi.encodePacked(providerName, "_vault"));
        bytes memory vaultBytes = variablesRegistry.getActiveVariable("QiaraBaseAssets", vaultKey);

        require(vaultBytes.length > 0, "Vault not authorized");

        vaultAddr = abi.decode(vaultBytes, (address));
    }

    function _verifyAllSignatures(bytes32 _messageHash,address[] calldata validators,bytes calldata _signatures) internal view {
        bytes32 ethHash = getEthSignedMessageHash(_messageHash);
        
        // 1. Fetch once to save gas and stack space
        address[] memory active_validators = validatorsRegistry.getActiveAddresses();

        for (uint256 i = 0; i < validators.length; i++) {
            bytes calldata signature = _signatures[i * 65 : (i + 1) * 65];
            address signer = recoverSigner(ethHash, signature);
            require(signer != address(0), "Invalid signature");

            // 2. Check if signer is in the active list
            bool isAuthorized = false;
            for (uint256 j = 0; j < active_validators.length; j++) {
                if (active_validators[j] == signer) {
                    isAuthorized = true;
                    break;
                }
            }
            require(isAuthorized, "Signer not an active validator");
        }
    }

    function fieldToString(uint256 _field) public pure returns (string memory) {
        if (_field == 0) return "";

        // Step 1: Cast to bytes32 to access individual bytes
        bytes32 b32 = bytes32(_field);
        
        // Step 2: Find the first non-zero byte (start of the string)
        uint8 start = 0;
        while (start < 32 && b32[start] == 0) {
            start++;
        }

        // Step 3: Find the last non-zero byte (end of the string)
        // This handles cases where there might be trailing zeros
        uint8 end = 31;
        while (end > start && b32[end] == 0) {
            end--;
        }

        uint8 len = (end - start) + 1;
        bytes memory result = new bytes(len);

        for (uint256 i = 0; i < len; i++) {
            result[i] = b32[start + i];
        }

        return string(result);
    }
    function fieldToAddress(uint256 _field) public pure returns (address) {
        return address(uint160(_field));
    }
    function fieldToBytes(uint256 _field) public pure returns (bytes memory) {
        return abi.encodePacked(_field);
    }


    function getEthSignedMessageHash(bytes32 _messageHash) public pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", _messageHash));
    }
    function recoverSigner(bytes32 _ethSignedMessageHash, bytes memory _signature)public pure returns (address){
        require(_signature.length == 65, "Invalid signature length");

        bytes32 r;
        bytes32 s;
        uint8 v;

        // 3. Split the signature using assembly
        assembly {
            r := mload(add(_signature, 32))
            s := mload(add(_signature, 64))
            v := byte(0, mload(add(_signature, 96)))
        }

        // 4. Use the ecrecover precompile
        return ecrecover(_ethSignedMessageHash, v, r, s);
    }
}