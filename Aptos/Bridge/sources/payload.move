module dev::QiaraPayloadV22{
    use std::signer;
    use std::vector;
    use std::string::{Self as string, String, utf8};
    use std::table;
    use aptos_std::from_bcs;
    use std::hash;
    use std::bcs;
    use aptos_std::bcs_stream::{Self};
    use dev::QiaraChainTypesV16::{Self as ChainTypes};
    use dev::QiaraTokenTypesV16::{Self as TokenTypes};
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
       
    public fun prepare_bridge_deposit(type_names: vector<String>, payload: vector<vector<u8>>): (vector<u8>, vector<u8>, String, String, String, String, u64, u64,String)  acquires Permissions  {
        
        // 1. Extract raw byte chunks
        let (_, addr_raw) = find_payload_value(utf8(b"addr"), type_names, payload);
        let (_, shared_raw) = find_payload_value(utf8(b"shared"), type_names, payload);
        let (_, token_raw) = find_payload_value(utf8(b"token"), type_names, payload);
        let (_, chain_raw) = find_payload_value(utf8(b"chain"), type_names, payload);
        let (_, provider_raw) = find_payload_value(utf8(b"provider"), type_names, payload);
        let (_, amount_raw) = find_payload_value(utf8(b"amount"), type_names, payload);
        let (_, hash_raw) = find_payload_value(utf8(b"hash"), type_names, payload);
        let (_, rate_raw) = find_payload_value(utf8(b"rate"), type_names, payload);

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

        // Extract U64
        let e = bcs_stream::deserialize_u64(&mut bcs_stream::new(amount_raw));
        let (_, consensus_type) = find_payload_value(utf8(b"consensus_type"), type_names, payload);
        let consensus = bcs_stream::deserialize_string(&mut bcs_stream::new(consensus_type));
        Nonce::increment_nonce(addr_bytes, consensus, Nonce::give_permission(&borrow_global<Permissions>(@dev).nonce));
        return (a, x, k, b, c, d, e, y, f)
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