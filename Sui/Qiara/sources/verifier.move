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

    use Qiara::QiaraExtractorV1::{Self as extractor, UnpackedTx};

    const BALANCE_RAW_VK: vector<u8> = x"752f86cd63db30f0ba3e5251c55f18bbc315e28d8670c0db987dad6e661e4921df931d770843eea0d327028fdfcad62f40c021bef3df750f3cce482c200ff022cca603212e8dc5df188234784bb4be7ce7a9b9e946310787d3d09c1dc119fb0a74136488ccf12fd4a7cbce2a592405db6b0f77d3ba9fd6221ec36f054d3a0430321924a1a001fe421ba3b3919f913790a36f27f20949c348db0d0ecbda664fa44b30f64baf95bdbe5fc9d24dea6f071f17ff6ea8f541e953249a4dc3ceeea008d83c8fa791f4ef5ff4c2c7607b931d05a8805d3311523a8864647813c75cfa0907000000000000002701f60be258dd23c437c1a32d57493443f65277a342bab73930bac91dde6c10a7e7c71c2837d469210fd4178d9a3b675b1bca19cb63c03bfbf3ed42cbf28b90df333ba7acfb3b9ad54df6932c13336156ebc5b35a57bea6b5132856cdcb280c8464b7c65dc5167e5e5e84e9e2ef235a8af8d0629b11a881b56a074da879c5804362f7428bb36efc656028ba5fb796c8aef30a7ec0c5ac8ca5409c467b976ba50000000000000000000000000000000000000000000000000000000000000040fe3a3ff592724ec0ca639c5fdfea83b83abffce2eecc358dd2186e141268ca9a";
    const VALIDATOR_RAW_VK: vector<u8> = x"2f9c0b4abc8cc3b18a24d7cc50838d36726a9bec4605fd3551450862835a0a108df67c8536306d5d47ad116b451ba088d36b75919539116dec140dc3602beb0a205e936cd378e14f30d290647c489336d8b2fe5850b5996a35ca66a40423e9a4cd0e0aec27e7a56e7efcd1f853e76ff066ad48b32570224cbeea7fbec0d2f405fa7a100645906434c25c250e1a53efb383ec428546fe15f84ff4f1ba20a2e22b71bbe3644b593deae4b23cace03f4dd20e19286c872cce8355661a4689b97622d8153921bb9682c5d7b4a70d767e8cd2d90ed57bf017061e4965f193ab58128a0600000000000000f69f23ed847e8092483ba07496215da2e7870fde79e2f2a211dd9286f259ad2c1c3a7790d390c3c76fba84dbe0552e8aa8edd7e515cacf74607893d14edd5e91000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000040d3a21acb1a1c730f7b2f455bb03c0bb0b916fa1f5eb66d61b5ea832e6fcab585";
    const VARIABLE_RAW_VK: vector<u8> = x"51ba86e7f7d457326a04d2738edeb2e92be266b88a8ca61f13b178c0b5298f0edc267fcf4b9a2d134e6adbef96b50a2feee6bf1da6e3eab000a16428507923022ba2a65e0bc9daf23166121d6f8e84c14616a7786c389f242b0325856afb340f37337b4cc63526e7fe9a3d78bd7d16b0af4c9d4140b37876c83167a2ebdb0a0e5b7094c6ae21e0bfd9006ab82375605bcf4864555f683d7fcb2566891f3715009e98e0363274ee8705edb7c607f20656e638da0c08867efefa208c15f384ef073e8ce2d55a7685864716ed91ed3442326840baf7585770170c6f9f33c855e81f0700000000000000f79adb4a94f4b623692f541f4ac1abe2eb11d30c0976f3a468994d51d3ece7a92eec6be204c02886cc70bab1c75324877e99ad68f9ba2e94502c9ecff12dee8c5808c3e95c0cbe36f01339c5ddd02b36b1a2434a6ef28968ed70f6f3f3b464aaaaa9ff1be0d320bab688e962dc96d56cf0dea3a50f306c39295dfcdbb47f360235145cd752b0c4890268c16e6ad5258842b1868188feeb9562656fa2c132f71c6688d932d28b87564c24f83b266351c72d6264c1e8e7fa281d989034e288c0a40000000000000000000000000000000000000000000000000000000000000040";

    const EInvalidProof: u64 = 0;
    const EWrongChainId: u64 = 1;

    const SUI_CHAIN_ID: u64 = 103;

    public fun verify_balance(public_inputs: vector<u8>, proof_points: vector<u8>): (address, u64, String, u256) {
        let curve = groth16::bn254();

        let pvk = groth16::prepare_verifying_key(&curve, &BALANCE_RAW_VK);
        let pi_struct = groth16::public_proof_inputs_from_bytes(public_inputs);
        let pp_struct = groth16::proof_points_from_bytes(proof_points);

        assert!(groth16::verify_groth16_proof(&curve, &pvk, &pi_struct, &pp_struct), 6666);

        // 2. Build Nullifier Logic
        let nullifier = extractor::build_nullifier(&public_inputs);

        // 3. Extract values
        let tx_data = extractor::extract_all_tx_data(&public_inputs);
        let user = extractor::extract_user_address(&public_inputs);
        
        // FIX: Use getter functions instead of .amount
        let amount = extractor::tx_amount(&tx_data);
        let vault_provider = extractor::extract_provider(&public_inputs);

        // 4. Safety check
        // FIX: Use getter functions instead of .chain_id
        let chain_id = extractor::tx_chain_id(&tx_data);
        assert!(chain_id == SUI_CHAIN_ID, EWrongChainId);

        // 5. Return values
        (user, amount, vault_provider, nullifier)
    }

    public entry fun verify_validator(public_inputs: vector<u8>,proof_points: vector<u8>) {
        let curve = groth16::bn254();

        let pvk = groth16::prepare_verifying_key(&curve, &VALIDATOR_RAW_VK);
        let pi_struct = groth16::public_proof_inputs_from_bytes(public_inputs);
        let pp_struct = groth16::proof_points_from_bytes(proof_points);

        assert!(groth16::verify_groth16_proof(&curve, &pvk, &pi_struct, &pp_struct), EInvalidProof);
    }


    public entry fun verify_variable(public_inputs: vector<u8>,proof_points: vector<u8>) {
        let curve = groth16::bn254();

        let pvk = groth16::prepare_verifying_key(&curve, &VARIABLE_RAW_VK);
        let pi_struct = groth16::public_proof_inputs_from_bytes(public_inputs);
        let pp_struct = groth16::proof_points_from_bytes(proof_points);

        assert!(groth16::verify_groth16_proof(&curve, &pvk, &pi_struct, &pp_struct), EInvalidProof);
    }

}