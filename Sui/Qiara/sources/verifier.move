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

    const BALANCE_FULL_VK: vector<u8> = x"e1a190f6856cd4239599bdcdb671df2a85b557f31408fe033c4eafcb8ca39799c683486ec250e85444f759cb3f5dfaf4b84f9cd21a316f8328fee38815f40e14e5d2914054b11fdc6027a6e473a0a2f310afd79f8ae732bc556ede1d781c5012edf692d95cbdde46ddda5ef7d422436779445c5e66006a42761e1f12efde0018c212f3aeb785e49712e7a9353349aaf1255dfb31b7bf60723a480d9293938e198cbf86be44029f94fb2ce52dfb53b173f6648962e0d772a5127ecf22fd5c1d076300ba27a9ddc710a1e6ac80c9c348bf64ef4e7dd15a5db8fc234bf9ab7c97a30700000000000000b8f61c54dca2a2ad2e5f4e9c65a9ce21e7756004eaf24da36e8d96693bad3b1740d06ff52efa29cee61d8bb254fe499bf8b9dc25f06a891679022ffcd89890983cacdef5bfd116ba22acb8a21510fb2b9b5a827aa755df4ebb8c5e9103dc138523b6a62a21566488b4bcc1727d9770435a550fdf01d284b27f8513e831bf8ea4671fd308358298d59bc9c9e84b02e83601b1801c4a38f11c3651d6ec1874d21a83928fe5c661ca3319276a1fd0fcd0dfa253649a3b19d2d42fca611922fe6d25c3a4c6b9c5a9bd663f1a09767fa160c42556d26f6dd9b6151ce7934d70987726";
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
        // 1. Verify the proof
        let curve = groth16::bn254();
        let pvk = groth16::prepare_verifying_key(&curve, &BALANCE_FULL_VK);
        let pi_struct = groth16::public_proof_inputs_from_bytes(public_inputs);
        let pp_struct = groth16::proof_points_from_bytes(proof_points);

        assert!(groth16::verify_groth16_proof(&curve, &pvk, &pi_struct, &pp_struct), EInvalidProof);

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