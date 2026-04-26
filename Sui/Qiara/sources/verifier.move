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

    const BALANCE_VK_GAMMA_ABC_G1: vector<u8> = x"2ad53ae3f81122123797f2b78b4ba9e8a9385cdd15067e2820586e3b42ce3e7817322cafec6e6ab50971a3405d24c0218c34bac7d68c3098a02f5b05564b09320365f4f4bfe37f271afb70296fbcfc1be0d1af8630cf61a9203a606b871b622303a200293dda046e0c58b47e9f6a829e4ae1ae81c120d5bc1773d760668b57f62e04bbd8d29b409121ff0d86aec3ff0bf00a2d42104c9e264c8c3c0b097c6b691048cd6ad5b7549fda6c4bbf20e827b365288c43954c6014c248d8fa40d7c7f517c27e91a4717a4d757b51838a291f162c5a8cffa155c39732280e6acb345a9d03361f7d2f02a1a448d4370aa60d46b14d58993ee00ad5f18db0745fbfaf89e82cca904853cf4e653ff22ab6580a20ee3b1f1499f45c1a0bdddedeb3d2353e1a18decc191dce3f27fcad86d09ac47050dc583e3c7a0d4ae86b6849ddce7990de000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c5fc71213ff8dfb619367f7490666f29d57404508d55526cd035cefd7a497f907e68ccd70ee91aa4a100036a19944eb04d654e65d2a83e496dc70372b880818";
    const BALANCE_VK_ALPHA_BETA_G2: vector<u8> = x"2eca3c4a537a830ea534e3763694f7519197e4b8b3a65b2a942223a8ff66f7932bd19544c1ffcdc0d64ff4b989edbf567d1177ba5b60c03bfce962508e2b9b9f21d1ba5cb674a7c33bfaeb6bbb1f0769699591503e88d5878d250114c224fd43150185eacfbb1caa100e4b49f6074c2c117e1dd8ad46387414a50b875167ffe01ada10698a7940c98663db41db68531744f2267d0cf13c448aa2289733588fdc1c8c90c653a8a6b1c68d40e1ef06e65b2bb4d7ce9a739c08f4d074366673bb15";
    const BALANCE_VK_GAMMA_G2_NEG_PC: vector<u8> = x"0efc2e6a8395e78aa3ad8343d38305063074040f19beac327dd1cc163b608f7a03f9101f90567b08e1cc967677e11870c91f0ebbd2a744b3de38bbf0acfd7886041dc00ca96d0fd58ac3ddb242e13e829d30d73f8ef0de9cb115d2885b0e1f9a226ebad0e5dba64f7b7e548efa315aaa4ec3db0053cdec997599e7275d483060";
    const BALANCE_VK_DELTA_G2_NEG_PC: vector<u8> = x"205818a13ccbd197376df9df5c7b3187ba6a330db5826603456b0032324b007704480ef8576713af36b96aae5f9044fd73f6f4ad7037c4778c764379e12abcd429af77d88e394ae15342aae4d6557b1a68b6c8010073c28008fc12578a532f2e1f50ae538a90dab5325611e5768a7cccf28bb29129d4dbbd61da0139ee9598c0";

    const VALIDATOR_VK_GAMMA_ABC_G1: vector<u8> = x"00a509aed13d925f94102f63c365b02b86d6585d84ce579924775f086dc0323d12ed32cd2af1abf65efd91a4d6564258ff7ff948794d80f6ea40a22f9379c4351c730aeca16e6d191f50f440ea5a2946c178263aa0900f03be6d3360cb6fb72c27fd731788de375d25f2fbd58073dc13d824ce9ac5832aac67283a995a30f0e00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002b50e0fe4bf3f5f030637ce43bd901664bda681313677ca70b469a38b3ea9469169311c6878274f1aded2595c02790b8847aeaf7c1dcdc620ee71ad7fb43d7b5";
    const VALIDATOR_VK_ALPHA_BETA_G2: vector<u8> = x"0c38a5a6331af6508c2c605eb9883bd4ad895e7d8c9a6c23070ef6ae04933b021cbefb0235cfb3bda64ac4d16d0e372cc4348974c11b96b7a61b8ef7ba3539cc096e386a3cb297307695b7997ac539327e7e0adf37d8b9d3ac30f39cf8365048252ec5ef7eedb90449cf931bff9fb05e9dfba11709c774df7df8aee9493ed02615ec55177a9efe15c0a788288ee85a92127264cc63358928d95e41269ff5fda20fa67535011dc5e982a2d2101ac89721619c70a413c2a1b21c318eb1ff47c7f3";
    const VALIDATOR_VK_GAMMA_G2_NEG_PC: vector<u8> = x"30048128b51b2be040694d2c26740dc6561cbbb3da45f55ddcafe0acc699719d2da36ddf8f6b82b19ad1e6c7a137da3d7dab41becddb43af698b8533ebfab3970cec548663d0b16b39c73bf25641adb96a7e134a97adc503206d9dbfda93af440e1ac436d54f592cc60e77e2e777709a3cf981ce133afef4403c967c55838245";
    const VALIDATOR_VK_DELTA_G2_NEG_PC: vector<u8> = x"10481ad5b970ba768b0a6a20fdad85a49f78d1f650ae618718c75d026ca241e61e63545cbb6efeefda09620dab83bfb970dc335990740f7112291388cf32a319090a6fd4e1dfe76372ff7113393b0811ff2653fe08daba470858e8b21eabb30e2721f08c6d35190080f877e0369d48e9a21dd70829722da057283b71d8111073";

    const VARIABLE_VK_GAMMA_ABC_G1: vector<u8> = x"179b2fbf1a28f619aa72bb84436e93ecaaa52898ccafef1d8daef5cb26eb6150110643269e67af82f0c25f4dd72a1219775c153b5e398d34716e995ee32554791fbaa8301b9f06755e75b449ca20f19abe54162c5dd3d4d99094f107560f1c2d2c2ca18fbdb95c774f63ece1bf6043d09e0c3cbd99ec59b266b2b5960a5e6da10c6740abd3304ced6a9625969407ce297431833583adf15d736cfe60e3936cd917182807ecd8f4ff750f06036ce889125fb1137b4b31f8a21aa76e0a96afea611630b89f72a2dafe571ec4d957ba929eba0a44e6f08466d1115534d08f78901303dacc8b070d0ffd1929a042ae007aba3aa3e63af82f8bc25ef7e68d2aa7a15920c14cf01dd768f046205682e698dafb4f36dd8395666fc4201d3dfda85dcac9118f546474abe3055e1ec5f9d85931c1c67fafa41a1beb43b41218b74ec5557d0ea4f886dc2513233fd11eafaece4cae03923a3dff73bc096f25b392794e29ed0fc0819c2dc55796493ac624f297e1633835a1fba02008120b2b3ae17919dd4e00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
    const VARIABLE_VK_ALPHA_BETA_G2: vector<u8> = x"1407518acb9ae9934ea478537612de9de5bf6618f171cd7f341512baf95d66361967b04f136e423420b55de810094cbb541aebd0bcf8e922bdd1669542e66c1a1262e6b9c13870d969ccb3d16ce7691fec588f5abc01fe9d5a25f33cc08bf57f2eb08a269214f169236eacff5c6438788c9904a565ad9fe9adb2dec30887e25f20e08d28157703ba8ee50e5a3c1cd909d5c4f6314f627e421a2938e2e7f1fe4f1fa0b56b0f3eb8b4c84879ee8ba6f03321fbff58b80d4ede6e811f191518df8c";
    const VARIABLE_VK_GAMMA_G2_NEG_PC: vector<u8> = x"16a4bccbe5582edf4e1d0f198ea800d8071795c5b9b70914faf7a5492900f4a62ab67ef2fdf2db2c16a54df52814e3fea1fa56019780fc0ab2a2272673f13a4b126aeaeb36e6a82b973361854f48941ccd77b7703f410f40c58f834f1ec8bde61221dc382c6465396e966366a4cdefefdd550d447d2a95f267c45f50f0a158a3";
    const VARIABLE_VK_DELTA_G2_NEG_PC: vector<u8> = x"0a541cc7c908c1b021ade84ffa291d90159ab21558cd0a5fe031a0b30ab0b74608b0e3dee580ef6c807261a4ec2bb9492fe4b773558e358cccc86d3aba63d0af158278eb56e18bc9f43dfa3eec2be5a4eb778b1d002ff488de1525d2962a14f70c2934e838649305345dab4fd7a6823da8776f15b56eef71f1c9b06c4972a550";

    //const TEST_PROOF: vector<u8> = x"0d08da35bfcdc702211f9a34e4730bfc196d8b181322c71b3cc3de2d65700daa90a593fa4f47d51b2f4a8f3798175243a2a7583c48303a218a91173be77de512b17ce22ecc8b779fcb9b72cd8d9f8c5945b31d7cd0f88c6e9df01d4d2809201b6265afbc80ecf938f7e95e882e10b02a625fa22a36b0084adf1b2a3e3b41da2b";
    //const TEST_PUBLIC: vector<u8> = x"6e656b6f546172616951000000000000000000000000000000000000000000004e4f4954414c464e49000000000000000000000000000000000000000000000040787d0100000000000000000000000000000000000000000000000000000000a527bb3a13be8a321ce9568661b6c6177e5a79919def9f6b27cd50acc696e726dc8825d08edcb82c1936c4628476c06de6d157678b5d0f0197d008f67ec4cd0e5fb3c9dc251e18ec3bf08ffa0ae0115e0c91de15345b76a5d252166e3d69ea14";

    const EInvalidProof: u64 = 0;
    const EWrongChainId: u64 = 1;

    const SUI_CHAIN_ID: u64 = 103;

    public fun verify_balance(public_inputs: vector<u8>,proof_points: vector<u8>): (address, u64, String, u256) {
        let curve = groth16::bn254();
        // 1. Verify the proof
        let curve = groth16::bn254();
        let pvk = groth16::pvk_from_bytes(BALANCE_VK_GAMMA_ABC_G1, BALANCE_VK_ALPHA_BETA_G2, BALANCE_VK_GAMMA_G2_NEG_PC, BALANCE_VK_DELTA_G2_NEG_PC);
        let pi_struct = groth16::public_proof_inputs_from_bytes(public_inputs);
        let pp_struct = groth16::proof_points_from_bytes(proof_points);

        assert!(groth16::verify_groth16_proof(&curve, &pvk, &pi_struct, &pp_struct), 6666);

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
        
        let pvk = groth16::pvk_from_bytes(BALANCE_VK_GAMMA_ABC_G1, BALANCE_VK_ALPHA_BETA_G2, BALANCE_VK_GAMMA_G2_NEG_PC, BALANCE_VK_DELTA_G2_NEG_PC);

        let public_inputs_struct = groth16::public_proof_inputs_from_bytes(public_inputs);
        let proof_points_struct = groth16::proof_points_from_bytes(proof_points);

        assert!(groth16::verify_groth16_proof(&curve, &pvk, &public_inputs_struct, &proof_points_struct), EInvalidProof);
    }


    public entry fun verify_variable(public_inputs: vector<u8>,proof_points: vector<u8>) {
        let curve = groth16::bn254();
        
        let pvk = groth16::pvk_from_bytes(BALANCE_VK_GAMMA_ABC_G1, BALANCE_VK_ALPHA_BETA_G2, BALANCE_VK_GAMMA_G2_NEG_PC, BALANCE_VK_DELTA_G2_NEG_PC);

        let public_inputs_struct = groth16::public_proof_inputs_from_bytes(public_inputs);
        let proof_points_struct = groth16::proof_points_from_bytes(proof_points);

        assert!(groth16::verify_groth16_proof(&curve, &pvk, &public_inputs_struct, &proof_points_struct), EInvalidProof);
    }

}