// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

interface IBalanceVerifier {
    function verifyProof(uint[2] calldata _pA, uint[2][2] calldata _pB, uint[2] calldata _pC, uint[7] calldata _pubSignals) external view returns (bool);
}
interface IVariableVerifier {
    function verifyProof(uint[2] calldata _pA, uint[2][2] calldata _pB, uint[2] calldata _pC, uint[6] calldata _pubSignals) external view returns (bool);
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
    string public vaultHeader; // 👈 Dynamic Vault Header

    mapping(uint256 => bool) public usedNullifiers;

    constructor(
        address _balance_verifier,
        address _variable_verifier,
        address _validator_verifier, 
        address _variablesRegistry, 
        address _validatorsRegistry,
        string memory _vaultHeader // 👈 Added Parameter
    ) Ownable(msg.sender) {
        balance_verifier = IBalanceVerifier(_balance_verifier);
        variable_verifier = IVariableVerifier(_variable_verifier);
        validator_verifier = IValidatorVerifier(_validator_verifier);
        variablesRegistry = IVariables(_variablesRegistry);
        validatorsRegistry = IValidators(_validatorsRegistry);
        vaultHeader = _vaultHeader; // 👈 Stored
    }

    function processZkWithdraw(uint[2] calldata _pA, uint[2][2] calldata _pB, uint[2] calldata _pC, uint[7] calldata _pubSignals, address[] calldata validators, bytes calldata _signatures) external {
        require(balance_verifier.verifyProof(_pA, _pB, _pC, _pubSignals), "Invalid ZK Proof");

        (uint256 amount, address vaultAddr, string memory storageName) = _prepareWithdrawal(_pubSignals);

        uint256 userL = _pubSignals[3];
        uint256 userH = _pubSignals[4];
        uint256 nullifier = _calculateNullifier7(_pubSignals);
        _verifyAllSignatures(bytes32(nullifier), validators, _signatures);
        require(!usedNullifiers[nullifier], "Replay attack detected");
        usedNullifiers[nullifier] = true;

        address user = address(uint160((userH << 128) | userL));
        IQiaraVault(vaultAddr).grantWithdrawalPermission(user, storageName, amount, nullifier);
    }

    function processZkVariable(uint[2] calldata _pA, uint[2][2] calldata _pB, uint[2] calldata _pC, uint[6] calldata _pubSignals, address[] calldata validators, bytes calldata _signatures) external {
        require(variable_verifier.verifyProof(_pA, _pB, _pC, _pubSignals), "Invalid ZK Proof");

        uint256 chainID = _pubSignals[5];
        require(chainID == block.chainid, "Wrong destination chain");

        string memory variableName = fieldToString(_pubSignals[3]);
        string memory variableHeader = fieldToString(_pubSignals[2]);
        bytes memory variableValue = fieldToBytes(_pubSignals[4]);

        uint256 nullifier = _calculateNullifier6(_pubSignals);
        _verifyAllSignatures(bytes32(nullifier), validators, _signatures);
        require(!usedNullifiers[nullifier], "Replay attack detected");
        usedNullifiers[nullifier] = true;

        variablesRegistry.addPendingVariable(variableHeader, variableName, variableValue);
    }

    function processZkValidator(uint[2] calldata _pA, uint[2][2] calldata _pB, uint[2] calldata _pC, uint[6] calldata _pubSignals, address[] calldata validators, bytes calldata _signatures) external {
        require(validator_verifier.verifyProof(_pA, _pB, _pC, _pubSignals), "Invalid ZK Proof");

        uint256 chainID = _pubSignals[4];
        require(chainID == block.chainid, "Wrong destination chain");

        uint256 nullifier = _calculateNullifier6(_pubSignals);
        _verifyAllSignatures(bytes32(nullifier), validators, _signatures);
        require(!usedNullifiers[nullifier], "Replay attack detected");
        usedNullifiers[nullifier] = true;

        address validator = fieldToAddress(_pubSignals[5]);
        validatorsRegistry.addPendingAddress(validator);
    }

    function _calculateNullifier7(uint256[7] calldata _pubSignals) internal pure returns (uint256) {
        bytes32 hash = keccak256(abi.encodePacked(
            _pubSignals[0],
            _pubSignals[1],
            _pubSignals[2],
            _pubSignals[3],
            _pubSignals[4],
            _pubSignals[5],
            _pubSignals[6]
        ));
        return uint256(hash);
    }

    function _calculateNullifier6(uint256[6] calldata _pubSignals) internal pure returns (uint256) {
        bytes32 hash = keccak256(abi.encodePacked(
            _pubSignals[0],
            _pubSignals[1],
            _pubSignals[2],
            _pubSignals[3],
            _pubSignals[4]
        ));
        return uint256(hash);
    }

    function _prepareWithdrawal(uint[7] calldata _pubSignals) internal view returns (uint256 amount, address vaultAddr, string memory storageName){
        uint256 packed = _pubSignals[5];
        uint256 chainID = packed & 0xFFFFFFFF;
        amount = (packed >> 32) & 0xFFFFFFFFFFFFFFFF;

        require(chainID == block.chainid, "Wrong destination chain");

        storageName = fieldToString(_pubSignals[5]);
        string memory providerName = fieldToString(_pubSignals[6]);

        string memory vaultKey = string(abi.encodePacked(providerName, "_vault"));
        
        // 👈 Uses dynamic vaultHeader state variable
        bytes memory vaultBytes = variablesRegistry.getActiveVariable(vaultHeader, vaultKey);

        require(vaultBytes.length > 0, "Vault not authorized");
        vaultAddr = abi.decode(vaultBytes, (address));
    }

    function _verifyAllSignatures(bytes32 _messageHash,address[] calldata validators,bytes calldata _signatures) internal view {
        bytes32 ethHash = getEthSignedMessageHash(_messageHash);
        address[] memory active_validators = validatorsRegistry.getActiveAddresses();

        for (uint256 i = 0; i < validators.length; i++) {
            bytes calldata signature = _signatures[i * 65 : (i + 1) * 65];
            address signer = recoverSigner(ethHash, signature);
            require(signer != address(0), "Invalid signature");

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
        bytes32 b32 = bytes32(_field);
        uint8 start = 0;
        while (start < 32 && b32[start] == 0) start++;
        uint8 end = 31;
        while (end > start && b32[end] == 0) end--;

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

    function recoverSigner(bytes32 _ethSignedMessageHash, bytes memory _signature) public pure returns (address){
        require(_signature.length == 65, "Invalid signature length");
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(_signature, 32))
            s := mload(add(_signature, 64))
            v := byte(0, mload(add(_signature, 96)))
        }
        return ecrecover(_ethSignedMessageHash, v, r, s);
    }
}