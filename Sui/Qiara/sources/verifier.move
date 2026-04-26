module Qiara::QiaraVerifierV1 {
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::TxContext;
    use sui::groth16;
    use std::bcs;
    use sui::table::{Self, Table};
    use std::string::{Self,String};
    use std::vector;
    use sui::table::length;

    use Qiara::QiaraExtractorV1::{Self as extractor};

    const BALANCE_FULL_VK: vector<u8> = x"93f766ffa82322942a5ba6b3b8e4979151f7943676e334a50e837a534a3ccaee710a8ad8d0e6a1b740f93081bfe236e65087312d72f697d71a8b16b1591faec343fd24c21401258d87d5883e5091956969071fbb6bebfa3bc3a774b65cbad1e1e0ff6751870ba514743846add81d7e112c4c07f6494b0e10aa1cbbcfea8501157a8f603b16ccd17d32acbe190f047430060583d34383ada38ae795836a2efcce8678fdacf0bb38deb344a7d2bb0e1fc97018e1777696cce1087b56901f10f9031dcdb7da6d4b3accb397d8c05b4664f6976cdc2db40e39a391d3050695a3e2e277004b3232006b45036682b50d336aba87317b5cdff96d3797d1cb3ca11858a0d4bc2ae17943768c77c43770adf4f673fd44905fae6ab936af136757f80e48043b6e5820287e0615dd5c38a9e8a94b8bb7f29737122211f8e33ad5aa07000000239abf9084b6714794e511f006d945bf914007e8450cbdb05e4bfd3e6d5efa1dcabbea3c1e0615a465324b49a840c01792fb846292905556a42490f53489110a6a0e283297c355a1ff8c5a2c161f298a83517b754d7a71a4917ec297696b7c09b3dededd0b1a5cf499141f3bee200a58b62af23f654ecf534890caec9d5a34cb63f2703a72bca22cc2f4380ad71487f5d3b98687905c9199d020f825244ac01f58a0790bf0364b33488a1acb9e037b4e66f0ed1fbbb750a417d9d154724e6430";
    const BALANCE_FULL_VK2: vector<u8> = x"93f766ffa82322942a5ba6b3b8e4979151f7943676e334a50e837a534a3ccaee710a8ad8d0e6a1b740f93081bfe236e65087312d72f697d71a8b16b1591faec343fd24c21401258d87d5883e5091956969071fbb6bebfa3bc3a774b65cbad1e1e0ff6751870ba514743846add81d7e112c4c07f6494b0e10aa1cbbcfea8501157a8f603b16ccd17d32acbe190f047430060583d34383ada38ae795836a2efcce8678fdacf0bb38deb344a7d2bb0e1fc97018e1777696cce1087b56901f10f9031dcdb7da6d4b3accb397d8c05b4664f6976cdc2db40e39a391d3050695a3e2e277004b3232006b45036682b50d336aba87317b5cdff96d3797d1cb3ca11858a0d4bc2ae17943768c77c43770adf4f673fd44905fae6ab936af136757f80e48043b6e5820287e0615dd5c38a9e8a94b8bb7f29737122211f8e33ad5aa070000006b603a20a961cf3086afd1e01bfcbc6f2970fb1a277fe3bff4f46583783ece420b3c8c4c269e4c10422d0af00bffc3ae860dff2191409bd2d8bb04ae23621b876a0e283297c355a1ff8c5a2c161f298a83517b754d7a71a4917ec297696b7c09b3dededd0b1a5cf499141f3bee200a58b62af23f654ecf534890caec9d5a34cb000000000000000000000000000000000000000000000000000000401a3e35d2ef5c03cd2655d5084540579df2660649f7679361fb8dff1312c75f8c00000000";

    const VALIDATOR_FULL_VK: vector<u8> = x"e1a190f6856cd4239599bdcdb671df2a85b557f31408fe033c4eafcb8ca39799c683486ec250e85444f759cb3f5dfaf4b84f9cd21a316f8328fee38815f40e14e5d2914054b11fdc6027a6e473a0a2f310afd79f8ae732bc556ede1d781c5012edf692d95cbdde46ddda5ef7d422436779445c5e66006a42761e1f12efde0018c212f3aeb785e49712e7a9353349aaf1255dfb31b7bf60723a480d9293938e198cbf86be44029f94fb2ce52dfb53b173f6648962e0d772a5127ecf22fd5c1d076300ba27a9ddc710a1e6ac80c9c348bf64ef4e7dd15a5db8fc234bf9ab7c97a30700000000000000b8f61c54dca2a2ad2e5f4e9c65a9ce21e7756004eaf24da36e8d96693bad3b1740d06ff52efa29cee61d8bb254fe499bf8b9dc25f06a891679022ffcd89890983cacdef5bfd116ba22acb8a21510fb2b9b5a827aa755df4ebb8c5e9103dc138523b6a62a21566488b4bcc1727d9770435a550fdf01d284b27f8513e831bf8ea4671fd308358298d59bc9c9e84b02e83601b1801c4a38f11c3651d6ec1874d21a83928fe5c661ca3319276a1fd0fcd0dfa253649a3b19d2d42fca611922fe6d25c3a4c6b9c5a9bd663f1a09767fa160c42556d26f6dd9b6151ce7934d70987726";
    const VARIABLE_FULL_VK: vector<u8> = x"e1a190f6856cd4239599bdcdb671df2a85b557f31408fe033c4eafcb8ca39799c683486ec250e85444f759cb3f5dfaf4b84f9cd21a316f8328fee38815f40e14e5d2914054b11fdc6027a6e473a0a2f310afd79f8ae732bc556ede1d781c5012edf692d95cbdde46ddda5ef7d422436779445c5e66006a42761e1f12efde0018c212f3aeb785e49712e7a9353349aaf1255dfb31b7bf60723a480d9293938e198cbf86be44029f94fb2ce52dfb53b173f6648962e0d772a5127ecf22fd5c1d076300ba27a9ddc710a1e6ac80c9c348bf64ef4e7dd15a5db8fc234bf9ab7c97a30700000000000000b8f61c54dca2a2ad2e5f4e9c65a9ce21e7756004eaf24da36e8d96693bad3b1740d06ff52efa29cee61d8bb254fe499bf8b9dc25f06a891679022ffcd89890983cacdef5bfd116ba22acb8a21510fb2b9b5a827aa755df4ebb8c5e9103dc138523b6a62a21566488b4bcc1727d9770435a550fdf01d284b27f8513e831bf8ea4671fd308358298d59bc9c9e84b02e83601b1801c4a38f11c3651d6ec1874d21a83928fe5c661ca3319276a1fd0fcd0dfa253649a3b19d2d42fca611922fe6d25c3a4c6b9c5a9bd663f1a09767fa160c42556d26f6dd9b6151ce7934d70987726";
 
    //const TEST_PROOF: vector<u8> = x"0d08da35bfcdc702211f9a34e4730bfc196d8b181322c71b3cc3de2d65700daa90a593fa4f47d51b2f4a8f3798175243a2a7583c48303a218a91173be77de512b17ce22ecc8b779fcb9b72cd8d9f8c5945b31d7cd0f88c6e9df01d4d2809201b6265afbc80ecf938f7e95e882e10b02a625fa22a36b0084adf1b2a3e3b41da2b";
    //const TEST_PUBLIC: vector<u8> = x"6e656b6f546172616951000000000000000000000000000000000000000000004e4f4954414c464e49000000000000000000000000000000000000000000000040787d0100000000000000000000000000000000000000000000000000000000a527bb3a13be8a321ce9568661b6c6177e5a79919def9f6b27cd50acc696e726dc8825d08edcb82c1936c4628476c06de6d157678b5d0f0197d008f67ec4cd0e5fb3c9dc251e18ec3bf08ffa0ae0115e0c91de15345b76a5d252166e3d69ea14";

    const EInvalidProof: u64 = 0;
    const EWrongChainId: u64 = 1;

    const SUI_CHAIN_ID: u64 = 103;

    public fun verify_balance(public_inputs: vector<u8>,proof_points: vector<u8>): (address, u64, String, u256) {
        let curve = groth16::bn254();
        assert!(vector::length(&VALIDATOR_FULL_VK) > 0, 100);
        assert!(vector::length(&BALANCE_FULL_VK2) > 0, 100);
        // 1. Verify the proof
        let curve = groth16::bn254();
        let pvk = groth16::prepare_verifying_key(&curve, &BALANCE_FULL_VK);
        let pvk2 = groth16::prepare_verifying_key(&curve, &BALANCE_FULL_VK2);
        let pi_struct = groth16::public_proof_inputs_from_bytes(public_inputs);
        let pp_struct = groth16::proof_points_from_bytes(proof_points);

        assert!(groth16::verify_groth16_proof(&curve, &pvk, &pi_struct, &pp_struct), 6666);
        assert!(groth16::verify_groth16_proof(&curve, &pvk2, &pi_struct, &pp_struct), 9999);

        // 2. Build Nullifier Logic
        let nullifier = extractor::build_nullifier(&public_inputs, string::utf8(b"zk"));

        // 3. Extract values
        let user = extractor::extract_user_address(&public_inputs);
        let amount = extractor::extract_amount(&public_inputs);
        let vault_provider = extractor::extract_provider(&public_inputs);

        // 4. Safety check, if the ID of the chain inside the proof matches SUI's chain ID
        let chain_id = extractor::extract_chain_id(&public_inputs);
        assert!(chain_id == SUI_CHAIN_ID, EWrongChainId);

        // 5. Return values for further processing
        return (user, amount, vault_provider, nullifier)
    }

    public entry fun verify_validator(public_inputs: vector<u8>,proof_points: vector<u8>) {
        let curve = groth16::bn254();
        
        assert!(vector::length(&VALIDATOR_FULL_VK) > 0, 100);
        
        let pvk = groth16::prepare_verifying_key(&curve, &VALIDATOR_FULL_VK);

        let public_inputs_struct = groth16::public_proof_inputs_from_bytes(public_inputs);
        let proof_points_struct = groth16::proof_points_from_bytes(proof_points);

        assert!(groth16::verify_groth16_proof(&curve, &pvk, &public_inputs_struct, &proof_points_struct), EInvalidProof);
    }


    public entry fun verify_variable(public_inputs: vector<u8>,proof_points: vector<u8>) {
        let curve = groth16::bn254();
        
        assert!(vector::length(&VARIABLE_FULL_VK) > 0, 100);
        
        let pvk = groth16::prepare_verifying_key(&curve, &VARIABLE_FULL_VK);

        let public_inputs_struct = groth16::public_proof_inputs_from_bytes(public_inputs);
        let proof_points_struct = groth16::proof_points_from_bytes(proof_points);

        assert!(groth16::verify_groth16_proof(&curve, &pvk, &public_inputs_struct, &proof_points_struct), EInvalidProof);
    }

}