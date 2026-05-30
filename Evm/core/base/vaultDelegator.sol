// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

interface IBalanceVerifier {
    function verifyProof(uint[8] calldata proof, uint[6] calldata input) external view;
}
interface IVariableVerifier {
    function verifyProof(uint[8] calldata proof, uint[7] calldata input) external view;
}
interface IValidatorVerifier {
    function verifyProof(uint[8] calldata proof, uint[7] calldata input) external view;
}

interface IQiaraVault {
    function directWithdraw(address user, string calldata assetName, uint256 amount, uint256 nullifier) external;
}

interface IVariables {
    function addPendingVariable(string calldata header, string calldata name, bytes calldata data) external;
    function getActiveVariable(string calldata header, string calldata name) external view returns (bytes memory);
}
interface IValidators{
    function addPendingAddress(address _user, bool isRemoval) external;
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

    function processZkWithdraw(uint[8] calldata proof, uint[6] calldata input,  bytes calldata _signatures) external {
        // 1. Verify ZK Proof
        balance_verifier.verifyProof(proof, input);

        (uint256 amount, address vaultAddr, string memory storageName) = _prepareWithdrawal(input);
        // 5. Replay Protection
        uint256 userL = input[2];
        uint256 userH = input[3];
        //revert("DEBUG_10000");
        uint256 nullifier = _calculateNullifier8(input);

        // --- DEBUG ABORT START ---
        // This will stop the transaction and show "DEBUG_100" in your stack trace
        //revert("DEBUG_100"); 
        // --- DEBUG ABORT END ---

        _verifyAllSignatures(bytes32(nullifier), _signatures);
        require(!usedNullifiers[nullifier], "Replay attack detected");
        usedNullifiers[nullifier] = true;
        //revert("DEBUG_10510");
        // 6. User Address Reconstruction
        address user = address(uint160((userH << 128) | userL));
        // revert("DEBUG_1051075");
        // 7. Final Call
        IQiaraVault(vaultAddr).directWithdraw(user, storageName, amount, nullifier);
    }
    function processZkVariable(uint[8] calldata proof, uint[7] calldata input, bytes calldata _signatures) external {
        // 1. Verify ZK Proof
       variable_verifier.verifyProof(proof, input);

        uint256 chainID = input[5];
        require(chainID == block.chainid, "Wrong destination chain");

        // 3. Convert Field Values to Strings
        string memory variableName = fieldToString(input[3]);
        string memory variableHeader = fieldToString(input[2]);
        bytes memory variableValue = fieldToBytes(input[4]);

        // 4. Replay Protection (Using SHA256)
        uint256 nullifier = _calculateNullifier7(input);
        _verifyAllSignatures(bytes32(nullifier), _signatures);
        require(!usedNullifiers[nullifier], "Replay attack detected");
        usedNullifiers[nullifier] = true;

        // 7. Final Call
        variablesRegistry.addPendingVariable(variableHeader, variableName, variableValue);
    }
   function processZkValidator(uint[8] calldata proof, uint[7] calldata input, bytes calldata _signatures) external {
        // 1. Verify ZK Proof
        validator_verifier.verifyProof(proof, input);

        // --- EXTRACTING IS_REMOVAL AND VALIDATOR ADDRESS ---
        // PackedContext is at index 2, contains (IsRemoval << 16) | Epoch [1]
        uint256 packedContext = input[2];
        // Extract IsRemoval: shift right by 16 bits and take the least significant bit
        bool isRemoval = (packedContext >> 16) & 1 == 1; 
        
        // ChainID is at index 4
        uint256 chainID = input[4];
        require(chainID == block.chainid, "Wrong destination chain");

        // Public inputs for the validator address and the associated data (if any)
        // Note: The actual validator pubkey is now reconstructed from indices 3, 4, 5, 6
        // The `input[5]` and `input[6]` are likely the XHigh/YHigh parts respectively.
        // Assuming you have a function in Go (or can recreate it in Solidity) to correctly reconstruct the public key from these parts
        // and then derive the address from it if needed for comparison.

        // If you need to use the *raw* 65-byte pubkey for comparison with stored validators,
        // you would need to reconstruct it here. For simplicity, we'll assume you are comparing addresses.
        // If your validator registry stores addresses, then deriving the address from the pubkey is correct.
        // If it stores the 65-byte pubkey, you'll need to reconstruct it and then potentially hash it to an address if that's what your registry uses.

        // Reconstruct the validator's address from its public key components if input[5] and input[6] represent its xHigh and yHigh respectively
        // This assumes the Go circuit's input packing: [Other inputs...], XLow(idx 3), XHigh(idx 4), YLow(idx 5), YHigh(idx 6)
        // In this function, input[5] and input[6] are the YLow and YHigh, so we need to adjust the logic if the public input indices differ.
        // Let's assume input indices for validator pubkey are correct as per your Go circuit:
        // input[3] -> ValidatorXLow
        // input[4] -> ValidatorXHigh
        // input[5] -> ValidatorYLow
        // input[6] -> ValidatorYHigh
        
        // Reconstruct the full 256-bit coordinates.
        uint256 x = (input[4] << 128) | input[3]; // xHigh << 128 | xLow
        uint256 y = (input[6] << 128) | input[5]; // yHigh << 128 | yLow

        // Hash the 64-byte coordinate concatenation (excluding the "04" prefix)
        // Then cast to uint160 to truncate to the last 20 bytes (Ethereum Address)
        address validatorAddress = address(uint160(uint256(keccak256(abi.encodePacked(x, y)))));


        // 4. Replay Protection
        // Nullifier calculation needs to be consistent with what was signed off-chain.
        // If signatures were made over the *7 inputs* and *not* the nullifier, use _calculateNullifier7.
        // If signatures were made over the *nullifier*, use _calculateNullifier7 for the message hash.
        uint256 nullifier = _calculateNullifier7(input); 
        _verifyAllSignatures(bytes32(nullifier), _signatures);
        require(!usedNullifiers[nullifier], "Replay attack detected");
        usedNullifiers[nullifier] = true;
        validatorsRegistry.addPendingAddress(validatorAddress, isRemoval);
    }

    // Dont hash the last pub signal, that contains the pubkey of the validator, which would result in all nulifiers being unique, leading to never reaching needed quarum
    function _calculateNullifier8(uint256[6] calldata input) internal pure returns (uint256) {
        // abi.encodePacked concatenates all values into a raw byte stream.
        // Hashing the entire array ensures that if ANY signal changes, the nullifier changes.
        bytes32 hash = keccak256(abi.encodePacked(
            input[0],
            input[1],
            input[2],
            input[3],
            input[4],
            input[5]
           // input[6]
           //input[7],
        ));

        return uint256(hash);
    }
    // Dont hash the last pub signal, that contains the pubkey of the validator, which would result in all nulifiers being unique, leading to never reaching needed quarum
    function _calculateNullifier7(uint256[7] calldata input) internal pure returns (uint256) {
        // abi.encodePacked concatenates all values into a raw byte stream.
        // Hashing the entire array ensures that if ANY signal changes, the nullifier changes.
        bytes32 hash = keccak256(abi.encodePacked(
            input[0],
            input[1],
            input[2],
            input[3],
            input[4],
            input[5],
            input[6]

            //_pubSignals[5],
        ));

        return uint256(hash);
    }



    function _prepareWithdrawal(uint[6] calldata input) internal view returns (uint256 amount, address vaultAddr, string memory storageName) {
        // 1. Unpack Signal 5 (PackedTxData)
        uint256 packed = input[5];
        
        // Amount: bits 0-63
        amount = uint256(uint64(packed)); 
        
        // ChainID: bits 64-95
        uint256 chainID = uint256(uint32(packed >> 64));
        require(chainID == block.chainid, "Wrong destination chain");
//revert("DEBUG_100") ;
        // StorageID: bits 128+ (Unpack first, then convert to string)
        uint256 storageID = packed >> 128;
        storageName = fieldToString(storageID);

        // 2. Handle Signal 6 (ProviderName)
        string memory providerName = fieldToString(input[4]);

        // 3. Registry Lookup Logic (As requested)
        //revert("DEBUG_123") ;
        string memory vaultKey = string(abi.encodePacked(providerName, "_vault"));
        //revert("DEBUG_111") ;
        bytes memory vaultBytes = variablesRegistry.getActiveVariable("QiaraBaseAssets", vaultKey);
        //revert("DEBUG_199") ;
        require(vaultBytes.length > 0, "Vault not authorized");
        //revert("DEBUG_1003") ;
        vaultAddr = address(uint160(bytes20(vaultBytes)));
       // revert("DEBUG_1004") ;
    }

    function _verifyAllSignatures(bytes32 _messageHash, bytes calldata _signatures) internal view {
        bytes32 ethHash = getEthSignedMessageHash(_messageHash);
        
        // 1. Fetch once to save gas and stack space
        address[] memory active_validators = validatorsRegistry.getActiveAddresses();
        for (uint256 i = 0; i < _signatures.length; i++) {
            bytes calldata signature = _signatures[i * 65 : (i + 1) * 65];
            //revert("DEBUG_110010");
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
            //revert("DEBUG_1010");
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


    function deriveAddressFromSplitPubKey(uint256 xLow, uint256 xHigh,uint256 yLow, uint256 yHigh) public pure returns (address) {
        // 1. Reconstruct the full 256-bit coordinates from the 128-bit limbs
        uint256 x = (xHigh << 128) | xLow;
        uint256 y = (yHigh << 128) | yLow;

        // 2. Hash the raw 64-byte coordinate concatenation (excluding the "04" prefix)
        // 3. Cast to uint160 to truncate to the last 20 bytes (Ethereum Address)
        return address(uint160(uint256(keccak256(abi.encodePacked(x, y)))));
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