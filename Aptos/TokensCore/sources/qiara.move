module dev::QiaraTokensQiaraV30 {
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
    use aptos_framework::object::{Self, Object, ConstructorRef};
    use aptos_framework::event;
    use std::string::{Self as string, String, utf8};

    use dev::QiaraCapabilitiesV14::{Self as capabilities};
    use dev::QiaraStorageV14::{Self as storage};

    use dev::QiaraTokenTypesV30::{Self as TokensType};

    use dev::QiaraGenesisV2::{Self as Genesis};

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
    struct Timers has copy,key {
        creation: u64,
        last_claimed: u64,
    }

    struct Tokenomics has copy,key{
        burned: u128,
        minted: u128,
        initial_supply: u128,
    }

    struct QiaraData has copy {
        timers: Timers,
        epoch: u64,
        inflation: u64,
        actual_inflation: u64,
        inflation_minimal: u64,
        inflation_debt: u64,
        burn_fee: u64,
        actual_burn_fee: u64,
        burn_fee_increase: u64,
        burn_fee_minimal: u64,
        validator_emissions_rate: u64,
        validator_emissions: u64,
        locked_qiara_rate: u64,
        tokenomics: Tokenomics,
        current_supply: u128,
        locked_qiara: u128,
    }

// === ENTRY FUNCTIONS === //
    public fun change_last_claim(shared:String, perm: Permission) acquires Timers {
        assert!(capabilities::assert_wallet_capability(shared, utf8(b"QiaraToken"), utf8(b"INFLATION_CLAIM")), ERROR_NOT_AUTHORIZED_FOR_CLAIMING);
        let timers = borrow_global_mut<Timers>(@dev);
        timers.last_claimed = timestamp::now_seconds();
    }

    public entry fun init_qiara(admin: &signer){
        let deploy_addr = signer::address_of(admin);

        if (!exists<Timers>(@dev)) {
            move_to(admin, Timers { creation: timestamp::now_seconds(), last_claimed: timestamp::now_seconds()});
        };
        if (!exists<Tokenomics>(@dev)) {
            move_to(admin, Tokenomics { burned: 0, minted: 0, initial_supply:  option::destroy_with_default(fungible_asset::supply(get_metadata(utf8(b"Qiara"))), 0),});
        };
    }


// === HELPER FUNCTIONS === //

    public fun accrue_burned_tokens(amount: u128, perm: Permission) acquires Tokenomics {
        let tokenomics = borrow_global_mut<Tokenomics>(@dev);
        tokenomics.burned = tokenomics.burned + amount;
    }

    public fun accrue_minted_tokens(amount: u128, perm: Permission) acquires Tokenomics {
        let tokenomics = borrow_global_mut<Tokenomics>(@dev);
        tokenomics.minted = tokenomics.minted + amount;
    }

    #[view]
    /// Return the address of the managed fungible asset that's created when this module is deployed.
    public fun get_metadata(symbol:String): Object<Metadata> {
        let asset_address = object::create_object_address(&ADMIN, bcs::to_bytes(&TokensType::convert_token_nickName_to_name(symbol))); // Ethereum -> Qiara31 Ethereum
        object::address_to_object<Metadata>(asset_address)
    }

// === VIEW FUNCTIONS === //
#[view]
    public fun get_qiara_data(): QiaraData acquires Timers, Tokenomics {
        let tokenomics = borrow_global<Tokenomics>(@dev);
        let inflation_debt = get_inflation_debt();
        let save_inflation;
        if( inflation_debt > get_inflation() ) {
            save_inflation = get_minimal_inflation();
        } else {
            save_inflation = get_inflation() - inflation_debt;
        };
        let timers = borrow_global<Timers>(@dev);
        QiaraData {
            timers: *timers,
            epoch: get_epoch(),
            inflation: get_inflation(),
            actual_inflation: save_inflation,
            inflation_minimal: get_minimal_inflation(),
            inflation_debt: get_inflation_debt(),
            burn_fee: get_burn_fee(),
            actual_burn_fee: Self::burn_fee(), // Explicitly calls the view function
            burn_fee_increase: get_burn_fee_increase(),
            burn_fee_minimal: get_burn_fee_minimal(),
            validator_emissions_rate: get_emissions_validators(),
            validator_emissions: calculate_emissions(),
            locked_qiara_rate: get_locked_qiara_rate(),
            tokenomics: *tokenomics,
            current_supply: 2000000000000 + tokenomics.initial_supply + tokenomics.minted - tokenomics.burned,
            locked_qiara: option::destroy_with_default(fungible_asset::supply(get_metadata(utf8(b"Burned Qiara"))), 0), // Safely unwraps Option<u128>
        }
    }

    #[view]
    public fun get_last_claimed(): u64 acquires Timers {
        borrow_global<Timers>(@dev).last_claimed
    }

    #[view] 
    public fun get_inflation(): u64 { // 10%
        storage::expect_u64(storage::viewConstant(utf8(b"QiaraToken"), utf8(b"INFLATION")))
    }

    #[view]
    public fun get_minimal_inflation(): u64 { // 10%
        storage::expect_u64(storage::viewConstant(utf8(b"QiaraToken"), utf8(b"MINIMAL_INFLATION")))
    }

    #[view]
    public fun get_emissions_validators(): u64 { // 1%
        storage::expect_u64(storage::viewConstant(utf8(b"QiaraToken"), utf8(b"EMISSIONS_VALIDATORS")))
    }

    
    #[view]
    public fun get_locked_qiara_rate(): u64 { // 25%
        storage::expect_u64(storage::viewConstant(utf8(b"QiaraToken"), utf8(b"LOCKED_QIARA_REWARD_RATE")))
    }

    #[view] 
    public fun get_inflation_debt(): u64 { // 0.025%
        get_epoch() * storage::expect_u64(storage::viewConstant(utf8(b"QiaraToken"), utf8(b"INFLATION_DEBT")))
    }

    #[view] 
    public fun get_burn_fee(): u64 { // 0.001%
        storage::expect_u64(storage::viewConstant(utf8(b"QiaraToken"), utf8(b"BURN_FEE")))
    }

    #[view]
    public fun get_burn_fee_minimal(): u64 { // 0.001%
        storage::expect_u64(storage::viewConstant(utf8(b"QiaraToken"), utf8(b"BURN_FEE_MINIMAL")))
    }

    #[view]
    public fun get_burn_fee_increase(): u64 { // 0.00025%
        get_epoch() * storage::expect_u64(storage::viewConstant(utf8(b"QiaraToken"), utf8(b"BURN_INCREASE")))
    }

    #[view]
    public fun get_epoch(): u64 acquires Timers { // 0
        let timers = borrow_global<Timers>(ADMIN);
        ((timestamp::now_seconds() - timers.creation ) / (Genesis::return_epoch_duration() as u64)) as u64
    }

    #[view]
    public fun claimable(circulating_supply: u128): u128 acquires Timers {
        let timers = borrow_global_mut<Timers>(ADMIN);

        // Seconds in a year
        let seconds_per_year = 31_536_000; // 365*24*60*60

        // Time since last claim
        let delta_seconds = timestamp::now_seconds() - timers.last_claimed;
        let actual_inflation = (get_inflation() - get_inflation_debt()) / 1_000_000  / 100; // Recheck later for math if the /100 is correct
        // Calculate claimable amount proportionally
        (circulating_supply * (actual_inflation as u128) * (delta_seconds as u128)) / (seconds_per_year as u128)
    }


    #[view]
    public fun burn_fee(): u64 acquires Timers {
        get_burn_fee_increase() + get_burn_fee()
    }

    #[view]
    public fun burn_calculation(amount: u64): (u64) acquires Timers {
        let fee = burn_fee();
        let scale = 100_000_000;
        
        let burn_amount = (amount *(fee)) / scale;
        if(burn_amount == 0){
            if(get_burn_fee_minimal() > amount){
                return amount;
            } else {
                return get_burn_fee_minimal();                
            };
        };
        return if(burn_amount > get_burn_fee_minimal()) {burn_amount} else {get_burn_fee_minimal()}
    }

    #[view]
    public fun calculate_emissions(): (u64) {
        let emissions = get_emissions_validators();
        let current_supply = option::destroy_with_default(fungible_asset::supply(get_metadata(utf8(b"Qiara"))), 0);
        return (emissions * (current_supply as u64)) / 1_000_000 / 100
    }

    #[view]
    public fun return_qiara_supply(): (u128) {
        option::destroy_with_default(fungible_asset::supply(get_metadata(utf8(b"Qiara"))), 0)
    }
}

