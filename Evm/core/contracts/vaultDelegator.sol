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
    function stageVariable(string calldata header,string calldata name,bytes calldata data,uint256 effectiveEpoch,uint256 newCommitment) external;
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

    mapping(uint256 => bool) public usedNullifiers;

    constructor(
        address _balance_verifier,
        address _variable_verifier,
        address _validator_verifier, 
        address _variablesRegistry, 
        address _validatorsRegistry,
        address _vault
    ) Ownable(msg.sender) {
        balance_verifier = IBalanceVerifier(_balance_verifier);
        variable_verifier = IVariableVerifier(_variable_verifier);
        validator_verifier = IValidatorVerifier(_validator_verifier);
        variablesRegistry = IVariables(_variablesRegistry);
        validatorsRegistry = IValidators(_validatorsRegistry);
        if (_vault == address(0)) revert ZeroAddress();
        vault = _vault;

    }

    // [0] OldAccountRoot, [1] NewAccountRoot, [2] UserAddressL, [3] UserAddressH, [4] ProviderName (VaultAddress), [5] PackedTxData
    function processZkWithdraw(uint256[8] calldata proof,uint256[6] calldata pubSignals,bytes calldata signatures) external {
        if (!balanceVerifier.verifyProof(proof, pubSignals)) revert InvalidProof();

        // 1. Unpack PackedTxData
        uint256 packed = pubSignals[5];
        uint256 amount = packed & 0xFFFFFFFFFFFFFFFF;
        uint256 chainID = (packed >> 64) & 0xFFFFFFFF;
        uint256 nonce = (packed >> 96) & 0xFFFFFFFF;
        uint256 storageID = packed >> 128;

        if (chainID != block.chainid) revert WrongChain();

        // 2. Decode Identifiers & Destination
        address user = address(uint160((pubSignals[3] << 128) | pubSignals[2]));
        string memory providerName = fieldToString(pubSignals[4]);
        string memory assetName = fieldToString(storageID);

        // 3. Prevent Double-Spend (Per User + Token Nonce)
        if (nonce != userNonces[user][storageID] + 1) revert InvalidNonce();
        userNonces[user][storageID] = nonce;

        // 4. Replay Protection & Multisig Verification
        uint256 nullifier = uint256(keccak256(abi.encodePacked(
            pubSignals[0], pubSignals[1], pubSignals[2], pubSignals[3], pubSignals[4], pubSignals[5]
        )));

        if (usedNullifiers[nullifier]) revert ReplayAttack();
        usedNullifiers[nullifier] = true;

        _verifyAllSignatures(bytes32(nullifier), signatures);

        // 5. Direct Dispatch to Central Vault
        IQiaraVault(vault).directWithdraw(providerName, user, assetName, amount, nullifier);
    }

    // 🟢 Process ZK Variable Update (7 Public Inputs)
    // [0] OldCommitment, [1] NewCommitment, [2] PackedContext ((Header << 16) | Epoch)
    // [3] NameLow, [4] NameHigh, [5] DataLow, [6] DataHigh
    function processZkVariable(uint256[8] calldata proof,uint256[7] calldata pubSignals,bytes calldata signatures) external {
        if (!variableVerifier.verifyProof(proof, pubSignals)) revert InvalidProof();

        // Replay Protection & Multisig Verification
        uint256 nullifier = uint256(keccak256(abi.encodePacked(
            pubSignals[0], pubSignals[1], pubSignals[2], pubSignals[3],
            pubSignals[4], pubSignals[5], pubSignals[6]
        )));

        if (usedNullifiers[nullifier]) revert ReplayAttack();
        usedNullifiers[nullifier] = true;

        _verifyAllSignatures(bytes32(nullifier), signatures);

        // Unpack signals
        uint256 epoch = pubSignals[2] & 0xFFFF;
        string memory variableHeader = fieldToString(pubSignals[2] >> 16);
        string memory variableName = fieldToString((pubSignals[4] << 128) | pubSignals[3]);
        bytes memory variableData = abi.encodePacked((pubSignals[6] << 128) | pubSignals[5]);

        // Stage update to activate next epoch across all chains
        variablesRegistry.stageVariable(variableHeader,variableName,variableData,epoch + 1,pubSignals[1]);
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

    function _verifyAllSignatures(bytes32 _messageHash, bytes calldata _signatures) internal view {
        uint256 numSignatures = _signatures.length / 65;
        if (numSignatures == 0 || _signatures.length % 65 != 0) revert InvalidSignaturesLength();
        if (numSignatures < _readMinValidators()) revert InsufficientValidators();

        bytes32 ethHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", _messageHash));
        address lastSigner = address(0);

        for (uint256 i = 0; i < numSignatures; i++) {
            bytes32 r;
            bytes32 s;
            uint8 v;
            assembly {
                let offset := add(_signatures.offset, mul(i, 65))
                r := calldataload(offset)
                s := calldataload(add(offset, 32))
                v := byte(0, calldataload(add(offset, 64)))
            }

            address signer = ecrecover(ethHash, v, r, s);
            if (signer <= lastSigner) revert DuplicateOrUnorderedSigner();
            lastSigner = signer;

            // $O(1) direct status check (replaced array scan loop)
            if (!validatorsRegistry.isValidatorActive(signer)) revert UnauthorizedValidator();
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