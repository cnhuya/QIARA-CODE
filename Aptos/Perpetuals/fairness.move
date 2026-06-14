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