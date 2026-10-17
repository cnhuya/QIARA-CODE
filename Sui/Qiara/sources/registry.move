module Qiara::QiaraRegistryV1 {
    use std::string::{Self, String};
    use std::vector;
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::table::{Self, Table};
    use sui::event;
    use sui::hash;
    use sui::bcs::{Self, BCS};
    use sui::clock::Clock;

    use Qiara::QiaraEpochManagerV1::{Self as epoch_manager, Config as EpochConfig};
    use Qiara::QiaraVariablesV1::{Self as vars, Registry as VariablesRegistry};
    use Qiara::QiaraValidatorsV1::{Self as validators, ValidatorState};

    const SUI_CHAIN_ID: u64 = 103;

    // --- Errors ---
    const EDevAccessRevoked: u64 = 0;
    const EReplayAttack: u64 = 1;
    const EInsufficientValidators: u64 = 2;
    const ETokenNotFound: u64 = 3;
    const EInvalidActionHash: u64 = 4;
    const EWrongChainId: u64 = 5;

    // --- Capabilities & State ---

    public struct RegistryAdminCap has key, store {
        id: UID,
    }

    public struct ProviderRegistry has key {
        id: UID,
        chain: String,
        dev_access_revoked: bool,
        providers: vector<String>,
        provider_tokens: Table<String, vector<String>>,
        token_addresses: Table<String, String>,
        executed_actions: Table<vector<u8>, bool>,
    }

    // --- Payloads ---

    public struct UpdateTokensPayload has copy, drop {
        provider: String,
        tokens: vector<String>,
        is_add: bool,
        nonce: u64,
        chain_id: u64,
    }

    public struct UpdateTokenAddressPayload has copy, drop {
        token: String,
        token_address: String,
        nonce: u64,
        chain_id: u64,
    }

    // --- Events (1:1 with Solana VaultEvent) ---

    public struct TokensUpdated has copy, drop {
        provider: String,
        tokens: vector<String>,
        is_add: bool,
        nonce: u64,
        hash: vector<u8>,
    }

    public struct TokenAddressUpdated has copy, drop {
        token: String,
        token_address: String,
        nonce: u64,
        hash: vector<u8>,
    }

    public struct DevAccessPermanentlyRevoked has copy, drop {}

    // --- Init ---

    fun init(ctx: &mut TxContext) {
        let admin_cap = RegistryAdminCap { id: object::new(ctx) };
        transfer::transfer(admin_cap, tx_context::sender(ctx));

        let reg = ProviderRegistry {
            id: object::new(ctx),
            chain: string::utf8(b"Sui"),
            dev_access_revoked: false,
            providers: vector::empty(),
            provider_tokens: table::new(ctx),
            token_addresses: table::new(ctx),
            executed_actions: table::new(ctx),
        };
        transfer::share_object(reg);
    }

    // --- Admin & Dev Handlers ---

    public entry fun dev_add_tokens(
        _cap: &RegistryAdminCap,
        reg: &mut ProviderRegistry,
        provider: String,
        tokens: vector<String>
    ) {
        assert!(!reg.dev_access_revoked, EDevAccessRevoked);
        internal_insert_tokens(reg, provider, tokens);
        event::emit(TokensUpdated {
            provider,
            tokens,
            is_add: true,
            nonce: 0,
            hash: vector::empty(),
        });
    }

    public entry fun dev_set_token_address(
        _cap: &RegistryAdminCap,
        reg: &mut ProviderRegistry,
        token: String,
        token_address: String
    ) {
        assert!(!reg.dev_access_revoked, EDevAccessRevoked);
        internal_set_token_address(reg, token, token_address);
        event::emit(TokenAddressUpdated {
            token,
            token_address,
            nonce: 0,
            hash: vector::empty(),
        });
    }

    public entry fun revoke_dev_access(
        _cap: &RegistryAdminCap,
        reg: &mut ProviderRegistry
    ) {
        assert!(!reg.dev_access_revoked, EDevAccessRevoked);
        reg.dev_access_revoked = true;
        event::emit(DevAccessPermanentlyRevoked {});
    }

    public entry fun set_chain(
        _cap: &RegistryAdminCap,
        reg: &mut ProviderRegistry,
        chain: String
    ) {
        reg.chain = chain;
    }

    // --- Cross-Chain Consensus Handlers (1:1 with Solana handle_update_tokens) ---

    public entry fun update_tokens(
        reg: &mut ProviderRegistry,
        val_state: &ValidatorState,
        var_reg: &VariablesRegistry,
        epoch_manager_state: &EpochConfig,
        message_hash: vector<u8>,
        raw_payload: vector<u8>,
        signatures: vector<vector<u8>>,
        clock: &Clock,
        _ctx: &mut TxContext
    ) {
        // 1. Verify that message_hash matches raw_payload
        let computed_hash = hash::keccak256(&raw_payload);
        assert!(message_hash == computed_hash, EInvalidActionHash);

        // 2. Consume action (Replay protection)
        assert!(!table::contains(&reg.executed_actions, message_hash), EReplayAttack);
        table::add(&mut reg.executed_actions, message_hash, true);

        // 3. Verify signatures against active validator set at current epoch
        let current_epoch = epoch_manager::get_current_epoch(epoch_manager_state, clock);
        if (vars::has_variable(var_reg, string::utf8(b"QiaraValidators"), string::utf8(b"MINIMUM_UNIQUE_VALIDATORS"))) {
            let min_required = (vars::get_variable_to_u8(
                var_reg,
                string::utf8(b"QiaraValidators"),
                string::utf8(b"MINIMUM_UNIQUE_VALIDATORS")
            ) as u64);
            assert!(vector::length(&signatures) >= min_required, EInsufficientValidators);
        };
        validators::verify_signatures(val_state, signatures, message_hash, current_epoch);

        // 4. Unpack canonical Move-compatible BCS payload
        let payload = unpack_update_tokens_payload(&raw_payload);

        // 5. Verify chain_id
        if (payload.chain_id != 0) {
            assert!(payload.chain_id == SUI_CHAIN_ID, EWrongChainId);
        };

        // 6. Update state
        if (payload.is_add) {
            internal_insert_tokens(reg, payload.provider, payload.tokens);
        } else {
            internal_remove_tokens(reg, payload.provider, payload.tokens);
        };

        // 7. Emit exact event
        event::emit(TokensUpdated {
            provider: payload.provider,
            tokens: payload.tokens,
            is_add: payload.is_add,
            nonce: payload.nonce,
            hash: message_hash,
        });
    }

    // --- 1:1 with Solana handle_update_token_address ---

    public entry fun update_token_address(
        reg: &mut ProviderRegistry,
        val_state: &ValidatorState,
        var_reg: &VariablesRegistry,
        epoch_manager_state: &EpochConfig,
        message_hash: vector<u8>,
        raw_payload: vector<u8>,
        signatures: vector<vector<u8>>,
        clock: &Clock,
        _ctx: &mut TxContext
    ) {
        // 1. Verify that message_hash matches raw_payload
        let computed_hash = hash::keccak256(&raw_payload);
        assert!(message_hash == computed_hash, EInvalidActionHash);

        // 2. Consume action (Replay protection)
        assert!(!table::contains(&reg.executed_actions, message_hash), EReplayAttack);
        table::add(&mut reg.executed_actions, message_hash, true);

        // 3. Verify signatures against active validator set at current epoch
        let current_epoch = epoch_manager::get_current_epoch(epoch_manager_state, clock);
        if (vars::has_variable(var_reg, string::utf8(b"QiaraValidators"), string::utf8(b"MINIMUM_UNIQUE_VALIDATORS"))) {
            let min_required = (vars::get_variable_to_u8(
                var_reg,
                string::utf8(b"QiaraValidators"),
                string::utf8(b"MINIMUM_UNIQUE_VALIDATORS")
            ) as u64);
            assert!(vector::length(&signatures) >= min_required, EInsufficientValidators);
        };
        validators::verify_signatures(val_state, signatures, message_hash, current_epoch);

        // 4. Unpack canonical Move-compatible BCS payload
        let payload = unpack_update_token_address_payload(&raw_payload);

        // 5. Verify chain_id
        if (payload.chain_id != 0) {
            assert!(payload.chain_id == SUI_CHAIN_ID, EWrongChainId);
        };

        // 6. Update state
        internal_set_token_address(reg, payload.token, payload.token_address);

        // 7. Emit exact event
        event::emit(TokenAddressUpdated {
            token: payload.token,
            token_address: payload.token_address,
            nonce: payload.nonce,
            hash: message_hash,
        });
    }

    // --- BCS Deserialization Helpers ---

    fun unpack_update_tokens_payload(raw_payload: &vector<u8>): UpdateTokensPayload {
        let mut bcs_data = bcs::new(*raw_payload);
        let first_byte = *vector::borrow(raw_payload, 0);

        // Handles both field definitions: (provider, tokens, is_add) vs (is_add, provider, tokens)
        if (first_byte <= 1 && vector::length(raw_payload) > 2 && *vector::borrow(raw_payload, 1) < 32) {
            let is_add = bcs::peel_bool(&mut bcs_data);
            let provider = string::utf8(bcs::peel_vec_u8(&mut bcs_data));
            let num_tokens = bcs::peel_vec_length(&mut bcs_data);
            let mut tokens = vector::empty<String>();
            let mut i = 0;
            while (i < num_tokens) {
                vector::push_back(&mut tokens, string::utf8(bcs::peel_vec_u8(&mut bcs_data)));
                i = i + 1;
            };
            let nonce = bcs::peel_u64(&mut bcs_data);
            let chain_id = peel_remaining_chain_id(bcs_data);
            UpdateTokensPayload { provider, tokens, is_add, nonce, chain_id }
        } else {
            let provider = string::utf8(bcs::peel_vec_u8(&mut bcs_data));
            let num_tokens = bcs::peel_vec_length(&mut bcs_data);
            let mut tokens = vector::empty<String>();
            let mut i = 0;
            while (i < num_tokens) {
                vector::push_back(&mut tokens, string::utf8(bcs::peel_vec_u8(&mut bcs_data)));
                i = i + 1;
            };
            let is_add = bcs::peel_bool(&mut bcs_data);
            let nonce = bcs::peel_u64(&mut bcs_data);
            let chain_id = peel_remaining_chain_id(bcs_data);
            UpdateTokensPayload { provider, tokens, is_add, nonce, chain_id }
        }
    }

    fun unpack_update_token_address_payload(raw_payload: &vector<u8>): UpdateTokenAddressPayload {
        let mut bcs_data = bcs::new(*raw_payload);
        let token = string::utf8(bcs::peel_vec_u8(&mut bcs_data));
        let token_address = string::utf8(bcs::peel_vec_u8(&mut bcs_data));
        let nonce = bcs::peel_u64(&mut bcs_data);
        let chain_id = peel_remaining_chain_id(bcs_data);

        UpdateTokenAddressPayload { token, token_address, nonce, chain_id }
    }

    fun peel_remaining_chain_id(bcs_data: BCS): u64 {
        let remainder = bcs::into_remainder_bytes(bcs_data);
        let r_len = vector::length(&remainder);
        if (r_len >= 8) {
            let mut bcs_rem = bcs::new(remainder);
            bcs::peel_u64(&mut bcs_rem)
        } else if (r_len >= 4) {
            let b0 = (*vector::borrow(&remainder, 0) as u64);
            let b1 = (*vector::borrow(&remainder, 1) as u64);
            let b2 = (*vector::borrow(&remainder, 2) as u64);
            let b3 = (*vector::borrow(&remainder, 3) as u64);
            b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
        } else {
            0
        }
    }

    // --- Views with Case-Insensitive Matching ---

    public fun is_provider_supported(reg: &ProviderRegistry, provider: String): bool {
        let (found, _) = find_provider_key(reg, &provider);
        found
    }

    public fun is_token_supported(reg: &ProviderRegistry, provider: String, token: String): bool {
        let (found_provider, canonical_key) = find_provider_key(reg, &provider);
        if (!found_provider) return false;

        let tokens = table::borrow(&reg.provider_tokens, canonical_key);
        contains_token_ignore_case(tokens, &token)
    }

    public fun get_token_address(reg: &ProviderRegistry, token: String): String {
        let (found, canonical_token) = find_token_address_key(reg, &token);
        if (found) {
            return *table::borrow(&reg.token_addresses, canonical_token)
        };

        // Fallback search across all provider lists
        let mut i = 0;
        let len = vector::length(&reg.providers);
        while (i < len) {
            let p = vector::borrow(&reg.providers, i);
            let tokens = table::borrow(&reg.provider_tokens, *p);
            let mut j = 0;
            let tlen = vector::length(tokens);
            while (j < tlen) {
                let t = vector::borrow(tokens, j);
                if (eq_ignore_case(t, &token)) {
                    let (t_found, c_token) = find_token_address_key(reg, t);
                    if (t_found) {
                        return *table::borrow(&reg.token_addresses, c_token)
                    };
                };
                j = j + 1;
            };
            i = i + 1;
        };
        string::utf8(b"")
    }

    public fun get_tokens(reg: &ProviderRegistry, provider: String): vector<String> {
        let (found, canonical_key) = find_provider_key(reg, &provider);
        if (!found) {
            vector::empty()
        } else {
            *table::borrow(&reg.provider_tokens, canonical_key)
        }
    }

    public fun get_all_providers(reg: &ProviderRegistry): vector<String> {
        reg.providers
    }

    // --- Internal State Helpers ---

    fun internal_insert_tokens(reg: &mut ProviderRegistry, provider: String, tokens: vector<String>) {
        let (found_provider, canonical_provider) = find_provider_key(reg, &provider);
        let provider_key = if (found_provider) {
            canonical_provider
        } else {
            vector::push_back(&mut reg.providers, provider);
            table::add(&mut reg.provider_tokens, provider, vector::empty());
            provider
        };

        let list = table::borrow_mut(&mut reg.provider_tokens, provider_key);
        let mut i = 0;
        let len = vector::length(&tokens);
        while (i < len) {
            let t = vector::borrow(&tokens, i);
            if (!contains_token_ignore_case(list, t)) {
                vector::push_back(list, *t);
            };
            i = i + 1;
        };
    }

    fun internal_remove_tokens(reg: &mut ProviderRegistry, provider: String, tokens: vector<String>) {
        let (found_provider, canonical_provider) = find_provider_key(reg, &provider);
        if (!found_provider) return;

        let list = table::borrow_mut(&mut reg.provider_tokens, canonical_provider);
        let mut i = 0;
        let len = vector::length(&tokens);
        while (i < len) {
            let target = vector::borrow(&tokens, i);
            let (found, index) = find_token_index_ignore_case(list, target);
            if (found) {
                vector::remove(list, index);
            };
            i = i + 1;
        };
    }

    fun internal_set_token_address(reg: &mut ProviderRegistry, token: String, token_address: String) {
        let (found, canonical_token) = find_token_address_key(reg, &token);
        if (found) {
            *table::borrow_mut(&mut reg.token_addresses, canonical_token) = token_address;
        } else {
            table::add(&mut reg.token_addresses, token, token_address);
        };
    }

    fun find_provider_key(reg: &ProviderRegistry, provider: &String): (bool, String) {
        if (table::contains(&reg.provider_tokens, *provider)) {
            return (true, *provider)
        };
        let mut i = 0;
        let len = vector::length(&reg.providers);
        while (i < len) {
            let p = vector::borrow(&reg.providers, i);
            if (eq_ignore_case(p, provider)) {
                return (true, *p)
            };
            i = i + 1;
        };
        (false, string::utf8(b""))
    }

    fun find_token_address_key(reg: &ProviderRegistry, token: &String): (bool, String) {
        if (table::contains(&reg.token_addresses, *token)) {
            return (true, *token)
        };
        let mut i = 0;
        let len = vector::length(&reg.providers);
        while (i < len) {
            let p = vector::borrow(&reg.providers, i);
            let tokens = table::borrow(&reg.provider_tokens, *p);
            let mut j = 0;
            let tlen = vector::length(tokens);
            while (j < tlen) {
                let candidate = vector::borrow(tokens, j);
                if (eq_ignore_case(candidate, token) && table::contains(&reg.token_addresses, *candidate)) {
                    return (true, *candidate)
                };
                j = j + 1;
            };
            i = i + 1;
        };
        (false, string::utf8(b""))
    }

    fun contains_token_ignore_case(tokens: &vector<String>, target: &String): bool {
        let (found, _) = find_token_index_ignore_case(tokens, target);
        found
    }

    fun find_token_index_ignore_case(tokens: &vector<String>, target: &String): (bool, u64) {
        let mut i = 0;
        let len = vector::length(tokens);
        while (i < len) {
            if (eq_ignore_case(vector::borrow(tokens, i), target)) {
                return (true, i)
            };
            i = i + 1;
        };
        (false, 0)
    }

    fun eq_ignore_case(s1: &String, s2: &String): bool {
        let b1 = string::as_bytes(s1);
        let b2 = string::as_bytes(s2);
        let len1 = vector::length(b1);
        if (len1 != vector::length(b2)) return false;
        let mut i = 0;
        while (i < len1) {
            let c1 = *vector::borrow(b1, i);
            let c2 = *vector::borrow(b2, i);
            let l1 = if (c1 >= 65 && c1 <= 90) { c1 + 32 } else { c1 };
            let l2 = if (c2 >= 65 && c2 <= 90) { c2 + 32 } else { c2 };
            if (l1 != l2) return false;
            i = i + 1;
        };
        true
    }
}