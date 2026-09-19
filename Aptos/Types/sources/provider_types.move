module dev::QiaraProviderTypesV71 {
    use std::string::{String, utf8};
    use std::vector;
    use std::signer;
    use std::bcs;
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    use dev::QiaraNonceV4::{Self as Nonce};
    use event::QiaraEventV1::{Self as Event};

    // === ERRORS === //
    const ERROR_INVALID_PROVIDER: u64 = 1;
    const ERROR_NOT_AUTHORIZED: u64 = 2;

    // === STRUCTS === //
    struct Providers has key {
        table: Map<String, Map<String, vector<String>>>
    }

    // === INIT === //
    fun init_module(admin: &signer) acquires Providers {
        assert!(signer::address_of(admin) == @dev, ERROR_NOT_AUTHORIZED);
        if (!exists<Providers>(@dev)) {
            move_to(admin, Providers { table: map::new() });
        };
        x_init(admin);
    }

    fun x_init(signer: &signer) acquires Providers {
        update_tokens_for_provider(signer, true, utf8(b"Kamino"), utf8(b"Solana"), vector[utf8(b"USDC"), utf8(b"Solana"), utf8(b"USDT"), utf8(b"JLP"), utf8(b"Bitcoin"), utf8(b"USDG")]);
        update_tokens_for_provider(signer, true, utf8(b"Juplend"), utf8(b"Solana"), vector[utf8(b"USDC"), utf8(b"Solana"), utf8(b"USDT"), utf8(b"JLP"), utf8(b"Bitcoin"), utf8(b"USDG")]);
        update_tokens_for_provider(signer, true, utf8(b"Morpho"), utf8(b"Robinhood"), vector[utf8(b"USDG")]);
        update_tokens_for_provider(signer, true, utf8(b"Curvance"), utf8(b"Monad"), vector[utf8(b"USDC"), utf8(b"Ethereum"), utf8(b"Monad"), utf8(b"Bitcoin"), utf8(b"AUSD"), utf8(b"earnAUSD")]);
        update_tokens_for_provider(signer, true, utf8(b"Neverland"), utf8(b"Monad"), vector[utf8(b"USDC"), utf8(b"Ethereum"), utf8(b"Monad"), utf8(b"Bitcoin"), utf8(b"AUSD")]);
        update_tokens_for_provider(signer, true, utf8(b"Morpho"), utf8(b"Monad"), vector[utf8(b"USDC"), utf8(b"Ethereum"), utf8(b"Monad"), utf8(b"AUSD")]);
        update_tokens_for_provider(signer, true, utf8(b"Aave"), utf8(b"Ethereum"), vector[utf8(b"USDC"), utf8(b"Ethereum")]);
        update_tokens_for_provider(signer, true, utf8(b"Morpho"), utf8(b"Ethereum"), vector[utf8(b"USDC"), utf8(b"Ethereum"), utf8(b"USDT"), utf8(b"Bitcoin")]);
        update_tokens_for_provider(signer, true, utf8(b"Aave"), utf8(b"Base"), vector[utf8(b"USDC"), utf8(b"Ethereum")]);
        update_tokens_for_provider(signer, true, utf8(b"Moonwell"), utf8(b"Base"), vector[utf8(b"USDC"), utf8(b"Ethereum"), utf8(b"Virtuals")]);
        update_tokens_for_provider(signer, true, utf8(b"Morpho"), utf8(b"Base"), vector[utf8(b"USDC"), utf8(b"Ethereum"), utf8(b"Virtuals")]);
        update_tokens_for_provider(signer, true, utf8(b"Suilend"), utf8(b"Sui"), vector[utf8(b"USDC"), utf8(b"USDT"), utf8(b"Ethereum"), utf8(b"Bitcoin"), utf8(b"Sui"), utf8(b"Deepbook")]);
        update_tokens_for_provider(signer, true, utf8(b"Alphalend"), utf8(b"Sui"), vector[utf8(b"USDC"), utf8(b"USDT"), utf8(b"Ethereum"), utf8(b"Bitcoin"), utf8(b"Sui"), utf8(b"Deepbook")]);
        update_tokens_for_provider(signer, true, utf8(b"Navi"), utf8(b"Sui"), vector[utf8(b"USDC"), utf8(b"USDT"), utf8(b"Ethereum"), utf8(b"Bitcoin"), utf8(b"Sui"), utf8(b"Deepbook")]);
        update_tokens_for_provider(signer, true, utf8(b"Bluefin"), utf8(b"Sui"), vector[utf8(b"USDC"), utf8(b"USDT"), utf8(b"Ethereum"), utf8(b"Bitcoin"), utf8(b"Sui"), utf8(b"Deepbook")]);
        update_tokens_for_provider(signer, true, utf8(b"Aave"), utf8(b"Aptos"), vector[utf8(b"Aptos"), utf8(b"USDT"), utf8(b"USDC")]);
        update_tokens_for_provider(signer, true, utf8(b"Echelon"), utf8(b"Aptos"), vector[utf8(b"Aptos"), utf8(b"USDT"), utf8(b"USDC")]);
        update_tokens_for_provider(signer, true, utf8(b"Qiara"), utf8(b"Aptos"), vector[utf8(b"Qiara"), utf8(b"Burned Qiara")]);
        update_tokens_for_provider(signer, true, utf8(b"Qiara"), utf8(b"Base"), vector[utf8(b"Qiara")]);
        update_tokens_for_provider(signer, true, utf8(b"Qiara"), utf8(b"Ethereum"), vector[utf8(b"Qiara")]);
        update_tokens_for_provider(signer, true, utf8(b"Qiara"), utf8(b"Solana"), vector[utf8(b"Qiara")]);
        update_tokens_for_provider(signer, true, utf8(b"Qiara"), utf8(b"Robinhood"), vector[utf8(b"Qiara")]);
        update_tokens_for_provider(signer, true, utf8(b"Qiara"), utf8(b"Sui"), vector[utf8(b"Qiara")]);
        update_tokens_for_provider(signer, true, utf8(b"Qiara"), utf8(b"Monad"), vector[utf8(b"Qiara")]);
    }

    // === ENTRY FUNCTIONS === //
    public entry fun update_tokens_for_provider(signer: &signer, is_add: bool, provider: String, chain: String, tokens: vector<String>) acquires Providers {
        assert!(signer::address_of(signer) == @dev, ERROR_NOT_AUTHORIZED);

        let providers = borrow_global_mut<Providers>(@dev);
        if (!map::contains_key(&providers.table, &provider)) {
            map::upsert(&mut providers.table, copy provider, map::new());
        };
        let chains_map = map::borrow_mut(&mut providers.table, &provider);
        if (!map::contains_key(chains_map, &chain)) {
            map::upsert(chains_map, copy chain, vector[]);
        };

        let token_list = map::borrow_mut(chains_map, &chain);
        let modified = vector[];

        while (!vector::is_empty(&tokens)) {
            let token = vector::pop_back(&mut tokens);
            if (is_add) {
                if (!vector::contains(token_list, &token)) {
                    vector::push_back(token_list, copy token);
                    vector::push_back(&mut modified, token);
                };
            } else {
                let (found, idx) = vector::index_of(token_list, &token);
                if (found) {
                    vector::swap_remove(token_list, idx);
                    vector::push_back(&mut modified, token);
                };
            };
        };

        if (!vector::is_empty(&modified)) {
            let nonce = Nonce::get_global_nonce_by_type(utf8(b"token_provider"));
            let action = if (is_add) utf8(b"Added Token For Provider") else utf8(b"Removed Token For Provider");
            let event_data = vector[
                Event::create_data_struct(utf8(b"action_id"), utf8(b"u256"), bcs::to_bytes(&1u256)),
                Event::create_data_struct(utf8(b"is_add"), utf8(b"bool"), bcs::to_bytes(&is_add)),
                Event::create_data_struct(utf8(b"chain"), utf8(b"string"), bcs::to_bytes(&chain)),
                Event::create_data_struct(utf8(b"provider"), utf8(b"string"), bcs::to_bytes(&provider)),
                Event::create_data_struct(utf8(b"nonce"), utf8(b"u256"), bcs::to_bytes(&(nonce as u256))),
                Event::create_data_struct(utf8(b"tokens"), utf8(b"vector<String>"), bcs::to_bytes(&modified)),
            ];
            Event::emit_types_event(action, event_data);
        };
    }

    public entry fun test_emit_provider_tokens_event(is_add: bool, action: String, chain: String, provider: String, nonce: u256, tokens: vector<String>) {
        let event_data = vector[
            Event::create_data_struct(utf8(b"action"), utf8(b"string"), bcs::to_bytes(&action)),
            Event::create_data_struct(utf8(b"action_id"), utf8(b"u256"), bcs::to_bytes(&1u256)),
            Event::create_data_struct(utf8(b"is_add"), utf8(b"bool"), bcs::to_bytes(&is_add)),
            Event::create_data_struct(utf8(b"chain"), utf8(b"string"), bcs::to_bytes(&chain)),
            Event::create_data_struct(utf8(b"provider"), utf8(b"string"), bcs::to_bytes(&provider)),
            Event::create_data_struct(utf8(b"nonce"), utf8(b"u256"), bcs::to_bytes(&nonce)),
            Event::create_data_struct(utf8(b"tokens"), utf8(b"vector<String>"), bcs::to_bytes(&tokens)),
        ];
        Event::emit_types_event(action, event_data);
    }

    // === VIEW FUNCTIONS === //
    public fun ensure_valid_provider(provider: String, chain: String) acquires Providers {
        let providers = borrow_global<Providers>(@dev);
        assert!(map::contains_key(&providers.table, &provider), ERROR_INVALID_PROVIDER);
        assert!(map::contains_key(map::borrow(&providers.table, &provider), &chain), ERROR_INVALID_PROVIDER);
    }

    #[view]
    public fun get_tokens(provider: String, chain: String): vector<String> acquires Providers {
        let providers = borrow_global<Providers>(@dev);
        *map::borrow(map::borrow(&providers.table, &provider), &chain)
    }

    #[view]
    public fun return_all_providers(): Map<String, Map<String, vector<String>>> acquires Providers {
        borrow_global<Providers>(@dev).table
    }
}