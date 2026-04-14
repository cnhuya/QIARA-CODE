module dev::QiaraTokenVaultsV2{
    use std::signer;
    use std::timestamp;
    use std::vector;    
    use std::bcs;
    use std::string::{Self as String, String, utf8};
    use std::table::{Self as table, Table};
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    use aptos_std::string_utils ::{Self as string_utils};
    use aptos_framework::fungible_asset::{Self, MintRef, TransferRef, BurnRef, Metadata, FungibleAsset, FungibleStore};
    use aptos_framework::dispatchable_fungible_asset;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::account;
    use event::QiaraEventV1::{Self as Event};

    use dev::QiaraTokensMetadataV3::{Self as TokensMetadata};
    use dev::QiaraTokensCoreV3::{Self as TokensCore, CoinMetadata, Access as TokensCoreAccess};
    use dev::QiaraTokensRatesV3::{Self as TokensRates, Access as TokensRatesAccess};
    use dev::QiaraTokensTiersV3::{Self as TokensTiers};

    use dev::QiaraMarginV2::{Self as Margin, Access as MarginAccess};
    use dev::QiaraRanksV2::{Self as Points, Access as PointsAccess};

    use dev::QiaraSharedV1::{Self as Shared};
    
    use dev::QiaraChainTypesV4::{Self as ChainTypes};

// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_INVALID_VAULT_TYPE: u64 = 2;

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


    struct Permissions has key, store, drop {
        margin: MarginAccess,
        points: PointsAccess,
        tokens_rates: TokensRatesAccess,
        tokens_core: TokensCoreAccess,
    }


// === STRUCTS === //
    struct GlobalVault has key, copy {
        //  token, chain, provider
        additional_rewards: Map<String,u256>,
        protocol_reserves: Map<String,u256>,
        protocol_revenue: Map<String,u256>
    }


// === INIT === //
    fun init_module(admin: &signer){
        if (!exists<GlobalVault>(@dev)) {
            move_to(admin, GlobalVault { additional_rewards: map::new<String, u256>(),protocol_reserves: map::new<String, u256>(),protocol_revenue: map::new<String, u256>() });
        };
        if (!exists<Permissions>(@dev)) {
            move_to(admin, Permissions {margin: Margin::give_access(admin), points: Points::give_access(admin), tokens_rates:  TokensRates::give_access(admin), tokens_core: TokensCore::give_access(admin)});
        };
    }

// === ENTRY FUN === //
    fun tttta(number: u64){
        abort(number);
    }

    public fun add_accumulated_rewards(type: String, token: String ,value: u256, cap: Permission) acquires GlobalVault{
        {
        let rewards = find_vault(borrow_global_mut<GlobalVault>(@dev),type, token);

        *rewards = *rewards + value;
        };

        let data = vector[
            // Items from the event top-level fields
            Event::create_data_struct(utf8(b"token"), utf8(b"string"), bcs::to_bytes(&token)),
            Event::create_data_struct(utf8(b"value"), utf8(b"u256"), bcs::to_bytes(&value)),
        ];

        Event::emit_historical_event(type, data);

    }

    public fun fast_add_accumulated_rewards(token: String , value: u256, cap: Permission) acquires GlobalVault{
        let value_protocol_revenue = value / 2;
        let value_protocol_reserves = value-value_protocol_revenue;

        add_accumulated_rewards(utf8(b"Protocol Revenue"), token, value_protocol_revenue, give_permission(&Access{}));
        add_accumulated_rewards(utf8(b"Protocol Reserves"), token, value_protocol_reserves, give_permission(&Access{}));
    }


// === PUBLIC VIEWS === //

    #[view]
    public fun return_vaults(tokens: vector<String>): GlobalVault acquires GlobalVault {
        return *borrow_global<GlobalVault>(@dev)
    }

// === MUT RETURNS === //
    fun find_vault(vaults: &mut GlobalVault, type: String, token: String): &mut u256 {
        // 1. Identify which map we are targeting
        let target_map = if (type == utf8(b"Protocol Revenue")) {
            &mut vaults.protocol_revenue
        } else if (type == utf8(b"Protocol Reserves")) {
            &mut vaults.protocol_reserves
        } else if (type == utf8(b"Additional Rewards")) {
            &mut vaults.additional_rewards
        } else {
            abort(ERROR_INVALID_VAULT_TYPE)
        };

        if (!map::contains_key(target_map, &token)) {
            map::add(target_map, token, 0);
        };

        map::borrow_mut(target_map, &token)
    }
}
