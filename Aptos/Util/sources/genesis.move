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

}