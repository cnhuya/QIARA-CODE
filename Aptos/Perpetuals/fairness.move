module dev::QiaraPerpsFairnessV2 {
    use std::signer;
    use std::table::{Self, Table};
    use std::vector;

    // === ERRORS === //
    const ERROR_PAGE_OUT_OF_BOUNDS: u64 = 1;
    const ERROR_POSITION_DOESNT_EXIST_IN_CURRENT_PAGE: u64 = 2;

    // === CONSTANTS === //
    const MAX_POSITIONS_PER_PAGE: u64 = 100;

    struct Tracker has key {
        page_index: u64,
        positionID_index: u256,
        last_removed_page: u64
    }

    struct Positions has key {
        table: Table<u64, vector<u256>>
    }

    /// === INIT ===
    fun init_module(admin: &signer) {
        let admin_addr = signer::address_of(admin);

        if (!exists<Tracker>(admin_addr)) {
            move_to(admin, Tracker { 
                page_index: 0,  
                positionID_index: 0,
                last_removed_page: 0
            });
        };

        if (!exists<Positions>(admin_addr)) {
            let table = table::new<u64, vector<u256>>();
            // Pre-initialize page 0 to simplify the add_user_position logic
            table::add(&mut table, 0, vector::empty());
            move_to(admin, Positions { table });
        };
    }

    public entry fun add_position() acquires Tracker, Positions {
        let tracker = borrow_global_mut<Tracker>(@dev);
        let user_positions = borrow_global_mut<Positions>(@dev);

        let positions = table::borrow_mut(&mut user_positions.table, tracker.page_index);
        
        // If current page is full, increment index and initialize the next page
        if (vector::length(positions) >= MAX_POSITIONS_PER_PAGE) {
            tracker.page_index = tracker.page_index + 1;
            table::add(&mut user_positions.table, tracker.page_index, vector::singleton(tracker.positionID_index));
        } else {
            vector::push_back(positions, tracker.positionID_index);
        };

        tracker.positionID_index = tracker.positionID_index + 1;
    }

    public entry fun remove_position(pageIndex: u64, positionID: u256) acquires Tracker, Positions {
        let tracker = borrow_global_mut<Tracker>(@dev);
        let user_positions = borrow_global_mut<Positions>(@dev);

        assert!(table::contains(&user_positions.table, pageIndex), ERROR_PAGE_OUT_OF_BOUNDS);

        let positions = table::borrow_mut(&mut user_positions.table, pageIndex);
        let (found, index) = vector::index_of(positions, &positionID);
        assert!(found, ERROR_POSITION_DOESNT_EXIST_IN_CURRENT_PAGE);
        
        vector::remove(positions, index);
        tracker.last_removed_page = pageIndex;
    }
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
