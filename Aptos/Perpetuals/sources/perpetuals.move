module dev::QiaraPerpsV1{
    use std::signer;
    use std::string::{Self as String, String, utf8};
    use std::vector;
    use std::table;
    use std::timestamp;
    use std::bcs;
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};

    use dev::QiaraMarginV17::{Self as Margin, Access as MarginAccess};
    use dev::QiaraRIV17::{Self as RI};
    use event::QiaraEventV1::{Self as Event};
    use dev::QiaraTokensMetadataV20::{Self as TokensMetadata, VMetadata};

    use dev::QiaraSharedV6::{Self as Shared};
    use dev::QiaraTokenTypesV20::{Self as TokensTypes};
    use dev::QiaraNonceV2::{Self as Nonce, Access as NonceAccess};
    use dev::QiaraVaultsV19::{Self as Market, Access as MarketAccess};

// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_MARKET_ALREADY_EXISTS: u64 = 2;
    const ERROR_LEVERAGE_TOO_LOW: u64 = 3;
    const ERROR_SENDER_DOESNT_MATCH_SIGNER: u64 = 4;
    const ERROR_UNKNOWN_PERP_TYPE: u64 = 5;

// === ACCESS === //
    struct Access has store, key, drop {}
    struct Permission has key, drop {}

    public fun give_access(s: &signer): Access {
        assert!(signer::address_of(s) == @dev, ERROR_NOT_ADMIN);
        Access {}
    }

    public fun give_permission(access: &Access): Permission {
        Permission {}
    }

/// === STRUCTS ===

    struct Permissions has key {
        margin: MarginAccess,
        market: MarketAccess,
    }

    struct Funding has store, key, drop, copy{
        rate: u128,
        previous_rate: u128,
        is_positive: bool
    }

    struct Asset has store, key, drop{
        asset: String,
        shorts: u256,
        longs: u256,
        long_interest_index: u128,
        short_interest_index: u128,
        long_funding_index: u128,
        short_funding_index: u128,
        leverage: u32,
        funding: Funding,
        last_trade: u64,
        avg_long_entry: u128,                      // Added for global long health tracking
        avg_short_entry: u128                       // Added for global short health tracking
    }
    
    struct ViewAsset has store, key{
        asset: String,
        shorts: u128,
        longs: u128,
        oi: u128,
        long_interest_index: u128,
        short_interest_index: u128,
        long_funding_index: u128,
        short_funding_index: u128,
        leverage: u32,
        utilization: u64,
        price: u128,
        denom: u128,
        funding: Funding,
        last_trade: u64
    }

    struct Position has copy, drop, store, key {
        size: u64,
        entry_price: u128,
        isLong: bool,
        leverage: u32,
        last_update: u64,
        interest_index: u256,
        reserve_chain: String,
        reserve_provider: String,
        reserve_token: String
    }

    struct ViewPosition has copy, drop, store, key {
        asset: String,
        used_margin: u256,
        usd_size: u256,
        size: u64,
        entry_price: u128,
        price: u256,
        isLong: bool,
        type_name: String,
        leverage: u32,
        pnl: u256,
        is_profit: bool,
        denom: u256,
        profit_fee: u64,
        last_update: u64
    }

    struct AssetBook has key, store {
        book: Map<String, Asset>,
    }

    struct UserBook has key, store {
        book: table::Table<String, Map<String, Position>>,
    }


/// === INIT ===
    fun init_module(admin: &signer) acquires Markets, AssetBook{

        if (!exists<AssetBook>(@dev)) {
            move_to(admin, AssetBook { book: map::new<String, Asset>()});
        };

        if (!exists<UserBook>(@dev)) {
            move_to(admin, UserBook { book: table::new<String, Map<String, Position>>()});
        };

        if (!exists<Permissions>(@dev)) {
            move_to(admin, Permissions { margin: Margin::give_access(admin), market: Market::give_access(admin),});
        };

        create_market(admin, utf8(b"Bitcoin"));
        create_market(admin, utf8(b"Ethereum"));
        create_market(admin, utf8(b"Sui"));
        create_market(admin, utf8(b"Monad"));
        create_market(admin, utf8(b"Virtuals"));
        create_market(admin, utf8(b"Aptos"));
        create_market(admin, utf8(b"Deepbook"));

    }


/// === ENTRY FUNCTIONS ===
    public entry fun create_market(admin: &signer, name: String) acquires Markets, AssetBook{
        TokensTypes::ensure_valid_token_nick_name(name);

        let asset_book = borrow_global_mut<AssetBook>(@dev);

        if (!map::contains_key(&asset_book.book, &name)) {
            map::upsert(&mut asset_book.book, name, Asset { 
                asset: name,
                shorts: 0,
                longs: 0,
                long_interest_index: 1000000000000, // Starts at 1.0 (1e12 scale)
                short_interest_index: 1000000000000, // Starts at 1.0 (1e12 scale)
                long_funding_index: 0,
                short_funding_index: 0,
                leverage: 0,
                funding: Funding { rate: 0, previous_rate: 0, is_positive: true },
                last_trade: timestamp::now_seconds(),
                avg_long_entry: 0,
                avg_short_entry: 0
            });
        };

        let markets = borrow_global_mut<Markets>(@dev);
        assert!(!vector::contains(&markets.list, &name),ERROR_MARKET_ALREADY_EXISTS);
        vector::push_back(&mut markets.list, name);
    }

    fun find_position(shared: String, name:String, user_book: &mut UserBook): &mut Position {
        if (!table::contains(&user_book.book, shared)) {
            table::add(&mut user_book.book, shared, map::new<String, Position>());
        };

        let user_map = table::borrow_mut(&mut user_book.book, shared);
        if(!map::contains_key(user_map, &name)){
            map::upsert(user_map, name, Position {
                size: 0,
                entry_price: 0,
                type: 0,
                leverage: 0,
                last_update: 0,
                entry_interest_index: 0,
                reserve_chain: utf8(b""),
                reserve_provider: utf8(b""),
                reserve_token: utf8(b"")
            });
        };

        map::borrow_mut(user_map, &name)
    }

    fun find_asset(asset: String, asset_book: &mut AssetBook): &mut Asset {
        map::borrow_mut(&mut asset_book.book, &asset)
    }


    // Native Interface
        public entry fun trade_limit(signer: &signer, user: vector<u8>, desired_price: u256, shared: String, asset: String, size:u256, leverage: u64, type: u8) {
            assert!(bcs::to_bytes(&signer::address_of(signer)) == user, ERROR_SENDER_DOESNT_MATCH_SIGNER);
            Shared::assert_is_sub_owner(shared, user);
            assert!(leverage >= 100, ERROR_LEVERAGE_TOO_LOW);

            let nonce = Nonce::return_user_nonce_by_type(user, utf8(b"native"));
            let identifier = Event::create_identifier(user, utf8(b"native"), bcs::to_bytes(&nonce));

            let data = vector[
                Event::create_data_struct(utf8(b"shared"), utf8(b"string"), bcs::to_bytes(&shared)),
                Event::create_data_struct(utf8(b"type"), utf8(b"string"), bcs::to_bytes(&convert_perp_type_to_name(type))),
                Event::create_data_struct(utf8(b"size"), utf8(b"u256"), bcs::to_bytes(&size)),
                Event::create_data_struct(utf8(b"leverage"), utf8(b"u64"), bcs::to_bytes(&leverage)),
                Event::create_data_struct(utf8(b"asset"), utf8(b"string"), bcs::to_bytes(&asset)),
                Event::create_data_struct(utf8(b"desired_price"), utf8(b"u256"), bcs::to_bytes(&desired_price)),
                Event::create_data_struct(utf8(b"nonce"), utf8(b"u256"), bcs::to_bytes(&nonce)),
                Event::create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"),identifier),
            ];

            Event::emit_automated_event(utf8(b"perps"), data);
        }

        public entry fun trade_util(signer: &signer, user: vector<u8>, shared: String, asset: String, size:u256, leverage: u64, type:String) acquires Permissions, AssetBook, UserBook{
            assert!(bcs::to_bytes(&signer::address_of(signer)) == user, ERROR_SENDER_DOESNT_MATCH_SIGNER);
            Shared::assert_is_sub_owner(shared, user);
            
            let position = find_position(shared, asset, borrow_global_mut<UserBook>(@dev));
            let asset_book = borrow_global_mut<AssetBook>(@dev);
            let price = TokensMetadata::get_coin_metadata_price(&TokensMetadata::get_coin_metadata_by_symbol(asset)); 

            if(type == utf8(b"flip") && (position.type == 1)){
                let (size_diff_usd, is_profit) = calculate_position(@0x0,  asset, shared, asset_book,position, size*2, leverage, 2, (price as u128), user);
                handle_pnl(asset, size_diff_usd, is_profit, user,shared );
            } else if(type == utf8(b"flip") && (position.type == 2)){
                let (size_diff_usd, is_profit) = calculate_position(@0x0, asset, shared, asset_book,position, size*2, leverage, 1, (price as u128), user);
                handle_pnl(asset, size_diff_usd, is_profit, user,shared );
            } else if(type == utf8(b"close") && (position.type == 2)){
                let (size_diff_usd, is_profit) = calculate_position(@0x0, asset, shared, asset_book,position, size, leverage, 1, (price as u128), user);
                handle_pnl(asset, size_diff_usd, is_profit, user,shared );
            } else if(type == utf8(b"close") && (position.type == 1)){
                let (size_diff_usd, is_profit) = calculate_position(@0x0,asset,shared, asset_book,position, size, leverage, 2, (price as u128), user);
                handle_pnl(asset, size_diff_usd, is_profit, user,shared );
            } else if(type == utf8(b"double") && (position.type == 1)){
                let (size_diff_usd, is_profit) = calculate_position(@0x0,asset, shared,asset_book,position, size, leverage, 1, (price as u128), user);
                handle_pnl(asset, size_diff_usd, is_profit, user,shared );
            } else if(type == utf8(b"double") && (position.type == 2)){
                let (size_diff_usd, is_profit) = calculate_position(@0x0, asset, shared,asset_book,position, size, leverage, 2, (price as u128), user);
                handle_pnl(asset, size_diff_usd, is_profit, user,shared );
            };
        }

        public entry fun trade(signer: &signer, user: vector<u8>, reserve_chain: String, reserve_provider: String, reserve_token: String, shared: String, chain:String, provider: String, asset: String, size:u256, leverage: u64, type: u8) acquires UserBook, AssetBook, Permissions {
            assert!(bcs::to_bytes(&signer::address_of(signer)) == user, ERROR_SENDER_DOESNT_MATCH_SIGNER);
            Shared::assert_is_sub_owner(shared, user);

            let position = find_position(shared, asset, borrow_global_mut<UserBook>(@dev));
            let asset_book = borrow_global_mut<AssetBook>(@dev);
            let price = TokensMetadata::get_coin_metadata_price(&TokensMetadata::get_coin_metadata_by_symbol(asset));
            assert!(leverage >= 100, ERROR_LEVERAGE_TOO_LOW);

            let (size_diff_usd, is_profit) = calculate_position(@0x0, asset, shared, asset_book,position, size, leverage, type, (price as u128), user);
            handle_pnl(asset, size_diff_usd, is_profit, user,shared );

        }

    // Permissionless Interface
        public fun p_trade_limit(validator: &signer, user: vector<u8>, shared: String,  chain:String, provider: String, asset: String, size:u256, leverage: u64,type: u8, desired_price: u256, perm: Permission){
            Shared::assert_is_sub_owner(shared, user);
            assert!(leverage >= 100, ERROR_LEVERAGE_TOO_LOW);

            let data = vector[
                Event::create_data_struct(utf8(b"validator"), utf8(b"address"), bcs::to_bytes(&signer::address_of(validator))),
                Event::create_data_struct(utf8(b"shared"), utf8(b"string"), bcs::to_bytes(&shared)),
                Event::create_data_struct(utf8(b"type"), utf8(b"string"), bcs::to_bytes(&convert_perp_type_to_name(type))),
                Event::create_data_struct(utf8(b"size"), utf8(b"u256"), bcs::to_bytes(&size)),
                Event::create_data_struct(utf8(b"leverage"), utf8(b"u64"), bcs::to_bytes(&leverage)),
                Event::create_data_struct(utf8(b"asset"), utf8(b"string"), bcs::to_bytes(&asset)),
                Event::create_data_struct(utf8(b"desired_price"), utf8(b"u256"), bcs::to_bytes(&desired_price)),
            ];

            Event::emit_automated_event(utf8(b"perps"), data);
        }

        public fun p_trade_util(validator: &signer,user: vector<u8>, shared: String,  chain:String, provider: String, asset: String, size:u256, leverage: u64, type:String, perm: Permission) acquires Permissions, AssetBook, UserBook{
            Shared::assert_is_sub_owner(shared, user);
            
            let position = find_position(shared, asset, borrow_global_mut<UserBook>(@dev));
            let asset_book = borrow_global_mut<AssetBook>(@dev);
            let price = TokensMetadata::get_coin_metadata_price(&TokensMetadata::get_coin_metadata_by_symbol(asset)); 

            if(type == utf8(b"flip") && (position.type == 1)){
                let (size_diff_usd, is_profit) = calculate_position(@0x0, asset, shared,asset_book,position, size*2, leverage, 2, (price as u128), user);
                handle_pnl(asset, size_diff_usd, is_profit, user,shared );
            } else if(type == utf8(b"flip") && (position.type == 2)){
                let (size_diff_usd, is_profit) = calculate_position(@0x0, asset, shared,asset_book,position, size*2, leverage, 1, (price as u128), user);
                handle_pnl(asset, size_diff_usd, is_profit, user,shared );
            } else if(type == utf8(b"close") && (position.type == 2)){
                let (size_diff_usd, is_profit) = calculate_position(@0x0, asset, shared,asset_book,position, size, leverage, 1, (price as u128), user);
                handle_pnl(asset, size_diff_usd, is_profit, user,shared );
            } else if(type == utf8(b"close") && (position.type == 1)){
                let (size_diff_usd, is_profit) = calculate_position(@0x0, asset, shared,asset_book,position, size, leverage, 2, (price as u128), user);
                handle_pnl(asset, size_diff_usd, is_profit, user,shared );
            } else if(type == utf8(b"double") && (position.type == 1)){
                let (size_diff_usd, is_profit) = calculate_position(@0x0, asset, shared,asset_book,position, size, leverage, 1, (price as u128), user);
                handle_pnl(asset, size_diff_usd, is_profit, user,shared );
            } else if(type == utf8(b"double") && (position.type == 2)){
                let (size_diff_usd, is_profit) = calculate_position(@0x0, asset, shared,asset_book,position, size, leverage, 2, (price as u128), user);
                handle_pnl(asset, size_diff_usd, is_profit, user,shared );
            };
        }

        public fun p_trade(validator: &signer,user: vector<u8>, shared: String,  chain:String, provider: String, asset: String, size:u256, leverage: u64, limit: u256, type: u8, perm: Permission) acquires UserBook, AssetBook, Permissions {
            Shared::assert_is_sub_owner(shared, user);

            let position = find_position(shared, asset, borrow_global_mut<UserBook>(@dev));

            let asset_book = borrow_global_mut<AssetBook>(@dev);
            let price = TokensMetadata::get_coin_metadata_price(&TokensMetadata::get_coin_metadata_by_symbol(asset));
            assert!(leverage >= 100, ERROR_LEVERAGE_TOO_LOW);

            let (size_diff_usd, is_profit) = calculate_position(@0x0, asset, shared, asset_book,position, size, leverage, type, (price as u128), user);
            handle_pnl(asset, size_diff_usd, is_profit, user,shared );

        }


/// === HELPER FUNCTIONS ===
    fun handle_pnl(asset: String, pnl: u256, is_profit: bool, sub_owner: vector<u8>, shared: String) acquires Permissions {
        if (pnl == 0) { 
            return; 
        };
        if (is_profit) {
            Margin::add_credit(shared,sub_owner, pnl, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        } else {
            Margin::remove_credit(shared,sub_owner, pnl, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        };
    }

    fun calculate_position(validator: address, assetName: String, shared: String, asset_book: &mut AssetBook,position: &mut Position,added_size: u256,leverage: u64,type: u8,oracle_price: u128, user: vector<u8>): (u256, bool)  {
        let asset = find_asset(assetName, asset_book);
        let curr_size: u256 = (position.size as u256);
        let add_size: u256 = (added_size as u256);
        let lev: u256 = (leverage as u256);
        let price: u256 = (oracle_price as u256);
        
        // Case 1: No existing position - open new
        if (position.size == 0) {
            position.size = added_size;
            position.leverage = leverage;
            position.type = type;
            position.entry_price = price;
            
            // Set entry index based on user's direction
            let current_interest_index = if (type == 1) { asset.long_interest_index } else { asset.short_interest_index };
            position.entry_interest_index = current_interest_index;
            position.last_update = timestamp::now_seconds();

            // Update asset tracking (and dynamically update the global interest rate indices)
            update_asset_leverage(asset, add_size, lev, type, true, price);
            
            let data = vector[
                        Event::create_data_struct(utf8(b"validator"), utf8(b"string"), bcs::to_bytes(&validator)),
                        Event::create_data_struct(utf8(b"shared"), utf8(b"string"), bcs::to_bytes(&shared)),
                        Event::create_data_struct(utf8(b"type"), utf8(b"string"), bcs::to_bytes(&convert_perp_type_to_name(type))),
                        Event::create_data_struct(utf8(b"size"), utf8(b"u256"), bcs::to_bytes(&added_size)),
                        Event::create_data_struct(utf8(b"leverage"), utf8(b"u64"), bcs::to_bytes(&leverage)),
                        Event::create_data_struct(utf8(b"used_margin"), utf8(b"u64"), bcs::to_bytes(&((added_size/lev)*100))),
                        Event::create_data_struct(utf8(b"asset"), utf8(b"string"), bcs::to_bytes(&assetName)),
                        Event::create_data_struct(utf8(b"entry_price"), utf8(b"u256"), bcs::to_bytes(&price)),
                        Event::create_data_struct(utf8(b"fee"), utf8(b"u256"), bcs::to_bytes(&0)),
                    ];
            Event::emit_perps_event(utf8(b"Open Position"), data);
            return (0, true);
        };

        let curr_lev: u256 = (position.leverage as u256);
        let curr_price: u256 = (position.entry_price as u256);
        let weighted_curr_lev = curr_size * curr_lev;
        let weighted_curr_price = curr_size * curr_price;

        // Case 2: Same direction - add exposure (Realize interest up to this point first)
        if (position.type == type) {
            let weighted_new_lev = add_size * lev;
            let weighted_new_price = add_size * price;

            let new_size = curr_size + add_size;
            let new_leverage = (weighted_curr_lev + weighted_new_lev) / new_size;
            let new_price = (weighted_curr_price + weighted_new_price) / new_size;

            // Compute accumulated interest on the existing portion before updating the position variables
            let current_interest_index = if (type == 1) { asset.long_interest_index } else { asset.short_interest_index };
            let (interest_pnl, is_profit) = calculate_and_deduct_interest(position, current_interest_index, 0, true, curr_size);

            position.size = new_size;
            position.leverage = (new_leverage as u64);
            position.entry_price = (new_price as u256);
            
            // Restart the interest index clock with the new snapshot
            position.entry_interest_index = current_interest_index;
            position.last_update = timestamp::now_seconds();

            // Update asset tracking
            update_asset_leverage(asset, add_size, lev, type, true, price);
            
            let data = vector[
                        Event::create_data_struct(utf8(b"validator"), utf8(b"string"), bcs::to_bytes(&validator)),
                        Event::create_data_struct(utf8(b"shared"), utf8(b"string"), bcs::to_bytes(&shared)),
                        Event::create_data_struct(utf8(b"type"), utf8(b"string"), bcs::to_bytes(&convert_perp_type_to_name(type))),
                        Event::create_data_struct(utf8(b"size"), utf8(b"u256"), bcs::to_bytes(&added_size)),
                        Event::create_data_struct(utf8(b"leverage"), utf8(b"u64"), bcs::to_bytes(&leverage)),
                        Event::create_data_struct(utf8(b"used_margin"), utf8(b"u64"), bcs::to_bytes(&((added_size/lev)*100))),
                        Event::create_data_struct(utf8(b"asset"), utf8(b"string"), bcs::to_bytes(&assetName)),
                        Event::create_data_struct(utf8(b"entry_price"), utf8(b"u256"), bcs::to_bytes(&price)),
                        Event::create_data_struct(utf8(b"fee"), utf8(b"u256"), bcs::to_bytes(&0)),
                    ];
            Event::emit_perps_event(utf8(b"Add Size"), data);
            
            // Realize interest deduction on the old size
            return (interest_pnl, is_profit) 
        };

        // Case 3: Opposite direction - reduce or flip
        if (add_size >= curr_size) {
            // Closing entire position (and maybe flipping)
            let closed_size = curr_size;
            let (pnl, is_profit) = calculate_pnl(position.type, curr_price, price, closed_size);
            
            // Settle interest accrued on the entire closed position
            let current_interest_index = if (position.type == 1) { asset.long_interest_index } else { asset.short_interest_index };
            let (final_pnl, final_is_profit) = calculate_and_deduct_interest(position, current_interest_index, pnl, is_profit, closed_size);

            // Remove entire old position from asset tracking
            update_asset_leverage(asset, curr_size, curr_lev, position.type, false, price);
            
            // Now flip into new side if there's remaining size
            let remaining_size = add_size - curr_size;
            if (remaining_size > 0) {
                position.size = remaining_size;
                position.leverage = leverage;
                position.type = type;
                position.entry_price = price;
                
                // Track interest snapshot of the new flipped direction
                let current_interest_index_new = if (type == 1) { asset.long_interest_index } else { asset.short_interest_index };
                position.entry_interest_index = current_interest_index_new;
                position.last_update = timestamp::now_seconds();
                
                // Add new position to asset tracking
                update_asset_leverage(asset, remaining_size, lev, type, true, price);
                
                let data = vector[
                            Event::create_data_struct(utf8(b"validator"), utf8(b"string"), bcs::to_bytes(&validator)),
                            Event::create_data_struct(utf8(b"shared"), utf8(b"string"), bcs::to_bytes(&shared)),
                            Event::create_data_struct(utf8(b"type"), utf8(b"string"), bcs::to_bytes(&convert_perp_type_to_name(type))),
                            Event::create_data_struct(utf8(b"size"), utf8(b"u256"), bcs::to_bytes(&added_size)),
                            Event::create_data_struct(utf8(b"leverage"), utf8(b"u64"), bcs::to_bytes(&leverage)),
                            Event::create_data_struct(utf8(b"used_margin"), utf8(b"u64"), bcs::to_bytes(&((added_size/lev)*100))),
                            Event::create_data_struct(utf8(b"asset"), utf8(b"string"), bcs::to_bytes(&assetName)),
                            Event::create_data_struct(utf8(b"entry_price"), utf8(b"u256"), bcs::to_bytes(&price)),
                            Event::create_data_struct(utf8(b"fee"), utf8(b"u256"), bcs::to_bytes(&0)),
                        ];
                Event::emit_perps_event(utf8(b"Reduce & Flip Side"), data);
            } else {
                // Fully closed, no new position
                position.size = 0;
                position.leverage = 0;
                position.entry_price = 0;
                position.entry_interest_index = 0;
                position.last_update = 0;

                let data = vector[
                            Event::create_data_struct(utf8(b"validator"), utf8(b"string"), bcs::to_bytes(&validator)),
                            Event::create_data_struct(utf8(b"shared"), utf8(b"string"), bcs::to_bytes(&shared)),
                            Event::create_data_struct(utf8(b"type"), utf8(b"string"), bcs::to_bytes(&convert_perp_type_to_name(type))),
                            Event::create_data_struct(utf8(b"size"), utf8(b"u256"), bcs::to_bytes(&added_size)),
                            Event::create_data_struct(utf8(b"leverage"), utf8(b"u64"), bcs::to_bytes(&leverage)),
                            Event::create_data_struct(utf8(b"used_margin"), utf8(b"u64"), bcs::to_bytes(&((added_size/lev)*100))),
                            Event::create_data_struct(utf8(b"asset"), utf8(b"string"), bcs::to_bytes(&assetName)),
                            Event::create_data_struct(utf8(b"entry_price"), utf8(b"u256"), bcs::to_bytes(&price)),
                            Event::create_data_struct(utf8(b"fee"), utf8(b"u256"), bcs::to_bytes(&0)),
                        ];
                Event::emit_perps_event(utf8(b"Close"), data);
            };

            return (final_pnl, final_is_profit)
        } else {
            // Partial close
            let closed_size = add_size;
            let (pnl, is_profit) = calculate_pnl(position.type, curr_price, price, closed_size);

            // Compute and settle interest on the closed portion only
            let current_interest_index = if (position.type == 1) { asset.long_interest_index } else { asset.short_interest_index };
            let (final_pnl, final_is_profit) = calculate_and_deduct_interest(position, current_interest_index, pnl, is_profit, closed_size);

            position.size = (curr_size - add_size);
            position.last_update = timestamp::now_seconds();

            // Remove closed portion from asset tracking
            update_asset_leverage(asset, closed_size, curr_lev, position.type, false, price);

            let data = vector[
                        Event::create_data_struct(utf8(b"validator"), utf8(b"string"), bcs::to_bytes(&validator)),
                        Event::create_data_struct(utf8(b"shared"), utf8(b"string"), bcs::to_bytes(&shared)),
                        Event::create_data_struct(utf8(b"type"), utf8(b"string"), bcs::to_bytes(&convert_perp_type_to_name(type))),
                        Event::create_data_struct(utf8(b"size"), utf8(b"u256"), bcs::to_bytes(&added_size)),
                        Event::create_data_struct(utf8(b"leverage"), utf8(b"u64"), bcs::to_bytes(&leverage)),
                        Event::create_data_struct(utf8(b"used_margin"), utf8(b"u64"), bcs::to_bytes(&((added_size/lev)*100))),
                        Event::create_data_struct(utf8(b"asset"), utf8(b"string"), bcs::to_bytes(&assetName)),
                        Event::create_data_struct(utf8(b"entry_price"), utf8(b"u256"), bcs::to_bytes(&price)),
                        Event::create_data_struct(utf8(b"fee"), utf8(b"u256"), bcs::to_bytes(&0)),
                    ];
            Event::emit_perps_event(utf8(b"Partial Close"), data);
            
            return (final_pnl, final_is_profit)
        }

    }

    fun update_asset_leverage(asset: &mut Asset,size: u256,leverage: u256,type: u8,is_add: bool, price: u256) {
        let now = timestamp::now_seconds();
        
        // Dynamically update the continuous interest indexes using the elapsed time up to this trade
        update_global_interest_indices(asset, (price as u128), now);

        if (type == 1) {
            if (is_add) {
                // Adding to longs: Update weighted leverage and global entry price
                let current_weighted_lev = asset.longs * (asset.leverage as u256);
                let new_weighted_lev = current_weighted_lev + (size * leverage);
                
                let current_weighted_entry = asset.longs * asset.avg_long_entry;
                asset.longs = asset.longs + size;
                asset.leverage = ((new_weighted_lev / asset.longs) as u64);
                asset.avg_long_entry = (current_weighted_entry + (size * (price as u128))) / asset.longs;
            } else {
                // Removing from longs
                let current_weighted_lev = asset.longs * (asset.leverage as u256);
                let removed_weighted_lev = size * leverage;
                
                // Prevent underflow
                if (asset.longs >= size) {
                    asset.longs = asset.longs - size;
                    if (asset.longs > 0) {
                        asset.leverage = (((current_weighted_lev - removed_weighted_lev) / asset.longs) as u64);
                    } else {
                        asset.leverage = 0;
                        asset.avg_long_entry = 0;
                    }
                };
            }
        } else {
            if (is_add) {
                // Adding to shorts: Update weighted leverage and global entry price
                let current_weighted_lev = asset.shorts * (asset.leverage as u256);
                let new_weighted_lev = current_weighted_lev + (size * leverage);
                
                let current_weighted_entry = asset.shorts * asset.avg_short_entry;
                asset.shorts = asset.shorts + size;
                asset.leverage = ((new_weighted_lev / asset.shorts) as u64);
                asset.avg_short_entry = (current_weighted_entry + (size * (price as u128))) / asset.shorts;
            } else {
                // Removing from shorts
                let current_weighted_lev = asset.shorts * (asset.leverage as u256);
                let removed_weighted_lev = size * leverage;
                
                // Prevent underflow
                if (asset.shorts >= size) {
                    asset.shorts = asset.shorts - size;
                    if (asset.shorts > 0) {
                        asset.leverage = (((current_weighted_lev - removed_weighted_lev) / asset.shorts) as u64);
                    } else {
                        asset.leverage = 0;
                        asset.avg_short_entry = 0;
                    }
                };
            }
        };

        let new_funding = calculate_funding(asset.longs, asset.shorts, 0, ((now - asset.last_trade) as u256), asset.funding.rate);
        asset.funding = new_funding;
    }

    fun calculate_pnl(type: u8, entry_price: u256, exit_price: u256, size: u256): (u256, bool) {
        if (type == 1) {
            if (exit_price >= entry_price) {
                ((exit_price - entry_price) * size, true)
            } else {
                ((entry_price - exit_price) * size, false)
            }
        } else {
            if (entry_price >= exit_price) {
                ((entry_price - exit_price) * size, true)
            } else {
                ((exit_price - entry_price) * size, false)
            }
        }
    }

    public fun estimate_pnl(position: &Position, current_price: u256): (u256, bool) {
        if (position.size == 0) {
            return (0, true)
        };

        let entry_price: u256 = (position.entry_price as u256);
        let size: u256 = (position.size as u256);

        if (position.type == 1) {
            if (current_price >= entry_price) {
                ((current_price - entry_price) * size, true)
            } else {
                ((entry_price - current_price) * size, false)
            }
        } else {
            if (entry_price >= current_price) {
                ((entry_price - current_price) * size, true)
            } else {
                ((current_price - entry_price) * size, false)
            }
        }
    }

/// === VIEW FUNCTIONS ===
    #[view]
    public fun get_positions(shared: String): Map<String, ViewPosition> acquires UserBook {
        let user_book = borrow_global_mut<UserBook>(@dev);
        let vect = map::new<String, ViewPosition>();

        if (!table::contains(&user_book.book, shared)) {
            return vect
        };

        let user_map = table::borrow_mut(&mut user_book.book, shared);
        let assets = map::keys(user_map);
        let len = vector::length(&assets);
        let i = 0;

        while (i < len) {
            let asset = vector::borrow(&assets, i);
            let position = get_position(*asset, shared);
            map::upsert(&mut vect, *asset, position);
            
            i = i + 1;
        };

        return vect
    }

    #[view]
    public fun get_position(asset:String, shared: String): ViewPosition acquires UserBook {
        let user_book = borrow_global_mut<UserBook>(@dev);

        let price = TokensMetadata::get_coin_metadata_price(&TokensMetadata::get_coin_metadata_by_symbol(asset));
        let denom = TokensMetadata::get_coin_metadata_denom(&TokensMetadata::get_coin_metadata_by_symbol(asset));

        if (!table::contains(&user_book.book, shared)) {
            return ViewPosition {type_name: utf8(b""), last_update: 0, asset: asset, used_margin: 0, usd_size: 0, size:0, entry_price:0, price: price, type:0, leverage:0, pnl: 0, is_profit: false, denom: denom, profit_fee: 0};
        };

        let user_map = table::borrow_mut(&mut user_book.book, shared);
        if(!map::contains_key(user_map, &asset)){
            return ViewPosition {type_name: utf8(b""), last_update: 0, asset: asset, used_margin: 0, usd_size: 0, size:0, entry_price:0, price: price, type:0, leverage:0, pnl: 0, is_profit: false, denom: denom, profit_fee: 0};
        };

        let position = map::borrow_mut(user_map, &asset);

        let (pnl, is_profit) = estimate_pnl(position, (price as u256));
        if(position.leverage == 0){
            position.leverage = 100;
        };
        ViewPosition {type_name: convert_perp_type_to_name(position.type), last_update: position.last_update, asset:asset, used_margin: ((position.size as u256)*(position.entry_price as u256) / (position.leverage as u256)), usd_size: (position.size as u256)*(position.entry_price as u256),  size: position.size , entry_price: position.entry_price, price: price, type:position.type, leverage:position.leverage, pnl: pnl, is_profit: is_profit, denom: denom, profit_fee: 0}
    }

    #[view]
    public fun get_market(asset: String): ViewAsset acquires AssetBook {
        let t = find_asset(asset, borrow_global_mut<AssetBook>(@dev));
        let price = TokensMetadata::get_coin_metadata_price(&TokensMetadata::get_coin_metadata_by_symbol(asset));
        let denom = TokensMetadata::get_coin_metadata_denom(&TokensMetadata::get_coin_metadata_by_symbol(asset));
        
        // Fixed: neutrophils placeholder compile error
        let oi = (t.shorts + t.longs) * price;
        ViewAsset { 
            last_trade: t.last_trade, 
            funding: t.funding, 
            asset: t.asset, 
            shorts: (t.shorts as u128), 
            longs: (t.longs as u128), 
            long_interest_index: t.long_interest_index,
            short_interest_index: t.short_interest_index,
            long_funding_index: t.long_funding_index,
            short_funding_index: t.short_funding_index,
            oi: (oi as u128), 
            leverage: t.leverage, 
            utilization: 0, 
            price: price, 
            denom: denom 
        }
    }

    #[view]
    public fun get_all_markets(): vector<ViewAsset> acquires Markets, AssetBook {
        let markets = borrow_global<Markets>(@dev);
        let len = vector::length(&markets.list);
        let vect = vector::empty<ViewAsset>();
        while(len>0){
            let market = vector::borrow(&markets.list, len-1);
            vector::push_back(&mut vect, get_market(*market));
            len=len-1;
        };
        vect
    }

    #[view]
    public fun calculateFunding(longs: u256, shorts: u256, neutrals: u256, last_update_sec: u256, previous_funding: u256): (Funding,u256,u256,u256,u256,u256) {
        let e18 = 1000000000000000000;
        let skewer = 900000;
        let scaler = 50;
        let weight = 200000000000;

        let is_positive = false;
        let gamma = 0;

        let longs_e18 = longs * e18;
        let shorts_e18 = shorts * e18;
        let neutrals_e18 = neutrals * e18;

        if(longs_e18 > shorts_e18){
            is_positive = true;
            gamma = (longs_e18 - shorts_e18);
        } else {
            is_positive = false;
            gamma = (shorts_e18 - longs_e18);
        };


        let previous_funding_e18 = previous_funding / 1000000;

        let total_liquidity_e18 = longs_e18 + shorts_e18 + neutrals_e18;

        let x = previous_funding_e18 * skewer;
        let y = gamma*e18 / total_liquidity_e18;
        let z = scaler * (weight + last_update_sec*1000000);

        let result = x + y * z;
        let funding = Funding { rate: result, previous_rate: previous_funding_e18, is_positive: is_positive };
        return (funding, x, y, z, 0,total_liquidity_e18)
    }
    
// === INTERNAL HELPER FUNCTIONS ===
    fun calculate_funding(longs: u256, shorts: u256, neutrals: u256, last_update_sec: u256, previous_funding: u256): Funding{
        let (funding,_,_,_,_,_) = calculateFunding(longs, shorts, neutrals, last_update_sec, previous_funding);
        return funding
    }

    /// Dynamically updates the global compounding interest indices based on direction and pool health.
    fun update_global_interest_indices(asset: &mut Asset, current_price: u128, now: u64) {
        let dt = now - asset.last_trade;
        if (dt > 0) {
            let base_rate: u128 = 250000000000; // 25% base borrow interest rate (1e12 scale)
            let long_rate = base_rate;
            let short_rate = base_rate;

            // If longs are collectively underwater (negative PnL): spike the long rate
            if (asset.avg_long_entry > 0 && current_price < asset.avg_long_entry) {
                let deviation = ((asset.avg_long_entry - current_price) as u128) * 1000000000000 / asset.avg_long_entry;
                long_rate = base_rate + deviation;
            };

            // If shorts are collectively underwater (negative PnL): spike the short rate
            if (asset.avg_short_entry > 0 && current_price > asset.avg_short_entry) {
                let deviation = ((current_price - asset.avg_short_entry) as u128) * 1000000000000 / asset.avg_short_entry;
                short_rate = base_rate + deviation;
            };

            // Accrue global indices
            let long_accrued = (long_rate / 31536000) * (dt as u128);
            let long_delta = (asset.long_interest_index * long_accrued) / 1000000000000;
            asset.long_interest_index = asset.long_interest_index + long_delta;

            let short_accrued = (short_rate / 31536000) * (dt as u128);
            let short_delta = (asset.short_interest_index * short_accrued) / 1000000000000;
            asset.short_interest_index = asset.short_interest_index + short_delta;

            asset.last_trade = now;
        };
    }

    /// Calculates and deducts the accrued interest on closed portion from the trade's profit/loss.
    fun calculate_and_deduct_interest(
        position: &Position, 
        current_interest_index: u128, 
        pnl: u256, 
        is_profit: bool, 
        closed_size: u256
    ): (u256, bool) {
        let entry_index = position.entry_interest_index;
        if (entry_index == 0) {
            entry_index = 1000000000000;
        };

        if (current_interest_index <= entry_index) {
            return (pnl, is_profit)
        };

        // Collateral (Used Margin) = Size * EntryPrice / Leverage
        let closed_collateral = (closed_size * (position.entry_price as u256)) / (position.leverage as u256);

        // Interest fee = Collateral * (CurrentIndex - EntryIndex) / EntryIndex
        let index_diff = current_interest_index - entry_index;
        let interest_fee = (closed_collateral * (index_diff as u256)) / (entry_index as u256);

        if (is_profit) {
            if (pnl >= interest_fee) {
                (pnl - interest_fee, true)
            } else {
                (interest_fee - pnl, false)
            }
        } else {
            (pnl + interest_fee, false)
        }
    }

    fun convert_perp_type_to_name(perp_type: u8): String {
        if (perp_type == 0) {
            return utf8(b"neutral")
        } else if (perp_type == 1) {
            return utf8(b"long")
        } else if (perp_type == 2) {
            return utf8(b"short")
        } else {
            abort ERROR_UNKNOWN_PERP_TYPE
        }
    }
}