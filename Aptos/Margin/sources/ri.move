module dev::QiaraRIV2{
    use std::signer;
    use std::string::{Self as String, String, utf8};
    use std::vector;
    use std::table::{Self, Table};

    use dev::QiaraTokenTypesV4::{Self as TokensType};
    use dev::QiaraChainTypesV4::{Self as ChainTypes};

// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_USER_DID_NOT_INITIALIZE_HIS_RI_YET: u64 = 2;
    const ERROR_SOME_OF_REWARD_STRUCT_IS_NONE: u64 = 2;
    const ERROR_SOME_OF_INTEREST_STRUCT_IS_NONE: u64 = 3;

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
// === STRUCTS === //
    // (shared storage owner) -> RI
    struct UsersRI has key {
        ri: Table<vector<u8>, RI>,
        perp_credit_profit: Table<vector<u8>, bool>,
    }

    struct RI has key, store, copy, drop{
        rewards: Reward,
        interests: Interest,
    }

    struct Reward has key, store, copy, drop{
        token: String,
        chain: String,
        provider: String,
    }

    struct Interest has key, store, copy, drop{
        token: String,
        chain: String,
        provider: String,
    }

// === INIT === //
    fun init_module(admin: &signer){
        if (!exists<UsersRI>(@dev)) {
            move_to(admin,UsersRI {ri: table::new<vector<u8>, RI>(), perp_credit_profit: table::new<vector<u8>, bool>()});
        };

    }

// === ENTRY FUN === //

    public fun ensure_ri(owner: vector<u8>) acquires UsersRI{

        let ri_table = borrow_global_mut<UsersRI>(@dev);

        if (!table::contains(&ri_table.ri, owner)) {
            table::add(&mut ri_table.ri, owner, RI { rewards: Reward { token: utf8(b"None"), chain: utf8(b"None"), provider: utf8(b"None")  }, interests: Interest { token: utf8(b"None"), chain: utf8(b"None"), provider: utf8(b"None")  } });
        };
    }

    public fun change_rewards(owner: vector<u8>, token: String, chain: String, provider: String) acquires UsersRI{
        ChainTypes::ensure_valid_chain_name(chain);

        let ri_table = borrow_global_mut<UsersRI>(@dev);

        let ri = table::borrow_mut(&mut ri_table.ri, owner);
        ri.rewards = Reward { token: token, chain: chain, provider: provider };
    }

    public fun change_interests(owner: vector<u8>,  token: String, chain: String, provider: String) acquires UsersRI{
        ChainTypes::ensure_valid_chain_name(chain);

        let ri_table = borrow_global_mut<UsersRI>(@dev);

        let ri = table::borrow_mut(&mut ri_table.ri, owner);
        ri.interests = Interest { token: token, chain: chain, provider: provider };
    }

    public fun change_perp_credit_profit(owner: vector<u8>, is_perp_credit: bool) acquires UsersRI{
        let ri_table = borrow_global_mut<UsersRI>(@dev);

        let ri = table::borrow_mut(&mut ri_table.perp_credit_profit, owner);
        *ri = is_perp_credit;
    }


// === PUBLIC VIEWS === //

    #[view]
    public fun get_user_ri(owner: vector<u8>): RI acquires UsersRI {
        *find_user_RI(borrow_global_mut<UsersRI>(@dev),owner)
    }

    #[view]
    public fun get_user_raw_rewards(owner: vector<u8>): (String, String, String) acquires UsersRI {
        let ri = find_user_RI(borrow_global_mut<UsersRI>(@dev),owner);
        return (ri.rewards.token, ri.rewards.chain, ri.rewards.provider)
    }

    #[view]
    public fun get_user_raw_interests(owner: vector<u8>): (String, String, String) acquires UsersRI {
        let ri = find_user_RI(borrow_global_mut<UsersRI>(@dev),owner);
        return (ri.interests.token, ri.interests.chain, ri.interests.provider)
    }

    #[view]
    public fun get_user_perp_isCredit(owner: vector<u8>): bool acquires UsersRI {
        let ri = find_user_perp_credit(borrow_global_mut<UsersRI>(@dev),owner);
        return ri
    }

// === MUT RETURNS === //
    fun find_user_RI(ri_table: &mut UsersRI,owner: vector<u8>): &mut RI {
        {
            if (!table::contains(&ri_table.ri, owner)) {
                abort ERROR_USER_DID_NOT_INITIALIZE_HIS_RI_YET
            };
        };

        let ri = table::borrow_mut(&mut ri_table.ri, owner);
        assert_safety(*ri);
        return ri
    }

    fun find_user_perp_credit(ri_table: &mut UsersRI,owner: vector<u8>): bool {
        {
            if (!table::contains(&ri_table.perp_credit_profit, owner)) {
                abort ERROR_USER_DID_NOT_INITIALIZE_HIS_RI_YET
            };
        };

        let ri = table::borrow_mut(&mut ri_table.perp_credit_profit, owner);
        return *ri
    }

    fun assert_safety(ri: RI){
        assert!(ri.rewards.token != utf8(b"None"), ERROR_SOME_OF_REWARD_STRUCT_IS_NONE);
        assert!(ri.rewards.chain != utf8(b"None"), ERROR_SOME_OF_REWARD_STRUCT_IS_NONE);
        assert!(ri.rewards.provider != utf8(b"None"), ERROR_SOME_OF_REWARD_STRUCT_IS_NONE);

        assert!(ri.interests.token != utf8(b"None"), ERROR_SOME_OF_INTEREST_STRUCT_IS_NONE);
        assert!(ri.interests.chain != utf8(b"None"), ERROR_SOME_OF_INTEREST_STRUCT_IS_NONE);
        assert!(ri.interests.provider != utf8(b"None"), ERROR_SOME_OF_INTEREST_STRUCT_IS_NONE);

    }

}
