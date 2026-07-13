module dev::QiaraTokensQiaraV41 {
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

    use event::QiaraEventV1::{Self as Event};

    use dev::QiaraCapabilitiesV18::{Self as capabilities};
    use dev::QiaraStorageV18::{Self as storage};

    use dev::QiaraTokenTypesV41::{Self as TokensType};

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
    struct Timers has copy,key, drop {
        creation: u64,
        last_claimed: u64,
    }


    struct QiaraData has copy, drop {
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
        base_burned_qiara_rate: u64,
        burned_qiara_rate: u64,
        qiara_supply: u256,
        burned_qiara: u256,
        ratio: u256
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
    }


// === HELPER FUNCTIONS === //

    public fun emit_qiara_events() acquires Timers {
        let qiara_data = get_qiara_data();

        let data = vector[
            Event::create_data_struct(utf8(b"qiara_supply"), utf8(b"u256"), bcs::to_bytes(&qiara_data.qiara_supply)),
            Event::create_data_struct(utf8(b"total_burned"), utf8(b"u256"), bcs::to_bytes(&qiara_data.burned_qiara)),
            Event::create_data_struct(utf8(b"inflation"), utf8(b"u64"), bcs::to_bytes(&qiara_data.actual_inflation)),
            Event::create_data_struct(utf8(b"burn_fee"), utf8(b"u64"), bcs::to_bytes(&qiara_data.actual_burn_fee)),
            Event::create_data_struct(utf8(b"burned_qiara_rate"), utf8(b"u64"), bcs::to_bytes(&qiara_data.burned_qiara_rate)),

        ];
        Event::emit_qiara_burn_event(data);

    }
    #[view]
    /// Return the address of the managed fungible asset that's created when this module is deployed.
    public fun get_metadata(symbol:String): Object<Metadata> {
        let asset_address = object::create_object_address(&ADMIN, bcs::to_bytes(&TokensType::convert_token_nickName_to_name(symbol))); // Ethereum -> Qiara31 Ethereum
        object::address_to_object<Metadata>(asset_address)
    }

// === VIEW FUNCTIONS === //
    #[view]
    public fun get_qiara_data(): QiaraData acquires Timers {
        let timers = borrow_global<Timers>(@dev);
        let (burned_qiara, qiara_supply, ratio) = get_ratio();
        QiaraData {
            timers: *timers,
            epoch: get_epoch(),
            inflation: get_inflation(),
            actual_inflation: get_actual_inflation(),
            inflation_minimal: get_minimal_inflation(),
            inflation_debt: get_inflation_debt(),
            burn_fee: get_burn_fee(),
            actual_burn_fee: Self::burn_fee(), // Explicitly calls the view function
            burn_fee_increase: get_burn_fee_increase(),
            burn_fee_minimal: get_burn_fee_minimal(),
            validator_emissions_rate: get_emissions_validators(),
            validator_emissions: calculate_emissions(),
            base_burned_qiara_rate: get_locked_qiara_rate(),
            burned_qiara_rate: get_burned_qiara_rate(),
            qiara_supply: qiara_supply,
            burned_qiara: burned_qiara,
            ratio: ratio,
        }
    }


    #[view]
    public fun get_actual_inflation(): (u64)  {
        let inflation_debt = get_inflation_debt();
        let save_inflation;
        if( inflation_debt > get_inflation() ) {
            save_inflation = get_minimal_inflation();
        } else {
            save_inflation = get_inflation() - inflation_debt;
        };
        (save_inflation)
    }

    #[view]
    public fun get_ratio(): (u256,u256,u256)  {
        let burned_qiara_supply_opt = fungible_asset::supply(get_metadata(utf8(b"Burned Qiara")));
        let burned_qiara_supply =std::option::destroy_some(burned_qiara_supply_opt);

        let qiara_supply_opt = fungible_asset::supply(get_metadata(utf8(b"Qiara")));
        let qiara_supply =std::option::destroy_some(qiara_supply_opt);

        ((burned_qiara_supply as u256), (qiara_supply as u256), (burned_qiara_supply*1_000_000*100 / qiara_supply) as u256)
    }

    #[view]
    public fun get_burned_qiara_rate(): u64 {
        let base_reward_rate = get_locked_qiara_rate();
        let (_,_, ratio) = get_ratio();
        base_reward_rate + (ratio as u64)/10

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

}

