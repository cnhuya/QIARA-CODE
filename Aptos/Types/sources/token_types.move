module dev::QiaraTokenTypesV70 {
    use std::string::{Self as string, String, utf8};
    use std::vector;
    use std::signer;
    use std::bcs;
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    use dev::QiaraNonceV4::{Self as Nonce};
    use event::QiaraEventV1::{Self as Event};
    use dev::QiaraChainTypesV70::{Self as ChainTypes};

    const TOKEN_PREFIX: vector<u8> = b"Qiara144 ";

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
    const ERROR_NOT_AUTHORIZED: u64 = 10;

    // === STRUCTS === //
    struct TokenChainData has store, copy, drop {
        address: String,
        decimals: u8,
    }

    struct Tokens has key {
        map: Map<String, Map<String, TokenChainData>>,
        reverse_map: Map<String, String>,
        nick_names: Map<String, String>,
    }

    // === INIT === //
    fun init_module(admin: &signer) acquires Tokens {
        assert!(signer::address_of(admin) == @dev, ERROR_NOT_AUTHORIZED);

        if (!exists<Tokens>(@dev)) {
            move_to(admin, Tokens { 
                map: map::new(), 
                reverse_map: map::new(), 
                nick_names: map::new() 
            });
        };
        x_init(admin);
    }

    fun x_init(signer: &signer) acquires Tokens {
        register_token_with_chains(signer, utf8(b"Qiara144 Qiara"), utf8(b"Qiara"), 
            vector[utf8(b"0x8C9621E38f74c59b0B784894f12C0CD5bE8a2f02"), utf8(b"0x0"), utf8(b"0x0"), utf8(b"0x0"), utf8(b"0x0"), utf8(b"0x0")], 
            vector[utf8(b"Sui"), utf8(b"Base"), utf8(b"Monad"), utf8(b"Ethereum"), utf8(b"Aptos"), utf8(b"Solana")],
            vector[9u8, 18u8, 18u8, 18u8, 8u8, 9u8]
        );
        register_token_with_chains(signer, utf8(b"Qiara144 Solana"), utf8(b"Solana"), 
            vector[utf8(b"AhC5BeQ238gzcoZ174B1xup4hnT1ckL5Tw3jS2Lph754")], 
            vector[utf8(b"Solana")],
            vector[8u8]
        );
        register_token_with_chains(signer, utf8(b"Qiara144 USDG"), utf8(b"USDG"), 
            vector[utf8(b"77fFeadUKQfgr6uKh1uZyCUVYZsdM4qQrm9mSsxxCdj2"), utf8(b"0x14eF7c5BFA22941eb49cf2AC3F99aC060942161b")], 
            vector[utf8(b"Solana"), utf8(b"Robinhood")],
            vector[8u8, 18u8]
        );
        register_token_with_chains(signer, utf8(b"Qiara144 JLP"), utf8(b"JLP"), 
            vector[utf8(b"CVi7oUumG14WjyWPSpdEQiHTBTfZTRX76c2KEKjQKRUr")], 
            vector[utf8(b"Solana")],
            vector[8u8]
        );
        register_token_with_chains(signer, utf8(b"Qiara144 Burned Qiara"), utf8(b"Burned Qiara"), 
            vector[utf8(b"0x0")], 
            vector[utf8(b"Aptos")],
            vector[8u8]
        );
        register_token_with_chains(signer, utf8(b"Qiara144 USDC"), utf8(b"USDC"), 
            vector[
                utf8(b"0x072651bd55f5894dea1fd9733b85409f1e16680ea2476fe2398b17904b8df7bc::usdc::USDC"),
                utf8(b"0x467a3b8A38fE71709F05BAf2B890C73acfD4cd89"),
                utf8(b"0x8d90fEE017450a47C8B873557e5B40670b0E0a6a"),
                utf8(b"0x32c6017328463463f781462e045BBD249eC111E1"),
                utf8(b"0x1E7A5656bAb1789398aC73159163ffB203e2645B"),
                utf8(b"9LPXvqdXQdLiFSSFqMsRzwiABpoNNh2oLrMc5vk84RB"),
                utf8(b"0x0")
            ], 
            vector[utf8(b"Sui"), utf8(b"Base"), utf8(b"Monad"), utf8(b"Ethereum"), utf8(b"Robinhood"), utf8(b"Solana"), utf8(b"Aptos")],
            vector[8u8, 18u8, 18u8, 18u8, 18u8, 8u8, 8u8]
        );
        register_token_with_chains(signer, utf8(b"Qiara144 USDT"), utf8(b"USDT"), 
            vector[
                utf8(b"0x072651bd55f5894dea1fd9733b85409f1e16680ea2476fe2398b17904b8df7bc::usdt::USDT"),
                utf8(b"0xb4c0119069E9c82D031cCFF167eB6a33AAd9347C"),
                utf8(b"0x2d6c8F8eD8667f42D931E73a57f033D03b11b477"),
                utf8(b"DWRhorhZnoxWHSe3fpJF5Gtz4YoAfevRZgyt3JnwF4i3"),
                utf8(b"0x0")
            ], 
            vector[utf8(b"Sui"), utf8(b"Monad"), utf8(b"Ethereum"), utf8(b"Solana"), utf8(b"Aptos")],
            vector[8u8, 18u8, 18u8, 8u8, 8u8]
        );
        register_token_with_chains(signer, utf8(b"Qiara144 AUSD"), utf8(b"AUSD"), 
            vector[utf8(b"0xef2b49A7B11b61eeFce6c5a0C0466D13e6C7aeA7"), utf8(b"0x0")], 
            vector[utf8(b"Monad"), utf8(b"Aptos")],
            vector[18u8, 8u8]
        );
        register_token_with_chains(signer, utf8(b"Qiara144 earnAUSD"), utf8(b"earnAUSD"), 
            vector[utf8(b"0x54328f1bD6438A8EE35CdeB412233511008F8B06"), utf8(b"0x0")], 
            vector[utf8(b"Monad"), utf8(b"Aptos")],
            vector[18u8, 8u8]
        );
        register_token_with_chains(signer, utf8(b"Qiara144 Ethereum"), utf8(b"Ethereum"), 
            vector[
                utf8(b"0x072651bd55f5894dea1fd9733b85409f1e16680ea2476fe2398b17904b8df7bc::eth::ETH"),
                utf8(b"0x3C09a5dB101fb4aC18A96Fc638ACF075b94a0aAc"),
                utf8(b"0x6C138f06Bd305c421678DC9C47dd92f6cb0E6f09"),
                utf8(b"0x118cE2B6010006C423c89D16056A068142bDDAFB"),
                utf8(b"0x7831e01f7168Be7E84690AfFfA436BcbCF64eC33"),
                utf8(b"0x0")
            ], 
            vector[utf8(b"Sui"), utf8(b"Base"), utf8(b"Monad"), utf8(b"Ethereum"), utf8(b"Robinhood"), utf8(b"Aptos")],
            vector[8u8, 18u8, 18u8, 18u8, 18u8, 8u8]
        );
        register_token_with_chains(signer, utf8(b"Qiara144 Bitcoin"), utf8(b"Bitcoin"),
            vector[
                utf8(b"0x072651bd55f5894dea1fd9733b85409f1e16680ea2476fe2398b17904b8df7bc::btc::BTC"),
                utf8(b"0x0e95449332B68158fA8fb06a145c50f743ad368A"),
                utf8(b"0xd7fa256f739b144649a45C7cd120aE1A60927908"),
                utf8(b"Drsao83oXx9aiCxtfpQXs8jNSggjLxFuwM3hYid8CpgQ"),
                utf8(b"0x0")
            ], 
            vector[utf8(b"Sui"), utf8(b"Monad"), utf8(b"Ethereum"), utf8(b"Solana"), utf8(b"Aptos")],
            vector[8u8, 18u8, 18u8, 8u8, 8u8]
        );
        register_token_with_chains(signer, utf8(b"Qiara144 Monad"), utf8(b"Monad"), 
            vector[utf8(b"0x860d01d42D8557F9A2f9725ef86Af24d1CDa3AE8"), utf8(b"0x0")], 
            vector[utf8(b"Monad"), utf8(b"Aptos")],
            vector[18u8, 8u8]
        );
        register_token_with_chains(signer, utf8(b"Qiara144 Aptos"), utf8(b"Aptos"), 
            vector[utf8(b"0x0")], 
            vector[utf8(b"Aptos")],
            vector[8u8]
        );
        register_token_with_chains(signer, utf8(b"Qiara144 Sui"), utf8(b"Sui"), 
            vector[utf8(b"0x072651bd55f5894dea1fd9733b85409f1e16680ea2476fe2398b17904b8df7bc::sui::SUI"), utf8(b"0x0")], 
            vector[utf8(b"Sui"), utf8(b"Aptos")],
            vector[8u8, 8u8]
        );
        register_token_with_chains(signer, utf8(b"Qiara144 Deepbook"), utf8(b"Deepbook"), 
            vector[utf8(b"0x072651bd55f5894dea1fd9733b85409f1e16680ea2476fe2398b17904b8df7bc::DEEP::DEEP"), utf8(b"0x0")], 
            vector[utf8(b"Sui"), utf8(b"Aptos")],
            vector[8u8, 6u8]
        );
        register_token_with_chains(signer, utf8(b"Qiara144 Virtuals"), utf8(b"Virtuals"), 
            vector[utf8(b"0x4a93DC1C3dEBd53F4aFc4D5040313B81a3D763B1"), utf8(b"0x0")], 
            vector[utf8(b"Base"), utf8(b"Aptos")],
            vector[18u8, 8u8]
        );
    }

    // === ADMIN / UPDATE FUNCTIONS === //

    public entry fun update_token_chain(admin: &signer,is_add: bool,token_name_or_nickname: String,nick_name: String,token_address: String,chain: String,decimals: u8) acquires Tokens {
        assert!(signer::address_of(admin) == @dev, ERROR_NOT_AUTHORIZED);
        ChainTypes::ensure_valid_chain_name(chain);

        let tokens = borrow_global_mut<Tokens>(@dev);
        let full_name = if (map::contains_key(&tokens.map, &token_name_or_nickname)) {
            token_name_or_nickname
        } else if (is_add && !string::is_empty(&nick_name)) {
            let res = utf8(TOKEN_PREFIX);
            string::append(&mut res, nick_name);
            res
        } else {
            let vals = map::values(&tokens.nick_names);
            assert!(vector::contains(&vals, &token_name_or_nickname), ERROR_INVALID_TOKEN);
            let res = utf8(TOKEN_PREFIX);
            string::append(&mut res, token_name_or_nickname);
            res
        };

        if (is_add) {
            if (!map::contains_key(&tokens.map, &full_name)) {
                map::upsert(&mut tokens.map, copy full_name, map::new());
            };
            let token_inner_map = map::borrow_mut(&mut tokens.map, &full_name);

            if (map::contains_key(token_inner_map, &chain)) {
                let old_addr = map::borrow(token_inner_map, &chain).address;
                if (old_addr != utf8(b"0x0")) {
                    let old_rev_key = create_reverse_key(chain, old_addr);
                    if (map::contains_key(&tokens.reverse_map, &old_rev_key)) {
                        let (_, _) = map::remove(&mut tokens.reverse_map, &old_rev_key);
                    };
                };
            };

            map::upsert(token_inner_map, chain, TokenChainData { address: token_address, decimals });

            if (token_address != utf8(b"0x0")) {
                let rev_key = create_reverse_key(chain, token_address);
                map::upsert(&mut tokens.reverse_map, rev_key, copy full_name);
            };
            if (!string::is_empty(&nick_name)) {
                map::upsert(&mut tokens.nick_names, copy full_name, nick_name);
            };
        } else {
            if (!map::contains_key(&tokens.map, &full_name)) return;
            let token_inner_map = map::borrow_mut(&mut tokens.map, &full_name);
            if (!map::contains_key(token_inner_map, &chain)) return;

            let (_, data) = map::remove(token_inner_map, &chain);
            if (data.address != utf8(b"0x0")) {
                let rev_key = create_reverse_key(chain, data.address);
                if (map::contains_key(&tokens.reverse_map, &rev_key)) {
                    let (_, _) = map::remove(&mut tokens.reverse_map, &rev_key);
                };
            };
        };

        let nonce = Nonce::get_global_nonce_by_type(utf8(b"token_chain"));
        let action = if (is_add) utf8(b"Updated Token on Chain") else utf8(b"Removed Token on Chain");
        let event_data = vector[
            Event::create_data_struct(utf8(b"action_id"), utf8(b"u256"), bcs::to_bytes(&2u256)),
            Event::create_data_struct(utf8(b"chain"), utf8(b"string"), bcs::to_bytes(&chain)),
            Event::create_data_struct(utf8(b"is_add"), utf8(b"bool"), bcs::to_bytes(&is_add)),
            Event::create_data_struct(utf8(b"token"), utf8(b"string"), bcs::to_bytes(&nick_name)),
            Event::create_data_struct(utf8(b"nonce"), utf8(b"u256"), bcs::to_bytes(&nonce)),
            Event::create_data_struct(utf8(b"address"), utf8(b"string"), bcs::to_bytes(&token_address)),
        ];
        Event::emit_types_event(action, event_data);
    }

   public entry fun register_token_with_chains(signer: &signer,token: String,nick_name: String,token_addresses: vector<String>,chains: vector<String>,decimals: vector<u8>) acquires Tokens {
        assert!(signer::address_of(signer) == @dev, ERROR_NOT_AUTHORIZED);
        
        let len = vector::length(&chains);
        assert!(len == vector::length(&token_addresses) && len == vector::length(&decimals), ERORR_ARGUMENT_LENGHT_MISSMATCH);


        // 2. Storage write
        let tokens = borrow_global_mut<Tokens>(@dev);

        if (!map::contains_key(&tokens.map, &token)) {
            map::add(&mut tokens.map, copy token, map::new());
        };
        let token_entry = map::borrow_mut(&mut tokens.map, &token);
        let nonce = Nonce::get_global_nonce_by_type(utf8(b"token_chain"));
        while (!vector::is_empty(&chains)) {
            let chain = vector::pop_back(&mut chains);
            let addr = vector::pop_back(&mut token_addresses);
            let dec = vector::pop_back(&mut decimals);

            ChainTypes::ensure_valid_chain_name(chain);

            if (addr != utf8(b"0x0")) {
                let rev_key = create_reverse_key(copy chain, copy addr);
                map::upsert(&mut tokens.reverse_map, rev_key, copy token);
            };

            // 1. Emit single batch event before draining vectors (optimal: 0 clones, 1 event)
            let event_data = vector[
                Event::create_data_struct(utf8(b"action_id"), utf8(b"u256"), bcs::to_bytes(&2u256)),
                Event::create_data_struct(utf8(b"token"), utf8(b"string"), bcs::to_bytes(&nick_name)),
                Event::create_data_struct(utf8(b"nonce"), utf8(b"u256"), bcs::to_bytes(&nonce)),
                Event::create_data_struct(utf8(b"is_add"), utf8(b"bool"), bcs::to_bytes(&true)),
                Event::create_data_struct(utf8(b"chain"), utf8(b"string"), bcs::to_bytes(&chain)),
                Event::create_data_struct(utf8(b"address"), utf8(b"string"), bcs::to_bytes(&addr)),
            ];
            Event::emit_types_event(utf8(b"Added Token On Chain"), event_data);

            map::upsert(token_entry, chain, TokenChainData { address: addr, decimals: dec });
        };

        map::upsert(&mut tokens.nick_names, token, nick_name);
    }


    public entry fun test_emit_token_chain_event(is_add: bool,action: String,chain: String,token: String,nonce: u256,token_address: String,) {
        let event_data = vector[
            Event::create_data_struct(utf8(b"action"), utf8(b"string"), bcs::to_bytes(&action)),
            Event::create_data_struct(utf8(b"action_id"), utf8(b"u256"), bcs::to_bytes(&2u256)),
            Event::create_data_struct(utf8(b"chain"), utf8(b"string"), bcs::to_bytes(&chain)),
            Event::create_data_struct(utf8(b"token"), utf8(b"string"), bcs::to_bytes(&token)),
            Event::create_data_struct(utf8(b"nonce"), utf8(b"u256"), bcs::to_bytes(&nonce)),
            Event::create_data_struct(utf8(b"is_add"), utf8(b"bool"), bcs::to_bytes(&true)),
            Event::create_data_struct(utf8(b"address"), utf8(b"string"), bcs::to_bytes(&token_address)),
        ];
        Event::emit_types_event(action, event_data);
    }


// === INTERNAL HELPER FUNCTIONS === //
    fun resolve_full_token_name(token_or_nick: String): String acquires Tokens {
        let tokens = borrow_global<Tokens>(@dev);
        if (map::contains_key(&tokens.map, &token_or_nick)) {
            token_or_nick
        } else {
            convert_token_nickName_to_name(token_or_nick)
        }
    }

    fun create_reverse_key(chain: String, addr: String): String {
        string::append(&mut chain, addr);
        chain
    }

// === VIEW & LOOKUP FUNCTIONS === //
    #[view]
    public fun return_all_tokens(): Map<String, Map<String, TokenChainData>> acquires Tokens {
        borrow_global<Tokens>(@dev).map
    }

    #[view]
    public fun return_full_tokens_list(): vector<String> acquires Tokens {
        map::keys(&borrow_global<Tokens>(@dev).map)
    }

    #[view]
    public fun return_full_nick_names_list(): vector<String> acquires Tokens {
        map::values(&borrow_global<Tokens>(@dev).nick_names)
    }

    #[view]
    public fun return_full_nick_names(): Map<String, String> acquires Tokens {
        borrow_global<Tokens>(@dev).nick_names
    }

    public fun ensure_token_supported_for_chain(token: String, chain: String) acquires Tokens {
        let tokens = borrow_global<Tokens>(@dev);
        assert!(map::contains_key(&tokens.map, &token), ERROR_INVALID_TOKEN);
        let inner = map::borrow(&tokens.map, &token);
        assert!(map::contains_key(inner, &chain), ERROR_TOKEN_NOT_SUPPORTED_FOR_THIS_CHAIN);
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
        map::borrow(token_entry, &chain).address
    }

    #[view]
    public fun get_token_decimals(chain: String, name: String): u8 acquires Tokens {
        name = convert_token_nickName_to_name(name);
        let tokens = borrow_global<Tokens>(@dev);
        let token_entry = map::borrow(&tokens.map, &name);
        assert!(map::contains_key(token_entry, &chain), 404);
        map::borrow(token_entry, &chain).decimals
    }

    #[view]
    public fun get_token_data(chain: String, name: String): TokenChainData acquires Tokens {
        name = convert_token_nickName_to_name(name);
        let tokens = borrow_global<Tokens>(@dev);
        let token_entry = map::borrow(&tokens.map, &name);
        assert!(map::contains_key(token_entry, &chain), 404);
        *map::borrow(token_entry, &chain)
    }

    #[view]
    public fun get_token_all_chains_data(token_name_or_nickname: String): Map<String, TokenChainData> acquires Tokens {
        let full_name = resolve_full_token_name(token_name_or_nickname);
        let tokens = borrow_global<Tokens>(@dev);
        assert!(map::contains_key(&tokens.map, &full_name), ERROR_INVALID_TOKEN);
        *map::borrow(&tokens.map, &full_name)
    }

    #[view]
    public fun convert_token_nickName_to_name(nick_name: String): String acquires Tokens {
        let tokens = borrow_global<Tokens>(@dev);
        let vals = map::values(&tokens.nick_names);
        assert!(vector::contains(&vals, &nick_name), ERROR_INVALID_TOKEN);
        let symbol = utf8(TOKEN_PREFIX);
        string::append(&mut symbol, nick_name);
        symbol
    }

    #[view]
    public fun convert_token_name_to_nickName(token_name: String): String acquires Tokens {
        let tokens = borrow_global<Tokens>(@dev);
        assert!(map::contains_key(&tokens.nick_names, &token_name), ERROR_INVALID_TOKEN);
        *map::borrow(&tokens.nick_names, &token_name)
    }

    public fun ensure_valid_token_nick_name(token_name: String) acquires Tokens {
        let tokens = borrow_global<Tokens>(@dev);
        let vals = map::values(&tokens.nick_names);
        assert!(vector::contains(&vals, &token_name), ERROR_INVALID_TOKEN);
    }
}