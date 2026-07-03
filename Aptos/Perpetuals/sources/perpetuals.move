module dev::QiaraPerpsV20 {
    use std::signer;
    use std::string::{Self as String, String, utf8};
    use std::vector;
    use std::table;
    use std::timestamp;
    use std::bcs;
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};

    use dev::QiaraMarginV25::{Self as Margin, Access as MarginAccess};
    use dev::QiaraRIV25::{Self as RI};
    use dev::QiaraRanksV25::{Self as Ranks, Access as RanksAccess};
    use event::QiaraEventV1::{Self as Event};
    use dev::QiaraTokensMetadataV32::{Self as TokensMetadata, VMetadata, Access as TokensMetadataAccess};

    use dev::QiaraSharedV11::{Self as Shared, Access as SharedAccess};
    use dev::QiaraNonceV2::{Self as Nonce, Access as NonceAccess};
    use dev::QiaraVaultsV34::{Self as Market, Access as MarketAccess};

    use dev::QiaraLiquidityV37::{Self as Liquidity};
    use dev::QiaraTokenVaultsV37::{Self as TokenVaults, Access as TokenVaultsAccess};

    use dev::QiaraStorageV14::{Self as storage};
    use dev::QiaraCapabilitiesV14::{Self as capabilities};
    use dev::QiaraOracleV6::{Self as oracle};
    use dev::QiaraChainTypesV32::{Self as ChainTypes};
    use dev::QiaraTokenTypesV32::{Self as TokensTypes};

    use dev::QiaraGasV10::{Self as Gas, Access as GasAccess};

    use dev::QiaraPerpsOrdersV20::{Self as Orders};


// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_MARKET_ALREADY_EXISTS: u64 = 2;
    const ERROR_LEVERAGE_TOO_LOW: u64 = 3;
    const ERROR_SENDER_DOESNT_MATCH_SIGNER: u64 = 4;
    const ERROR_UNKNOWN_PERP_TYPE: u64 = 5;
    const ERROR_ZERO_SIZE: u64 = 7;
    const ERROR_SIZE_TOO_SMALL: u64 = 8;
    const ERROR_USD_SIZE_TOO_SMALL: u64 = 9;
    const ERROR_NOT_AUTHORIZED_FOR_ORDER_EXECUTION: u64 = 10;
    const ERROR_PRICE_NOT_SETTLED: u64 = 11;

// === ACCESS === //
    struct Access has store, key, drop {}
    struct Permission has key, drop {}

    public fun give_access(s: &signer): Access {
        assert!(signer::address_of(s) == @dev, ERROR_NOT_ADMIN);
        Access {}
    }

    public fun give_permission(_access: &Access): Permission {
        Permission {}
    }

/// === STRUCTS ===

    struct Permissions has key {
        margin: MarginAccess,
        metadata: TokensMetadataAccess,
        market: MarketAccess,
        gas: GasAccess,
        token_vaults: TokenVaultsAccess,
        shared: SharedAccess,
        ranks: RanksAccess
    }

    struct Funding has store, key, drop, copy {
        rate: u128,
        previous_rate: u128,
        is_positive: bool
    }

    struct Asset has store, key, drop {
        asset: String,
        ema_price: u256,
        shorts: u256,
        longs: u256,
        long_interest_index: u128,
        short_interest_index: u128,
        long_funding_index: u128,
        short_funding_index: u128,
        leverage: u32,
        funding: Funding,
        last_trade: u64,
        avg_long_entry: u128,
        avg_short_entry: u128,
        last_ema_update: u64,
    }
    
    struct ViewAsset has store, key, drop {
        asset: String,
        ema_price: u256,
        shorts: u256,
        longs: u256,
        oi: u256,
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

    struct Position has copy, drop, store {
        size: u128,
        entry_price: u128,
        isLong: bool,
        leverage: u32,
        last_update: u64,
        interest_index: u256,
        reserve_chain: String,
        reserve_provider: String,
        reserve_token: String,
        accrued_interest: u256,
    }

    struct ViewPosition has copy, drop, store, key {
        asset: String,
        used_margin: u256,
        usd_size: u256,
        size: u128,
        entry_price: u128,
        price: u256,
        isLong: bool,
        type_name: String,
        leverage: u32,
        pnl: u256,
        is_profit: bool,
        denom: u256,
        profit_fee: u64,
        last_update: u64,
        accrued_interest: u256,
        reserve_chain: String,
        reserve_provider: String,
        reserve_token: String,
    }

    struct AssetBook has key, store {
        book: Map<String, Asset>,
    }

    struct UserBook has key, store {
        book: table::Table<String, Map<String, Position>>,
    }
    
    struct Markets has key, store {
        list: vector<String>,
    }

/// === INIT ===
    fun init_module(admin: &signer) {
        if (!exists<Markets>(@dev)) { move_to(admin, Markets { list: vector::empty<String>() }); };
        if (!exists<AssetBook>(@dev)) { move_to(admin, AssetBook { book: map::new<String, Asset>() }); };
        if (!exists<UserBook>(@dev)) { move_to(admin, UserBook { book: table::new<String, Map<String, Position>>() }); };
        if (!exists<Permissions>(@dev)) {
            move_to(admin, Permissions { 
                ranks: Ranks::give_access(admin),
                gas: Gas::give_access(admin),
                margin: Margin::give_access(admin), 
                market: Market::give_access(admin),
                metadata: TokensMetadata::give_access(admin),
                token_vaults: TokenVaults::give_access(admin),
                shared: Shared::give_access(admin)
            });
        };

        let initial_markets = vector[
            utf8(b"Bitcoin"), utf8(b"Ethereum"), utf8(b"Sui"), utf8(b"Monad"), 
            utf8(b"Virtuals"), utf8(b"Aptos"), utf8(b"Deepbook")
        ];
        
        let i = 0;
        while (i < vector::length(&initial_markets)) {
            create_market(admin, *vector::borrow(&initial_markets, i));
            i = i + 1;
        };
    }

/// === CAPABILITY FUNCTIONS ===
    public entry fun execute_order(signer: &signer, shared: String, id: u64) acquires UserBook, AssetBook, Permissions {
        Shared::assert_is_sub_owner(shared, bcs::to_bytes(&signer::address_of(signer)));
        assert!(capabilities::assert_wallet_capability(shared, utf8(b"QiaraPerps"), utf8(b"ORDER_EXECUTION")), ERROR_NOT_AUTHORIZED_FOR_ORDER_EXECUTION);
        let (shared,user,asset,size,desired_price,isLong,leverage,reserve_chain,reserve_provider,reserve_token) = Orders::get_limit_order_deconstructed(id);
        Ranks::add_experience(shared, experience_for_action(), Ranks::give_permission(&borrow_global<Permissions>(@dev).ranks));
        let price = TokensMetadata::get_coin_metadata_price(&TokensMetadata::get_coin_metadata_by_symbol(copy asset));
        
        if(isLong) {
            assert!((price as u128) <= desired_price, ERROR_PRICE_NOT_SETTLED);
        } else {
            assert!((price  as u128) >= desired_price, ERROR_PRICE_NOT_SETTLED);
        };

        execute_trade(user, shared, asset, (size as u256), (leverage as u64), isLong, reserve_chain, reserve_provider, reserve_token);
    }

/// === ENTRY FUNCTIONS ===
    public entry fun create_market(_admin: &signer, name: String) acquires Markets, AssetBook {
        TokensTypes::ensure_valid_token_nick_name(name);

        let asset_book = borrow_global_mut<AssetBook>(@dev);
        let initial_price = TokensMetadata::get_coin_metadata_price(&TokensMetadata::get_coin_metadata_by_symbol(name));

        if (!map::contains_key(&asset_book.book, &name)) {
            map::upsert(&mut asset_book.book, name, Asset { 
                asset: name,
                ema_price: (initial_price as u256),
                shorts: 0, longs: 0,
                long_interest_index: 1000000000000,
                short_interest_index: 1000000000000,
                long_funding_index: 0, short_funding_index: 0,
                leverage: 0,
                funding: Funding { rate: 0, previous_rate: 0, is_positive: true },
                last_trade: timestamp::now_seconds(),
                avg_long_entry: 0, avg_short_entry: 0,
                last_ema_update: timestamp::now_seconds(),
            });
        };

        let markets = borrow_global_mut<Markets>(@dev);
        if (!vector::contains(&markets.list, &name)) {
            vector::push_back(&mut markets.list, name);
        };
    }
    public entry fun accrue_interest(user: vector<u8>, shared: String, asset: String) acquires UserBook, AssetBook {
        accrue_interest_internal(user, shared, asset);
    }
    public entry fun trade(signer: &signer, user: vector<u8>, shared: String, asset: String, size: u256, leverage: u64, isLong: bool, reserve_chain: String, reserve_provider: String, reserve_token: String) acquires UserBook, AssetBook, Permissions {
        assert!(bcs::to_bytes(&signer::address_of(signer)) == user, ERROR_SENDER_DOESNT_MATCH_SIGNER);
        execute_trade(user, shared, asset, size, leverage, isLong, reserve_chain, reserve_provider, reserve_token);
    }
    public entry fun update_oracle_and_trade(signer: &signer, user: vector<u8>, shared: String, asset: String, size: u256, leverage: u64, isLong: bool, reserve_chain: String, reserve_provider: String, reserve_token: String, price_update_data: vector<vector<u8>>) acquires UserBook, AssetBook, Permissions {
        assert!(bcs::to_bytes(&signer::address_of(signer)) == user, ERROR_SENDER_DOESNT_MATCH_SIGNER);
        let metadata = TokensMetadata::get_coin_metadata_by_symbol(asset);
        let oracleID = TokensMetadata::get_coin_metadata_oracleID(&metadata);
        oracle::update_price(signer, price_update_data, oracleID);
        execute_trade(user, shared, asset, size, leverage, isLong, reserve_chain, reserve_provider, reserve_token);
    }
    public entry fun update_oracle_with_reward(signer: &signer, user: vector<u8>, shared: String, asset: String, price_update_data: vector<vector<u8>>) acquires  Permissions {
        assert!(bcs::to_bytes(&signer::address_of(signer)) == user, ERROR_SENDER_DOESNT_MATCH_SIGNER);
        Shared::assert_is_sub_owner(shared, bcs::to_bytes(&signer::address_of(signer)));
        
        let metadata = TokensMetadata::get_coin_metadata_by_symbol(asset);
        let oracleID = TokensMetadata::get_coin_metadata_oracleID(&metadata);

        oracle::update_price(signer, price_update_data, oracleID);
        Ranks::add_experience(shared, experience_for_action(), Ranks::give_permission(&borrow_global<Permissions>(@dev).ranks));

    }
    public entry fun batch_update_oracle_with_reward(signer: &signer, user: vector<u8>, shared: String, asset: vector<String>, price_update_data: vector<vector<vector<u8>>>) acquires  Permissions {
        assert!(bcs::to_bytes(&signer::address_of(signer)) == user, ERROR_SENDER_DOESNT_MATCH_SIGNER);
        Shared::assert_is_sub_owner(shared, bcs::to_bytes(&signer::address_of(signer)));
        

        let ids = vector::empty();
        let len = vector::length(&asset);
        while(len>0){
            let asset = vector::borrow(&asset, len-1);
            let metadata = TokensMetadata::get_coin_metadata_by_symbol(*asset);
            let oracleID = TokensMetadata::get_coin_metadata_oracleID(&metadata);
            vector::push_back(&mut ids, oracleID);
            len = len-1;
        }

        oracle::batch_update_price(signer, price_update_data, ids);
        Ranks::add_experience(shared, experience_for_action()*(len as u256), Ranks::give_permission(&borrow_global<Permissions>(@dev).ranks));

    }

    public entry fun change_reserve(signer: &signer, user: vector<u8>, shared: String, asset: String, new_reserve_chain: String, new_reserve_provider: String, new_reserve_token: String) acquires UserBook, AssetBook {
        ChainTypes::ensure_valid_chain_name(new_reserve_chain);
        TokensTypes::ensure_valid_token_nick_name(new_reserve_token);
        
        Shared::assert_is_sub_owner(copy shared, copy user);

        // IMPORTANT: We must accrue interest BEFORE changing the reserve.
        // This ensures the debt is snapshotted using the OLD reserve's borrow rate.
        accrue_interest_internal(copy user, copy shared, copy asset);

        // Now update the position with the new reserve info
        let user_book = borrow_global_mut<UserBook>(@dev);
        let position = find_position(copy shared, copy asset, user_book);
        
        // Ensure there is actually an active position to change
        assert!(position.size > 0, ERROR_ZERO_SIZE); 

        position.reserve_chain = copy new_reserve_chain;
        position.reserve_provider = copy new_reserve_provider;
        position.reserve_token = copy new_reserve_token;

        // Emit an event to index the change off-chain
        let data = vector[
            Event::create_data_struct(utf8(b"user"), utf8(b"vector<u8>"), copy user),
            Event::create_data_struct(utf8(b"shared"), utf8(b"string"), bcs::to_bytes(&shared)),
            Event::create_data_struct(utf8(b"asset"), utf8(b"string"), bcs::to_bytes(&asset)),
            Event::create_data_struct(utf8(b"new_reserve_chain"), utf8(b"string"), bcs::to_bytes(&new_reserve_chain)),
            Event::create_data_struct(utf8(b"new_reserve_provider"), utf8(b"string"), bcs::to_bytes(&new_reserve_provider)),
            Event::create_data_struct(utf8(b"new_reserve_token"), utf8(b"string"), bcs::to_bytes(&new_reserve_token)),
        ];
        Event::emit_perps_event(utf8(b"Reserve Changed"), data);
    }


/// === PERMISSIONELESS INTERFACE ===

    public fun p_accrue_interest(validator: &signer, user: vector<u8>, shared: String, asset: String, perm: Permission) acquires UserBook, AssetBook {
        accrue_interest_internal(user, shared, asset);
    
        let data = vector[
            Event::create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&utf8(b"main"))),
            Event::create_data_struct(utf8(b"validator"), utf8(b"vector<u8>"), bcs::to_bytes(&signer::address_of(validator))),
            Event::create_data_struct(utf8(b"sender"), utf8(b"address"), bcs::to_bytes(&user)),
            Event::create_data_struct(utf8(b"shared_storage"), utf8(b"string"), bcs::to_bytes(&shared)),
            Event::create_data_struct(utf8(b"asset"), utf8(b"string"), bcs::to_bytes(&asset)),
        ];
        Event::emit_perps_event(utf8(b"Interest Accrued"), data);

    }
    public fun p_trade(validator: &signer, user: vector<u8>, shared: String, asset: String, size: u256, leverage: u64, isLong: bool, reserve_chain: String, reserve_provider: String, reserve_token: String, perm: Permission) acquires UserBook, AssetBook, Permissions {
        execute_trade(user, shared, asset, size, leverage, isLong, reserve_chain, reserve_provider, reserve_token);
    }
    public fun p_update_oracle_and_trade(validator: &signer, user: vector<u8>, shared: String, asset: String, size: u256, leverage: u64, isLong: bool, reserve_chain: String, reserve_provider: String, reserve_token: String, price_update_data: vector<vector<u8>>, perm: Permission) acquires UserBook, AssetBook, Permissions {
        let metadata = TokensMetadata::get_coin_metadata_by_symbol(asset);
        let oracleID = TokensMetadata::get_coin_metadata_oracleID(&metadata);
        oracle::update_price(validator, price_update_data, oracleID);
        execute_trade(user, shared, asset, size, leverage, isLong, reserve_chain, reserve_provider, reserve_token);
    }
    public  fun p_change_reserve(validator: &signer, user: vector<u8>, shared: String, asset: String, new_reserve_chain: String, new_reserve_provider: String, new_reserve_token: String, perm: Permission) acquires UserBook, AssetBook {
        ChainTypes::ensure_valid_chain_name(new_reserve_chain);
        TokensTypes::ensure_valid_token_nick_name(new_reserve_token);
        
        Shared::assert_is_sub_owner(copy shared, copy user);

        // IMPORTANT: We must accrue interest BEFORE changing the reserve.
        // This ensures the debt is snapshotted using the OLD reserve's borrow rate.
        accrue_interest_internal(copy user, copy shared, copy asset);

        // Now update the position with the new reserve info
        let user_book = borrow_global_mut<UserBook>(@dev);
        let position = find_position(copy shared, copy asset, user_book);
        
        // Ensure there is actually an active position to change
        assert!(position.size > 0, ERROR_ZERO_SIZE); 

        position.reserve_chain = copy new_reserve_chain;
        position.reserve_provider = copy new_reserve_provider;
        position.reserve_token = copy new_reserve_token;

        // Emit an event to index the change off-chain
        let data = vector[
            Event::create_data_struct(utf8(b"user"), utf8(b"vector<u8>"), copy user),
            Event::create_data_struct(utf8(b"shared"), utf8(b"string"), bcs::to_bytes(&shared)),
            Event::create_data_struct(utf8(b"asset"), utf8(b"string"), bcs::to_bytes(&asset)),
            Event::create_data_struct(utf8(b"new_reserve_chain"), utf8(b"string"), bcs::to_bytes(&new_reserve_chain)),
            Event::create_data_struct(utf8(b"new_reserve_provider"), utf8(b"string"), bcs::to_bytes(&new_reserve_provider)),
            Event::create_data_struct(utf8(b"new_reserve_token"), utf8(b"string"), bcs::to_bytes(&new_reserve_token)),
        ];
        Event::emit_perps_event(utf8(b"Reserve Changed"), data);
    }

    public fun p_update_oracle_with_reward(validator: &signer, user: vector<u8>, shared: String, asset: String, price_update_data: vector<vector<u8>>, perm: Permission) acquires  Permissions {
        Shared::assert_is_sub_owner(copy shared, copy user);
        
        let metadata = TokensMetadata::get_coin_metadata_by_symbol(asset);
        let oracleID = TokensMetadata::get_coin_metadata_oracleID(&metadata);

        oracle::update_price(validator, price_update_data, oracleID);
        Ranks::add_experience(shared, experience_for_action(), Ranks::give_permission(&borrow_global<Permissions>(@dev).ranks));

    }
    public fun p_batch_update_oracle_with_reward(validator: &signer, user: vector<u8>, shared: String, asset: vector<String>, price_update_data: vector<vector<vector<u8>>>, perm: Permission) acquires  Permissions {
        Shared::assert_is_sub_owner(copy shared, copy user);

        let ids = vector::empty();
        let len = vector::length(&asset);
        while(len>0){
            let asset = vector::borrow(&asset, len-1);
            let metadata = TokensMetadata::get_coin_metadata_by_symbol(*asset);
            let oracleID = TokensMetadata::get_coin_metadata_oracleID(&metadata);
            vector::push_back(&mut ids, oracleID);
            len = len-1;
        }

        oracle::batch_update_price(validator, price_update_data, ids);
        Ranks::add_experience(shared, experience_for_action()*(len as u256), Ranks::give_permission(&borrow_global<Permissions>(@dev).ranks));

    }

// === HELPER FUNCTIONS ===

    fun execute_trade( user: vector<u8>, shared: String, asset: String, size: u256, leverage: u64, isLong: bool, reserve_chain: String, reserve_provider: String, reserve_token: String) acquires UserBook, AssetBook, Permissions {
        ensure_safety(asset, size, reserve_chain, reserve_provider, reserve_token);
        Shared::assert_is_sub_owner(shared, copy user);
        assert!(leverage >= 100, ERROR_LEVERAGE_TOO_LOW);
        assert!(size > 0, ERROR_ZERO_SIZE);

        // Pre-accrue without active global borrows
        let usd_amount =  TokensMetadata::getValue(asset, size);
        let gas_rate = Gas::add_leverage(asset, leverage, usd_amount, Gas::give_permission(&borrow_global<Permissions>(@dev).gas));

        accrue_interest_internal(copy user, copy shared, copy asset);

        let market = get_market(asset);
        let (_, impact_fee) = TokensMetadata::impact(asset, size, market.shorts + market.longs, isLong, utf8(b"Perps"), TokensMetadata::give_permission(&borrow_global<Permissions>(@dev).metadata));
     
        handle_gas_fee(shared, user, asset);

        let price = TokensMetadata::get_coin_metadata_price(&TokensMetadata::get_coin_metadata_by_symbol(copy asset));

        // Borrows hold strictly scoped
        let user_book = borrow_global_mut<UserBook>(@dev);
        let position = find_position(copy shared, copy asset, user_book);
        let asset_book = borrow_global_mut<AssetBook>(@dev);
        
        let (size_diff_usd, is_profit) = calculate_position(@0x0, copy asset,  user, copy shared, asset_book, position, size, leverage, isLong, (price as u128), user, reserve_chain, reserve_provider, reserve_token);
        
        handle_pnl(asset, size_diff_usd, is_profit, user, shared);
    }

    fun handle_gas_fee(shared: String, user: vector<u8>, token: String): u256 acquires Permissions{
        let (total_user_usd, _, _, _, _, _, _, _, _, _, _) = Margin::get_user_total_usd(shared);
        let (user_gas_index, user_last_time_interacted) = Shared::extract_raw_gas_relations(Shared::return_shared_ownership_new(shared));
        let (gas_fee, gas_index) = Gas::calculate_gas_fee_from_index(user_gas_index, total_user_usd);

        Shared::update_gas_index(shared, gas_index, Shared::give_permission(&borrow_global<Permissions>(@dev).shared));
        Margin::remove_credit(shared, user, gas_fee, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        TokenVaults::fast_add_accumulated_rewards(token, gas_fee, TokenVaults::give_permission(&borrow_global<Permissions>(@dev).token_vaults));
        return gas_fee
    }

    fun calculate_position(validator: address, assetName: String, user: vector<u8>, shared: String, asset_book: &mut AssetBook, position: &mut Position, added_size: u256, leverage: u64, isLong: bool, oracle_price: u128, _user: vector<u8>, reserve_chain: String, reserve_provider: String, reserve_token: String): (u256, bool) {
        let asset = map::borrow_mut(&mut asset_book.book, &assetName);
        let curr_size: u256 = (position.size as u256);
        let add_size: u256 = added_size;
        let lev: u256 = (leverage as u256);
        let price: u256 = (oracle_price as u256);
        let current_interest_index = if (isLong) { asset.long_interest_index } else { asset.short_interest_index };
        
        // Convert the bool to the u8 type (1 = long, 2 = short) for the helper functions
        let perp_type: u8 = if (isLong) { 1 } else { 2 };
        
        // Case 1: Open New
        if (position.size == 0) {
            position.size = (added_size as u128);
            position.leverage = (leverage as u32);
            position.isLong = isLong;
            position.entry_price = (price as u128);
            position.interest_index = (current_interest_index as u256);
            position.last_update = timestamp::now_seconds();
            position.accrued_interest = 0;
            
            // Save newly supplied reserves info
            position.reserve_chain = copy reserve_chain;
            position.reserve_provider = copy reserve_provider;
            position.reserve_token = copy reserve_token;

            update_asset_leverage(asset, add_size, leverage, perp_type, true);
            emit_position_event(validator,user, shared, perp_type, added_size, leverage, assetName, price, utf8(b"Open Position"), reserve_chain, reserve_provider, reserve_token, isLong);
            return (0, true);
        };

        let curr_lev: u256 = (position.leverage as u256);
        let curr_price: u256 = (position.entry_price as u256);
        let weighted_curr_lev = curr_size * curr_lev;
        let weighted_curr_price = curr_size * curr_price;

        // Case 2: Increase Size
        if (position.isLong == isLong) {
            let weighted_new_lev = add_size * lev;
            let weighted_new_price = add_size * price;
            let new_size = curr_size + add_size;

            let (paid_interest, _) = settle_interest(position, 0, true, curr_size, curr_size);

            position.size = (new_size as u128);
            position.leverage = ((weighted_curr_lev + weighted_new_lev) / new_size as u32);
            position.entry_price = ((weighted_curr_price + weighted_new_price) / new_size as u128);
            position.interest_index = (current_interest_index as u256);
            position.last_update = timestamp::now_seconds();

            // Update to latest reserve info
            position.reserve_chain = copy reserve_chain;
            position.reserve_provider = copy reserve_provider;
            position.reserve_token = copy reserve_token;

            update_asset_leverage(asset, add_size, leverage, perp_type, true);
            emit_position_event(validator, user,shared, perp_type, added_size, leverage, assetName, price, utf8(b"Add Size"), reserve_chain, reserve_provider, reserve_token, isLong);
            
            return (paid_interest, false);
        };

        // Helper to grab the OLD direction for removing size
        let old_perp_type = if (position.isLong) { 1 } else { 2 };

        // Case 3: Flip / Fully Close
        if (add_size >= curr_size) {
            let (pnl, is_profit) = calculate_pnl(position.isLong, curr_price, price, curr_size);
            let (final_pnl, final_is_profit) = settle_interest(position, pnl, is_profit, curr_size, curr_size);

            // Remove the old position exposure
            update_asset_leverage(asset, curr_size, leverage, old_perp_type, false);
            
            let remaining_size = add_size - curr_size;
            if (remaining_size > 0) {
                position.size = (remaining_size as u128);
                position.leverage = (leverage as u32);
                position.isLong = isLong;
                position.entry_price = (price as u128);
                position.interest_index = (current_interest_index as u256);
                position.last_update = timestamp::now_seconds();
                position.accrued_interest = 0; 

                // Start new flipped position with latest reserve info
                position.reserve_chain = copy reserve_chain;
                position.reserve_provider = copy reserve_provider;
                position.reserve_token = copy reserve_token;
                
                // Add the new flipped exposure
                update_asset_leverage(asset, remaining_size, leverage, perp_type, true);
                emit_position_event(validator, user, shared, perp_type, added_size, leverage, assetName, price, utf8(b"Reduce & Flip Side"), reserve_chain, reserve_provider, reserve_token, isLong);
            } else {
                position.size = 0;
                position.leverage = 0;
                position.entry_price = 0;
                position.interest_index = 0;
                position.accrued_interest = 0;

                // Reset reserve fields to empty
                position.reserve_chain = utf8(b"");
                position.reserve_provider = utf8(b"");
                position.reserve_token = utf8(b"");

                emit_position_event(validator,user,  shared, perp_type, added_size, leverage, assetName, price, utf8(b"Close"), reserve_chain, reserve_provider, reserve_token, isLong);
            };

            return (final_pnl, final_is_profit)
        } else {
            // Case 4: Partial Close
            let (pnl, is_profit) = calculate_pnl(position.isLong, curr_price, price, add_size);
            let (final_pnl, final_is_profit) = settle_interest(position, pnl, is_profit, add_size, curr_size);

            position.size = ((curr_size - add_size) as u128);
            position.last_update = timestamp::now_seconds();

            // Note: intentionally leaving reserve details untouched here to keep the active margin state.

            // Remove only the closed portion from exposure
            update_asset_leverage(asset, add_size, leverage, old_perp_type, false);
            emit_position_event(validator, user, shared, perp_type, added_size, leverage, assetName, price, utf8(b"Partial Close"), reserve_chain, reserve_provider, reserve_token, isLong);
            
            return (final_pnl, final_is_profit)
        }
    }

    fun settle_interest(position: &mut Position, pnl: u256, is_profit: bool, closed_size: u256, curr_size: u256): (u256, bool) {
        if (position.accrued_interest == 0 || curr_size == 0 || closed_size == 0) return (pnl, is_profit);

        let paid_interest = position.accrued_interest * closed_size / curr_size;
        position.accrued_interest = position.accrued_interest - paid_interest;

        if (is_profit) {
            if (pnl >= paid_interest) { (pnl - paid_interest, true) } else { (paid_interest - pnl, false) }
        } else {
            (pnl + paid_interest, false)
        }
    }

    fun calculate_user_interest(asset: &Asset, position: &Position, _current_price: u256, current_time: u64): (u128, u256) {
        if (position.size == 0) return (0, 0);
        let time_delta = (current_time - position.last_update) as u128;
        if (time_delta == 0) return (0, 0);
        
        let ema_price = asset.ema_price;
        let entry = (position.entry_price as u256);
        if (entry == 0) return (0, ema_price);

        let is_profitable = if (position.isLong) { ema_price >= entry } else { entry >= ema_price };
        let drawdown_percent = if (!is_profitable) {
            if (position.isLong) {
                if (entry > ema_price) { ((entry - ema_price) * 10000 / entry) as u128 } else { 0 }
            } else {
                if (ema_price > entry) { ((ema_price - entry) * 10000 / entry) as u128 } else { 0 }
            }
        } else { 0 };
        
        // Fetch dynamic borrow rate from Liquidity module
        let (_, _, _, _, final_borrow_rate) = Liquidity::return_raw_data_vault(position.reserve_token, position.reserve_chain, position.reserve_provider);

        // Convert the 1_000_000 scale to the 1_000_000_000_000 (1e12) scale
        let base_rate: u128 = (final_borrow_rate as u128) * 1000000; 
        
        let x = drawdown_percent;
        let exp_multiplier = (10000 + x + (x * x / 20000) + (x * x * x / 600000000));
        let annual_rate = base_rate * exp_multiplier / 10000;
        
        let position_value = (position.size as u128) * (position.entry_price as u128);
        let year_seconds: u128 = 365 * 24 * 3600;
        let interest = position_value * annual_rate * time_delta / (year_seconds * 1000000000000);
        
        let current_index = if (position.isLong) { asset.long_interest_index } else { asset.short_interest_index };
        let index_interest = if (position.interest_index > 0) {
            let cur_idx_u128 = current_index as u128;
            let pos_idx_u128 = position.interest_index as u128;
            
            // Manual saturating subtraction (Move has no native saturating_sub)
            let index_diff = if (cur_idx_u128 > pos_idx_u128) { cur_idx_u128 - pos_idx_u128 } else { 0 };
            position_value * index_diff / 1000000000000
        } else { 0 };
        
        (interest + index_interest, ema_price)
    }

    fun update_ema(asset: &mut Asset, spot_price: u256) {
        let now = timestamp::now_seconds();
        let time_passed = now - asset.last_ema_update;
        if (time_passed < 60) return;
        
        let periods = time_passed / 60;
        let computed_alpha = 1000 * periods; 
        let alpha = if (computed_alpha > 10000) 10000 else computed_alpha;
        let denominator = 10000;
        
        asset.ema_price = ((alpha as u256) * spot_price + ((denominator - alpha) as u256) * asset.ema_price) / (denominator as u256);
        asset.last_ema_update = now - (time_passed % 60); // Prevents time tracking drift
    }

    fun update_asset_leverage(asset: &mut Asset, size_delta: u256, leverage: u64, perp_type: u8, is_increase: bool) {
        let is_long = perp_type == 1;
        if (is_increase) {
            if (is_long) { asset.longs = asset.longs + size_delta; } 
            else { asset.shorts = asset.shorts + size_delta; };
        } else {
            if (is_long) { 
                asset.longs = if (asset.longs > size_delta) asset.longs - size_delta else 0; 
            } else { 
                asset.shorts = if (asset.shorts > size_delta) asset.shorts - size_delta else 0; 
            };
        };
        if (leverage > 0) asset.leverage = (leverage as u32);
    }

    fun find_position(shared: String, name: String, user_book: &mut UserBook): &mut Position {
        if (!table::contains(&user_book.book, shared)) table::add(&mut user_book.book, copy shared, map::new<String, Position>());
        let user_map = table::borrow_mut(&mut user_book.book, shared);
        
        if (!map::contains_key(user_map, &name)) {
            map::upsert(user_map, copy name, Position {
                size: 0, entry_price: 0, isLong: false, leverage: 0, last_update: 0,
                interest_index: 0, reserve_chain: utf8(b""), reserve_provider: utf8(b""),
                reserve_token: utf8(b""), accrued_interest: 0,
            });
        };
        map::borrow_mut(user_map, &name)
    }

    fun calculate_pnl(is_long: bool, entry_price: u256, exit_price: u256, size: u256): (u256, bool) {
        if (is_long) {
            if (exit_price >= entry_price) ((exit_price - entry_price) * size, true) else ((entry_price - exit_price) * size, false)
        } else {
            if (entry_price >= exit_price) ((entry_price - exit_price) * size, true) else ((exit_price - entry_price) * size, false)
        }
    }

    fun emit_position_event(validator: address, user:vector<u8>, shared: String, type: u8, size: u256, leverage: u64, assetName: String, price: u256, event_name: String, reserve_chain: String, reserve_provider: String, reserve_token: String, is_long: bool) {
        let data = vector[
            Event::create_data_struct(utf8(b"validator"), utf8(b"string"), bcs::to_bytes(&validator)),
            Event::create_data_struct(utf8(b"user"), utf8(b"string"), bcs::to_bytes(&user)),
            Event::create_data_struct(utf8(b"shared"), utf8(b"string"), bcs::to_bytes(&shared)),
            Event::create_data_struct(utf8(b"type"), utf8(b"string"), bcs::to_bytes(&type)),
            Event::create_data_struct(utf8(b"size"), utf8(b"u256"), bcs::to_bytes(&size)),
            Event::create_data_struct(utf8(b"leverage"), utf8(b"u64"), bcs::to_bytes(&leverage)),
            Event::create_data_struct(utf8(b"used_margin"), utf8(b"u64"), bcs::to_bytes(&(((size*price) / (leverage as u256)) * 100))),
            Event::create_data_struct(utf8(b"asset"), utf8(b"string"), bcs::to_bytes(&assetName)),
            Event::create_data_struct(utf8(b"entry_price"), utf8(b"u256"), bcs::to_bytes(&price)),
            Event::create_data_struct(utf8(b"fee"), utf8(b"u256"), bcs::to_bytes(&0)),
            Event::create_data_struct(utf8(b"reserve_chain"), utf8(b"string"), bcs::to_bytes(&reserve_chain)),
            Event::create_data_struct(utf8(b"reserve_provider"), utf8(b"string"), bcs::to_bytes(&reserve_provider)),
            Event::create_data_struct(utf8(b"reserve_token"), utf8(b"string"), bcs::to_bytes(&reserve_token)),
            Event::create_data_struct(utf8(b"is_long"), utf8(b"bool"), bcs::to_bytes(&is_long)),
        ];
        Event::emit_perps_event(event_name, data);
    }

    fun accrue_interest_internal(user: vector<u8>, shared: String, asset: String) acquires UserBook, AssetBook {
        let user_book = borrow_global_mut<UserBook>(@dev);
        let position = find_position(shared, copy asset, user_book);
        if (position.size == 0) return;
        
        let price = TokensMetadata::get_coin_metadata_price(&TokensMetadata::get_coin_metadata_by_symbol(copy asset));
        let asset_book = borrow_global_mut<AssetBook>(@dev);
        let asset_ref = map::borrow_mut(&mut asset_book.book, &asset);
        
        update_ema(asset_ref, (price as u256));
        
        let current_time = timestamp::now_seconds();
        let (interest, _) = calculate_user_interest(asset_ref, position, (price as u256), current_time);
        
        position.accrued_interest = position.accrued_interest + (interest as u256);
        let current_index = if (position.isLong) { asset_ref.long_interest_index } else { asset_ref.short_interest_index };
        position.interest_index = (current_index as u256);
        position.last_update = current_time;
        
        let data = vector[
            Event::create_data_struct(utf8(b"user"), utf8(b"vector<u8>"), bcs::to_bytes(&user)),
            Event::create_data_struct(utf8(b"shared"), utf8(b"string"), bcs::to_bytes(&shared)),
            Event::create_data_struct(utf8(b"asset"), utf8(b"string"), bcs::to_bytes(&asset)),
            Event::create_data_struct(utf8(b"interest"), utf8(b"u256"), bcs::to_bytes(&(interest as u256))),
        ];
        Event::emit_perps_event(utf8(b"Interest Accrued"), data);
    }

    fun handle_pnl(_asset: String, pnl: u256, is_profit: bool, sub_owner: vector<u8>, shared: String) acquires Permissions {
        if (pnl == 0) return; 
        
        let permissions = borrow_global<Permissions>(@dev);
        if (is_profit) {
            Margin::add_credit(shared, sub_owner, pnl, Margin::give_permission(&permissions.margin));
        } else {
            Margin::remove_credit(shared, sub_owner, pnl, Margin::give_permission(&permissions.margin));
        };
    }


// === VIEW FUNCTIONS ===

    fun empty_view_position(asset: String, price: u128, denom: u128): ViewPosition {
        ViewPosition {
            type_name: utf8(b""), last_update: 0, asset: asset, used_margin: 0, usd_size: 0, 
            size: 0, entry_price: 0, price: (price as u256), isLong: false, leverage: 0, 
            pnl: 0, is_profit: false, denom: (denom as u256), profit_fee: 0, accrued_interest: 0, reserve_chain: utf8(b""), reserve_provider: utf8(b""), reserve_token: utf8(b"")
        }
    }

    fun build_view_position(asset: String, position: &Position, asset_ref: &Asset): ViewPosition {
        let price = TokensMetadata::get_coin_metadata_price(&TokensMetadata::get_coin_metadata_by_symbol(copy asset));
        let denom = TokensMetadata::get_coin_metadata_denom(&TokensMetadata::get_coin_metadata_by_symbol(copy asset));
        
        let (pnl, is_profit) = estimate_pnl(position, (price as u256));
        let (pending_interest, _) = calculate_user_interest(asset_ref, position, (price as u256), timestamp::now_seconds());
        
        ViewPosition {
            type_name: if (position.isLong) utf8(b"long") else utf8(b"short"),
            last_update: position.last_update,
            asset: asset,
            used_margin: if (position.leverage > 0) (((position.size as u256) * (position.entry_price as u256)) / (position.leverage as u256))*100 else 0,
            usd_size: (position.size as u256) * (position.entry_price as u256),
            size: position.size,
            entry_price: position.entry_price,
            price: (price as u256),
            isLong: position.isLong,
            leverage: position.leverage,
            pnl: pnl,
            is_profit: is_profit,
            denom: (denom as u256),
            profit_fee: 0,
            accrued_interest: position.accrued_interest + (pending_interest as u256),
            reserve_chain: position.reserve_chain,
            reserve_provider: position.reserve_provider,
            reserve_token: position.reserve_token,
        }
    }

    fun build_view_market(asset: String, asset_ref: &Asset): ViewAsset {
        let price = TokensMetadata::get_coin_metadata_price(&TokensMetadata::get_coin_metadata_by_symbol(copy asset));
        let denom = TokensMetadata::get_coin_metadata_denom(&TokensMetadata::get_coin_metadata_by_symbol(copy asset));
        
        ViewAsset { 
            last_trade: asset_ref.last_trade, funding: asset_ref.funding, asset: asset_ref.asset, ema_price: asset_ref.ema_price,
            shorts: asset_ref.shorts, longs: asset_ref.longs, 
            long_interest_index: asset_ref.long_interest_index, short_interest_index: asset_ref.short_interest_index,
            long_funding_index: asset_ref.long_funding_index, short_funding_index: asset_ref.short_funding_index,
            oi: (asset_ref.shorts + asset_ref.longs) * (price as u256), leverage: asset_ref.leverage, utilization: 0, 
            price: (price as u128), denom: (denom as u128),
        }
    }

    #[view]
    public fun get_position(asset: String, shared: String): ViewPosition acquires UserBook, AssetBook {
        let price = TokensMetadata::get_coin_metadata_price(&TokensMetadata::get_coin_metadata_by_symbol(copy asset));
        let denom = TokensMetadata::get_coin_metadata_denom(&TokensMetadata::get_coin_metadata_by_symbol(copy asset));
        let user_book = borrow_global<UserBook>(@dev);
        
        if (!table::contains(&user_book.book, copy shared)) return empty_view_position(copy asset, (price as u128), (denom as u128));
        let user_map = table::borrow(&user_book.book, shared);
        if (!map::contains_key(user_map, &asset)) return empty_view_position(copy asset, (price as u128), (denom as u128));

        let position = map::borrow(user_map, &asset);
        
        let asset_book = borrow_global<AssetBook>(@dev);
        let asset_ref = map::borrow(&asset_book.book, &asset);
        
        build_view_position(asset, position, asset_ref)
    }

    #[view]
    public fun get_market(asset: String): ViewAsset acquires AssetBook {
        let asset_book = borrow_global<AssetBook>(@dev);
        let asset_ref = map::borrow(&asset_book.book, &asset);
        
        build_view_market(asset, asset_ref)
    }

    #[view]
    public fun get_all_positions(shared: String): vector<ViewPosition> acquires Markets, UserBook, AssetBook {
        let markets = borrow_global<Markets>(@dev);
        let user_book = borrow_global<UserBook>(@dev);
        let asset_book = borrow_global<AssetBook>(@dev);
        let result = vector::empty<ViewPosition>();
        
        if (!table::contains(&user_book.book, copy shared)) {
            return result
        };
        
        let user_map = table::borrow(&user_book.book, shared);
        
        let i = 0;
        let len = vector::length(&markets.list);
        while (i < len) {
            let asset = *vector::borrow(&markets.list, i);
            if (map::contains_key(user_map, &asset)) {
                let position = map::borrow(user_map, &asset);
                if (position.size > 0) {
                    let asset_ref = map::borrow(&asset_book.book, &asset);
                    vector::push_back(&mut result, build_view_position(asset, position, asset_ref));
                }
            };
            i = i + 1;
        };
        
        result
    }

    #[view]
    public fun get_all_markets(): vector<ViewAsset> acquires Markets, AssetBook {
        let markets = borrow_global<Markets>(@dev);
        let asset_book = borrow_global<AssetBook>(@dev);
        let result = vector::empty<ViewAsset>();
        
        let i = 0;
        let len = vector::length(&markets.list);
        while (i < len) {
            let asset = *vector::borrow(&markets.list, i);
            let asset_ref = map::borrow(&asset_book.book, &asset);
            vector::push_back(&mut result, build_view_market(asset, asset_ref));
            i = i + 1;
        };
        
        result
    }

    #[view]
     public fun min_usd_size(): u256 {
        storage::expect_u64(storage::viewConstant(utf8(b"QiaraPerps"), utf8(b"MIN_USD_SIZE_PER_TRADE"))) as u256
    }

    #[view]
     public fun min_token_size(): u256 {
        storage::expect_u64(storage::viewConstant(utf8(b"QiaraPerps"), utf8(b"MIN_TOKEN_SIZE_PER_TRADE"))) as u256
    }

    #[view]
     public fun experience_for_action(): u256 {
        storage::expect_u64(storage::viewConstant(utf8(b"QiaraRanks"), utf8(b"POINTS_PER_PERP_ACTION"))) as u256
    }


    fun ensure_safety(token: String, amount: u256, reserve_chain: String, reserve_provider: String, reserve_token: String) {
        assert!(amount >= min_token_size(), ERROR_SIZE_TOO_SMALL);
        assert!(TokensMetadata::getValue(token, amount) >= min_usd_size(), ERROR_USD_SIZE_TOO_SMALL);
        ChainTypes::ensure_valid_chain_name(reserve_chain);
        TokensTypes::ensure_valid_token_nick_name(reserve_token);
    }

    public fun estimate_pnl(position: &Position, current_price: u256): (u256, bool) {
        if (position.size == 0) return (0, true);
        calculate_pnl(position.isLong, (position.entry_price as u256), current_price, (position.size as u256))
    }
}