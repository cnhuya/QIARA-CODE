module dev::QiaraProviderTypesV4 {
    use std::string::{Self as string, String, utf8};
    use std::vector;
    use std::signer;
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};

    // === ERRORS === //
    const ERROR_INVALID_PROVIDER: u64 = 1;
    const ERROR_NOT_AUTHORIZED: u64 = 2;

    // === STRUCTS === //

    // Forward: Provider -> Chain -> (VaultAddress, List of Tokens)
    struct ProviderData has store, drop, copy {
        vault_address: String,
        tokens: vector<String>
    }

    struct Providers has key {
        // Map<ProviderName, Map<ChainName, ProviderData>>
        table: Map<String, Map<String, ProviderData>>
    }

    // Reverse: VaultAddress -> Chain -> ProviderName
    struct ReverseProviders has key {
        // Map<VaultAddress, Map<ChainName, ProviderName>>
        table: Map<String, Map<String, String>>
    }


    // === INIT === //
    fun init_module(admin: &signer)  acquires Providers, ReverseProviders {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == @dev, ERROR_NOT_AUTHORIZED);

        if (!exists<Providers>(admin_addr)) {
            move_to(admin, Providers { table: map::new<String, Map<String, ProviderData>>() });
        };
        if (!exists<ReverseProviders>(admin_addr)) {
            move_to(admin, ReverseProviders { table: map::new<String, Map<String, String>>() });
        };

        x_init(admin);

    }


fun x_init(signer: &signer) acquires Providers, ReverseProviders {
    // === 1. Register Vaults (Sets Forward & Reverse Maps) ===
    // Syntax: register_vault(signer, provider_name, chain_name, vault_address)
    
    // Monad Vaults
    register_vault(signer, utf8(b"Curvance"), utf8(b"Monad"), utf8(b"0xCV_MON_VAULT"));
    register_vault(signer, utf8(b"Neverland"), utf8(b"Monad"), utf8(b"0xNL_MON_VAULT"));
    register_vault(signer, utf8(b"Morpho"), utf8(b"Monad"), utf8(b"0xMO_MON_VAULT"));

    // Ethereum Vaults
    register_vault(signer, utf8(b"Aave"), utf8(b"Ethereum"), utf8(b"0xAA_ETH_VAULT"));
    register_vault(signer, utf8(b"Morpho"), utf8(b"Ethereum"), utf8(b"0xMO_ETH_VAULT"));

    // Base Vaults
    register_vault(signer, utf8(b"Aave"), utf8(b"Base"), utf8(b"0x182872c478976A04401919d034eF003De456EE8D"));
    register_vault(signer, utf8(b"Moonwell"), utf8(b"Base"), utf8(b"0xMW_BAS_VAULT"));
    register_vault(signer, utf8(b"Morpho"), utf8(b"Base"), utf8(b"0xMO_BAS_VAULT"));

    // Sui Vaults
    register_vault(signer, utf8(b"Suilend"), utf8(b"Sui"), utf8(b"0xSL_SUI_VAULT"));
    register_vault(signer, utf8(b"Alphalend"), utf8(b"Sui"), utf8(b"0xAL_SUI_VAULT"));
    register_vault(signer, utf8(b"Navi"), utf8(b"Sui"), utf8(b"0xNV_SUI_VAULT"));
    register_vault(signer, utf8(b"Bluefin"), utf8(b"Sui"), utf8(b"0xBL_SUI_VAULT"));
    // Aptos Vaults
    register_vault(signer, utf8(b"Echelon"), utf8(b"Aptos"), utf8(b"0xSP_SUP_VAULT"));
    register_vault(signer, utf8(b"Aave"), utf8(b"Aptos"), utf8(b"0xSP_SUP_VAULT"));

    // === 2. Allow Tokens (Fills the 'tokens' vector in ProviderData) ===
    
    // Monad Tokens
    allow_tokens_for_provider(signer, utf8(b"Curvance"), utf8(b"Monad"), vector[utf8(b"USDC"), utf8(b"Ethereum"), utf8(b"Monad"), utf8(b"USDT0"), utf8(b"Bitcoin"), utf8(b"AUSD"), utf8(b"earnAUSD")]);
    allow_tokens_for_provider(signer, utf8(b"Neverland"), utf8(b"Monad"), vector[utf8(b"USDC"), utf8(b"Ethereum"), utf8(b"Monad"), utf8(b"USDT0"), utf8(b"Bitcoin"), utf8(b"AUSD")]);
    allow_tokens_for_provider(signer, utf8(b"Morpho"), utf8(b"Monad"), vector[utf8(b"USDC"), utf8(b"Ethereum"), utf8(b"Monad"), utf8(b"USDT0"), utf8(b"AUSD")]);
    
    // Ethereum Tokens
    allow_tokens_for_provider(signer, utf8(b"Aave"), utf8(b"Ethereum"), vector[utf8(b"USDC"), utf8(b"Ethereum")]);
    allow_tokens_for_provider(signer, utf8(b"Morpho"), utf8(b"Ethereum"), vector[utf8(b"USDC"), utf8(b"Ethereum"), utf8(b"USDT"), utf8(b"Bitcoin")]);

    // Base Tokens
    allow_tokens_for_provider(signer, utf8(b"Aave"), utf8(b"Base"), vector[utf8(b"USDC"), utf8(b"Ethereum")]);
    allow_tokens_for_provider(signer, utf8(b"Moonwell"), utf8(b"Base"), vector[utf8(b"USDC"), utf8(b"Ethereum"), utf8(b"Virtuals")]);
    allow_tokens_for_provider(signer, utf8(b"Morpho"), utf8(b"Base"), vector[utf8(b"USDC"), utf8(b"Ethereum"), utf8(b"Virtuals")]);

    // Sui Tokens
    allow_tokens_for_provider(signer, utf8(b"Suilend"), utf8(b"Sui"), vector[utf8(b"USDC"), utf8(b"USDT"), utf8(b"Ethereum"), utf8(b"Bitcoin"), utf8(b"Sui"), utf8(b"Deepbook")]);
    allow_tokens_for_provider(signer, utf8(b"Alphalend"), utf8(b"Sui"), vector[utf8(b"USDC"), utf8(b"USDT"), utf8(b"Ethereum"), utf8(b"Bitcoin"), utf8(b"Sui"), utf8(b"Deepbook")]);
    allow_tokens_for_provider(signer, utf8(b"Navi"), utf8(b"Sui"), vector[utf8(b"USDC"), utf8(b"USDT"), utf8(b"Ethereum"), utf8(b"Bitcoin"), utf8(b"Sui"), utf8(b"Deepbook")]);
    allow_tokens_for_provider(signer, utf8(b"Bluefin"), utf8(b"Sui"), vector[utf8(b"USDC"), utf8(b"USDT"), utf8(b"Ethereum"), utf8(b"Bitcoin"), utf8(b"Sui"), utf8(b"Deepbook")]);

    // Aptos Tokens
    allow_tokens_for_provider(signer, utf8(b"Aave"), utf8(b"Aptos"), vector[utf8(b"Aptos"), utf8(b"USDT"), utf8(b"USDC")]);
    allow_tokens_for_provider(signer, utf8(b"Echelon"), utf8(b"Aptos"), vector[utf8(b"Aptos"), utf8(b"USDT"), utf8(b"USDC")]);
}

    public entry fun reg_bluefin(signer: &signer) acquires ReverseProviders , Providers{
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
            map::upsert(&mut providers.table, provider, map::new<String, ProviderData>());
        };
        let chains_map = map::borrow_mut(&mut providers.table, &provider);
        
        let data = ProviderData { 
            vault_address: vault_addr, 
            tokens: vector::empty<String>() 
        };
        map::upsert(chains_map, chain, data);

        // 2. Update Reverse Map
        let rev_providers = borrow_global_mut<ReverseProviders>(@dev);
        if (!map::contains_key(&rev_providers.table, &vault_addr)) {
            map::upsert(&mut rev_providers.table, vault_addr, map::new<String, String>());
        };
        let rev_chains_map = map::borrow_mut(&mut rev_providers.table, &vault_addr);
        map::upsert(rev_chains_map, chain, provider);
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
        
        // 1. Check if the Provider exists in the table
        if (!map::contains_key(&providers_ref.table, &provider)) {
            abort ERROR_INVALID_PROVIDER
        };

        let chains_map = map::borrow(&providers_ref.table, &provider);

        // 2. Check if that Provider is registered on the specific Chain
        if (!map::contains_key(chains_map, &chain)) {
            abort ERROR_INVALID_PROVIDER
        };
        
        // Success: the provider/chain combo exists.
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
    public fun return_all_providers():  Map<String, Map<String, ProviderData>> acquires Providers {
        let providers = borrow_global<Providers>(@dev);
        providers.table
    }
}