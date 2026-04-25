module Qiara::QiaraExtractorV1 {
    use std::vector;
    use std::string::{Self, String};
    use std::hash; // Added for sha2_256
    use sui::address;
    use sui::bcs;

    // --- Constants ---
    const E_INVALID_CHAIN_ID: u64 = 0;
    const E_INVALID_INPUT_LENGTH: u64 = 400;
    const E_VALUE_OVERFLOW: u64 = 401;


    public struct UnpackedTx has drop {
        chain_id: u64,
        amount: u64,
        nonce: u64,
        storage_id: u64
    }

    // --- Public Extraction API ---

    public fun extract_chain_id(inputs: &vector<u8>): u64 {
        let packed_bytes = extract_chunk(inputs, 7);
        unpack_slot_8(bytes_to_u256(packed_bytes)).chain_id
    }

    public fun extract_amount(inputs: &vector<u8>): u64 {
        let packed_bytes = extract_chunk(inputs, 7);
        unpack_slot_8(bytes_to_u256(packed_bytes)).amount
    }

    public fun extract_nonce(inputs: &vector<u8>): u64 {
        let packed_bytes = extract_chunk(inputs, 7);
        unpack_slot_8(bytes_to_u256(packed_bytes)).nonce
    }

    public fun extract_user_address(inputs: &vector<u8>): address {
        let low_u256 = bytes_to_u256(extract_chunk(inputs, 3));
        let high_u256 = bytes_to_u256(extract_chunk(inputs, 4));
        reconstruct_address(high_u256, low_u256)
    }

    public fun extract_token(inputs: &vector<u8>): String {
        u256_to_string(bytes_to_u256(extract_chunk(inputs, 5)))
    }

    public fun extract_provider(inputs: &vector<u8>): String {
        u256_to_string(bytes_to_u256(extract_chunk(inputs, 6)))
    }

    /// Builds a Nullifier using SHA256(user_low, user_high, nonce)
    /// This matches Solidity's abi.encodePacked(a, b, c) -> sha256
    public fun build_nullifier(inputs: &vector<u8>, type_name: String): u256 {
        let user_l = bytes_to_u256(extract_chunk(inputs, 3));
        let user_h = bytes_to_u256(extract_chunk(inputs, 4));
        let nonce = (extract_nonce(inputs) as u256);

        // 1. Replicate Solidity bitwise logic: (userH << 128) | userL
        // This creates the single 32-byte "userBytes" word
        let user_bytes_combined = (user_h << 128) | user_l;

        let mut data = vector::empty<u8>();
        
        // 2. Append only TWO 32-byte words (64 bytes total)
        vector::append(&mut data, u256_to_bytes_be(user_bytes_combined));
        vector::append(&mut data, bcs::to_bytes(&type_name));
        vector::append(&mut data, u256_to_bytes_be(nonce));

        // 3. Compute SHA256
        let hash_bytes = hash::sha2_256(data);

        // 4. Convert back to u256
        bytes_to_u256_be(hash_bytes)
    }
    // --- Internal Bit Shifting & Unpacking ---

    fun unpack_slot_8(packed_data: u256): UnpackedTx {
        UnpackedTx {
            amount:     ((packed_data) & 0xFFFFFFFFFFFFFFFF) as u64,           // Bits 0-63
            chain_id:   ((packed_data >> 64) & 0xFFFFFFFF) as u64,             // Bits 64-95 (only 32 bits used)
            nonce:      ((packed_data >> 96) & 0xFFFFFFFFFFFFFFFF) as u64,     // Bits 96-127
            storage_id: ((packed_data >> 128) & 0xFFFFFFFFFFFFFFFF) as u64,    // Bits 128-191
        }
    }

    fun reconstruct_address(high: u256, low: u256): address {
        let mut addr_bytes = vector::empty<u8>();
        vector::append(&mut addr_bytes, u256_to_bytes_be_part(high, 16));
        vector::append(&mut addr_bytes, u256_to_bytes_be_part(low, 16));
        address::from_bytes(addr_bytes)
    }

    // --- Core Conversion Utilities ---

    fun extract_chunk(inputs: &vector<u8>, index: u64): vector<u8> {
        let start = index * 32;
        assert!(vector::length(inputs) >= start + 32, E_INVALID_INPUT_LENGTH);
        
        let mut chunk = vector::empty<u8>();
        let mut i = 0;
        while (i < 32) {
            vector::push_back(&mut chunk, *vector::borrow(inputs, start + i));
            i = i + 1;
        };
        chunk
    }

    /// Used for reading public signals (usually Little Endian from Circom)
    public fun bytes_to_u256(bytes: vector<u8>): u256 {
        let mut res: u256 = 0;
        let mut i = 32;
        while (i > 0) {
            i = i - 1;
            res = (res << 8) | (*vector::borrow(&bytes, i) as u256);
        };
        res
    }

    /// Converts u256 to Big Endian bytes to match Solidity's abi.encode encoding
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

    /// Converts Big Endian hash result back to u256
    fun bytes_to_u256_be(bytes: vector<u8>): u256 {
        let mut res: u256 = 0;
        let mut i = 0;
        while (i < 32) {
            res = (res << 8) | (*vector::borrow(&bytes, i) as u256);
            i = i + 1;
        };
        res
    }

    /// Helper for address reconstruction
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
        let mut i = 0;
        while (i < 32) {
            let byte = ((temp >> 248) & 0xFF) as u8;
            if (byte != 0) { 
                vector::push_back(&mut bytes, byte); 
            };
            temp = temp << 8;
            i = i + 1;
        };
        string::utf8(bytes)
    }
}