module dev::QiaraTPerpsV2 {
    use std::signer;
    use std::table::{Self, Table};
    use std::vector;

    struct Tracker has key {
        page_index: u64,
        position_index: u256,
    }

    struct UserPositions has key {
        // index | position_ids
        table: Table<u64, vector<u256>>
    }

    /// === INIT ===
    fun init_module(admin: &signer) {
        if (!exists<Tracker>(@dev)) {
            move_to(admin, Tracker { page_index: 0,  position_index: 0});
        };

        if (!exists<UserPositions>(@dev)) {
            move_to(admin, UserPositions { table: table::new<u64, vector<u256>>()});
        };
    }

    public entry fun add_user_position(_signer: &signer) acquires Tracker, UserPositions {
        let tracker = borrow_global_mut<Tracker>(@dev);
        let user_positions = borrow_global_mut<UserPositions>(@dev);

        // Ensure the current page/index exists in the table
        if (!table::contains(&user_positions.table, tracker.page_index)) {
            table::add(&mut user_positions.table, tracker.page_index, vector::empty<u256>());
        };

        // If the current page is full (10 items), increment tracker index and create a new row
        let current_len = vector::length(table::borrow(&user_positions.table, tracker.page_index));
        if (current_len >= 10) {
            tracker.page_index = tracker.page_index + 1;
            table::add(&mut user_positions.table, tracker.page_index, vector::empty<u256>());
        };

        // Safely push to the active index page
        let positions = table::borrow_mut(&mut user_positions.table, tracker.page_index);
        vector::push_back(positions, tracker.position_index);
        tracker.position_index = tracker.position_index + 1;
    }
}