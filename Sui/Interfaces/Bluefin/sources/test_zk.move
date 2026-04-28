module 0x0::SignatureTester {
    use std::vector;
    use std::debug;
    use sui::ecdsa_k1;

    // Data from your Go logs
    const RAW_INPUTS: vector<u8> = x"7751b1419426e73e04eed985ff6401464c4e4933e12d3bba90f3a32ec77ada2ed74588d9a377c174565f37f426aa1d491a76b6582ae9efe9685b7c5bfe5e84009311a2cb4e72057f29a9edabd7d76f6300000000000000000000000000000000c1faaa92140000000000000000000000000000000000000000000000000000006e696665756c4200000000000000000000000000000000000000000000000000131a000000000000670000000100000043445355000000000000000000000000";
    const RAW_SIGNATURE: vector<u8> = x"fc4c58421dfc3c9281888cba72dc9179b3127039d04d0b0b91604607fc19dedc7eb2cb1f58cd4d43434b767f28877aca48cc56cb3fb02869e42b24e757fab1d500";
    const RAW_PUBKEY: vector<u8> = x"04437e14e19b814339b143d47d23ff2703cddd7624ee50ad5b40f032d511695b4a7d7833e780533ca86fb1edd4ced0a548b9e9f1cf1f2eecdb45cfa913e67f633f";

    #[test]
    public fun test_verify_sig() {
        // 1. Recover compressed key from signature (flag 1 = Keccak256)
        let recovered_compressed = ecdsa_k1::secp256k1_ecrecover(&RAW_SIGNATURE, &RAW_INPUTS, 0);
        
        debug::print(&std::string::utf8(b"--- Recovered Compressed (33 bytes) ---"));
        debug::print(&recovered_compressed);

        // 2. Decompress to get uncompressed (65 bytes, starts with 0x04)
        let recovered_uncompressed = ecdsa_k1::decompress_pubkey(&recovered_compressed);

        debug::print(&std::string::utf8(b"--- Recovered Uncompressed (65 bytes) ---"));
        debug::print(&recovered_uncompressed);

        debug::print(&std::string::utf8(b"--- Expected Pubkey (65 bytes) ---"));
        debug::print(&RAW_PUBKEY);

        // 3. Final Verification
        assert!(vector::length(&recovered_uncompressed) == 65, 8888);
        assert!(RAW_PUBKEY == recovered_uncompressed, 5474);
        
        debug::print(&std::string::utf8(b"SUCCESS: Signatures match perfectly!"));
    }
}