module dev::QiaraTokensQiaraV3 {
    use std::signer;
    use std::option;
    use std::vector;
    use std::bcs;
    use std::timestamp;
    use std::type_info::{Self, TypeInfo};
    use aptos_framework::fungible_asset::{Self, MintRef, TransferRef, BurnRef, Metadata, FungibleAsset, FungibleStore};
    use aptos_framework::dispatchable_fungible_asset;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::function_info;
    use aptos_framework::account;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::event;
    use std::string::{Self as string, String, utf8};

    use dev::QiaraTokensCoreV3::{Self as TokensCore};

    use dev::QiaraCapabilitiesV1::{Self as capabilities};
    use dev::QiaraStorageV1::{Self as storage};
    const ADMIN: address = @dev;

    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_NOT_AUTHORIZED_FOR_CLAIMING: u64 = 2;

// === ACCESS === //
    struct Access has store, key, drop {}
    struct Permission has copy, key, drop {}

    public fun give_access(s: &signer): Access {
        assert!(signer::address_of(s) == @dev, ERROR_NOT_ADMIN);
        Access {}
    }

    public fun give_permission(access: &Access): Permission {
        Permission {}
    }
    
// === STRUCTS === //

    struct Timers has key {
        creation: u64,
        last_claimed: u64,
    }

// === INIT === //
    public fun init_qiara(admin: &signer){
        assert!(signer::address_of(admin) == @dev, ERROR_NOT_ADMIN);
        if (!exists<Timers>(@dev)) {
            move_to(admin, Timers { creation: timestamp::now_seconds(), last_claimed: timestamp::now_seconds()});
        };
    }

// === ENTRY FUNCTIONS === //
    public fun change_last_claim(claimer: &signer, perm: Permission) acquires Timers {
        assert!(capabilities::assert_wallet_capability(signer::address_of(claimer), utf8(b"QiaraToken"), utf8(b"INFLATION_CLAIM")), ERROR_NOT_AUTHORIZED_FOR_CLAIMING);
        let timers = borrow_global_mut<Timers>(@dev);
        timers.last_claimed = timestamp::now_seconds();
    }


// === HELPFER FUNCTIONS === //

    #[view]
    public fun get_last_claimed(): u64 acquires Timers{
        borrow_global<Timers>(@dev).last_claimed
    }

    #[view]
    public fun get_inflation(): u64 {
        storage::expect_u64(storage::viewConstant(utf8(b"QiaraToken"), utf8(b"INFLATION")))
    }

    #[view]
    public fun get_inflation_debt(): u64 {
        storage::expect_u64(storage::viewConstant(utf8(b"QiaraToken"), utf8(b"INFLATION_DEBT")))
    }

    #[view]
    public fun get_minimal_fee(): u64 { // 500
        storage::expect_u64(storage::viewConstant(utf8(b"QiaraToken"), utf8(b"BURN_FEE_MINIMAL")))
    }

    #[view]
    public fun get_burn_fee(): u64 { // 500
        storage::expect_u64(storage::viewConstant(utf8(b"QiaraToken"), utf8(b"BURN_FEE")))
    }

    #[view]
    public fun get_burn_fee_increase(): u64 { // 100
        storage::expect_u64(storage::viewConstant(utf8(b"QiaraToken"), utf8(b"BURN_INCREASE")))
    }


    #[view]
    public fun get_month(): u64  acquires Timers{ // 0
        let timers = borrow_global<Timers>(ADMIN);
        ((timestamp::now_seconds() - timers.creation ) / 2_629_743)
    }

    #[view]
    public fun claimable(circulating_supply: u128): u128 acquires Timers {
        let timers = borrow_global_mut<Timers>(ADMIN);

        // Seconds in a year
        let seconds_per_year = 31_536_000; // 365*24*60*60

        // Time since last claim
        let delta_seconds = timestamp::now_seconds() - timers.last_claimed;

        // Calculate claimable amount proportionally
        (circulating_supply * (get_inflation() as u128) * (delta_seconds as u128)) / ((seconds_per_year as u128) * 10_000)
    }

}