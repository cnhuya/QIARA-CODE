module dev::QiaraTokenTypesV52 {
    use std::string::{Self as string, String, utf8};
    use std::vector;
    use std::signer;
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};

    use dev::QiaraChainTypesV52::{Self as ChainTypes};

    const TOKEN_PREFIX: vector<u8> = b"Qiara126 ";
    const SYMBOL_PREFIX: vector<u8> = b"Q";

// === ERRORS === //
    const ERROR_INVALID_TOKEN: u64 = 1;
    const ERROR_INVALID_CONVERT_TOKEN: u64 = 2;
    const ERROR_INVALID_CONVERT_SYMBOL: u64 = 3;
    const ERROR_TOKEN_NOT_SUPPORTED_FOR_THIS_CHAIN: u64 = 4;
    const ERROR_TKN_ADDRESSES_CHAINS_LENGTH_MISMATCH: u64 = 5;
    const ERROR_TOKEN_ALREADY_REGISTERED: u64 = 6;
    const ERROR_TOKEN_ADDR_ALREADY_REGISTERED: u64 = 7;
    const ERROR_CHAIN_ALREADY_REGISTERED_FOR_THIS_TKN: u64 = 8;
    const ERORR_ARGUMENT_LENGHT_MISSMATCH: u64 = 9;

// === STRUCTS === //

    struct Tokens has key {
        // Original: Token -> Chain -> Address / CoinType / Mint
        map: Map<String, Map<String, String>>,
        // Reverse: "ChainAddress" -> Token Name (Reverse Lookup)
        reverse_map: Map<String, String>, 
        nick_names: Map<String, String>,
    }

// === INIT === //
    fun init_module(admin: &signer) acquires Tokens {
        assert!(signer::address_of(admin) == @dev, 1);

        if (!exists<Tokens>(@dev)) {
            move_to(admin, Tokens { 
                map: map::new<String, Map<String, String>>(), 
                reverse_map: map::new<String, String>(), 
                nick_names: map::new<String, String>() 
            });
        };
        x_init(admin);
    }

    fun create_reverse_key(chain: String, addr: String): String {
        string::append(&mut chain, addr);
        chain
    }

    fun x_init(signer: &signer) acquires Tokens {
        // -------------------------------------------------------------
        // 1. QIARA TOKEN
        // -------------------------------------------------------------
        register_token_with_chains(signer, utf8(b"Qiara126 Qiara"), utf8(b"Qiara"), 
            vector[
                utf8(b"0x8C9621E38f74c59b0B784894f12C0CD5bE8a2f02"), // Sui
                utf8(b"0x0"), // Base
                utf8(b"0x0"), // Monad
                utf8(b"0x0"), // Ethereum
                utf8(b"0x0"), // Aptos
                utf8(b"0x0")  // Solana
            ], 
            vector[utf8(b"Sui"), utf8(b"Base"), utf8(b"Monad"), utf8(b"Ethereum"), utf8(b"Aptos"), utf8(b"Solana")]
        );

        // -------------------------------------------------------------
        // 2. SOLANA (SOL)
        // -------------------------------------------------------------
        register_token_with_chains(signer, utf8(b"Qiara126 Solana"), utf8(b"Solana"), 
            vector[utf8(b"AhC5BeQ238gzcoZ174B1xup4hnT1ckL5Tw3jS2Lph754")], 
            vector[utf8(b"Solana")]
        );

        // -------------------------------------------------------------
        // 3. syrupUSDC
        // -------------------------------------------------------------
        register_token_with_chains(signer, utf8(b"Qiara126 syrupUSDC"), utf8(b"syrupUSDC"), 
            vector[utf8(b"0x0")], 
            vector[utf8(b"Solana")]
        );

        // -------------------------------------------------------------
        // 4. USDG
        // -------------------------------------------------------------
        register_token_with_chains(signer, utf8(b"Qiara126 USDG"), utf8(b"USDG"), 
            vector[
                utf8(b"77fFeadUKQfgr6uKh1uZyCUVYZsdM4qQrm9mSsxxCdj2"), // Solana
                utf8(b"0x14eF7c5BFA22941eb49cf2AC3F99aC060942161b")  // Robinhood
            ], 
            vector[utf8(b"Solana"), utf8(b"Robinhood")]
        );

        // -------------------------------------------------------------
        // 5. JLP
        // -------------------------------------------------------------
        register_token_with_chains(signer, utf8(b"Qiara126 JLP"), utf8(b"JLP"), 
            vector[utf8(b"CVi7oUumG14WjyWPSpdEQiHTBTfZTRX76c2KEKjQKRUr")], 
            vector[utf8(b"Solana")]
        );

        // -------------------------------------------------------------
        // 6. BURNED QIARA
        // -------------------------------------------------------------
        register_token_with_chains(signer, utf8(b"Qiara126 Burned Qiara"), utf8(b"Burned Qiara"), 
            vector[utf8(b"0x0")], 
            vector[utf8(b"Aptos")]
        );

        // -------------------------------------------------------------
        // 7. USDC
        // -------------------------------------------------------------
        register_token_with_chains(signer, utf8(b"Qiara126 USDC"), utf8(b"USDC"), 
            vector[
                utf8(b"0x072651bd55f5894dea1fd9733b85409f1e16680ea2476fe2398b17904b8df7bc::usdc::USDC"), // Sui
                utf8(b"0x467a3b8A38fE71709F05BAf2B890C73acfD4cd89"), // Base
                utf8(b"0x8d90fEE017450a47C8B873557e5B40670b0E0a6a"), // Monad
                utf8(b"0x32c6017328463463f781462e045BBD249eC111E1"), // Ethereum (Sepolia)
                utf8(b"0x1E7A5656bAb1789398aC73159163ffB203e2645B"), // Robinhood
                utf8(b"9LPXvqdXQdLiFSSFqMsRzwiABpoNNh2oLrMc5vk84RB"), // Solana
                utf8(b"0x0")                                          // Aptos
            ], 
            vector[utf8(b"Sui"), utf8(b"Base"), utf8(b"Monad"), utf8(b"Ethereum"), utf8(b"Robinhood"), utf8(b"Solana"), utf8(b"Aptos")]
        );

        // -------------------------------------------------------------
        // 8. USDT
        // -------------------------------------------------------------
        register_token_with_chains(signer, utf8(b"Qiara126 USDT"), utf8(b"USDT"), 
            vector[
                utf8(b"0x072651bd55f5894dea1fd9733b85409f1e16680ea2476fe2398b17904b8df7bc::usdt::USDT"), // Sui
                utf8(b"0xb4c0119069E9c82D031cCFF167eB6a33AAd9347C"), // Monad
                utf8(b"0x2d6c8F8eD8667f42D931E73a57f033D03b11b477"), // Ethereum (Sepolia)
                utf8(b"DWRhorhZnoxWHSe3fpJF5Gtz4YoAfevRZgyt3JnwF4i3"), // Solana
                utf8(b"0x0"),                                          // Base
                utf8(b"0x0")                                           // Aptos
            ], 
            vector[utf8(b"Sui"), utf8(b"Monad"), utf8(b"Ethereum"), utf8(b"Solana"), utf8(b"Base"), utf8(b"Aptos")]
        );

        // -------------------------------------------------------------
        // 9. USDT0, AUSD, EARNAUSD
        // -------------------------------------------------------------
        register_token_with_chains(signer, utf8(b"Qiara126 USDT0"), utf8(b"USDT0"), 
            vector[utf8(b"0x0"), utf8(b"0x0")], 
            vector[utf8(b"Monad"), utf8(b"Aptos")]
        );
        
        register_token_with_chains(signer, utf8(b"Qiara126 AUSD"), utf8(b"AUSD"), 
            vector[
                utf8(b"0xef2b49A7B11b61eeFce6c5a0C0466D13e6C7aeA7"), // Monad
                utf8(b"0x0")                                          // Aptos
            ], 
            vector[utf8(b"Monad"), utf8(b"Aptos")]
        );

        register_token_with_chains(signer, utf8(b"Qiara126 earnAUSD"), utf8(b"earnAUSD"), 
            vector[
                utf8(b"0x54328f1bD6438A8EE35CdeB412233511008F8B06"), // Monad
                utf8(b"0x0")                                          // Aptos
            ], 
            vector[utf8(b"Monad"), utf8(b"Aptos")]
        );

        // -------------------------------------------------------------
        // 10. ETHEREUM (ETH)
        // -------------------------------------------------------------
        register_token_with_chains(signer, utf8(b"Qiara126 Ethereum"), utf8(b"Ethereum"), 
            vector[
                utf8(b"0x072651bd55f5894dea1fd9733b85409f1e16680ea2476fe2398b17904b8df7bc::eth::ETH"), // Sui
                utf8(b"0x3C09a5dB101fb4aC18A96Fc638ACF075b94a0aAc"), // Base
                utf8(b"0x6C138f06Bd305c421678DC9C47dd92f6cb0E6f09"), // Monad
                utf8(b"0x118cE2B6010006C423c89D16056A068142bDDAFB"), // Ethereum (Sepolia)
                utf8(b"0x7831e01f7168Be7E84690AfFfA436BcbCF64eC33"), // Robinhood
                utf8(b"0x0")                                          // Aptos
            ], 
            vector[utf8(b"Sui"), utf8(b"Base"), utf8(b"Monad"), utf8(b"Ethereum"), utf8(b"Robinhood"), utf8(b"Aptos")]
        );

        // -------------------------------------------------------------
        // 11. BITCOIN (BTC)
        // -------------------------------------------------------------
        register_token_with_chains(signer, utf8(b"Qiara126 Bitcoin"), utf8(b"Bitcoin"),
            vector[
                utf8(b"0x072651bd55f5894dea1fd9733b85409f1e16680ea2476fe2398b17904b8df7bc::btc::BTC"), // Sui
                utf8(b"0x0e95449332B68158fA8fb06a145c50f743ad368A"), // Monad
                utf8(b"0xd7fa256f739b144649a45C7cd120aE1A60927908"), // Ethereum (Sepolia)
                utf8(b"Drsao83oXx9aiCxtfpQXs8jNSggjLxFuwM3hYid8CpgQ"), // Solana
                utf8(b"0x0"),                                          // Base
                utf8(b"0x0")                                           // Aptos
            ], 
            vector[utf8(b"Sui"), utf8(b"Monad"), utf8(b"Ethereum"), utf8(b"Solana"), utf8(b"Base"), utf8(b"Aptos")]
        );

        // -------------------------------------------------------------
        // 12. MONAD
        // -------------------------------------------------------------
        register_token_with_chains(signer, utf8(b"Qiara126 Monad"), utf8(b"Monad"), 
            vector[
                utf8(b"0x860d01d42D8557F9A2f9725ef86Af24d1CDa3AE8"), // Monad
                utf8(b"0x0")                                          // Aptos
            ], 
            vector[utf8(b"Monad"), utf8(b"Aptos")]
        );

        // -------------------------------------------------------------
        // 13. APTOS
        // -------------------------------------------------------------
        register_token_with_chains(signer, utf8(b"Qiara126 Aptos"), utf8(b"Aptos"), 
            vector[utf8(b"0x0")], 
            vector[utf8(b"Aptos")]
        );

        // -------------------------------------------------------------
        // 14. SUI & DEEPBOOK
        // -------------------------------------------------------------
        register_token_with_chains(signer, utf8(b"Qiara126 Sui"), utf8(b"Sui"), 
            vector[
                utf8(b"0x072651bd55f5894dea1fd9733b85409f1e16680ea2476fe2398b17904b8df7bc::sui::SUI"), // Sui
                utf8(b"0x0")                                                                              // Aptos
            ], 
            vector[utf8(b"Sui"), utf8(b"Aptos")]
        );

        register_token_with_chains(signer, utf8(b"Qiara126 Deepbook"), utf8(b"Deepbook"), 
            vector[
                utf8(b"0x072651bd55f5894dea1fd9733b85409f1e16680ea2476fe2398b17904b8df7bc::DEEP::DEEP"), // Sui
                utf8(b"0x0")                                                                                // Aptos
            ], 
            vector[utf8(b"Sui"), utf8(b"Aptos")]
        );

        // -------------------------------------------------------------
        // 15. VIRTUALS
        // -------------------------------------------------------------
        register_token_with_chains(signer, utf8(b"Qiara126 Virtuals"), utf8(b"Virtuals"), 
            vector[
                utf8(b"0x4a93DC1C3dEBd53F4aFc4D5040313B81a3D763B1"), // Base
                utf8(b"0x0"),                                          // Ethereum
                utf8(b"0x0")                                           // Aptos
            ], 
            vector[utf8(b"Base"), utf8(b"Ethereum"), utf8(b"Aptos")]
        );
    }

// === FUNCTIONS === //

    public entry fun register_token_with_chains(signer: &signer, token: String, nick_name: String, token_address: vector<String>, chains: vector<String>) acquires Tokens {
        let tokens = borrow_global_mut<Tokens>(@dev);

        let len_chains = vector::length(&chains);
        let len_addr = vector::length(&token_address);

        assert!(len_chains == len_addr, ERORR_ARGUMENT_LENGHT_MISSMATCH);

        // 1. Initialize the Token entry if it doesn't exist
        if (!map::contains_key(&tokens.map, &token)) {
            let inner_map = map::new<String, String>();
            map::upsert(&mut tokens.map, token, inner_map);
        };

        let token_entry = map::borrow_mut(&mut tokens.map, &token);

        // 2. Loop through and store both Forward and Reverse mappings
        let i = 0;
        while (i < len_chains) {
            let chain = vector::borrow(&chains, i);
            let addr = vector::borrow(&token_address, i);

            // Chain validation
            ChainTypes::ensure_valid_chain_name(*chain);

            // Forward Mapping: Token -> Chain -> Address
            map::upsert(token_entry, *chain, *addr);

            // Reverse Mapping: (Chain + Address) -> Token Name
            // Only index if the address is not a placeholder (0x0)
            if (*addr != utf8(b"0x0")) {
                let rev_key = create_reverse_key(*chain, *addr);
                map::upsert(&mut tokens.reverse_map, rev_key, token);
            };

            i = i + 1;
        };

        // 3. Update Nickname
        map::upsert(&mut tokens.nick_names, token, nick_name);
    }

    public entry fun add_token_chain(signer: &signer, token: String, nick_name: String, token_address: String, chain: String) acquires Tokens {
        let tokens = borrow_global_mut<Tokens>(@dev);

        // 1. Standard Nested Map Update
        if (!map::contains_key(&tokens.map, &token)) {
            let inner_map = map::new<String, String>();
            map::upsert(&mut tokens.map, token, inner_map);
        };
        let token_inner_map = map::borrow_mut(&mut tokens.map, &token);
        map::upsert(token_inner_map, chain, token_address);

        // 2. Reverse Lookup Update
        let rev_key = create_reverse_key(chain, token_address);
        map::upsert(&mut tokens.reverse_map, rev_key, token);

        // 3. Nickname Update
        map::upsert(&mut tokens.nick_names, token, nick_name);
    }

    #[view]
    public fun return_all_tokens(): Map<String, Map<String, String>> acquires Tokens {
        borrow_global<Tokens>(@dev).map
    }

    #[view]
    public fun return_full_tokens_list(): vector<String> acquires Tokens {
        let tokens = borrow_global<Tokens>(@dev);
        map::keys(&tokens.map)
    }

    #[view]
    public fun return_full_nick_names_list(): vector<String> acquires Tokens {
        let tokens = borrow_global<Tokens>(@dev);
        map::values(&tokens.nick_names)
    }

    #[view]
    public fun return_full_nick_names(): Map<String, String> acquires Tokens {
        borrow_global<Tokens>(@dev).nick_names
    }

    public fun ensure_token_supported_for_chain(token: String, chain: String) acquires Tokens {
        let tokens = borrow_global<Tokens>(@dev);
        if (!map::contains_key(&tokens.map, &token)) {
            abort ERROR_INVALID_TOKEN
        };
    }
    
    #[view]
    public fun get_token_name_from_address(chain: String, addr: String): String acquires Tokens {
        let tokens = borrow_global<Tokens>(@dev);
        let rev_key = create_reverse_key(chain, addr);
        
        assert!(map::contains_key(&tokens.reverse_map, &rev_key), 404);
        convert_token_name_to_nickName(*map::borrow(&tokens.reverse_map, &rev_key))
    }

    #[view]
    public fun get_token_address_from_name(chain: String, name: String): String acquires Tokens {
        name = convert_token_nickName_to_name(name);
        let tokens = borrow_global<Tokens>(@dev);
        let token_entry = map::borrow(&tokens.map, &name);
        assert!(map::contains_key(token_entry, &chain), 404);
        *map::borrow(token_entry, &chain)
    }

    #[view]
    public fun convert_token_nickName_to_name(nick_name: String): String acquires Tokens {
        let tokens = borrow_global<Tokens>(@dev);
        let nick_names = map::values(&tokens.nick_names);
        assert!(vector::contains(&nick_names, &nick_name), ERROR_INVALID_TOKEN);

        let len = vector::length(&nick_names);
        while (len > 0) {
            let name = vector::borrow(&nick_names, len - 1);
            if (*name == nick_name) {
                let symbol = string::utf8(TOKEN_PREFIX);
                string::append_utf8(&mut symbol, *string::bytes(vector::borrow(&nick_names, len - 1)));
                return symbol
            };
            len = len - 1;
        }; 
        abort ERROR_INVALID_TOKEN
    }

    #[view]
    public fun convert_token_name_to_nickName(token_name: String): String acquires Tokens {
        let tokens = borrow_global<Tokens>(@dev);
        let names = map::keys(&tokens.nick_names);
        let nick_names = map::values(&tokens.nick_names);
        assert!(vector::contains(&names, &token_name), ERROR_INVALID_TOKEN);
        let len = vector::length(&names);
        while (len > 0) {
            let name = vector::borrow(&names, len - 1);
            if (*name == token_name) {
                return *vector::borrow(&nick_names, len - 1);
            };
            len = len - 1;
        };
        abort ERROR_INVALID_TOKEN
    }

    public fun ensure_valid_token_nick_name(token_name: String) acquires Tokens {
        let tokens = borrow_global<Tokens>(@dev);
        let names = map::values(&tokens.nick_names);
        assert!(vector::contains(&names, &token_name), ERROR_INVALID_TOKEN);
    }
}