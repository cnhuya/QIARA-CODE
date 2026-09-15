module dev::QiaraProviderTypesV69 {
    use std::string::{String, utf8};
    use std::vector;
    use std::signer;
    use std::bcs; // 👈 Added missing import
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    use dev::QiaraNonceV3::{Self as Nonce, Access as NonceAccess};
    use event::QiaraEventV1::{Self as Event};

    // === ERRORS === //
    const ERROR_INVALID_PROVIDER: u64 = 1;
    const ERROR_NOT_AUTHORIZED: u64 = 2;

    // === STRUCTS === //
    struct ProviderData has store, drop, copy {
        vault_address: String,
        tokens: vector<String>
    }

    struct Providers has key {
        table: Map<String, Map<String, ProviderData>>
    }

    struct ReverseProviders has key {
        table: Map<String, Map<String, String>>
    }

    // === INIT === //
    fun init_module(admin: &signer) acquires Providers, ReverseProviders {
        assert!(signer::address_of(admin) == @dev, ERROR_NOT_AUTHORIZED);

        if (!exists<Providers>(@dev)) {
            move_to(admin, Providers { table: map::new() });
        };
        if (!exists<ReverseProviders>(@dev)) {
            move_to(admin, ReverseProviders { table: map::new() });
        };

        x_init(admin);
    }

    fun x_init(signer: &signer) acquires Providers, ReverseProviders {
        // === 1. Register Vaults ===

        // Robinhood Vaults
        set_vault(signer, utf8(b"Morpho"), utf8(b"Robinhood"), utf8(b"0x19b5Df938a05F5487eA0e7E63E10a7a255B44a02"));

        // Monad Vaults
        set_vault(signer, utf8(b"Curvance"), utf8(b"Monad"), utf8(b"0x06aeeba577402EBe1F098AFe970b58F8629D45f2"));
        set_vault(signer, utf8(b"Neverland"), utf8(b"Monad"), utf8(b"0x1a310274278De8Ccbe4A7Ea45C6AD37D487EbAe5"));
        set_vault(signer, utf8(b"Morpho"), utf8(b"Monad"), utf8(b"0xBFf73b9fBbDeFf3b0f9df22F4c74d70fA1A21f18"));

        // Ethereum Vaults
        set_vault(signer, utf8(b"Aave"), utf8(b"Ethereum"), utf8(b"0xa4A1BF1C95636f0947AE0a4dEfDD340c75F47276"));
        set_vault(signer, utf8(b"Morpho"), utf8(b"Ethereum"), utf8(b"0x82840a7CBb3C449700827dCD22B064881f24704b"));

        // Base Vaults
        set_vault(signer, utf8(b"Aave"), utf8(b"Base"), utf8(b"0xEBD670327C17c295ed93414A2cf1fE6f9255938a"));
        set_vault(signer, utf8(b"Moonwell"), utf8(b"Base"), utf8(b"0x7EfADeBa0c36c9e1b3e98C8b1D732F00976E7A78"));
        set_vault(signer, utf8(b"Morpho"), utf8(b"Base"), utf8(b"0x202691E2d6E015de3760d56CfDc5d534EB53d326"));

        // Sui Vaults
        set_vault(signer, utf8(b"Suilend"), utf8(b"Sui"), utf8(b"0x974f50b56e30d9cd33d9dd962c10cffd6c6c088e4e6f9c16cbfc6c26b129f748"));
        set_vault(signer, utf8(b"Alphalend"), utf8(b"Sui"), utf8(b"0x03ca8de6a024eeecbc4e11eb33fb2f90c7f7c9be55416082df7e4d794453c7dd"));
        set_vault(signer, utf8(b"Navi"), utf8(b"Sui"), utf8(b"0x6d627f42b39cdf1d77f4037aa49b243eff9a95b1f370c675a951d96261fa0733"));
        set_vault(signer, utf8(b"Bluefin"), utf8(b"Sui"), utf8(b"0x686b848b7c230efba497b1535afc11dda7865ec972a24f3b121356733b0aeea6"));

        // Aptos Vaults
        set_vault(signer, utf8(b"Echelon"), utf8(b"Aptos"), utf8(b"0xSP_SUP_VAULT"));
        set_vault(signer, utf8(b"Aave"), utf8(b"Aptos"), utf8(b"0xSP_SUP_VAULT"));
        set_vault(signer, utf8(b"Qiara"), utf8(b"Aptos"), utf8(b"0xSP_SUP_VAULT"));

        // Solana Vaults
        set_vault(signer, utf8(b"Juplend"), utf8(b"Solana"), utf8(b"3Khp3aJddTh5k525iYdT7i41smfQDJ4mfb9iKVNSzuRA"));
        set_vault(signer, utf8(b"Kamino"), utf8(b"Solana"), utf8(b"HMVmEzQ1UiPnJmykdq1JEohcyg1PcT5NuZ1aHuyKhVVk"));

        // === 2. Allow Tokens ===
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
    }

    // === ENTRY FUNCTIONS === //

    public entry fun set_vault(signer: &signer, provider: String, chain: String, vault_addr: String) acquires Providers, ReverseProviders {
        assert!(signer::address_of(signer) == @dev, ERROR_NOT_AUTHORIZED);

        let providers = borrow_global_mut<Providers>(@dev);
        if (!map::contains_key(&providers.table, &provider)) {
            map::upsert(&mut providers.table, provider, map::new());
        };
        let chains_map = map::borrow_mut(&mut providers.table, &provider);

        let rev_providers = borrow_global_mut<ReverseProviders>(@dev);

        if (map::contains_key(chains_map, &chain)) {
            let data = map::borrow_mut(chains_map, &chain);
            let old_addr = data.vault_address;
            data.vault_address = vault_addr;

            if (old_addr != vault_addr && map::contains_key(&rev_providers.table, &old_addr)) {
                let old_rev_map = map::borrow_mut(&mut rev_providers.table, &old_addr);
                if (map::contains_key(old_rev_map, &chain)) {
                    let (_, _) = map::remove(old_rev_map, &chain);
                };
            };
        } else {
            map::upsert(chains_map, chain, ProviderData { vault_address: vault_addr, tokens: vector::empty() });
        };

        if (!map::contains_key(&rev_providers.table, &vault_addr)) {
            map::upsert(&mut rev_providers.table, vault_addr, map::new());
        };
        let rev_chains_map = map::borrow_mut(&mut rev_providers.table, &vault_addr);
        map::upsert(rev_chains_map, chain, provider);
    }

    public entry fun update_tokens_for_provider(signer: &signer, is_add: bool, provider: String, chain: String, tokens: vector<String>) acquires Providers {
        assert!(signer::address_of(signer) == @dev, ERROR_NOT_AUTHORIZED);

        let providers = borrow_global_mut<Providers>(@dev);
        assert!(map::contains_key(&providers.table, &provider), ERROR_INVALID_PROVIDER);
        let chains_map = map::borrow_mut(&mut providers.table, &provider);
        assert!(map::contains_key(chains_map, &chain), ERROR_INVALID_PROVIDER);

        let data = map::borrow_mut(chains_map, &chain);
        let modified = vector[];

        while (!vector::is_empty(&tokens)) {
            let token = vector::pop_back(&mut tokens);
            if (is_add) {
                if (!vector::contains(&data.tokens, &token)) {
                    vector::push_back(&mut data.tokens, copy token);
                    vector::push_back(&mut modified, token);
                };
            } else {
                let (found, idx) = vector::index_of(&data.tokens, &token);
                if (found) {
                    vector::swap_remove(&mut data.tokens, idx);
                    vector::push_back(&mut modified, token);
                };
            };
        };

        let nonce = Nonce::get_global_nonce_by_type(utf8(b"token_provider"));
        if (!vector::is_empty(&modified)) {
            let action = if (is_add) utf8(b"Added Token For Provider") else utf8(b"Removed Token For Provider");
            let event_data = vector[
                Event::create_data_struct(utf8(b"action_id"), utf8(b"u256"), bcs::to_bytes(&1u256)),
                Event::create_data_struct(utf8(b"is_add"), utf8(b"bool"), bcs::to_bytes(&is_add)),
                Event::create_data_struct(utf8(b"chain"), utf8(b"string"), bcs::to_bytes(&chain)),
                Event::create_data_struct(utf8(b"provider"), utf8(b"string"), bcs::to_bytes(&provider)),
                Event::create_data_struct(utf8(b"nonce"), utf8(b"u256"), bcs::to_bytes(&nonce)),
                Event::create_data_struct(utf8(b"tokens"), utf8(b"vector<String>"), bcs::to_bytes(&modified)),
            ];
            Event::emit_types_event(action, event_data);
        };
    }

    public entry fun test_emit_provider_tokens_event(is_add: bool, action: String, chain: String,provider: String,nonce: u256,tokens: vector<String>,) {
        let action = if (is_add) utf8(b"Added Token For Provider") else utf8(b"Removed Token For Provider");
        let event_data = vector[
            Event::create_data_struct(utf8(b"action_id"), utf8(b"u256"), bcs::to_bytes(&action_id)),
            Event::create_data_struct(utf8(b"is_add"), utf8(b"bool"), bcs::to_bytes(&is_add)),
            Event::create_data_struct(utf8(b"chain"), utf8(b"string"), bcs::to_bytes(&chain)),
            Event::create_data_struct(utf8(b"provider"), utf8(b"string"), bcs::to_bytes(&provider)),
            Event::create_data_struct(utf8(b"nonce"), utf8(b"u256"), bcs::to_bytes(&nonce)),
            Event::create_data_struct(utf8(b"tokens"), utf8(b"vector<String>"), bcs::to_bytes(&tokens)),
        ];
        Event::emit_types_event(action, event_data);
    }

    // === VIEW FUNCTIONS === //

    #[view]
    public fun get_vault_by_name(provider: String, chain: String): String acquires Providers {
        let providers = borrow_global<Providers>(@dev);
        let chains_map = map::borrow(&providers.table, &provider);
        let data = map::borrow(chains_map, &chain);
        data.vault_address
    }

    public fun ensure_valid_provider(provider: String, chain: String) acquires Providers {
        let providers_ref = borrow_global<Providers>(@dev);
        assert!(map::contains_key(&providers_ref.table, &provider), ERROR_INVALID_PROVIDER);
        let chains_map = map::borrow(&providers_ref.table, &provider);
        assert!(map::contains_key(chains_map, &chain), ERROR_INVALID_PROVIDER);
    }

    #[view]
    public fun get_name_by_vault(vault_addr: String, chain: String): String acquires ReverseProviders {
        let rev_providers = borrow_global<ReverseProviders>(@dev);
        let rev_chains_map = map::borrow(&rev_providers.table, &vault_addr);
        *map::borrow(rev_chains_map, &chain)
    }

    #[view]
    public fun get_tokens(provider: String, chain: String): vector<String> acquires Providers {
        let providers = borrow_global<Providers>(@dev);
        let chains_map = map::borrow(&providers.table, &provider);
        let data = map::borrow(chains_map, &chain);
        data.tokens
    }

    #[view]
    public fun return_all_providers(): Map<String, Map<String, ProviderData>> acquires Providers {
        let providers = borrow_global<Providers>(@dev);
        providers.table
    }

    public fun get_provider_tokens(data: &ProviderData): &vector<String> {
        &data.tokens
    }
}