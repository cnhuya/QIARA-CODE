module dev::QiaraGenesisV2 {
    use std::vector;
    use std::signer;
    use aptos_framework::timestamp;
    struct Genesis has key {
        genesis: u256,
    }

    const ERROR_NOT_ADMIN: u64 = 1;

    // === INIT === //
    fun init_module(admin: &signer) {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == @dev, ERROR_NOT_ADMIN);
        move_to(admin, Genesis {genesis: (timestamp::now_seconds() as u256)});
    }

    #[view]
    public fun return_epoch(): u256 acquires Genesis {
        let val = borrow_global<Genesis>(@dev);
        let time_diff = (timestamp::now_seconds() as u256) - val.genesis;
        return time_diff/60
    }

    #[view]
    public fun return_genesis_timestamp(): u256 acquires Genesis {
        let val = borrow_global<Genesis>(@dev);
        return val.genesis;
    }

    #[view]
    public fun return_epoch_duration(): u256 {
        return 60
    }


    // REMOVE IN FUTURE (FORGOT TO INCLUDE GENESIS TIMESTAMP)
    #[view]
    public fun return_epoch_summary(): (u256, u256) acquires Genesis {
        return (return_epoch(), return_epoch_duration())
    }

    #[view]
    public fun return_epoch_summary_new(): (u256, u256 , u256) acquires Genesis {
        return (return_epoch(), return_epoch_duration(), return_genesis_timestamp())
    }

}