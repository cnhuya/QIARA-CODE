module Qiara::QiaraExtractorV1 {
    use std::vector;
    use std::string::{Self, String};
    use sui::hash;
    use sui::address;

    // --- Constants ---
    const E_INVALID_INPUT_LENGTH: u64 = 400;

    // Indices based on Go Circuit Public Inputs (Tx Balance Circuit)
    const INDEX_OLD_ROOT: u64 = 0;
    const INDEX_NEW_ROOT: u64 = 1;
    const INDEX_USER_L: u64   = 2;
    const INDEX_USER_H: u64   = 3;
    const INDEX_VAULT: u64    = 4;
    const INDEX_PACKED_TX: u64 = 5;

    // --- Return Structures ---

    public struct UnpackedTx has drop {
        chain_id: u64,
        amount: u64,
        nonce: u64,
        storage_id: u64
    }


    // --- Getters for UnpackedTx ---

    public fun tx_amount(self: &UnpackedTx): u64 {
        self.amount
    }

    public fun tx_chain_id(self: &UnpackedTx): u64 {
        self.chain_id
    }

    public fun tx_nonce(self: &UnpackedTx): u64 {
        self.nonce
    }

    public fun tx_storage_id(self: &UnpackedTx): u64 {
        self.storage_id
    }

    // --- Public Extraction API ---

    /// Extracts and reconstructs VariableHeader and VariableName as Strings.
    /// Requires at least 7 public inputs (224 bytes).
    public fun extract_variable_strings(inputs: &vector<u8>): (String, String, vector<u8>) {
        assert!(vector::length(inputs) >= 224, E_INVALID_INPUT_LENGTH);

        // 1. Extract and unpack VariableHeader (upper bits of index 2)
        let packed_context = bytes_to_u256(extract_chunk(inputs, 2));
        let variable_header = u256_to_string(packed_context >> 16);

        // 2. Reconstruct VariableName as a combined u256 and convert to String
        let name_low = bytes_to_u256(extract_chunk(inputs, 3));
        let name_high = bytes_to_u256(extract_chunk(inputs, 4));
        let name_u256 = (name_high << 128) | name_low;
        let variable_name = u256_to_string(name_u256);

        // 3. Reconstruct NewVariableData (Index 5 and 6)
        let data_low = bytes_to_u256(extract_chunk(inputs, 5));
        let data_high = bytes_to_u256(extract_chunk(inputs, 6));
        
        // Combined 32-byte payload reconstructed inline
        let mut variable_data = vector::empty<u8>();
        vector::append(&mut variable_data, u256_to_bytes_be_part(data_high, 16));
        vector::append(&mut variable_data, u256_to_bytes_be_part(data_low, 16));

        (variable_header, variable_name, variable_data)
    }

    /// Extract and reconstruct the 65-byte SEC1 uncompressed validator public key.
    /// Coordinates are at indices 3 (XLow), 4 (XHigh), 5 (YLow), and 6 (YHigh).
    /// Requires at least 7 public inputs (224 bytes).
    public fun extract_validator_pubkey(inputs: &vector<u8>): vector<u8> {
        assert!(vector::length(inputs) >= 224, E_INVALID_INPUT_LENGTH);

        let x_low  = bytes_to_u256(extract_chunk(inputs, 3));
        let x_high = bytes_to_u256(extract_chunk(inputs, 4));
        let y_low  = bytes_to_u256(extract_chunk(inputs, 5));
        let y_high = bytes_to_u256(extract_chunk(inputs, 6));

        let mut pubkey = vector::empty<u8>();
        
        // 1. Uncompressed SEC1 format prefix (0x04)
        vector::push_back(&mut pubkey, 0x04);

        // 2. Reconstruct X Coordinate (High 16 bytes then Low 16 bytes)
        vector::append(&mut pubkey, u256_to_bytes_be_part(x_high, 16));
        vector::append(&mut pubkey, u256_to_bytes_be_part(x_low, 16));

        // 3. Reconstruct Y Coordinate (High 16 bytes then Low 16 bytes)
        vector::append(&mut pubkey, u256_to_bytes_be_part(y_high, 16));
        vector::append(&mut pubkey, u256_to_bytes_be_part(y_low, 16));

        pubkey
    }

    /// Extracts the validator is_removal status from PackedContext (index 2).
    /// Returns true if it is a removal operation, and false if it is an addition.
    public fun extract_validator_is_removal(inputs: &vector<u8>): bool {
        assert!(vector::length(inputs) >= 224, E_INVALID_INPUT_LENGTH);

        // Extract PackedContext (index 2)
        let packed_context = bytes_to_u256(extract_chunk(inputs, 2));

        // Shift right by 16 bits and mask the LSB
        ((packed_context >> 16) & 1) == 1
    }

    /// Extracts and unpacks balance transaction data.
    /// Requires at least 6 public inputs (192 bytes).
    public fun extract_all_tx_data(inputs: &vector<u8>): UnpackedTx {
        assert!(vector::length(inputs) >= 192, E_INVALID_INPUT_LENGTH);
        let packed_bytes = extract_chunk(inputs, INDEX_PACKED_TX);
        unpack_slot(bytes_to_u256(packed_bytes))
    }

    /// Extracts and reconstructs user address.
    /// Requires at least 4 public inputs (128 bytes).
    public fun extract_user_address(inputs: &vector<u8>): address {
        assert!(vector::length(inputs) >= 128, E_INVALID_INPUT_LENGTH);
        let low_u256 = bytes_to_u256(extract_chunk(inputs, INDEX_USER_L));
        let high_u256 = bytes_to_u256(extract_chunk(inputs, INDEX_USER_H));
        reconstruct_address(high_u256, low_u256)
    }

    /// Extract VaultAddress (index 4) - often used as a token/contract ID.
    /// Requires at least 5 public inputs (160 bytes).
    public fun extract_provider(inputs: &vector<u8>): String {
        assert!(vector::length(inputs) >= 160, E_INVALID_INPUT_LENGTH);
        u256_to_string(bytes_to_u256(extract_chunk(inputs, INDEX_VAULT)))
    }

    public fun extract_old_root(inputs: &vector<u8>): u256 {
        assert!(vector::length(inputs) >= 32, E_INVALID_INPUT_LENGTH);
        bytes_to_u256(extract_chunk(inputs, INDEX_OLD_ROOT))
    }

    public fun extract_new_root(inputs: &vector<u8>): u256 {
        assert!(vector::length(inputs) >= 64, E_INVALID_INPUT_LENGTH);
        bytes_to_u256(extract_chunk(inputs, INDEX_NEW_ROOT))
    }

    /// Matches Solidity: keccak256(abi.encodePacked(input[0...5]))
    /// This takes the first 6 public signals, converts them to Big Endian (Solidity format),
    /// concatenates them, and hashes them using Keccak256.
    public fun build_nullifier(inputs: &vector<u8>): u256 {
        assert!(vector::length(inputs) >= 192, E_INVALID_INPUT_LENGTH);
        let mut data = vector::empty<u8>();
        
        let mut i = 0;
        // We iterate from index 0 to 5 (the first 6 signals)
        // This excludes index 6 (validator pubkey) to allow for quorum reaching
        while (i < 6) {
            // 1. Extract the 32-byte signal from the proof (Little Endian)
            let signal_le = extract_chunk(inputs, i);
            
            // 2. Convert to u256 then to Big Endian bytes 
            // (This replicates Solidity's uint256 memory layout)
            let val = bytes_to_u256(signal_le);
            let signal_be = u256_to_bytes_be(val);
            
            // 3. Append to the buffer (abi.encodePacked concatenation)
            vector::append(&mut data, signal_be);
            
            i = i + 1;
        };

        // 4. Compute Keccak256 (Standard Ethereum/Solidity hash)
        let hash_bytes = hash::keccak256(&data);

        // 5. Convert the 32-byte hash result back to a u256
        bytes_to_u256_be(hash_bytes)
    }

    // --- Internal Bit Shifting & Unpacking ---

    /// Matches Go: Amount(64) | ChainID(32) | Nonce(32) | StorageID(64+)
    fun unpack_slot(packed_data: u256): UnpackedTx {
        UnpackedTx {
            amount:     ((packed_data) & 0xFFFFFFFFFFFFFFFF) as u64,                // Bits 0-63
            chain_id:   ((packed_data >> 64) & 0xFFFFFFFF) as u64,                  // Bits 64-95
            nonce:      ((packed_data >> 96) & 0xFFFFFFFF) as u64,                  // Bits 96-127
            storage_id: ((packed_data >> 128) & 0xFFFFFFFFFFFFFFFF) as u64,         // Bits 128-191
        }
    }

    fun reconstruct_address(high: u256, low: u256): address {
        let mut addr_bytes = vector::empty<u8>();
        // high is bits 128-255, low is 0-127
        vector::append(&mut addr_bytes, u256_to_bytes_be_part(high, 16));
        vector::append(&mut addr_bytes, u256_to_bytes_be_part(low, 16));
        address::from_bytes(addr_bytes)
    }

    // --- Core Conversion Utilities ---

    /// Extracts a 32-byte chunk from the flattened inputs vector
    fun extract_chunk(inputs: &vector<u8>, index: u64): vector<u8> {
        let start = index * 32;
        let mut chunk = vector::empty<u8>();
        let mut i = 0;
        while (i < 32) {
            vector::push_back(&mut chunk, *vector::borrow(inputs, start + i));
            i = i + 1;
        };
        chunk
    }

    /// Converts Little Endian bytes (from Proof) to u256
    public fun bytes_to_u256(bytes: vector<u8>): u256 {
        let mut res: u256 = 0;
        let mut i = 32;
        while (i > 0) {
            i = i - 1;
            res = (res << 8) | (*vector::borrow(&bytes, i) as u256);
        };
        res
    }

    /// Converts u256 to Big Endian bytes (for Solidity Compatibility)
    fun u256_to_bytes_be(value: u256): vector<u8> {
        let mut bytes = vector::empty<u8>();
        let mut i = 0;
        while (i < 32) {
            let byte = ((value >> ((31 - i) * 8)) & 0xFF) as u8;
            vector::push_back(&mut bytes, byte);
            i = i + 1;
        };
        bytes
    }

    /// Converts Big Endian bytes (from Hash) back to u256
    fun bytes_to_u256_be(bytes: vector<u8>): u256 {
        let mut res: u256 = 0;
        let mut i = 0;
        while (i < 32) {
            res = (res << 8) | (*vector::borrow(&bytes, i) as u256);
            i = i + 1;
        };
        res
    }

    fun u256_to_bytes_be_part(value: u256, len: u64): vector<u8> {
        let mut bytes = vector::empty<u8>();
        let mut i = 0;
        while (i < len) {
            let byte = ((value >> (((len - 1 - i) * 8) as u8)) & 0xFF) as u8;
            vector::push_back(&mut bytes, byte);
            i = i + 1;
        };
        bytes
    }

    public fun u256_to_string(value: u256): String {
        let mut bytes = vector::empty<u8>();
        let mut temp = value;
        while (temp > 0) {
            let byte = (temp & 0xFF) as u8;
            if (byte != 0) { 
                vector::push_back(&mut bytes, byte); 
            };
            temp = temp >> 8;
        };
        vector::reverse(&mut bytes);
        string::utf8(bytes)
    }
}