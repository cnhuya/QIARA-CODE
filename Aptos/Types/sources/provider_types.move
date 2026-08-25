module dev::QiaraProviderTypesV52 {
    use std::string::{String, utf8};
    use std::vector;
    use std::signer;
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};

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
    register_vault(signer, utf8(b"Morpho"), utf8(b"Robinhood"), utf8(b"0x8CF23E7B6cF0Ab28ea9D2510C227Ca122f8a76b1"));

    // Monad Vaults
    register_vault(signer, utf8(b"Curvance"), utf8(b"Monad"), utf8(b"0xF6cd54715F27f0A0854Fe7B6aB1dbb03073720Ea"));
    register_vault(signer, utf8(b"Neverland"), utf8(b"Monad"), utf8(b"0xD3D784911d1697e29e58FBa570C813fa2cbc02b6"));
    register_vault(signer, utf8(b"Morpho"), utf8(b"Monad"), utf8(b"0x014e8F184D5b752F589A4481Ba484296072E9D48"));

    // Ethereum (Sepolia) Vaults
    register_vault(signer, utf8(b"Aave"), utf8(b"Ethereum"), utf8(b"0x215d0d089FDc14837fBaa213b0E7266d8D9dE152"));
    register_vault(signer, utf8(b"Morpho"), utf8(b"Ethereum"), utf8(b"0x0FE607b4824Ac62a48c83cD5247A0eC207620003"));

    // Base Vaults
    register_vault(signer, utf8(b"Aave"), utf8(b"Base"), utf8(b"0x75D72FE5aFcFe3Af6e7546766196598CA107B588"));
    register_vault(signer, utf8(b"Moonwell"), utf8(b"Base"), utf8(b"0x2Bfec4481B640Ada65B79878E5f156969A2FaBE3"));
    register_vault(signer, utf8(b"Morpho"), utf8(b"Base"), utf8(b"0xFa429bcb45738815ca54b8A6e5d8Fb9938AaAc53"));

    // Sui Vaults (Updated)
    register_vault(signer, utf8(b"Suilend"), utf8(b"Sui"), utf8(b"0x1de788a3e30fae39f8e0453c15fe2e5ad9bcb528cab307c6f9fd7a6dfceadb4c"));
    register_vault(signer, utf8(b"Alphalend"), utf8(b"Sui"), utf8(b"0x87582743a0f7d461789f55c087fddd5ba3424c528b590860da78fd0c3db55d41"));
    register_vault(signer, utf8(b"Navi"), utf8(b"Sui"), utf8(b"0x993372c31df39a839e93fa72dab58fdd44c8ad13233f0720f69d6fa7c7a559de"));
    register_vault(signer, utf8(b"Bluefin"), utf8(b"Sui"), utf8(b"0x3365765f9bdc6fb88c75200a56ccdee0bb0b4cadd58ab7ceb5da2d33585a4de3"));

    // Aptos Vaults
    register_vault(signer, utf8(b"Echelon"), utf8(b"Aptos"), utf8(b"0xSP_SUP_VAULT"));
    register_vault(signer, utf8(b"Aave"), utf8(b"Aptos"), utf8(b"0xSP_SUP_VAULT"));
    register_vault(signer, utf8(b"Qiara"), utf8(b"Aptos"), utf8(b"0xSP_SUP_VAULT"));

    // Solana Vaults (Real PDAs)
    register_vault(signer, utf8(b"Juplend"), utf8(b"Solana"), utf8(b"FS2UEzMMJYzE6QSwG2eGcXVz6V5DCdbC1yzsLGkEDCYd"));
    register_vault(signer, utf8(b"Kamino"), utf8(b"Solana"), utf8(b"2jD7Vp9fjZUaJkTdzskyrgTpWWoGXQhbuh9NvhDRgnD8"));

    // === 2. Allow Tokens ===
    allow_tokens_for_provider(signer, utf8(b"Kamino"), utf8(b"Solana"), vector[utf8(b"USDC"), utf8(b"Solana"), utf8(b"USDT"), utf8(b"JLP"), utf8(b"Bitcoin"), utf8(b"USDG"), utf8(b"syrupUSDC")]);
    allow_tokens_for_provider(signer, utf8(b"Juplend"), utf8(b"Solana"), vector[utf8(b"USDC"), utf8(b"Solana"), utf8(b"USDT"), utf8(b"JLP"), utf8(b"Bitcoin"), utf8(b"USDG"), utf8(b"syrupUSDC")]);
    allow_tokens_for_provider(signer, utf8(b"Morpho"), utf8(b"Robinhood"), vector[utf8(b"USDG")]);
    allow_tokens_for_provider(signer, utf8(b"Curvance"), utf8(b"Monad"), vector[utf8(b"USDC"), utf8(b"Ethereum"), utf8(b"Monad"), utf8(b"USDT0"), utf8(b"Bitcoin"), utf8(b"AUSD"), utf8(b"earnAUSD")]);
    allow_tokens_for_provider(signer, utf8(b"Neverland"), utf8(b"Monad"), vector[utf8(b"USDC"), utf8(b"Ethereum"), utf8(b"Monad"), utf8(b"USDT0"), utf8(b"Bitcoin"), utf8(b"AUSD")]);
    allow_tokens_for_provider(signer, utf8(b"Morpho"), utf8(b"Monad"), vector[utf8(b"USDC"), utf8(b"Ethereum"), utf8(b"Monad"), utf8(b"USDT0"), utf8(b"AUSD")]);
    allow_tokens_for_provider(signer, utf8(b"Aave"), utf8(b"Ethereum"), vector[utf8(b"USDC"), utf8(b"Ethereum")]);
    allow_tokens_for_provider(signer, utf8(b"Morpho"), utf8(b"Ethereum"), vector[utf8(b"USDC"), utf8(b"Ethereum"), utf8(b"USDT"), utf8(b"Bitcoin")]);
    allow_tokens_for_provider(signer, utf8(b"Aave"), utf8(b"Base"), vector[utf8(b"USDC"), utf8(b"Ethereum")]);
    allow_tokens_for_provider(signer, utf8(b"Moonwell"), utf8(b"Base"), vector[utf8(b"USDC"), utf8(b"Ethereum"), utf8(b"Virtuals")]);
    allow_tokens_for_provider(signer, utf8(b"Morpho"), utf8(b"Base"), vector[utf8(b"USDC"), utf8(b"Ethereum"), utf8(b"Virtuals")]);
    allow_tokens_for_provider(signer, utf8(b"Suilend"), utf8(b"Sui"), vector[utf8(b"USDC"), utf8(b"USDT"), utf8(b"Ethereum"), utf8(b"Bitcoin"), utf8(b"Sui"), utf8(b"Deepbook")]);
    allow_tokens_for_provider(signer, utf8(b"Alphalend"), utf8(b"Sui"), vector[utf8(b"USDC"), utf8(b"USDT"), utf8(b"Ethereum"), utf8(b"Bitcoin"), utf8(b"Sui"), utf8(b"Deepbook")]);
    allow_tokens_for_provider(signer, utf8(b"Navi"), utf8(b"Sui"), vector[utf8(b"USDC"), utf8(b"USDT"), utf8(b"Ethereum"), utf8(b"Bitcoin"), utf8(b"Sui"), utf8(b"Deepbook")]);
    allow_tokens_for_provider(signer, utf8(b"Bluefin"), utf8(b"Sui"), vector[utf8(b"USDC"), utf8(b"USDT"), utf8(b"Ethereum"), utf8(b"Bitcoin"), utf8(b"Sui"), utf8(b"Deepbook")]);
    allow_tokens_for_provider(signer, utf8(b"Aave"), utf8(b"Aptos"), vector[utf8(b"Aptos"), utf8(b"USDT"), utf8(b"USDC")]);
    allow_tokens_for_provider(signer, utf8(b"Echelon"), utf8(b"Aptos"), vector[utf8(b"Aptos"), utf8(b"USDT"), utf8(b"USDC")]);
    allow_tokens_for_provider(signer, utf8(b"Qiara"), utf8(b"Aptos"), vector[utf8(b"Qiara"), utf8(b"Burned Qiara")]);
}

    public entry fun reg_bluefin(signer: &signer) acquires ReverseProviders, Providers {
        register_vault(signer, utf8(b"Bluefin"), utf8(b"Sui"), utf8(b"0xBL_SUI_VAULT"));
        allow_tokens_for_provider(signer, utf8(b"Bluefin"), utf8(b"Sui"), vector[utf8(b"USDC"), utf8(b"USDT"), utf8(b"Ethereum"), utf8(b"Bitcoin"), utf8(b"Sui"), utf8(b"Deepbook")]);
    }

    // === ENTRY FUNCTIONS === //

    public entry fun register_vault(
        signer: &signer, 
        provider: String, 
        chain: String, 
        vault_addr: String
    ) acquires Providers, ReverseProviders {
        assert!(signer::address_of(signer) == @dev, ERROR_NOT_AUTHORIZED);

        // 1. Update Forward Map
        let providers = borrow_global_mut<Providers>(@dev);
        if (!map::contains_key(&providers.table, &provider)) {
            map::upsert(&mut providers.table, provider, map::new());
        };
        let chains_map = map::borrow_mut(&mut providers.table, &provider);
        map::upsert(chains_map, chain, ProviderData { vault_address: vault_addr, tokens: vector::empty() });

        // 2. Update Reverse Map
        let rev_providers = borrow_global_mut<ReverseProviders>(@dev);
        if (!map::contains_key(&rev_providers.table, &vault_addr)) {
            map::upsert(&mut rev_providers.table, vault_addr, map::new());
        };
        let rev_chains_map = map::borrow_mut(&mut rev_providers.table, &vault_addr);
        map::upsert(rev_chains_map, chain, provider);
    }

    /// Updates vault address while keeping existing allowed tokens intact and syncing reverse lookup
    public entry fun update_vault_address(
        signer: &signer,
        provider: String,
        chain: String,
        new_vault_addr: String
    ) acquires Providers, ReverseProviders {
        assert!(signer::address_of(signer) == @dev, ERROR_NOT_AUTHORIZED);

        // 1. Update Forward Map & get old address
        let providers = borrow_global_mut<Providers>(@dev);
        assert!(map::contains_key(&providers.table, &provider), ERROR_INVALID_PROVIDER);
        let chains_map = map::borrow_mut(&mut providers.table, &provider);
        assert!(map::contains_key(chains_map, &chain), ERROR_INVALID_PROVIDER);

        let data = map::borrow_mut(chains_map, &chain);
        let old_vault_addr = data.vault_address;
        data.vault_address = new_vault_addr;

        // 2. Clean up Old Reverse Map
        let rev_providers = borrow_global_mut<ReverseProviders>(@dev);
        if (map::contains_key(&rev_providers.table, &old_vault_addr)) {
            let old_rev_chains = map::borrow_mut(&mut rev_providers.table, &old_vault_addr);
            if (map::contains_key(old_rev_chains, &chain)) {
                let (_, _) = map::remove(old_rev_chains, &chain);
            };
        };

        // 3. Set New Reverse Map
        if (!map::contains_key(&rev_providers.table, &new_vault_addr)) {
            map::upsert(&mut rev_providers.table, new_vault_addr, map::new());
        };
        let new_rev_chains = map::borrow_mut(&mut rev_providers.table, &new_vault_addr);
        map::upsert(new_rev_chains, chain, provider);
    }

    public entry fun allow_tokens_for_provider(
        _signer: &signer, 
        provider: String, 
        chain: String, 
        new_tokens: vector<String>
    ) acquires Providers {
        let providers = borrow_global_mut<Providers>(@dev);
        let chains_map = map::borrow_mut(&mut providers.table, &provider);
        let data = map::borrow_mut(chains_map, &chain);
        
        let i = 0;
        let len = vector::length(&new_tokens);
        while (i < len) {
            let token = vector::borrow(&new_tokens, i);
            if (!vector::contains(&data.tokens, token)) {
                vector::push_back(&mut data.tokens, *token);
            };
            i = i + 1;
        };
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