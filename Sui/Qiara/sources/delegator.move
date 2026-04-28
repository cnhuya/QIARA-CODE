module Qiara::QiaraDelegatorV1 {
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::object::{Self, UID, ID};
    use sui::transfer;
    use sui::tx_context::TxContext;
    use sui::groth16;
    use std::type_name::{Self, TypeName};
    use sui::table::{Self, Table};
    use sui::event;
    use sui::bcs;
    use sui::ecdsa_k1;
    use std::string::{Self, String};
    use std::vector;
    use sui::dynamic_field as df;

    use Qiara::QiaraVariablesV1::{Self as vars};
    use Qiara::QiaraValidatorsV1::{Self as validators, ValidatorState}; 
    use Qiara::QiaraVerifierV1::{Self as zk};

    // Your VK here (keep as is for now)
    const FULL_VK: vector<u8> = x"93f766ffa82322942a5ba6b3b8e4979151f7943676e334a50e837a534a3ccaee710a8ad8d0e6a1b740f93081bfe236e65087312d72f697d71a8b16b1591faec343fd24c21401258d87d5883e5091956969071fbb6bebfa3bc3a774b65cbad1e1e0ff6751870ba514743846add81d7e112c4c07f6494b0e10aa1cbbcfea8501157a8f603b16ccd17d32acbe190f047430060583d34383ada38ae795836a2efcce8678fdacf0bb38deb344a7d2bb0e1fc97018e1777696cce1087b56901f10f9031dcdb7da6d4b3accb397d8c05b4664f6976cdc2db40e39a391d3050695a3e2e277004b3232006b45036682b50d336aba87317b5cdff96d3797d1cb3ca11858a0d4bc2ae17943768c77c43770adf4f673fd44905fae6ab936af136757f80e48043b6e5820287e0615dd5c38a9e8a94b8bb7f29737122211f8e33ad5aa07000000239abf9084b6714794e511f006d945bf914007e8450cbdb05e4bfd3e6d5efa1dcabbea3c1e0615a465324b49a840c01792fb846292905556a42490f53489110a6a0e283297c355a1ff8c5a2c161f298a83517b754d7a71a4917ec297696b7c09b3dededd0b1a5cf499141f3bee200a58b62af23f654ecf534890caec9d5a34cb63f2703a72bca22cc2f4380ad71487f5d3b98687905c9199d020f825244ac01f58a0790bf0364b33488a1acb9e037b4e66f0ed1fbbb750a417d9d154724e6430";
    
//old working vk key: e2f26dbea299f5223b646cb1fb33eadb059d9407559d7441dfd902e3a79a4d2dabb73dc17fbc13021e2471e0c08bd67d8401f52b73d6d07483794cad4778180e0c06f33bbc4c79a9cadef253a68084d382f17788f885c9afd176f7cb2f036789edf692d95cbdde46ddda5ef7d422436779445c5e66006a42761e1f12efde0018c212f3aeb785e49712e7a9353349aaf1255dfb31b7bf60723a480d9293938e199724fac10fb1354561ecc8dca62e7889bda784b877ca9893321e7c18995cb7135266e70432baad4c9ef17deba5fb5e6eae6e06b267f1fbdf4be51a3594608a8f0900000000000000bc362f16280ebe552bc8736dbb9968df088b173a674457b176b30aeff2e55412b96811007d17429f882eb7bb646e960e3dcc21fe0b5995a8601f02319dd880a85b6af5ed5970844f50ff7b0c7770ebf2f5f7ef2cff288d0ca2ecf6f91665020a8fd3a6d7ed4488fce0b4dd6ed3b76026fcfc465e1077d04375ab8b2fa685771cd1082965c6e5fc8caad4f12336c879e8feed5877c5c64b31021c48db7db087a0299d8d46213437398b504207a0d26b60f0752367d23f8ba51ac710e2a84fb800a8b1c575a42c791e07f55ed94d1478094b9524c9d54f1e7e8415249d49d0008190a816b4b52765e4f693c06829dd6e8b4b1db6a6fae7901e849e57a40373742755667da1acfeefef00f8d4c619b728f88df523270cf7c5759212275db61ce592

//000000000000000000000000000000000000000000000000000000401a3e35d2ef5c03cd2655d5084540579df2660649f7679361fb8dff1312c75f8c0000000093f766ffa82322942a5ba6b3b8e4979151f7943676e334a50e837a534a3ccaee710a8ad8d0e6a1b740f93081bfe236e65087312d72f697d71a8b16b1591faec343fd24c21401258d87d5883e5091956969071fbb6bebfa3bc3a774b65cbad1e1e0ff6751870ba514743846add81d7e112c4c07f6494b0e10aa1cbbcfea8501157a8f603b16ccd17d32acbe190f047430060583d34383ada38ae795836a2efcce8678fdacf0bb38deb344a7d2bb0e1fc97018e1777696cce1087b56901f10f9031dcdb7da6d4b3accb397d8c05b4664f6976cdc2db40e39a391d3050695a3e2e277004b3232006b45036682b50d336aba87317b5cdff96d3797d1cb3ca11858a02b43d51e86bc8973883bc88f520b098c02bb6fa0519546c950ec98a807f1b7fbc491a7dfd781f9ea22a3c7561756b474480d68c8edddee071cc52a55f8ffffff6b603a20a961cf3086afd1e01bfcbc6f2970fb1a277fe3bff4f46583783ece420b3c8c4c269e4c10422d0af00bffc3ae860dff2191409bd2d8bb04ae23621b8795f1d7cd683caa5e0073a5d3e9e0d6757cae848ab2858e5b6e813d68969483f64c212122f4e5a30b66ebe0c411dff5a749d50dc09ab130acb76f351362a5cb34
//e2f26dbea299f5223b646cb1fb33eadb059d9407559d7441dfd902e3a79a4d2dabb73dc17fbc13021e2471e0c08bd67d8401f52b73d6d07483794cad4778180e0c06f33bbc4c79a9cadef253a68084d382f17788f885c9afd176f7cb2f036789edf692d95cbdde46ddda5ef7d422436779445c5e66006a42761e1f12efde0018c212f3aeb785e49712e7a9353349aaf1255dfb31b7bf60723a480d9293938e199724fac10fb1354561ecc8dca62e7889bda784b877ca9893321e7c18995cb7135266e70432baad4c9ef17deba5fb5e6eae6e06b267f1fbdf4be51a3594608a8f0900000000000000bc362f16280ebe552bc8736dbb9968df088b173a674457b176b30aeff2e55412b96811007d17429f882eb7bb646e960e3dcc21fe0b5995a8601f02319dd880a85b6af5ed5970844f50ff7b0c7770ebf2f5f7ef2cff288d0ca2ecf6f91665020a8fd3a6d7ed4488fce0b4dd6ed3b76026fcfc465e1077d04375ab8b2fa685771cd1082965c6e5fc8caad4f12336c879e8feed5877c5c64b31021c48db7db087a0299d8d46213437398b504207a0d26b60f0752367d23f8ba51ac710e2a84fb800a8b1c575a42c791e07f55ed94d1478094b9524c9d54f1e7e8415249d49d0008190a816b4b52765e4f693c06829dd6e8b4b1db6a6fae7901e849e57a40373742755667da1acfeefef00f8d4c619b728f88df523270cf7c5759212275db61ce592
//93f766ffa82322942a5ba6b3b8e4979151f7943676e334a50e837a534a3ccaee710a8ad8d0e6a1b740f93081bfe236e65087312d72f697d71a8b16b1591faec343fd24c21401258d87d5883e5091956969071fbb6bebfa3bc3a774b65cbad1e1e0ff6751870ba514743846add81d7e112c4c07f6494b0e10aa1cbbcfea8501157a8f603b16ccd17d32acbe190f047430060583d34383ada38ae795836a2efcce8678fdacf0bb38deb344a7d2bb0e1fc97018e1777696cce1087b56901f10f9031dcdb7da6d4b3accb397d8c05b4664f6976cdc2db40e39a391d3050695a3e2e277004b3232006b45036682b50d336aba87317b5cdff96d3797d1cb3ca11858a0d4bc2ae17943768c77c43770adf4f673fd44905fae6ab936af136757f80e48043b6e5820287e0615dd5c38a9e8a94b8bb7f29737122211f8e33ad5aa070000006b603a20a961cf3086afd1e01bfcbc6f2970fb1a277fe3bff4f46583783ece420b3c8c4c269e4c10422d0af00bffc3ae860dff2191409bd2d8bb04ae23621b876a0e283297c355a1ff8c5a2c161f298a83517b754d7a71a4917ec297696b7c09b3dededd0b1a5cf499141f3bee200a58b62af23f654ecf534890caec9d5a34cb000000000000000000000000000000000000000000000000000000401a3e35d2ef5c03cd2655d5084540579df2660649f7679361fb8dff1312c75f8c00000000
//93f766ffa82322942a5ba6b3b8e4979151f7943676e334a50e837a534a3ccaee710a8ad8d0e6a1b740f93081bfe236e65087312d72f697d71a8b16b1591faec343fd24c21401258d87d5883e5091956969071fbb6bebfa3bc3a774b65cbad1e1e0ff6751870ba514743846add81d7e112c4c07f6494b0e10aa1cbbcfea8501157a8f603b16ccd17d32acbe190f047430060583d34383ada38ae795836a2efcce8678fdacf0bb38deb344a7d2bb0e1fc97018e1777696cce1087b56901f10f9031dcdb7da6d4b3accb397d8c05b4664f6976cdc2db40e39a391d3050695a3e2e277004b3232006b45036682b50d336aba87317b5cdff96d3797d1cb3ca11858a0d4bc2ae17943768c77c43770adf4f673fd44905fae6ab936af136757f80e48043b6e5820287e0615dd5c38a9e8a94b8bb7f29737122211f8e33ad5aa07000000239abf9084b6714794e511f006d945bf914007e8450cbdb05e4bfd3e6d5efa1dcabbea3c1e0615a465324b49a840c01792fb846292905556a42490f53489110a6a0e283297c355a1ff8c5a2c161f298a83517b754d7a71a4917ec297696b7c09b3dededd0b1a5cf499141f3bee200a58b62af23f654ecf534890caec9d5a34cb63f2703a72bca22cc2f4380ad71487f5d3b98687905c9199d020f825244ac01f58a0790bf0364b33488a1acb9e037b4e66f0ed1fbbb750a417d9d154724e6430  
    const EInvalidProof: u64 = 0;
    const EInvalidPublicInputs: u64 = 1;
    const ENullifierUsed: u64 = 2;
    const ENotAuthorized: u64 = 3;
    const EWrongProviderProvided: u64 = 4;
    const EProviderAlreadyExists: u64 = 5;
    const EUnsupportedProviderName: u64 = 6;
    const EInsufficientPermission: u64 = 7;
    const ENotSupported: u64 = 8;
    const EWrongChainId: u64 = 9;
    const EInvalidSignature: u64 = 10;
    const ENotValidator: u64 = 11;

    // Events
    public struct TokenListed has copy, drop {
        vault_id: ID,
        token_type: String,
        provider_name: String
    }

    public struct SupportedTokenKey has copy, drop, store {
        token_type: TypeName
    }

    public struct VaultInfo has store, copy, drop {
        addr: address,
        vault_id: ID,
        admin_cap_id: ID,
    }

    public struct AdminCap has key, store { 
        id: UID,
        vault_id: ID 
    }

    public struct Vault has key {
        id: UID,
        provider_name: String,
        addr: address,
    }

    public struct ReserveKey<phantom T> has copy, drop, store {}

    public struct Nullifiers has key, store {
        id: UID,
        table: table::Table<u256, bool>,
    }

    public struct ProviderManager has key {
        id: UID,
        vaults: Table<String, VaultInfo>
    }

    fun init(ctx: &mut TxContext) {
        let nullifiers = Nullifiers { id: object::new(ctx), table: table::new(ctx) };
        transfer::share_object(nullifiers);

        let manager = ProviderManager { id: object::new(ctx), vaults: table::new(ctx) };
        transfer::share_object(manager);
    }


    public entry fun create_vault(config: &mut ProviderManager, registry: &vars::Registry, provider_name: String, ctx: &mut TxContext) {
        
        let provider_interface_module_address = vars::get_variable_to_address(registry, string::utf8(b"QiaraSuiProviders"), provider_name);

        // Check if a provider already exists to prevent overwriting
        assert!(!table::contains(&config.vaults, provider_name), EProviderAlreadyExists);

        // 2. Create the Vault
        let vault_uid = object::new(ctx);
        let vault_id = object::uid_to_inner(&vault_uid);
        let vault = Vault {id: vault_uid, provider_name: provider_name, addr: provider_interface_module_address,};

        // 3. Create the AdminCap
        let cap_uid = object::new(ctx);
        let admin_cap_id = object::uid_to_inner(&cap_uid);
        let admin_cap = AdminCap { id: cap_uid,vault_id };

        // 4. Store the information in GlobalConfig
        let info = VaultInfo {
            addr: provider_interface_module_address,
            vault_id,
            admin_cap_id,};
        table::add(&mut config.vaults, provider_name, info);

        // 5. Transfer and Share
        transfer::public_transfer(admin_cap, provider_interface_module_address);
        transfer::share_object(vault);
    }

    /// Anyone can call this. It checks the governance-controlled registry 
    /// to see if the token is valid for this provider.
    public entry fun list_new_token<T>(vault: &mut Vault, registry: &vars::Registry) {
        let token_type = type_name::get<T>();
        
        // 1. Convert ASCII TypeName string to a UTF-8 String
        let ascii_type_name = type_name::into_string(token_type);
        let mut asset_key = string::from_ascii(ascii_type_name); 

        // 2. Now you can append UTF-8 strings
        string::append(&mut asset_key, string::utf8(b"_"));
        string::append(&mut asset_key, vault.provider_name);

        // 3. Query the registry
        // Note: I added 'registry' to the parameters as 'get_variable' likely needs the object
        let asset_bytes = vars::get_variable(registry, string::utf8(b"QiaraSuiAssets"), asset_key);
        // 4. In Move, variables usually return vector<u8>. 
        // If you're storing the type string in the registry, you verify it here.
        
        df::add(&mut vault.id, SupportedTokenKey { token_type }, true);

        event::emit(TokenListed {
            vault_id: object::id(vault),
            token_type: string::from_ascii(type_name::get_module(&type_name::get<T>())),
            provider_name: vault.provider_name,
        });

    }

    /// Adds funds to the vault. 
    /// If the token hasn't been deposited before, it initializes the reserve.
    public fun increase_reserve<T>(vault: &mut Vault, coin: Coin<T>) {
        let reserve_key = ReserveKey<T> {};
        let coin_balance = coin::into_balance(coin);

        if (!df::exists_(&vault.id, reserve_key)) {
            // Initialize the reserve field if it doesn't exist
            df::add(&mut vault.id, reserve_key, coin_balance);
        } else {
            // Borrow existing and join
            let reserve = df::borrow_mut<ReserveKey<T>, Balance<T>>(&mut vault.id, reserve_key);
            balance::join(reserve, coin_balance);
        }
    }

    /// Removes funds from the vault.
    /// Added an assertion to ensure the reserve actually exists and has enough funds.
    public fun decrease_reserve<T>(vault: &mut Vault, amount: u64): Balance<T> {
        let reserve_key = ReserveKey<T> {};
        
        // 1. Critical Check: Does the reserve even exist?
        // If we don't check this, df::borrow_mut will abort with code 1.
        assert!(df::exists_(&vault.id, reserve_key), ENotSupported);

        let reserve = df::borrow_mut<ReserveKey<T>, Balance<T>>(&mut vault.id, reserve_key);
        
        // 2. Critical Check: Is there enough in the reserve?
        // balance::split will abort automatically if amount > balance, 
        // but a custom error is clearer for debugging.
        assert!(balance::value(reserve) >= amount, EInsufficientPermission);

        balance::split(reserve, amount)
    }

    public fun grant_permission<T>(config: &ProviderManager, state: &ValidatorState, nullifiers: &mut Nullifiers, public_inputs: vector<u8>,proof_points: vector<u8>,signatures: vector<vector<u8>>): (address, u64, u256) {
        // 1. Verify the proof and extract values
        let (user, amount, vault_provider, nullifier) = zk::verify_balance(public_inputs, proof_points);

        // 2. Verify signatures from validators and ensure they are valid and from active validators
        verify_signatures(state, signatures, public_inputs);

        // 3. Check if nullifier has been used before to prevent double-withdrawals
        if(table::contains(&nullifiers.table, nullifier)) {
            abort ENullifierUsed;
        };  
        table::add(&mut nullifiers.table, nullifier, true);

        // 4. Safety check, if provider is supported
        assert!(table::contains(&config.vaults, vault_provider), EWrongProviderProvided);

        // 5. Return values 
        return (user, amount, nullifier)
    }


    public fun borrow_id(vault: &Vault): &UID {
        &vault.id
    }
    public fun borrow_id_mut(vault: &mut Vault): &mut UID {
        &mut vault.id
    }
    public fun is_token_supported<T>(vault: &Vault): bool {
        let token_type = type_name::get<T>();
        df::exists_(&vault.id, SupportedTokenKey { token_type })
    }

    fun verify_signatures(state: &ValidatorState, signatures: vector<vector<u8>>,inputs: vector<u8>) {
        let mut n = vector::length(&signatures);
        
        // This must match what Go signs - the public inputs
        // No longer a static string, but the actual inputs data
        let msg = inputs;
        
        let validator_pubkeys = validators::get_active_pubkeys(state);
        
        while (n > 0) {
            let i = n - 1;
            let recovered_key = ecdsa_k1::secp256k1_ecrecover(&signatures[i], &msg, 1);
            assert!(vector::contains(&validator_pubkeys, &recovered_key), ENotValidator);
            n = i;
        }
    }

    public fun is_nullifier_used(nullifiers: &Nullifiers, nullifier: u256): bool {
        table::contains(&nullifiers.table, nullifier)
    }


}