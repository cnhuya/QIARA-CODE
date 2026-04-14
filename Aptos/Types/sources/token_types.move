module dev::QiaraTokenTypesV4 {
    use std::string::{Self as string, String, utf8};
    use std::vector;
    use std::signer;
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    use std::table::{Self, Table};

    use dev::QiaraChainTypesV4::{Self as ChainTypes};

    const TOKEN_PREFIX: vector<u8> = b"Qiara80 ";
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
        // Original: Token -> Chain -> Address
        map: Map<String, Map<String, String>>,
        // New: "ChainAddress" -> Token Name (Reverse Lookup)
        reverse_map: Map<String, String>, 
        nick_names: Map<String, String>,
    }

// === INIT === //
    fun init_module(admin: &signer) acquires Tokens{
        assert!(signer::address_of(admin) == @dev, 1);

        if (!exists<Tokens>(@dev)) {
            move_to(admin, Tokens { map: map::new<String, Map<String, String>>(), reverse_map: map::new<String, String>(), nick_names: map::new<String, String>() });
        };
        x_init(admin);
    }

    fun create_reverse_key(chain: String, addr: String): String {
        string::append(&mut chain, addr);
        chain
    }

    fun tttta(er: u64){
        abort er
    }

fun x_init(signer: &signer) acquires Tokens {
    // Qiara Token: 1 Real Address, 4 Placeholders
    register_token_with_chains(signer, utf8(b"Qiara80 Qiara"), utf8(b"Qiara"), 
        vector[utf8(b"0x8C9621E38f74c59b0B784894f12C0CD5bE8a2f02"), utf8(b"0x0"), utf8(b"0x0"), utf8(b"0x0"), utf8(b"0x0")], 
        vector[utf8(b"Sui"), utf8(b"Base"), utf8(b"Monad"), utf8(b"Ethereum"), utf8(b"Aptos")]
    );
    
    // USDC: Moved real address to index 1 (Base), index 0 (Sui) is now 0x0
    register_token_with_chains(signer, utf8(b"Qiara80 USDC"), utf8(b"USDC"), 
        vector[utf8(b"0x0"), utf8(b"0x0D5322Af414db3bd855cC44424F8532859469957"), utf8(b"0x0"), utf8(b"0x0"), utf8(b"0x0")], 
        vector[utf8(b"Sui"), utf8(b"Base"), utf8(b"Aptos"), utf8(b"Monad"), utf8(b"Ethereum")]
    );
    
    // USDT: 4 chains -> 4 placeholders
    register_token_with_chains(signer, utf8(b"Qiara80 USDT"), utf8(b"USDT"), 
        vector[utf8(b"0x0"), utf8(b"0x0"), utf8(b"0x0"), utf8(b"0x0")], 
        vector[utf8(b"Sui"), utf8(b"Base"), utf8(b"Aptos"), utf8(b"Ethereum")]
    );

    // USDT0, AUSD, earnAUSD: 2 chains -> 2 placeholders
    register_token_with_chains(signer, utf8(b"Qiara80 USDT0"), utf8(b"USDT0"), vector[utf8(b"0x0"), utf8(b"0x0")], vector[utf8(b"Monad"), utf8(b"Aptos")]);
    register_token_with_chains(signer, utf8(b"Qiara80 AUSD"), utf8(b"AUSD"), vector[utf8(b"0x0"), utf8(b"0x0")], vector[utf8(b"Monad"), utf8(b"Aptos")]);
    register_token_with_chains(signer, utf8(b"Qiara80 earnAUSD"), utf8(b"earnAUSD"), vector[utf8(b"0x0"), utf8(b"0x0")], vector[utf8(b"Monad"), utf8(b"Aptos")]);

    // Ethereum: 5 chains -> 5 placeholders
    register_token_with_chains(signer, utf8(b"Qiara80 Ethereum"), utf8(b"Ethereum"), 
        vector[utf8(b"0x0"), utf8(b"0x0"), utf8(b"0x0"), utf8(b"0x0"), utf8(b"0x0")], 
        vector[utf8(b"Sui"), utf8(b"Base"), utf8(b"Aptos"), utf8(b"Monad"), utf8(b"Ethereum")]
    );
    
    // Bitcoin: 5 chains -> 5 placeholders
    register_token_with_chains(signer, utf8(b"Qiara80 Bitcoin"), utf8(b"Bitcoin"),
        vector[utf8(b"0x0"), utf8(b"0x0"), utf8(b"0x0"), utf8(b"0x0"), utf8(b"0x0")], 
        vector[utf8(b"Sui"), utf8(b"Monad"), utf8(b"Ethereum"), utf8(b"Base"), utf8(b"Aptos")]
    );
    
    // Monad: 2 chains -> 2 placeholders
    register_token_with_chains(signer, utf8(b"Qiara80 Monad"), utf8(b"Monad"), vector[utf8(b"0x0"), utf8(b"0x0")], vector[utf8(b"Monad"), utf8(b"Aptos")]);
    
    // Aptos: 1 chain -> 1 placeholder
    register_token_with_chains(signer, utf8(b"Qiara80 Aptos"), utf8(b"Aptos"), 
        vector[utf8(b"0x0")], 
        vector[utf8(b"Aptos")]
    );
    
    // Sui & Deepbook: 2 chains -> 2 placeholders
    register_token_with_chains(signer, utf8(b"Qiara80 Sui"), utf8(b"Sui"), vector[utf8(b"0x0"), utf8(b"0x0")], vector[utf8(b"Sui"), utf8(b"Aptos")]);
    register_token_with_chains(signer, utf8(b"Qiara80 Deepbook"), utf8(b"Deepbook"), vector[utf8(b"0x0"), utf8(b"0x0")], vector[utf8(b"Sui"), utf8(b"Aptos")]);
    
    // Virtuals: 3 chains -> 3 placeholders
    register_token_with_chains(signer, utf8(b"Qiara80 Virtuals"), utf8(b"Virtuals"), 
        vector[utf8(b"0x0"), utf8(b"0x0"), utf8(b"0x0")], 
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
            // Only index it if the address is not a placeholder (0x0)
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

        // 2. REVERSE SEARCH UPDATE
        // Create a unique key using Chain + Address
        let rev_key = create_reverse_key(chain, token_address);
        map::upsert(&mut tokens.reverse_map, rev_key, token);

        // 3. Nickname Update
        map::upsert(&mut tokens.nick_names, token, nick_name);
    }

    #[view]
    public fun return_all_tokens(): Map<String, Map<String, String>> acquires Tokens{
        borrow_global_mut<Tokens>(@dev).map
    }

    #[view]
    public fun return_full_tokens_list(): vector<String> acquires Tokens{
        let tokens = borrow_global_mut<Tokens>(@dev);
        map::keys(&tokens.map)
    }

    #[view]
    public fun return_full_nick_names_list(): vector<String> acquires Tokens{
        let tokens = borrow_global_mut<Tokens>(@dev);
        map::values(&tokens.nick_names)
    }

    #[view]
    public fun return_full_nick_names(): Map<String, String> acquires Tokens{
        borrow_global_mut<Tokens>(@dev).nick_names
    }

    public fun ensure_token_supported_for_chain(token: String, chain: String) acquires Tokens{
        let tokens = borrow_global_mut<Tokens>(@dev);

        if (!map::contains_key(&tokens.map, &token)) {
            abort ERROR_INVALID_TOKEN
        };
    }

    // Define constants at the module level
    
    #[view]
    public fun get_token_name_from_address(chain: String, addr: String): String acquires Tokens {
        let tokens = borrow_global<Tokens>(@dev);
        let rev_key = create_reverse_key(chain, addr);
        
        assert!(map::contains_key(&tokens.reverse_map, &rev_key), 404); // Error if not found
        convert_token_name_to_nickName(*map::borrow(&tokens.reverse_map, &rev_key))
    }

    #[view]
    public fun get_token_address_from_name(chain: String, name: String): String acquires Tokens {
        name = convert_token_nickName_to_name(name);
        let tokens = borrow_global<Tokens>(@dev);
        let token_entry = map::borrow(&tokens.map, &name);
        assert!(map::contains_key(token_entry, &chain), 404); // Error if not found
        *map::borrow(token_entry, &chain)
    }

    #[view]
    public fun convert_token_nickName_to_name(nick_name: String): String acquires Tokens{
        
        let tokens = borrow_global_mut<Tokens>(@dev);

        let nick_names = map::values(&tokens.nick_names);
        assert!(vector::contains(&nick_names, &nick_name), ERROR_INVALID_TOKEN);
       // if (!map::contains_key(&tokens.nick_names, &nick_name)) {
       //     abort ERROR_INVALID_TOKEN
       // };

        let len = vector::length(&nick_names);
        while(len>0){
            let name = vector::borrow(&nick_names, len-1);
            if(*name == nick_name){
                let symbol = string::utf8(TOKEN_PREFIX);
                string::append_utf8(&mut symbol, *string::bytes(vector::borrow(&nick_names, len-1)));

                return symbol
            };
        len=len-1;
        }; 
        abort ERROR_INVALID_TOKEN
    }
    #[view]
    public fun convert_token_name_to_nickName(token_name: String): String acquires Tokens{
        
        let tokens = borrow_global_mut<Tokens>(@dev);

        let names = map::keys(&tokens.nick_names);
        let nick_names = map::values(&tokens.nick_names);
        assert!(vector::contains(&names, &token_name), ERROR_INVALID_TOKEN);
        let len = vector::length(&names);
        while(len>0){
            let name = vector::borrow(&names, len-1);
            if(*name == token_name){
                return *vector::borrow(&nick_names, len-1);
            };
        len=len-1;
        };
        abort ERROR_INVALID_TOKEN
    }

    public fun ensure_valid_token_nick_name(token_name: String) acquires Tokens{
        let tokens = borrow_global_mut<Tokens>(@dev);

        let names = map::values(&tokens.nick_names);
        assert!(vector::contains(&names, &token_name), ERROR_INVALID_TOKEN);
    }
}
