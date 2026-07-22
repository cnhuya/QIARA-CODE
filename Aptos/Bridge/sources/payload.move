module dev::QiaraPayloadV52

{
    use std::signer;
    use std::vector;
    use std::string::{Self as string, String, utf8};
    use std::table;
    use aptos_std::from_bcs;
    use std::hash;
    use std::bcs;
    use aptos_std::bcs_stream::{Self};
    use dev::QiaraChainTypesV50::{Self as ChainTypes};
    use dev::QiaraTokenTypesV50::{Self as TokenTypes};
    use event::QiaraEventV1::{Self as Event};

    use dev::QiaraNonceV2::{Self as Nonce, Access as NonceAccess};
    use dev::QiaraOmniNonceV2::{Self as OmniNonce, Access as OmniNonceAccess};
    //use dev::QiaraIdentifierV1::{Self as identifier};

    const ERROR_PAYLOAD_LENGTH_MISMATCH_WITH_TYPES: u64 = 0;
    const ERROR_PAYLOAD_MISS_CHAIN: u64 = 1;
    const ERROR_PAYLOAD_MISS_TYPE: u64 = 2;
    const ERROR_PAYLOAD_MISS_HASH: u64 = 3;
    const ERROR_PAYLOAD_MISS_TIME: u64 = 4;
    const ERROR_TYPE_NOT_FOUND: u64 = 5;
    const ERROR_PAYLOAD_MISS_CONSENSUS_TYPE: u64 = 6;

    // ----------------------------------------------------------------
    // Module init
    // ----------------------------------------------------------------
    fun init_module(admin: &signer) {
        assert!(signer::address_of(admin) == @dev, 1);

        if (!exists<Permissions>(@dev)) {
            move_to(admin, Permissions {nonce: Nonce::give_access(admin), omni_nonce: OmniNonce::give_access(admin)});
        };

    }


    struct Permissions has key, store, drop {
        nonce: NonceAccess,
        omni_nonce: OmniNonceAccess,
    }


    fun tttta(error: u64){
        abort error
    }

public fun ensure_valid_payload(type_names: vector<String>, payload: vector<vector<u8>>) {
    let len = vector::length(&type_names);
    let payload_len = vector::length(&payload);
    assert!(len == payload_len, ERROR_PAYLOAD_LENGTH_MISMATCH_WITH_TYPES);
    assert!(vector::contains(&type_names, &string::utf8(b"time")), ERROR_PAYLOAD_MISS_TIME);
    assert!(vector::contains(&type_names, &string::utf8(b"consensus_type")), ERROR_PAYLOAD_MISS_CONSENSUS_TYPE);

    let (_, chain_bytes) = find_payload_value(string::utf8(b"chain"), type_names, payload);
    
    let chain_name = bcs_stream::deserialize_string(&mut bcs_stream::new(chain_bytes));
    ChainTypes::ensure_valid_chain_name(chain_name);
    if (vector::contains(&type_names, &string::utf8(b"token"))) {
        let (_, token_bytes) = find_payload_value(string::utf8(b"token"), type_names, payload);
        
        let token_name = bcs_stream::deserialize_string(&mut bcs_stream::new(token_bytes));
        TokenTypes::ensure_valid_token_nick_name(token_name);
    }
}

    public fun create_omnichain_identifier(type_names: vector<String>, payload: vector<vector<u8>>): vector<u8>{
        let (_, addedValidator) = find_payload_value(utf8(b"added_validator"), type_names, payload);
        let (_, removedValidator) = find_payload_value(utf8(b"removed_validator"), type_names, payload);
        let (_, nonce) = find_payload_value(utf8(b"nonce"), type_names, payload);
       // Nonce::increment_nonce(addr_bytes, consensus, Nonce::give_permission(&borrow_global<Permissions>(@dev).nonce));

        Event::create_omnichain_identifier(addedValidator, removedValidator, nonce)

    }

    public fun create_omnichain_identifier_variables(type_names: vector<String>, payload: vector<vector<u8>>): vector<u8>{
        let (_, addedValidator) = find_payload_value(utf8(b"header"), type_names, payload);
        let (_, removedValidator) = find_payload_value(utf8(b"constant"), type_names, payload);
        let (_, nonce) = find_payload_value(utf8(b"nonce"), type_names, payload);
       // Nonce::increment_nonce(addr_bytes, consensus, Nonce::give_permission(&borrow_global<Permissions>(@dev).nonce));

        Event::create_omnichain_identifier2(addedValidator, removedValidator, nonce)

    }

    public fun create_identifier(type_names: vector<String>, payload: vector<vector<u8>>): vector<u8>{
        let (_, addr) = find_payload_value(utf8(b"addr"), type_names, payload);
        let (_, nonce) = find_payload_value(utf8(b"nonce"), type_names, payload);
        let (_, consensus_type) = find_payload_value(utf8(b"consensus_type"), type_names, payload);
        let addr_stream = &mut bcs_stream::new(addr);
        let addr_bytes = bcs_stream::deserialize_vector(addr_stream, |s| bcs_stream::deserialize_u8(s));
        let consensus = bcs_stream::deserialize_string(&mut bcs_stream::new(consensus_type));
       // Nonce::increment_nonce(addr_bytes, re, Nonce::give_permission(&borrow_global<Permissions>(@dev).nonce));

        Event::create_identifier(addr, consensus, nonce)

    }

    public fun find_payload_value(value: String, vect: vector<String>, from: vector<vector<u8>>): (String, vector<u8>){
        let (isFound, index) = vector::index_of(&vect, &value);
        assert!(isFound, ERROR_TYPE_NOT_FOUND);
        return (value, *vector::borrow(&from, index))
    }

   public fun prepare_omnichain_event(type_names: vector<String>, payload: vector<vector<u8>>) acquires Permissions  {
        let (_, type_raw) = find_payload_value(utf8(b"fun_type"), type_names, payload);
        let type = bcs_stream::deserialize_string(&mut bcs_stream::new(type_raw));
        OmniNonce::increment_nonce(type, OmniNonce::give_permission(&borrow_global<Permissions>(@dev).omni_nonce));
    }
       
    public fun prepare_bridge_deposit(type_names: vector<String>, payload: vector<vector<u8>>): (vector<u8>, vector<u8>, String, String, String, String, u64, u64, u64, String)  acquires Permissions  {
        
        // 1. Extract raw byte chunks
        let (_, addr_raw) = find_payload_value(utf8(b"addr"), type_names, payload);
        let (_, shared_raw) = find_payload_value(utf8(b"shared"), type_names, payload);
        let (_, token_raw) = find_payload_value(utf8(b"token"), type_names, payload);
        let (_, chain_raw) = find_payload_value(utf8(b"chain"), type_names, payload);
        let (_, provider_raw) = find_payload_value(utf8(b"provider"), type_names, payload);
        let (_, amount_raw) = find_payload_value(utf8(b"amount"), type_names, payload);
        let (_, hash_raw) = find_payload_value(utf8(b"hash"), type_names, payload);
        let (_, rate_raw) = find_payload_value(utf8(b"rate"), type_names, payload);
        let (_, rewards_raw) = find_payload_value(utf8(b"rewards"), type_names, payload);

        // 2. Decode using bcs_stream

        let (_, addr_raw) = find_payload_value(utf8(b"addr"), type_names, payload);
        let addr_stream = &mut bcs_stream::new(addr_raw);
        let addr_bytes = bcs_stream::deserialize_vector(addr_stream, |s| bcs_stream::deserialize_u8(s));
        
        let a = addr_bytes;
        let x = addr_bytes;

        // Extract Strings
        let k = bcs_stream::deserialize_string(&mut bcs_stream::new(shared_raw));
        let b = bcs_stream::deserialize_string(&mut bcs_stream::new(token_raw));
        let c = bcs_stream::deserialize_string(&mut bcs_stream::new(chain_raw));
        let d = bcs_stream::deserialize_string(&mut bcs_stream::new(provider_raw));
        let f = bcs_stream::deserialize_string(&mut bcs_stream::new(hash_raw));
        let y = bcs_stream::deserialize_u64(&mut bcs_stream::new(rate_raw));
        let u = bcs_stream::deserialize_u64(&mut bcs_stream::new(rewards_raw));

        // Extract U64
        let e = bcs_stream::deserialize_u64(&mut bcs_stream::new(amount_raw));
        let (_, consensus_type) = find_payload_value(utf8(b"consensus_type"), type_names, payload);
        let consensus = bcs_stream::deserialize_string(&mut bcs_stream::new(consensus_type));
        Nonce::increment_nonce(addr_bytes, consensus, Nonce::give_permission(&borrow_global<Permissions>(@dev).nonce));
        return (a, x, k, b, c, d, e, y, u, f)
    }

    public fun prepare_modular_storage_creation(type_names: vector<String>, payload: vector<vector<u8>>): (String, vector<u8>, String, String, String, u64,u64,)  acquires Permissions {
        let (_, name_raw) = find_payload_value(utf8(b"shared"), type_names, payload);
        let (_, user_raw) = find_payload_value(utf8(b"addr"), type_names, payload);
        let (_, ref_code_raw) = find_payload_value(utf8(b"ref_code"), type_names, payload);
        let (_, used_ref_code_raw) = find_payload_value(utf8(b"used_ref_code"), type_names, payload);
        let (_, selected_validator_raw) = find_payload_value(utf8(b"selected_validator"), type_names, payload);
        let (_, xp_tax_raw) = find_payload_value(utf8(b"xp_tax"), type_names, payload);
        let (_, fee_tax_raw) = find_payload_value(utf8(b"fee_tax"), type_names, payload);

        let user_stream = &mut bcs_stream::new(user_raw);
        let user_bytes = bcs_stream::deserialize_vector(user_stream, |s| bcs_stream::deserialize_u8(s));
        let ref_code = bcs_stream::deserialize_string(&mut bcs_stream::new(ref_code_raw));
        let used_ref_code = bcs_stream::deserialize_string(&mut bcs_stream::new(used_ref_code_raw));
        let selected_validator = bcs_stream::deserialize_string(&mut bcs_stream::new(selected_validator_raw));
        let xp_tax = bcs_stream::deserialize_u64(&mut bcs_stream::new(xp_tax_raw));
        let fee_tax = bcs_stream::deserialize_u64(&mut bcs_stream::new(fee_tax_raw));

        let name = bcs_stream::deserialize_string(&mut bcs_stream::new(name_raw));
        let (_, consensus_type) = find_payload_value(utf8(b"consensus_type"), type_names, payload);
        let consensus = bcs_stream::deserialize_string(&mut bcs_stream::new(consensus_type));
        Nonce::increment_nonce(user_bytes, consensus, Nonce::give_permission(&borrow_global<Permissions>(@dev).nonce));
        return (name, user_bytes, ref_code, used_ref_code, selected_validator, xp_tax, fee_tax)
    }

    public fun prepare_p_allow_sub_owner(type_names: vector<String>, payload: vector<vector<u8>>): (String, vector<u8>,vector<u8>)  acquires Permissions {
        let (_, name_raw) = find_payload_value(utf8(b"shared"), type_names, payload);
        let (_, user_raw) = find_payload_value(utf8(b"addr"), type_names, payload);
        let (_, sub_owner_raw) = find_payload_value(utf8(b"sub_owner"), type_names, payload);

        let user_stream = &mut bcs_stream::new(user_raw);
        let user_bytes = bcs_stream::deserialize_vector(user_stream, |s| bcs_stream::deserialize_u8(s));

        let sub_owner_stream = &mut bcs_stream::new(sub_owner_raw);
        let sub_owner_bytes = bcs_stream::deserialize_vector(sub_owner_stream, |s| bcs_stream::deserialize_u8(s));

        let name = bcs_stream::deserialize_string(&mut bcs_stream::new(name_raw));
        let (_, consensus_type) = find_payload_value(utf8(b"consensus_type"), type_names, payload);
        let consensus = bcs_stream::deserialize_string(&mut bcs_stream::new(consensus_type));
        Nonce::increment_nonce(user_bytes, consensus, Nonce::give_permission(&borrow_global<Permissions>(@dev).nonce));
        return (name, user_bytes, sub_owner_bytes)
    }

    public fun prepare_p_remove_sub_owner(type_names: vector<String>, payload: vector<vector<u8>>): (String, vector<u8>,vector<u8> )  acquires Permissions {
        let (_, name_raw) = find_payload_value(utf8(b"shared"), type_names, payload); 
        let (_, user_raw) = find_payload_value(utf8(b"addr"), type_names, payload);
        let (_, sub_owner_raw) = find_payload_value(utf8(b"sub_owner"), type_names, payload);

        let user_stream = &mut bcs_stream::new(user_raw);
        let user_bytes = bcs_stream::deserialize_vector(user_stream, |s| bcs_stream::deserialize_u8(s));

        let sub_owner_stream = &mut bcs_stream::new(sub_owner_raw);
        let sub_owner_bytes = bcs_stream::deserialize_vector(sub_owner_stream, |s| bcs_stream::deserialize_u8(s));
        let (_, consensus_type) = find_payload_value(utf8(b"consensus_type"), type_names, payload);
        let consensus = bcs_stream::deserialize_string(&mut bcs_stream::new(consensus_type));
        Nonce::increment_nonce(user_bytes, consensus, Nonce::give_permission(&borrow_global<Permissions>(@dev).nonce));
        let name = bcs_stream::deserialize_string(&mut bcs_stream::new(name_raw));

        return (name, user_bytes, sub_owner_bytes)
    }

    public fun prepare_p_change_used_ref_code(type_names: vector<String>, payload: vector<vector<u8>>): (String, vector<u8>, String )  acquires Permissions {
        let (_, name_raw) = find_payload_value(utf8(b"shared"), type_names, payload); 
        let (_, user_raw) = find_payload_value(utf8(b"addr"), type_names, payload);
        let (_, new_used_ref_code_raw) = find_payload_value(utf8(b"ref_code"), type_names, payload);

        let user_stream = &mut bcs_stream::new(user_raw);
        let user_bytes = bcs_stream::deserialize_vector(user_stream, |s| bcs_stream::deserialize_u8(s));

        let new_used_ref_code = bcs_stream::deserialize_string(&mut bcs_stream::new(new_used_ref_code_raw));
        let (_, consensus_type) = find_payload_value(utf8(b"consensus_type"), type_names, payload);
        let consensus = bcs_stream::deserialize_string(&mut bcs_stream::new(consensus_type));
        Nonce::increment_nonce(user_bytes, consensus, Nonce::give_permission(&borrow_global<Permissions>(@dev).nonce));
        let name = bcs_stream::deserialize_string(&mut bcs_stream::new(name_raw));

        return (name, user_bytes, new_used_ref_code)
    }

public fun prepare_p_accrue_interest(type_names: vector<String>, payload: vector<vector<u8>>): (vector<u8>, String, String) acquires Permissions {
        let (_, user_raw) = find_payload_value(utf8(b"addr"), type_names, payload);
        let (_, shared_raw) = find_payload_value(utf8(b"shared"), type_names, payload);
        let (_, asset_raw) = find_payload_value(utf8(b"asset"), type_names, payload);

        let user_stream = &mut bcs_stream::new(user_raw);
        let user_bytes = bcs_stream::deserialize_vector(user_stream, |s| bcs_stream::deserialize_u8(s));
        let shared = bcs_stream::deserialize_string(&mut bcs_stream::new(shared_raw));
        let asset = bcs_stream::deserialize_string(&mut bcs_stream::new(asset_raw));

        let (_, consensus_type) = find_payload_value(utf8(b"consensus_type"), type_names, payload);
        let consensus = bcs_stream::deserialize_string(&mut bcs_stream::new(consensus_type));
        Nonce::increment_nonce(user_bytes, consensus, Nonce::give_permission(&borrow_global<Permissions>(@dev).nonce));

        return (user_bytes, shared, asset)
    }

    public fun prepare_p_trade(type_names: vector<String>, payload: vector<vector<u8>>): (vector<u8>, String, String, u64, u64, bool, String, String, String) acquires Permissions {
        let (_, user_raw) = find_payload_value(utf8(b"addr"), type_names, payload);
        let (_, shared_raw) = find_payload_value(utf8(b"shared"), type_names, payload);
        let (_, asset_raw) = find_payload_value(utf8(b"asset"), type_names, payload);
        let (_, size_raw) = find_payload_value(utf8(b"size"), type_names, payload);
        let (_, leverage_raw) = find_payload_value(utf8(b"leverage"), type_names, payload);
        let (_, is_long_raw) = find_payload_value(utf8(b"is_long"), type_names, payload);
        let (_, reserve_chain_raw) = find_payload_value(utf8(b"reserve_chain"), type_names, payload);
        let (_, reserve_provider_raw) = find_payload_value(utf8(b"reserve_provider"), type_names, payload);
        let (_, reserve_token_raw) = find_payload_value(utf8(b"reserve_token"), type_names, payload);

        let user_stream = &mut bcs_stream::new(user_raw);
        let user_bytes = bcs_stream::deserialize_vector(user_stream, |s| bcs_stream::deserialize_u8(s));
        let shared = bcs_stream::deserialize_string(&mut bcs_stream::new(shared_raw));
        let asset = bcs_stream::deserialize_string(&mut bcs_stream::new(asset_raw));
        let size = bcs_stream::deserialize_u64(&mut bcs_stream::new(size_raw));
        let leverage = bcs_stream::deserialize_u64(&mut bcs_stream::new(leverage_raw));
        let is_long = bcs_stream::deserialize_bool(&mut bcs_stream::new(is_long_raw));
        let reserve_chain = bcs_stream::deserialize_string(&mut bcs_stream::new(reserve_chain_raw));
        let reserve_provider = bcs_stream::deserialize_string(&mut bcs_stream::new(reserve_provider_raw));
        let reserve_token = bcs_stream::deserialize_string(&mut bcs_stream::new(reserve_token_raw));

        let (_, consensus_type) = find_payload_value(utf8(b"consensus_type"), type_names, payload);
        let consensus = bcs_stream::deserialize_string(&mut bcs_stream::new(consensus_type));
        Nonce::increment_nonce(user_bytes, consensus, Nonce::give_permission(&borrow_global<Permissions>(@dev).nonce));

        return (user_bytes, shared, asset, size, leverage, is_long, reserve_chain, reserve_provider, reserve_token)
    }

    public fun prepare_p_update_oracle_and_trade(type_names: vector<String>, payload: vector<vector<u8>>): (vector<u8>, String, String, u64, u64, bool, String, String, String, vector<vector<u8>>) acquires Permissions {
        let (_, user_raw) = find_payload_value(utf8(b"addr"), type_names, payload);
        let (_, shared_raw) = find_payload_value(utf8(b"shared"), type_names, payload);
        let (_, asset_raw) = find_payload_value(utf8(b"asset"), type_names, payload);
        let (_, size_raw) = find_payload_value(utf8(b"size"), type_names, payload);
        let (_, leverage_raw) = find_payload_value(utf8(b"leverage"), type_names, payload);
        let (_, is_long_raw) = find_payload_value(utf8(b"isLong"), type_names, payload);
        let (_, reserve_chain_raw) = find_payload_value(utf8(b"reserve_chain"), type_names, payload);
        let (_, reserve_provider_raw) = find_payload_value(utf8(b"reserve_provider"), type_names, payload);
        let (_, reserve_token_raw) = find_payload_value(utf8(b"reserve_token"), type_names, payload);
        let (_, price_update_raw) = find_payload_value(utf8(b"price_update_data"), type_names, payload);

        let user_stream = &mut bcs_stream::new(user_raw);
        let user_bytes = bcs_stream::deserialize_vector(user_stream, |s| bcs_stream::deserialize_u8(s));
        let shared = bcs_stream::deserialize_string(&mut bcs_stream::new(shared_raw));
        let asset = bcs_stream::deserialize_string(&mut bcs_stream::new(asset_raw));
        let size = bcs_stream::deserialize_u64(&mut bcs_stream::new(size_raw));
        let leverage = bcs_stream::deserialize_u64(&mut bcs_stream::new(leverage_raw));
        let is_long = bcs_stream::deserialize_bool(&mut bcs_stream::new(is_long_raw));
        let reserve_chain = bcs_stream::deserialize_string(&mut bcs_stream::new(reserve_chain_raw));
        let reserve_provider = bcs_stream::deserialize_string(&mut bcs_stream::new(reserve_provider_raw));
        let reserve_token = bcs_stream::deserialize_string(&mut bcs_stream::new(reserve_token_raw));

        let price_update_stream = &mut bcs_stream::new(price_update_raw);
        let price_update_data = bcs_stream::deserialize_vector(price_update_stream, |s| {
            bcs_stream::deserialize_vector(s, |inner_s| bcs_stream::deserialize_u8(inner_s))
        });

        let (_, consensus_type) = find_payload_value(utf8(b"consensus_type"), type_names, payload);
        let consensus = bcs_stream::deserialize_string(&mut bcs_stream::new(consensus_type));
        Nonce::increment_nonce(user_bytes, consensus, Nonce::give_permission(&borrow_global<Permissions>(@dev).nonce));

        return (user_bytes, shared, asset, size, leverage, is_long, reserve_chain, reserve_provider, reserve_token, price_update_data)
    }

    public fun prepare_p_change_reserve(type_names: vector<String>, payload: vector<vector<u8>>): (vector<u8>, String, String, String, String, String) acquires Permissions {
        let (_, user_raw) = find_payload_value(utf8(b"addr"), type_names, payload);
        let (_, shared_raw) = find_payload_value(utf8(b"shared"), type_names, payload);
        let (_, asset_raw) = find_payload_value(utf8(b"asset"), type_names, payload);
        let (_, chain_raw) = find_payload_value(utf8(b"new_reserve_chain"), type_names, payload);
        let (_, provider_raw) = find_payload_value(utf8(b"new_reserve_provider"), type_names, payload);
        let (_, token_raw) = find_payload_value(utf8(b"new_reserve_token"), type_names, payload);

        let user_stream = &mut bcs_stream::new(user_raw);
        let user_bytes = bcs_stream::deserialize_vector(user_stream, |s| bcs_stream::deserialize_u8(s));
        let shared = bcs_stream::deserialize_string(&mut bcs_stream::new(shared_raw));
        let asset = bcs_stream::deserialize_string(&mut bcs_stream::new(asset_raw));
        let new_reserve_chain = bcs_stream::deserialize_string(&mut bcs_stream::new(chain_raw));
        let new_reserve_provider = bcs_stream::deserialize_string(&mut bcs_stream::new(provider_raw));
        let new_reserve_token = bcs_stream::deserialize_string(&mut bcs_stream::new(token_raw));

        let (_, consensus_type) = find_payload_value(utf8(b"consensus_type"), type_names, payload);
        let consensus = bcs_stream::deserialize_string(&mut bcs_stream::new(consensus_type));
        Nonce::increment_nonce(user_bytes, consensus, Nonce::give_permission(&borrow_global<Permissions>(@dev).nonce));

        return (user_bytes, shared, asset, new_reserve_chain, new_reserve_provider, new_reserve_token)
    }

public fun prepare_p_create_limit_order(type_names: vector<String>, payload: vector<vector<u8>>): (vector<u8>, String, String, u64, u128, bool, u32, String, String, String) acquires Permissions {
        let (_, user_raw) = find_payload_value(utf8(b"addr"), type_names, payload);
        let (_, shared_raw) = find_payload_value(utf8(b"shared"), type_names, payload);
        let (_, asset_raw) = find_payload_value(utf8(b"asset"), type_names, payload);
        let (_, size_raw) = find_payload_value(utf8(b"size"), type_names, payload);
        let (_, price_raw) = find_payload_value(utf8(b"desired_price"), type_names, payload);
        let (_, is_long_raw) = find_payload_value(utf8(b"isLong"), type_names, payload);
        let (_, leverage_raw) = find_payload_value(utf8(b"leverage"), type_names, payload);
        let (_, chain_raw) = find_payload_value(utf8(b"reserve_chain"), type_names, payload);
        let (_, provider_raw) = find_payload_value(utf8(b"reserve_provider"), type_names, payload);
        let (_, token_raw) = find_payload_value(utf8(b"reserve_token"), type_names, payload);

        let user_stream = &mut bcs_stream::new(user_raw);
        let user_bytes = bcs_stream::deserialize_vector(user_stream, |s| bcs_stream::deserialize_u8(s));
        let shared = bcs_stream::deserialize_string(&mut bcs_stream::new(shared_raw));
        let asset = bcs_stream::deserialize_string(&mut bcs_stream::new(asset_raw));
        let size = bcs_stream::deserialize_u64(&mut bcs_stream::new(size_raw));
        let desired_price = bcs_stream::deserialize_u128(&mut bcs_stream::new(price_raw));
        let is_long = bcs_stream::deserialize_bool(&mut bcs_stream::new(is_long_raw));
        let leverage = bcs_stream::deserialize_u32(&mut bcs_stream::new(leverage_raw));
        let reserve_chain = bcs_stream::deserialize_string(&mut bcs_stream::new(chain_raw));
        let reserve_provider = bcs_stream::deserialize_string(&mut bcs_stream::new(provider_raw));
        let reserve_token = bcs_stream::deserialize_string(&mut bcs_stream::new(token_raw));

        let (_, consensus_type) = find_payload_value(utf8(b"consensus_type"), type_names, payload);
        let consensus = bcs_stream::deserialize_string(&mut bcs_stream::new(consensus_type));
        Nonce::increment_nonce(user_bytes, consensus, Nonce::give_permission(&borrow_global<Permissions>(@dev).nonce));

        return (user_bytes, shared, asset, size, desired_price, is_long, leverage, reserve_chain, reserve_provider, reserve_token)
    }

    public fun prepare_p_create_twap_order(type_names: vector<String>, payload: vector<vector<u8>>): (vector<u8>, String, String, vector<u64>, vector<u64>, bool, u32, String, String, String) acquires Permissions {
        let (_, user_raw) = find_payload_value(utf8(b"addr"), type_names, payload);
        let (_, shared_raw) = find_payload_value(utf8(b"shared"), type_names, payload);
        let (_, asset_raw) = find_payload_value(utf8(b"asset"), type_names, payload);
        let (_, periods_raw) = find_payload_value(utf8(b"periods"), type_names, payload);
        let (_, sizes_raw) = find_payload_value(utf8(b"sizes"), type_names, payload);
        let (_, price_raw) = find_payload_value(utf8(b"desired_price"), type_names, payload);
        let (_, is_long_raw) = find_payload_value(utf8(b"isLong"), type_names, payload);
        let (_, leverage_raw) = find_payload_value(utf8(b"leverage"), type_names, payload);
        let (_, chain_raw) = find_payload_value(utf8(b"reserve_chain"), type_names, payload);
        let (_, provider_raw) = find_payload_value(utf8(b"reserve_provider"), type_names, payload);
        let (_, token_raw) = find_payload_value(utf8(b"reserve_token"), type_names, payload);

        let user_stream = &mut bcs_stream::new(user_raw);
        let user_bytes = bcs_stream::deserialize_vector(user_stream, |s| bcs_stream::deserialize_u8(s));
        let shared = bcs_stream::deserialize_string(&mut bcs_stream::new(shared_raw));
        let asset = bcs_stream::deserialize_string(&mut bcs_stream::new(asset_raw));

        let periods_stream = &mut bcs_stream::new(periods_raw);
        let periods = bcs_stream::deserialize_vector(periods_stream, |s| bcs_stream::deserialize_u64(s));

        let sizes_stream = &mut bcs_stream::new(sizes_raw);
        let sizes = bcs_stream::deserialize_vector(sizes_stream, |s| bcs_stream::deserialize_u64(s));

        let is_long = bcs_stream::deserialize_bool(&mut bcs_stream::new(is_long_raw));
        let leverage = bcs_stream::deserialize_u32(&mut bcs_stream::new(leverage_raw));
        let reserve_chain = bcs_stream::deserialize_string(&mut bcs_stream::new(chain_raw));
        let reserve_provider = bcs_stream::deserialize_string(&mut bcs_stream::new(provider_raw));
        let reserve_token = bcs_stream::deserialize_string(&mut bcs_stream::new(token_raw));

        let (_, consensus_type) = find_payload_value(utf8(b"consensus_type"), type_names, payload);
        let consensus = bcs_stream::deserialize_string(&mut bcs_stream::new(consensus_type));
        Nonce::increment_nonce(user_bytes, consensus, Nonce::give_permission(&borrow_global<Permissions>(@dev).nonce));

        return (user_bytes, shared, asset, periods, sizes, is_long, leverage, reserve_chain, reserve_provider, reserve_token)
    }

    public fun prepare_p_remove_limit_order(type_names: vector<String>, payload: vector<vector<u8>>): (vector<u8>, String, u64) acquires Permissions {
        let (_, user_raw) = find_payload_value(utf8(b"addr"), type_names, payload);
        let (_, shared_raw) = find_payload_value(utf8(b"shared"), type_names, payload);
        let (_, id_raw) = find_payload_value(utf8(b"id"), type_names, payload);

        let user_stream = &mut bcs_stream::new(user_raw);
        let user_bytes = bcs_stream::deserialize_vector(user_stream, |s| bcs_stream::deserialize_u8(s));
        let shared = bcs_stream::deserialize_string(&mut bcs_stream::new(shared_raw));
        let id = bcs_stream::deserialize_u64(&mut bcs_stream::new(id_raw));

        let (_, consensus_type) = find_payload_value(utf8(b"consensus_type"), type_names, payload);
        let consensus = bcs_stream::deserialize_string(&mut bcs_stream::new(consensus_type));
        Nonce::increment_nonce(user_bytes, consensus, Nonce::give_permission(&borrow_global<Permissions>(@dev).nonce));

        return (user_bytes, shared, id)
    }

    public fun prepare_p_remove_twap_order(type_names: vector<String>, payload: vector<vector<u8>>): (vector<u8>, String, u64) acquires Permissions {
        let (_, user_raw) = find_payload_value(utf8(b"addr"), type_names, payload);
        let (_, shared_raw) = find_payload_value(utf8(b"shared"), type_names, payload);
        let (_, id_raw) = find_payload_value(utf8(b"id"), type_names, payload);

        let user_stream = &mut bcs_stream::new(user_raw);
        let user_bytes = bcs_stream::deserialize_vector(user_stream, |s| bcs_stream::deserialize_u8(s));
        let shared = bcs_stream::deserialize_string(&mut bcs_stream::new(shared_raw));
        let id = bcs_stream::deserialize_u64(&mut bcs_stream::new(id_raw));

        let (_, consensus_type) = find_payload_value(utf8(b"consensus_type"), type_names, payload);
        let consensus = bcs_stream::deserialize_string(&mut bcs_stream::new(consensus_type));
        Nonce::increment_nonce(user_bytes, consensus, Nonce::give_permission(&borrow_global<Permissions>(@dev).nonce));

        return (user_bytes, shared, id)
    }

    public fun prepare_modular_withdraw(type_names: vector<String>, payload: vector<vector<u8>>): (String, vector<u8>,  String, String, String, u64, vector<u8>)  acquires Permissions {
        let (_, name_raw) = find_payload_value(utf8(b"shared"), type_names, payload);
        let (_, user_raw) = find_payload_value(utf8(b"addr"), type_names, payload);
        let (_, symbol_raw) = find_payload_value(utf8(b"token"), type_names, payload);
        let (_, chain_raw) = find_payload_value(utf8(b"chain"), type_names, payload);
        let (_, provider_raw) = find_payload_value(utf8(b"provider"), type_names, payload);
        let (_, amount_raw) = find_payload_value(utf8(b"amount"), type_names, payload);
        let user_stream = &mut bcs_stream::new(user_raw);
        let user_bytes = bcs_stream::deserialize_vector(user_stream, |s| bcs_stream::deserialize_u8(s));

        let symbol = bcs_stream::deserialize_string(&mut bcs_stream::new(symbol_raw));
        let chain = bcs_stream::deserialize_string(&mut bcs_stream::new(chain_raw));
        let provider = bcs_stream::deserialize_string(&mut bcs_stream::new(provider_raw));
        //assert!(provider == utf8(b"Bluefin"), 100);
        let amount = bcs_stream::deserialize_u64(&mut bcs_stream::new(amount_raw));
        let name = bcs_stream::deserialize_string(&mut bcs_stream::new(name_raw));
        let (_, consensus_type) = find_payload_value(utf8(b"consensus_type"), type_names, payload);
        let consensus = bcs_stream::deserialize_string(&mut bcs_stream::new(consensus_type));
        Nonce::increment_nonce(user_bytes, consensus, Nonce::give_permission(&borrow_global<Permissions>(@dev).nonce));
        return (name, user_bytes, symbol, chain, provider, amount, user_bytes)
    }

public fun prepare_finalize_bridge(
    type_names: vector<String>, 
    payload: vector<vector<u8>>
): (vector<u8>, String, String, String, String, String, String, String, u64, u256, u256)  acquires Permissions  {
    
    // 1. Extract raw byte chunks using your existing finder
    let (_, addr) = find_payload_value(utf8(b"addr"), type_names, payload);
    let (_, shared_raw) = find_payload_value(utf8(b"shared"), type_names, payload);
    //let (_, val_root_raw) = find_payload_value(utf8(b"validator_root"), type_names, payload);
    let (_, old_root_raw) = find_payload_value(utf8(b"old_root"), type_names, payload);
    let (_, new_root_raw) = find_payload_value(utf8(b"new_root"), type_names, payload);
    let (_, symbol_raw) = find_payload_value(utf8(b"token"), type_names, payload);
    let (_, chain_raw) = find_payload_value(utf8(b"chain"), type_names, payload);
    let (_, provider_raw) = find_payload_value(utf8(b"provider"), type_names, payload);
    let (_, total_outflow_raw) = find_payload_value(utf8(b"total_outflow"), type_names, payload);
    let (_, amount_raw) = find_payload_value(utf8(b"additional_outflow"), type_names, payload);
    let (_, nonce_raw) = find_payload_value(utf8(b"nonce"), type_names, payload);

    // 2. Decode each chunk into Move types using BCS streams
        let addr_stream = &mut bcs_stream::new(addr);
        let addr_bytes = bcs_stream::deserialize_vector(addr_stream, |s| bcs_stream::deserialize_u8(s));
        let y = addr_bytes;
    let k = bcs_stream::deserialize_string(&mut bcs_stream::new(shared_raw));
    let x = utf8(b"");
    let a = bcs_stream::deserialize_string(&mut bcs_stream::new(old_root_raw));
    let b = bcs_stream::deserialize_string(&mut bcs_stream::new(new_root_raw));
    let c = bcs_stream::deserialize_string(&mut bcs_stream::new(symbol_raw));
    let d = bcs_stream::deserialize_string(&mut bcs_stream::new(chain_raw));
    let h = bcs_stream::deserialize_string(&mut bcs_stream::new(provider_raw));
    // Numbers
    let e = bcs_stream::deserialize_u64(&mut bcs_stream::new(amount_raw));
     //              tttta(100);
    let n = bcs_stream::deserialize_u256(&mut bcs_stream::new(total_outflow_raw));
     //          tttta(0);
    let f = bcs_stream::deserialize_u256(&mut bcs_stream::new(nonce_raw));
      //          tttta(0);
              let (_, consensus_type) = find_payload_value(utf8(b"consensus_type"), type_names, payload);
        let consensus = bcs_stream::deserialize_string(&mut bcs_stream::new(consensus_type));
        Nonce::increment_nonce(addr_bytes, consensus, Nonce::give_permission(&borrow_global<Permissions>(@dev).nonce));
    return (y, k, x, a, b, c, d, h, e, n, f)
}

}