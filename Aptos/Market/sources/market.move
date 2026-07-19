module dev::QiaraVaultsV61 {
    use std::signer;
    use std::string::{Self as String, String, utf8};
    use std::timestamp;
    use std::vector;
    use std::type_info::{Self, TypeInfo};
    use std::table::{Self as table, Table};
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    use aptos_std::string_utils ::{Self as string_utils};
    use std::bcs;
    use aptos_framework::from_bcs;

    use aptos_framework::fungible_asset::{Self, MintRef, TransferRef, BurnRef, Metadata, FungibleAsset, FungibleStore};
    use aptos_framework::dispatchable_fungible_asset;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::account;

    use dev::QiaraTokensCoreV45::{Self as TokensCore, CoinMetadata, Access as TokensCoreAccess};
    use dev::QiaraTokensMetadataV45::{Self as TokensMetadata, VMetadata, Access as TokensMetadataAccess};
    use dev::QiaraTokensTiersV45::{Self as TokensTiers};
    use dev::QiaraWrapperGateV45::{Self as WrapperGate};

    use dev::QiaraMarginV45::{Self as Margin, Access as MarginAccess};
    use dev::QiaraRanksV45::{Self as Points, Access as PointsAccess};
    use dev::QiaraRIV45::{Self as RI};
    use dev::QiaraBurnedQiaraV45::{Self as BurnedQiara};

    use dev::QiaraTokenTypesV45::{Self as TokensTypes};
    use dev::QiaraChainTypesV45::{Self as ChainTypes};
    use dev::QiaraProviderTypesV45::{Self as ProviderTypes};

    use dev::QiaraStorageV18::{Self as storage, Access as StorageAccess};
    use dev::QiaraCapabilitiesV18::{Self as capabilities, Access as CapabilitiesAccess};

    use dev::QiaraSharedV15::{Self as Shared, Access as SharedAccess};

    use dev::QiaraGasV11::{Self as Gas, Access as GasAccess};

    use dev::QiaraLiquidityV60::{Self as Liquidity, Access as LiquidityAccess};
    use dev::QiaraTokenVaultsV60::{Self as TokenVaults, Access as TokenVaultsAccess};


    use event::QiaraEventV1::{Self as Event};

// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_VAULT_NOT_INITIALIZED: u64 = 99;
    const ERROR_INSUFFICIENT_BALANCE: u64 = 3;
    const ERROR_USER_VAULT_NOT_INITIALIZED: u64 = 4;
    const ERROR_NOT_ENOUGH_LIQUIDITY: u64 = 5;
    const ERROR_NOT_ELIGIBLE_FOR_LIQUIDATION: u64 = 6;
    const ERROR_INVALID_COIN_TYPE: u64 = 6;
    const ERROR_BORROW_COLLATERAL_OVERFLOW: u64 = 7;
    const ERROR_INSUFFICIENT_COLLATERAL: u64 = 8;
    const ERROR_NO_PENDING_DEPOSITS_FOR_THIS_VAULT_PROVIDER: u64 = 9;
    const ERROR_NO_DEPOSITS_FOR_THIS_VAULT_PROVIDER: u64 = 10;
    const ERROR_CANT_LIQUIDATE_THIS_VAULT: u64 = 11;
    const ERROR_CANT_ACRUE_THIS_VAULT: u64 = 12;
    const ERROR_NO_VAULT_FOUND: u64 = 13;
    const ERROR_NO_VAULT_FOUND_FULL_CYCLE: u64 = 14;
    const ERROR_UNLOCK_BIGGER_THAN_LOCK: u64 = 15;
    const ERROR_NOT_ENOUGH_MARGIN: u64 = 16;
    const ERROR_INVALID_TOKEN: u64 = 17;
    const ERROR_TOKEN_NOT_INITIALIZED_FOR_THIS_CHAIN: u64 = 18;
    const ERROR_PROVIDER_DOESNT_SUPPORT_THIS_TOKEN_ON_THIS_CHAIN: u64 = 19;
    const ERROR_SENDER_DOESNT_MATCH_SIGNER: u64 = 20;
    const ERROR_WITHDRAW_LIMIT_EXCEEDED: u64 = 21;
    const ERROR_ARGUMENT_LENGHT_MISSMATCH: u64 = 22;
    const ERROR_NOT_ENOUGH_CREDITS: u64 = 23;


    const ERROR_A: u64 = 101;
    const ERROR_B: u64 = 102;
    const ERROR_C: u64 = 103;
// === ACCESS === //
    struct Access has store, key, drop {}
    struct Permission has store, key, drop, copy {}

    public fun give_access(s: &signer): Access {
        assert!(signer::address_of(s) == @dev, ERROR_NOT_ADMIN);
        Access {}
    }

    public fun give_permission(access: &Access): Permission {
        Permission {}
    }

    struct Permissions has key, store, drop {
        liquidity: LiquidityAccess,
        token_vaults: TokenVaultsAccess,
        margin: MarginAccess,
        points: PointsAccess,
        tokens_core: TokensCoreAccess,
        tokens_metadata: TokensMetadataAccess,
        storage: StorageAccess,
        capabilities: CapabilitiesAccess,
        gas: GasAccess,
        shared_access: SharedAccess
    }

// === FUNCTIONS === //
    fun init_module(admin: &signer){
        if (!exists<Permissions>(@dev)) {
            move_to(admin, Permissions {shared_access: Shared::give_access(admin), gas: Gas::give_access(admin), token_vaults: TokenVaults::give_access(admin), liquidity: Liquidity::give_access(admin), margin: Margin::give_access(admin), points: Points::give_access(admin), tokens_core: TokensCore::give_access(admin),tokens_metadata: TokensMetadata::give_access(admin), storage:  storage::give_access(admin), capabilities:  capabilities::give_access(admin)});
        };
    }

// === CONSENSUS INTERFACE === //
    /// Deposit on behalf of `recipient`
    /// No need for recipient to have signed anything.

    public fun c_bridge_deposit(validator: &signer, shared: String, sender: vector<u8>, token: String, chain: String, provider: String, amount: u64, lend_rate: u64, reward: u64, permission: Permission) acquires Permissions {
        Shared::assert_is_sub_owner(shared, sender);
        let amount_u256 = (amount as u256)*1000000000000000000;

        let (total_liquidity, total_borrowed, total_deposited, total_staked, total_accumulated_rewards, total_native_accumulated_rewards, total_accumulated_interest, virtual_borrowed, virtual_deposited, total_shares, last_update) = Liquidity::return_raw_vault(token, chain, provider);
        let (_, _fee) = TokensMetadata::impact(token, amount_u256/1000000000000000000, total_deposited/1000000000000000000, true, utf8(b"spot"), TokensMetadata::give_permission(&borrow_global<Permissions>(@dev).tokens_metadata));
      
        let gas_rate = Gas::add_deposit(token, amount_u256, Gas::give_permission(&borrow_global<Permissions>(@dev).gas));
        
        let (amount_u256_taxed,fee) = assert_minimal_fee(token, chain, provider,  amount_u256, _fee);
        if(amount_u256_taxed == 0) { return };

        Liquidity::admin_accrue_rewards_from_lz(token, chain, provider, reward, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));
        
        let obj = Shared::ensure_shared_fungible_storage(shared,TokensCore::get_metadata(token), Shared::give_permission(&borrow_global<Permissions>(@dev).shared_access));
        let fa = TokensCore::withdraw(shared, obj, amount, chain);

        // 1. Deposit standard assets and retrieve physical LP shares
        let shares_fa = Liquidity::deposit_token(token, chain, provider, fa, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));

        // 2. Deposit physical LP shares directly using Shared's secure storage logic
        let lp_metadata = Liquidity::return_lp_metadata(token, chain, provider);
        let user_lp_store = Shared::ensure_shared_fungible_storage(shared, lp_metadata, Shared::give_permission(&borrow_global<Permissions>(@dev).shared_access));
        fungible_asset::deposit(user_lp_store, shares_fa);

        Margin::update_reward_index(shared, sender, token, chain, provider, total_accumulated_rewards, Margin::give_permission(&borrow_global<Permissions>(@dev).margin)); 
        Margin::add_deposit(shared, sender, token, chain, provider, amount_u256_taxed, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));

        let (total_rewards, total_interest, user_borrow_interest, user_lend_rewards, user_points, total_apr, borrow_apr, utilization, price, user_gas_reducted, user_xp_increased, shares_ratio) = new_accrue(shared, sender, token, chain, provider);

        let data = vector[
            Event::create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&utf8(b"zk"))),
            Event::create_data_struct(utf8(b"validator"), utf8(b"vector<u8>"), bcs::to_bytes(&signer::address_of(validator))),
            Event::create_data_struct(utf8(b"recipient"), utf8(b"vector<u8>"), bcs::to_bytes(&sender)),
            Event::create_data_struct(utf8(b"token"), utf8(b"string"), bcs::to_bytes(&token)),
            Event::create_data_struct(utf8(b"chain"), utf8(b"string"), bcs::to_bytes(&chain)),
            Event::create_data_struct(utf8(b"provider"), utf8(b"string"), bcs::to_bytes(&provider)),

            Event::create_data_struct(utf8(b"amount"), utf8(b"u256"), bcs::to_bytes(&amount_u256_taxed)),
            Event::create_data_struct(utf8(b"fee"), utf8(b"u256"), bcs::to_bytes(&fee)),
            Event::create_data_struct(utf8(b"points"), utf8(b"u256"), bcs::to_bytes(&user_points)),
            Event::create_data_struct(utf8(b"lend_rewards"), utf8(b"u256"), bcs::to_bytes(&user_lend_rewards)),
        
            Event::create_data_struct(utf8(b"total_rewards"), utf8(b"u256"), bcs::to_bytes(&total_rewards)),
            Event::create_data_struct(utf8(b"total_interest"), utf8(b"u256"), bcs::to_bytes(&total_interest)),
            Event::create_data_struct(utf8(b"total_apr"), utf8(b"u256"), bcs::to_bytes(&total_apr)),
            Event::create_data_struct(utf8(b"borrow_apr"), utf8(b"u256"), bcs::to_bytes(&borrow_apr)),
            Event::create_data_struct(utf8(b"utilization"), utf8(b"u256"), bcs::to_bytes(&utilization)),

            Event::create_data_struct(utf8(b"additional_xp_from_ref_code"), utf8(b"u256"), bcs::to_bytes(&user_xp_increased)),
            Event::create_data_struct(utf8(b"fee_reduced_from_ref_code"), utf8(b"u256"), bcs::to_bytes(&user_gas_reducted)),

            Event::create_data_struct(utf8(b"ratio"), utf8(b"u256"), bcs::to_bytes(&shares_ratio)),

            Event::create_data_struct(utf8(b"total_deposited"), utf8(b"u256"), bcs::to_bytes(&total_deposited)),
            Event::create_data_struct(utf8(b"total_borrowed"), utf8(b"u256"), bcs::to_bytes(&total_borrowed)),
            Event::create_data_struct(utf8(b"total_staked"), utf8(b"u256"), bcs::to_bytes(&total_staked)),
            Event::create_data_struct(utf8(b"price"), utf8(b"u256"), bcs::to_bytes(&price)),
            
        ];

        if(user_borrow_interest > 0){
            vector::push_back(&mut data, Event::create_data_struct(utf8(b"borrow_interest"), utf8(b"u256"), bcs::to_bytes(&user_borrow_interest)))
        };
        Event::emit_market_event(utf8(b"Bridge Deposit"), data);
    }

    // Recipient needs to be address here, in case permissioneless user wants to withdraw to existing Supra wallet.
    public fun c_bridge_withdraw(validator: &signer, shared: String, sender: vector<u8>, recipient: address, token: String, chain: String, provider: String, amount: u64, lend_rate: u64, reward: u64,permission: Permission) acquires Permissions {
        let (total_liquidity,total_borrowed, total_deposited, total_staked, total_accumulated_rewards, total_native_accumulated_rewards, total_accumulated_interest, virtual_borrowed, virtual_deposited, total_shares, last_update) = Liquidity::return_raw_vault(token, chain, provider);
        Liquidity::admin_accrue_rewards_from_lz(token, chain, provider, reward, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));

        let amount_u256 = (amount as u256)*1000000000000000000;
        
        let (_, _fee) = TokensMetadata::impact(token, amount_u256/1000000000000000000, total_deposited/1000000000000000000, true, utf8(b"spot"), TokensMetadata::give_permission(&borrow_global<Permissions>(@dev).tokens_metadata));
      
        let gas_rate = Gas::add_withdraw(token, amount_u256, Gas::give_permission(&borrow_global<Permissions>(@dev).gas));
        
        let (amount_u256_taxed,fee) = assert_minimal_fee(token, chain, provider,  amount_u256, _fee);
        if(amount_u256_taxed == 0) { return };

        Margin::update_reward_index(shared, sender, token, chain, provider, fee, Margin::give_permission(&borrow_global<Permissions>(@dev).margin)); 
        Margin::remove_deposit(shared, sender, token, chain, provider, amount_u256_taxed, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));

        // 1. Redeems LP shares from shared storage, depositing underlying into shared storage
        let lp_shares_to_redeem = amount_u256_taxed / 1000000000000000000;
        Liquidity::withdraw_token(shared, token, chain, provider, lp_shares_to_redeem, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));

        // 2. Withdraw from shared storage and transfer to the recipient's primary store
        let user_shared_store = Shared::ensure_shared_fungible_storage(shared, TokensCore::get_metadata(token), Shared::give_permission(&borrow_global<Permissions>(@dev).shared_access));
        let fa = TokensCore::withdraw(shared, user_shared_store, amount, chain);
        let user_storage = primary_fungible_store::ensure_primary_store_exists(recipient, TokensCore::get_metadata(token));
        TokensCore::deposit(shared, user_storage, fa, chain);

        let (total_rewards, total_interest, user_borrow_interest, user_lend_rewards, user_points, total_apr, borrow_apr, utilization, price, user_gas_reducted, user_xp_increased, shares_ratio) = new_accrue(shared, sender, token, chain, provider);

        let data = vector[
            Event::create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&utf8(b"zk"))),
            Event::create_data_struct(utf8(b"validator"), utf8(b"vector<u8>"), bcs::to_bytes(&signer::address_of(validator))),
            Event::create_data_struct(utf8(b"recipient"), utf8(b"vector<u8>"), bcs::to_bytes(&sender)),
            Event::create_data_struct(utf8(b"token"), utf8(b"string"), bcs::to_bytes(&token)),
            Event::create_data_struct(utf8(b"chain"), utf8(b"string"), bcs::to_bytes(&chain)),
            Event::create_data_struct(utf8(b"provider"), utf8(b"string"), bcs::to_bytes(&provider)),
            Event::create_data_struct(utf8(b"recipient"), utf8(b"address"), bcs::to_bytes(&recipient)),

            Event::create_data_struct(utf8(b"amount"), utf8(b"u256"), bcs::to_bytes(&amount_u256_taxed)),
            Event::create_data_struct(utf8(b"fee"), utf8(b"u256"), bcs::to_bytes(&fee)),
            Event::create_data_struct(utf8(b"points"), utf8(b"u256"), bcs::to_bytes(&user_points)),
            Event::create_data_struct(utf8(b"lend_rewards"), utf8(b"u256"), bcs::to_bytes(&user_lend_rewards)),

            Event::create_data_struct(utf8(b"total_rewards"), utf8(b"u256"), bcs::to_bytes(&total_rewards)),
            Event::create_data_struct(utf8(b"total_interest"), utf8(b"u256"), bcs::to_bytes(&total_interest)),
            Event::create_data_struct(utf8(b"total_apr"), utf8(b"u256"), bcs::to_bytes(&total_apr)),
            Event::create_data_struct(utf8(b"borrow_apr"), utf8(b"u256"), bcs::to_bytes(&borrow_apr)),
            Event::create_data_struct(utf8(b"utilization"), utf8(b"u256"), bcs::to_bytes(&utilization)),

            Event::create_data_struct(utf8(b"additional_xp_from_ref_code"), utf8(b"u256"), bcs::to_bytes(&user_xp_increased)),
            Event::create_data_struct(utf8(b"fee_reduced_from_ref_code"), utf8(b"u256"), bcs::to_bytes(&user_gas_reducted)),

            Event::create_data_struct(utf8(b"ratio"), utf8(b"u256"), bcs::to_bytes(&shares_ratio)),

            Event::create_data_struct(utf8(b"total_deposited"), utf8(b"u256"), bcs::to_bytes(&total_deposited)),
            Event::create_data_struct(utf8(b"total_borrowed"), utf8(b"u256"), bcs::to_bytes(&total_borrowed)),
            Event::create_data_struct(utf8(b"total_staked"), utf8(b"u256"), bcs::to_bytes(&total_staked)),
            Event::create_data_struct(utf8(b"price"), utf8(b"u256"), bcs::to_bytes(&price)),
        ];

        if(user_borrow_interest > 0){
            vector::push_back(&mut data, Event::create_data_struct(utf8(b"borrow_interest"), utf8(b"u256"), bcs::to_bytes(&user_borrow_interest)))
        };

        Event::emit_market_event(utf8(b"Bridge Withdraw"),data);
    }

    // Recipient needs to be address here, in case permissioneless user wants to borrow to existing Supra wallet.
    public fun c_bridge_borrow(validator: &signer, shared: String, sender: vector<u8>, recipient: address, token: String, chain: String, provider: String, amount: u64, lend_rate: u64, reward: u64, permission: Permission) acquires Permissions {
        let amount_u256 = (amount as u256)*1000000000000000000;

        let (total_liquidity, total_borrowed, total_deposited, total_staked, total_accumulated_rewards, total_native_accumulated_rewards, total_accumulated_interest, virtual_borrowed, virtual_deposited, total_shares, last_update) = Liquidity::return_raw_vault(token, chain, provider);

        let (_, _fee) = TokensMetadata::impact(token, amount_u256/1000000000000000000, total_deposited/1000000000000000000, true, utf8(b"spot"), TokensMetadata::give_permission(&borrow_global<Permissions>(@dev).tokens_metadata));
      
        let gas_rate = Gas::add_borrow(token, amount_u256, Gas::give_permission(&borrow_global<Permissions>(@dev).gas));
        
        let (amount_u256_taxed,fee) = assert_minimal_fee(token, chain, provider,  amount_u256, _fee);
        if(amount_u256_taxed == 0) { return };


        Margin::update_reward_index(shared, sender, token, chain, provider, fee, Margin::give_permission(&borrow_global<Permissions>(@dev).margin)); 
    
        Liquidity::admin_accrue_rewards_from_lz(token, chain, provider, reward, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));

        let storage = Liquidity::return_storage(token, chain, provider);
        let storage_address_string = non_user_storage_helper(&storage);

        let fa = TokensCore::withdraw(storage_address_string, storage, amount, chain);
        TokensCore::deposit(shared, primary_fungible_store::ensure_primary_store_exists(recipient,TokensCore::get_metadata(token)), fa, chain);

        assert!(total_deposited >= (amount as u256), ERROR_NOT_ENOUGH_LIQUIDITY);
        Liquidity::remove_deposit(token, chain, provider, amount_u256, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));

        Margin::add_borrow(shared, sender, token, chain, provider, (amount as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        Liquidity::add_borrow(token, chain, provider, amount_u256, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));
        let (total_rewards, total_interest, user_borrow_interest, user_lend_rewards, user_points, total_apr, borrow_apr, utilization, price, user_gas_reducted, user_xp_increased, shares_ratio) = new_accrue(shared,  sender, token, chain, provider);
        let data = vector[
            Event::create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&utf8(b"zk"))),
            Event::create_data_struct(utf8(b"validator"), utf8(b"vector<u8>"), bcs::to_bytes(&signer::address_of(validator))),
            Event::create_data_struct(utf8(b"sender"), utf8(b"vector<u8>"), bcs::to_bytes(&sender)),
            Event::create_data_struct(utf8(b"token"), utf8(b"string"), bcs::to_bytes(&token)),
            Event::create_data_struct(utf8(b"chain"), utf8(b"string"), bcs::to_bytes(&chain)),
            Event::create_data_struct(utf8(b"provider"), utf8(b"string"), bcs::to_bytes(&provider)),
            Event::create_data_struct(utf8(b"recipient"), utf8(b"address"), bcs::to_bytes(&recipient)),

            Event::create_data_struct(utf8(b"amount"), utf8(b"u256"), bcs::to_bytes(&amount_u256_taxed)),
            Event::create_data_struct(utf8(b"fee"), utf8(b"u256"), bcs::to_bytes(&fee)),
            Event::create_data_struct(utf8(b"points"), utf8(b"u256"), bcs::to_bytes(&user_points)),
            Event::create_data_struct(utf8(b"lend_rewards"), utf8(b"u256"), bcs::to_bytes(&user_lend_rewards)),

            Event::create_data_struct(utf8(b"total_rewards"), utf8(b"u256"), bcs::to_bytes(&total_rewards)),
            Event::create_data_struct(utf8(b"total_interest"), utf8(b"u256"), bcs::to_bytes(&total_interest)),
            Event::create_data_struct(utf8(b"total_apr"), utf8(b"u256"), bcs::to_bytes(&total_apr)),
            Event::create_data_struct(utf8(b"borrow_apr"), utf8(b"u256"), bcs::to_bytes(&borrow_apr)),
            Event::create_data_struct(utf8(b"utilization"), utf8(b"u256"), bcs::to_bytes(&utilization)),

            Event::create_data_struct(utf8(b"additional_xp_from_ref_code"), utf8(b"u256"), bcs::to_bytes(&user_xp_increased)),
            Event::create_data_struct(utf8(b"fee_reduced_from_ref_code"), utf8(b"u256"), bcs::to_bytes(&user_gas_reducted)),

            Event::create_data_struct(utf8(b"ratio"), utf8(b"u256"), bcs::to_bytes(&shares_ratio)),

            Event::create_data_struct(utf8(b"total_deposited"), utf8(b"u256"), bcs::to_bytes(&total_deposited)),
            Event::create_data_struct(utf8(b"total_borrowed"), utf8(b"u256"), bcs::to_bytes(&total_borrowed)),
            Event::create_data_struct(utf8(b"total_staked"), utf8(b"u256"), bcs::to_bytes(&total_staked)),
            Event::create_data_struct(utf8(b"price"), utf8(b"u256"), bcs::to_bytes(&price)),
        ];

        if(user_borrow_interest > 0){
            vector::push_back(&mut data, Event::create_data_struct(utf8(b"borrow_interest"), utf8(b"u256"), bcs::to_bytes(&user_borrow_interest)))
        };

        Event::emit_market_event(utf8(b"Bridge Borrow"),data);
    }

    public fun c_bridge_repay(validator: &signer, shared: String, sender: vector<u8>,token: String, chain: String, provider: String, amount: u64, lend_rate: u64, permission: Permission) acquires Permissions {
        let amount_u256 = (amount as u256)*1000000000000000000;
        let (total_liquidity, total_borrowed, total_deposited, total_staked, total_accumulated_rewards, total_native_accumulated_rewards, total_accumulated_interest, virtual_borrowed, virtual_deposited, total_shares, last_update) = Liquidity::return_raw_vault(token, chain, provider);
        let (_, fee) = TokensMetadata::impact(token, amount_u256, total_deposited, false, utf8(b"spot"), TokensMetadata::give_permission(&borrow_global<Permissions>(@dev).tokens_metadata));
        
        Margin::update_reward_index(shared, sender, token, chain, provider, fee, Margin::give_permission(&borrow_global<Permissions>(@dev).margin)); 
    
        let fa = TokensCore::mint(token, chain, amount, TokensCore::give_permission(&borrow_global<Permissions>(@dev).tokens_core)); 
        
        // UPGRADE: Deposit repayment directly into vault storage (Do not mint LP shares for repayments)
        let storage = Liquidity::return_storage(token, chain, provider);
        let storage_address_string = non_user_storage_helper(&storage);
        TokensCore::deposit(storage_address_string, storage, fa, chain);

        Margin::remove_borrow(shared, sender, token, chain, provider, (amount as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        
        Liquidity::add_deposit(token, chain, provider, amount_u256, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));
        Liquidity::remove_borrow(token, chain, provider, amount_u256, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));

        let (total_rewards, total_interest, user_borrow_interest, user_lend_rewards,user_points, total_apr, borrow_apr, utilization, price, user_gas_reducted, user_xp_increased, shares_ratio) = new_accrue(shared, sender, token, chain, provider);
        let data = vector[
            Event::create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&utf8(b"zk"))),
            Event::create_data_struct(utf8(b"validator"), utf8(b"vector<u8>"), bcs::to_bytes(&signer::address_of(validator))),
            Event::create_data_struct(utf8(b"sender"), utf8(b"vector<u8>"), bcs::to_bytes(&sender)),
            Event::create_data_struct(utf8(b"token"), utf8(b"string"), bcs::to_bytes(&token)),
            Event::create_data_struct(utf8(b"chain"), utf8(b"string"), bcs::to_bytes(&chain)),
            Event::create_data_struct(utf8(b"provider"), utf8(b"string"), bcs::to_bytes(&provider)),

            Event::create_data_struct(utf8(b"amount"), utf8(b"u256"), bcs::to_bytes(&amount_u256)),
            Event::create_data_struct(utf8(b"fee"), utf8(b"u256"), bcs::to_bytes(&fee)),
            Event::create_data_struct(utf8(b"points"), utf8(b"u256"), bcs::to_bytes(&user_points)),
            Event::create_data_struct(utf8(b"lend_rewards"), utf8(b"u256"), bcs::to_bytes(&user_lend_rewards)),

            Event::create_data_struct(utf8(b"total_rewards"), utf8(b"u256"), bcs::to_bytes(&total_rewards)),
            Event::create_data_struct(utf8(b"total_interest"), utf8(b"u256"), bcs::to_bytes(&total_interest)),
            Event::create_data_struct(utf8(b"total_apr"), utf8(b"u256"), bcs::to_bytes(&total_apr)),
            Event::create_data_struct(utf8(b"borrow_apr"), utf8(b"u256"), bcs::to_bytes(&borrow_apr)),
            Event::create_data_struct(utf8(b"utilization"), utf8(b"u256"), bcs::to_bytes(&utilization)),

            Event::create_data_struct(utf8(b"additional_xp_from_ref_code"), utf8(b"u256"), bcs::to_bytes(&user_xp_increased)),
            Event::create_data_struct(utf8(b"fee_reduced_from_ref_code"), utf8(b"u256"), bcs::to_bytes(&user_gas_reducted)),

            Event::create_data_struct(utf8(b"ratio"), utf8(b"u256"), bcs::to_bytes(&shares_ratio)),

            Event::create_data_struct(utf8(b"total_deposited"), utf8(b"u256"), bcs::to_bytes(&total_deposited)),
            Event::create_data_struct(utf8(b"total_borrowed"), utf8(b"u256"), bcs::to_bytes(&total_borrowed)),
            Event::create_data_struct(utf8(b"total_staked"), utf8(b"u256"), bcs::to_bytes(&total_staked)),
            Event::create_data_struct(utf8(b"price"), utf8(b"u256"), bcs::to_bytes(&price)),
        ];

        if(user_borrow_interest > 0){
            vector::push_back(&mut data, Event::create_data_struct(utf8(b"borrow_interest"), utf8(b"u256"), bcs::to_bytes(&user_borrow_interest)))
        };

        Event::emit_market_event(utf8(b"Bridge Repay"),data);

    }

    public entry fun c_bridge_claim_rewards(validator: &signer,  shared: String, sender: vector<u8>,  token: String, chain: String, provider: String) acquires Permissions {
        let (total_liquidity, total_borrowed, total_deposited, total_staked, total_accumulated_rewards, total_native_accumulated_rewards, total_accumulated_interest, virtual_borrowed, virtual_deposited, total_shares, last_update) = Liquidity::return_raw_vault(token, chain, provider);
        let (_,_,user_deposited, user_borrowed, _, user_rewards, _, user_interest, _, _, _, _, _, _,_) = Margin::get_user_raw_balance(shared, token, chain, provider);

        let reward_amount = user_rewards;
        let interest_amount = user_interest;

        let storage = Liquidity::return_storage(token, chain, provider);
        let storage_address_string = non_user_storage_helper(&storage);

        let (total_rewards, total_interest, user_borrow_interest, user_lend_rewards, user_points, total_apr, borrow_apr, utilization, price, user_gas_reducted, user_xp_increased, shares_ratio) = new_accrue(shared, sender, token, chain, provider);
        let data = vector[
            Event::create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&utf8(b"zk"))),
            Event::create_data_struct(utf8(b"validator"), utf8(b"vector<u8>"), bcs::to_bytes(&signer::address_of(validator))),
            Event::create_data_struct(utf8(b"sender"), utf8(b"vector<u8>"), bcs::to_bytes(&sender)),
            Event::create_data_struct(utf8(b"shared"), utf8(b"string"), bcs::to_bytes(&shared)),
            Event::create_data_struct(utf8(b"token"), utf8(b"string"), bcs::to_bytes(&token)),
            Event::create_data_struct(utf8(b"chain"), utf8(b"string"), bcs::to_bytes(&chain)),
            Event::create_data_struct(utf8(b"provider"), utf8(b"string"), bcs::to_bytes(&provider)),

            Event::create_data_struct(utf8(b"points"), utf8(b"u256"), bcs::to_bytes(&user_points)),
            Event::create_data_struct(utf8(b"lend_rewards"), utf8(b"u256"), bcs::to_bytes(&user_lend_rewards)),
            Event::create_data_struct(utf8(b"total_rewards"), utf8(b"u256"), bcs::to_bytes(&total_rewards)),
            Event::create_data_struct(utf8(b"total_interest"), utf8(b"u256"), bcs::to_bytes(&total_interest)),
            Event::create_data_struct(utf8(b"total_apr"), utf8(b"u256"), bcs::to_bytes(&total_apr)),
            Event::create_data_struct(utf8(b"borrow_apr"), utf8(b"u256"), bcs::to_bytes(&borrow_apr)),
            Event::create_data_struct(utf8(b"utilization"), utf8(b"u256"), bcs::to_bytes(&utilization)),

            Event::create_data_struct(utf8(b"additional_xp_from_ref_code"), utf8(b"u256"), bcs::to_bytes(&user_xp_increased)),
            Event::create_data_struct(utf8(b"fee_reduced_from_ref_code"), utf8(b"u256"), bcs::to_bytes(&user_gas_reducted)),

            Event::create_data_struct(utf8(b"ratio"), utf8(b"u256"), bcs::to_bytes(&shares_ratio)),

            Event::create_data_struct(utf8(b"total_deposited"), utf8(b"u256"), bcs::to_bytes(&total_deposited)),
            Event::create_data_struct(utf8(b"total_borrowed"), utf8(b"u256"), bcs::to_bytes(&total_borrowed)),
            Event::create_data_struct(utf8(b"total_staked"), utf8(b"u256"), bcs::to_bytes(&total_staked)),
            Event::create_data_struct(utf8(b"price"), utf8(b"u256"), bcs::to_bytes(&price)),
        ];

        if(user_borrow_interest > 0){
            vector::push_back(&mut data, Event::create_data_struct(utf8(b"borrow_interest"), utf8(b"u256"), bcs::to_bytes(&user_borrow_interest)))
        };


        if(reward_amount > interest_amount){
            let reward = (reward_amount - interest_amount);
            Event::create_data_struct(utf8(b"amount"), utf8(b"u256"), bcs::to_bytes(&reward));
            
            // Redeem shares and deposit underlying into shared storage
            Liquidity::withdraw_token(shared, token, chain, provider, reward, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));
            
            // Withdraw from shared storage and burn
            let user_shared_store = Shared::ensure_shared_fungible_storage(shared, TokensCore::get_metadata(token), Shared::give_permission(&borrow_global<Permissions>(@dev).shared_access));
            let fa = TokensCore::withdraw(shared, user_shared_store, (reward as u64), chain);
            TokensCore::burn_fa(token, chain, fa, TokensCore::give_permission(&borrow_global<Permissions>(@dev).tokens_core));
          
            assert!(total_deposited >= (reward as u256), ERROR_NOT_ENOUGH_LIQUIDITY);
            Event::emit_market_event(utf8(b"Bridge Claim Rewards"), data);
        } else{
            let interest = (interest_amount - reward_amount);
            Event::create_data_struct(utf8(b"amount"), utf8(b"u256"), bcs::to_bytes(&interest));

            Margin::remove_deposit(shared, sender, token, chain, provider, interest, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));

            let fa = TokensCore::mint(token, chain, (interest as u64), TokensCore::give_permission(&borrow_global<Permissions>(@dev).tokens_core)); 
            
            // UPGRADE: Deposit interest/yield directly into vault storage (Do not mint LP shares for yield payments)
            TokensCore::deposit(storage_address_string, storage, fa, chain);

            Liquidity::add_deposit(token, chain, provider, (interest as u256), Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));
            Event::emit_market_event(utf8(b"Bridge Pay Interest"), data);
        };
        Margin::remove_interest(shared, sender, token, chain, provider, (reward_amount as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        Margin::remove_rewards(shared, sender, token, chain, provider, (interest_amount as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
    }
// === NATIVE INTERFACE === //

    public entry fun stake(signer: &signer, shared: String, token: String, chain: String, provider: String, amount: u64) acquires Permissions {
        let sender = bcs::to_bytes(&signer::address_of(signer));
        let amount_u256 = (amount as u256)*1000000000000000000;
        let (total_liquidity,total_borrowed, total_deposited, total_staked, total_accumulated_rewards, total_native_accumulated_rewards, total_accumulated_interest, virtual_borrowed, virtual_deposited, total_shares, last_update) = Liquidity::return_raw_vault(token, chain, provider);


        let (_, _fee) = TokensMetadata::impact(token, amount_u256/1000000000000000000, total_deposited/1000000000000000000, true, utf8(b"spot"), TokensMetadata::give_permission(&borrow_global<Permissions>(@dev).tokens_metadata));
      
        let gas_rate = Gas::add_deposit(token, amount_u256, Gas::give_permission(&borrow_global<Permissions>(@dev).gas));
        
        let (amount_u256_taxed,fee) = assert_minimal_fee(token, chain, provider,  amount_u256, _fee);
        if(amount_u256_taxed == 0) { return };


        let obj = Shared::ensure_shared_fungible_storage(shared,TokensCore::get_metadata(token), Shared::give_permission(&borrow_global<Permissions>(@dev).shared_access));
        let fa = TokensCore::withdraw(shared, obj, amount, chain);
        
        // 1. Deposit underlying assets and retrieve physical LP shares
        let shares_fa = Liquidity::deposit_token(token, chain, provider, fa, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));
        Liquidity::add_stake(token, chain, provider, amount_u256_taxed, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));
        
        // UPGRADE: Deposit minted LP shares directly using Shared's secure storage logic
        let lp_metadata = Liquidity::return_lp_metadata(token, chain, provider);
        let user_lp_store = Shared::ensure_shared_fungible_storage(shared, lp_metadata, Shared::give_permission(&borrow_global<Permissions>(@dev).shared_access));
        fungible_asset::deposit(user_lp_store, shares_fa);

        Margin::update_reward_index(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider, total_accumulated_rewards, Margin::give_permission(&borrow_global<Permissions>(@dev).margin)); 
        Margin::add_stake(shared,bcs::to_bytes(&signer::address_of(signer)), token, chain, provider, amount_u256, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        let (total_rewards, total_interest, user_borrow_interest, user_lend_rewards,  user_points, total_apr, borrow_apr, utilization, price, user_gas_reducted, user_xp_increased, shares_ratio) = new_accrue(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider);
        let data = vector[
            Event::create_data_struct(utf8(b"sender"), utf8(b"address"), bcs::to_bytes(&signer::address_of(signer))),
            Event::create_data_struct(utf8(b"shared"), utf8(b"string"), bcs::to_bytes(&shared)),
            Event::create_data_struct(utf8(b"token"), utf8(b"string"), bcs::to_bytes(&token)),
            Event::create_data_struct(utf8(b"chain"), utf8(b"string"), bcs::to_bytes(&chain)),
            Event::create_data_struct(utf8(b"provider"), utf8(b"string"), bcs::to_bytes(&provider)),
            Event::create_data_struct(utf8(b"amount"), utf8(b"u256"), bcs::to_bytes(&amount_u256)),

            Event::create_data_struct(utf8(b"total_rewards"), utf8(b"u256"), bcs::to_bytes(&total_rewards)),
            Event::create_data_struct(utf8(b"total_interest"), utf8(b"u256"), bcs::to_bytes(&total_interest)),
            Event::create_data_struct(utf8(b"total_apr"), utf8(b"u256"), bcs::to_bytes(&total_apr)),
            Event::create_data_struct(utf8(b"borrow_apr"), utf8(b"u256"), bcs::to_bytes(&borrow_apr)),
            Event::create_data_struct(utf8(b"utilization"), utf8(b"u256"), bcs::to_bytes(&utilization)),

            Event::create_data_struct(utf8(b"additional_xp_from_ref_code"), utf8(b"u256"), bcs::to_bytes(&user_xp_increased)),
            Event::create_data_struct(utf8(b"fee_reduced_from_ref_code"), utf8(b"u256"), bcs::to_bytes(&user_gas_reducted)),

            Event::create_data_struct(utf8(b"ratio"), utf8(b"u256"), bcs::to_bytes(&shares_ratio)),

            Event::create_data_struct(utf8(b"total_deposited"), utf8(b"u256"), bcs::to_bytes(&total_deposited)),
            Event::create_data_struct(utf8(b"total_borrowed"), utf8(b"u256"), bcs::to_bytes(&total_borrowed)),
            Event::create_data_struct(utf8(b"total_staked"), utf8(b"u256"), bcs::to_bytes(&total_staked)),
            Event::create_data_struct(utf8(b"price"), utf8(b"u256"), bcs::to_bytes(&price)),

        ];
        Event::emit_market_event(utf8(b"Stake"), data);
    }

    public entry fun unstake(signer: &signer, shared: String, token: vector<String>, chain: vector<String>, provider: vector<String>, amount: vector<u64>) acquires Permissions {
        assert!(vector::length(&token) == vector::length(&chain), ERROR_ARGUMENT_LENGHT_MISSMATCH);
        let sender = bcs::to_bytes(&signer::address_of(signer));
        let vect_amnt = vector::empty<u256>();

        let len = vector::length(&token);
        while(len>0){
            let _chain = *vector::borrow(&chain, len-1);
            let _token = *vector::borrow(&token, len-1);
            let _provider = *vector::borrow(&provider, len-1);
            let _amount = *vector::borrow(&amount, len-1);
            let amount_u256 = (_amount as u256)*1000000000000000000;
            let (total_liquidity, total_borrowed, total_deposited, total_staked, total_accumulated_rewards, total_native_accumulated_rewards, total_accumulated_interest, virtual_borrowed, virtual_deposited, total_shares, last_update) = Liquidity::return_raw_vault(_token, _chain, _provider);

            let (_, _fee) = TokensMetadata::impact(_token, amount_u256/1000000000000000000, total_deposited/1000000000000000000, true, utf8(b"spot"), TokensMetadata::give_permission(&borrow_global<Permissions>(@dev).tokens_metadata));
        
            let gas_rate = Gas::add_withdraw(_token, amount_u256, Gas::give_permission(&borrow_global<Permissions>(@dev).gas));
            
        
            let (amount_u256_w_fee_taxed, _w_fee) = handle_withdrawal_fee(_token, _chain, _provider,  amount_u256);
            if(amount_u256_w_fee_taxed == 0) { return };

            let (amount_u256_taxed,fee) = assert_minimal_fee(_token, _chain, _provider,  amount_u256_w_fee_taxed, _fee);
            if(amount_u256_taxed == 0) { return };


            len=len-1;

            let obj = primary_fungible_store::ensure_primary_store_exists(signer::address_of(signer),TokensCore::get_metadata(_token));

            // Redeem shares and deposit underlying directly to shared storage, then transfer to signer's personal wallet
            Liquidity::withdraw_token(shared, _token, _chain, _provider, amount_u256_taxed, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));
            Liquidity::remove_stake(_token, _chain, _provider, amount_u256_taxed, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));
            
            let user_shared_store = Shared::ensure_shared_fungible_storage(shared, TokensCore::get_metadata(_token), Shared::give_permission(&borrow_global<Permissions>(@dev).shared_access));
            let fa = TokensCore::withdraw(shared, user_shared_store, (_amount as u64), _chain);
            TokensCore::deposit(shared, primary_fungible_store::ensure_primary_store_exists(signer::address_of(signer),TokensCore::get_metadata(_token)), fa, _chain);
            
            vector::push_back(&mut vect_amnt, amount_u256_taxed);
            Margin::update_reward_index(shared, bcs::to_bytes(&signer::address_of(signer)), _token, _chain, _provider, total_accumulated_rewards, Margin::give_permission(&borrow_global<Permissions>(@dev).margin)); 
        };

        Margin::remove_stake(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider, vect_amnt, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        
        let data = vector[
            Event::create_data_struct(utf8(b"sender"), utf8(b"address"), bcs::to_bytes(&signer::address_of(signer))),
            Event::create_data_struct(utf8(b"shared"), utf8(b"string"), bcs::to_bytes(&shared)),
            Event::create_data_struct(utf8(b"token"), utf8(b"vector<String>"), bcs::to_bytes(&token)),
            Event::create_data_struct(utf8(b"chain"), utf8(b"vector<String>"), bcs::to_bytes(&chain)),
            Event::create_data_struct(utf8(b"provider"), utf8(b"vector<String>"), bcs::to_bytes(&provider)),
            Event::create_data_struct(utf8(b"amount"), utf8(b"vector<u256>"), bcs::to_bytes(&vect_amnt)),

        ];
        Event::emit_market_event(utf8(b"Unstake"), data);
    }

    public entry fun swap_credit_to(signer: &signer, shared: String, token: String, chain: String, provider: String, amount: u256) acquires Permissions {
        Shared::assert_is_sub_owner(shared, bcs::to_bytes(&signer::address_of(signer)));
        let (user_credits, isPositive) = Margin::get_user_credit(shared);
        assert!(isPositive, ERROR_NOT_ENOUGH_CREDITS);
        assert!(user_credits >= amount, ERROR_NOT_ENOUGH_CREDITS);
  
        // 1. Retrieve the swap fee (stored as 100 for 1%)
        let credit_swap_fee = storage::expect_u64(storage::viewConstant(utf8(b"QiaraMargin"), utf8(b"CREDIT_SWAP_FEE")));

        // 2. Calculate the 1% fee amount (multiply first, then divide by 10000 to prevent precision loss)
        let fee_amount = (amount * (credit_swap_fee as u256)) / 1_000_000;

        // 3. Deduct the fee to get the post-tax amount
        let taxed_amount = amount - fee_amount;

        // 4. Calculate the token amount based on the post-tax amount
        let token_amount = TokensMetadata::getValueByCoin(token, taxed_amount);

        // 5. Deposit the post-tax amount, but remove the full initial amount of credit from the user
        Margin::add_deposit(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider, token_amount, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        Margin::remove_credit(shared, bcs::to_bytes(&signer::address_of(signer)), amount, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));

        let data = vector[
            Event::create_data_struct(utf8(b"sender"), utf8(b"address"), bcs::to_bytes(&signer::address_of(signer))),
            Event::create_data_struct(utf8(b"shared"), utf8(b"string"), bcs::to_bytes(&shared)),
            Event::create_data_struct(utf8(b"token"), utf8(b"string"), bcs::to_bytes(&token)),
            Event::create_data_struct(utf8(b"chain"), utf8(b"string"), bcs::to_bytes(&chain)),
            Event::create_data_struct(utf8(b"provider"), utf8(b"string"), bcs::to_bytes(&provider)),
            Event::create_data_struct(utf8(b"amount"), utf8(b"u256"), bcs::to_bytes(&amount)),
        ];
        Event::emit_market_event(utf8(b"Swap Credit to"), data);
    }

    public entry fun deposit(signer: &signer, shared: String, token: String, chain: String, provider: String, amount: u64) acquires Permissions {
        let sender = bcs::to_bytes(&signer::address_of(signer));
        let amount_u256 = (amount as u256)*1000000000000000000;

        let (total_liquidity, total_borrowed, total_deposited, total_staked, total_accumulated_rewards,total_native_accumulated_rewards,  total_accumulated_interest, virtual_borrowed, virtual_deposited, total_shares, last_update) = Liquidity::return_raw_vault(token, chain, provider);

        let (_, _fee) = TokensMetadata::impact(token, amount_u256/1000000000000000000, total_deposited/1000000000000000000, true, utf8(b"spot"), TokensMetadata::give_permission(&borrow_global<Permissions>(@dev).tokens_metadata));
      
        let gas_rate = Gas::add_deposit(token, amount_u256, Gas::give_permission(&borrow_global<Permissions>(@dev).gas));
        
        let (amount_u256_taxed,fee) = assert_minimal_fee(token, chain, provider,  amount_u256, _fee);
        if(amount_u256_taxed == 0) { return };


        let obj = Shared::ensure_shared_fungible_storage(shared,TokensCore::get_metadata(token), Shared::give_permission(&borrow_global<Permissions>(@dev).shared_access));
        let fa = TokensCore::withdraw(shared, obj, amount, chain);

        // 1. Deposit underlying assets and retrieve physical LP shares
        let shares_fa = Liquidity::deposit_token(token, chain, provider, fa, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));
        //tttta(1);
        // UPGRADE: Deposit minted LP shares directly using Shared's secure storage logic
        let lp_metadata = Liquidity::return_lp_metadata(token, chain, provider);
        let user_lp_store = Shared::ensure_shared_fungible_storage(shared, lp_metadata, Shared::give_permission(&borrow_global<Permissions>(@dev).shared_access));
       //         tttta(2);
       fungible_asset::deposit(user_lp_store, shares_fa);
//tttta(3);
        Margin::update_reward_index(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider, total_accumulated_rewards, Margin::give_permission(&borrow_global<Permissions>(@dev).margin)); 
        Margin::add_deposit(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider, amount_u256_taxed, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
 
        Margin::add_locked_fee(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider, ((fee-1000000000000000000)*99)/100, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        let (total_rewards, total_interest, user_borrow_interest, user_lend_rewards, user_points, total_apr, borrow_apr, utilization, price, user_gas_reducted, user_xp_increased, shares_ratio) = new_accrue(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider);
        let data = vector[
            Event::create_data_struct(utf8(b"sender"), utf8(b"address"), bcs::to_bytes(&signer::address_of(signer))),
            Event::create_data_struct(utf8(b"shared"), utf8(b"string"), bcs::to_bytes(&shared)),
            Event::create_data_struct(utf8(b"token"), utf8(b"string"), bcs::to_bytes(&token)),
            Event::create_data_struct(utf8(b"chain"), utf8(b"string"), bcs::to_bytes(&chain)),
            Event::create_data_struct(utf8(b"provider"), utf8(b"string"), bcs::to_bytes(&provider)),

            Event::create_data_struct(utf8(b"amount"), utf8(b"u256"), bcs::to_bytes(&amount_u256_taxed)),
            Event::create_data_struct(utf8(b"fee"), utf8(b"u256"), bcs::to_bytes(&fee)),
            Event::create_data_struct(utf8(b"points"), utf8(b"u256"), bcs::to_bytes(&user_points)),
            Event::create_data_struct(utf8(b"lend_rewards"), utf8(b"u256"), bcs::to_bytes(&user_lend_rewards)),

            Event::create_data_struct(utf8(b"total_rewards"), utf8(b"u256"), bcs::to_bytes(&total_rewards)),
            Event::create_data_struct(utf8(b"total_interest"), utf8(b"u256"), bcs::to_bytes(&total_interest)),
            Event::create_data_struct(utf8(b"total_apr"), utf8(b"u256"), bcs::to_bytes(&total_apr)),
            Event::create_data_struct(utf8(b"borrow_apr"), utf8(b"u256"), bcs::to_bytes(&borrow_apr)),
            Event::create_data_struct(utf8(b"utilization"), utf8(b"u256"), bcs::to_bytes(&utilization)),

            Event::create_data_struct(utf8(b"additional_xp_from_ref_code"), utf8(b"u256"), bcs::to_bytes(&user_xp_increased)),
            Event::create_data_struct(utf8(b"fee_reduced_from_ref_code"), utf8(b"u256"), bcs::to_bytes(&user_gas_reducted)),

             Event::create_data_struct(utf8(b"ratio"), utf8(b"u256"), bcs::to_bytes(&shares_ratio)),

            Event::create_data_struct(utf8(b"total_deposited"), utf8(b"u256"), bcs::to_bytes(&(total_deposited+amount_u256_taxed))),
            Event::create_data_struct(utf8(b"total_borrowed"), utf8(b"u256"), bcs::to_bytes(&total_borrowed)),
            Event::create_data_struct(utf8(b"total_staked"), utf8(b"u256"), bcs::to_bytes(&total_staked)),
            Event::create_data_struct(utf8(b"price"), utf8(b"u256"), bcs::to_bytes(&price)),
        ];

        if(user_borrow_interest > 0){
            vector::push_back(&mut data, Event::create_data_struct(utf8(b"borrow_interest"), utf8(b"u256"), bcs::to_bytes(&user_borrow_interest)))
        };

        Event::emit_market_event(utf8(b"Deposit"), data);
    }

    public entry fun withdraw_and_unwrap(
        signer: &signer, 
        shared: String, 
        token: String, 
        chain: String, 
        provider: String, 
        amount: u64
    ) acquires Permissions {
        let sender = bcs::to_bytes(&signer::address_of(signer));
        let amount_u256 = (amount as u256)*1000000000000000000;

        let (total_liquidity, total_borrowed, total_deposited, total_staked, total_accumulated_rewards, total_native_accumulated_rewards, total_accumulated_interest, virtual_borrowed, virtual_deposited, total_shares, last_update) = Liquidity::return_raw_vault(token, chain, provider);

        let (_, _fee) = TokensMetadata::impact(token, amount_u256/1000000000000000000, total_deposited/1000000000000000000, true, utf8(b"spot"), TokensMetadata::give_permission(&borrow_global<Permissions>(@dev).tokens_metadata));
      
        let gas_rate = Gas::add_withdraw(token, amount_u256, Gas::give_permission(&borrow_global<Permissions>(@dev).gas));
        
        let (amount_u256_w_fee_taxed, _w_fee) = handle_withdrawal_fee(token, chain, provider,  amount_u256);
        if(amount_u256_w_fee_taxed == 0) { return };

        let (amount_u256_taxed, fee) = assert_minimal_fee(token, chain, provider,  amount_u256_w_fee_taxed, _fee);
        if(amount_u256_taxed == 0) { return };

        assert!(total_deposited >= amount_u256_taxed, ERROR_NOT_ENOUGH_LIQUIDITY);

        // 1. Redeem shares and deposit underlying into shared storage
        let lp_shares_to_redeem = (amount_u256_taxed-fee)/1000000000000000000;
        Liquidity::withdraw_token(shared, token, chain, provider, lp_shares_to_redeem, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));

        // 2. Withdraw custom wrapped token from shared storage
        let user_shared_store = Shared::ensure_shared_fungible_storage(shared, TokensCore::get_metadata(token), Shared::give_permission(&borrow_global<Permissions>(@dev).shared_access));
        let custom_fa = TokensCore::withdraw(shared, user_shared_store, (lp_shares_to_redeem as u64), chain);

        // 3. Unwrap custom token into standard/normal FA using the helper in WrapperGate
        let unwrapped_fa = WrapperGate::unwrap_to_standard_fa(
            shared, 
            token, 
            chain, 
            provider, 
            custom_fa
        );

        // 4. Deposit unwrapped FA directly into the user's primary/personal wallet
        let unwrapped_metadata = fungible_asset::asset_metadata(&unwrapped_fa);
        let user_storage = primary_fungible_store::ensure_primary_store_exists(signer::address_of(signer), unwrapped_metadata);
        fungible_asset::deposit(user_storage, unwrapped_fa);

        // 5. Update Margin checkpoints
        Margin::update_reward_index(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider, total_accumulated_rewards, Margin::give_permission(&borrow_global<Permissions>(@dev).margin)); 
        Margin::remove_deposit(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider, amount_u256_taxed, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));

        // 6. Accrue
        let (total_rewards, total_interest, user_borrow_interest, user_lend_rewards,  user_points, total_apr, borrow_apr, utilization, price, user_gas_reducted, user_xp_increased, shares_ratio) = new_accrue(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider);
            
        let data = vector[
            // Items from the event top-level fields
            Event::create_data_struct(utf8(b"sender"), utf8(b"address"), bcs::to_bytes(&signer::address_of(signer))),
            Event::create_data_struct(utf8(b"shared"), utf8(b"string"), bcs::to_bytes(&shared)),
            Event::create_data_struct(utf8(b"token"), utf8(b"string"), bcs::to_bytes(&token)),
            Event::create_data_struct(utf8(b"chain"), utf8(b"string"), bcs::to_bytes(&chain)),
            Event::create_data_struct(utf8(b"provider"), utf8(b"string"), bcs::to_bytes(&provider)),

            // Original items from the data vector
            Event::create_data_struct(utf8(b"amount"), utf8(b"u256"), bcs::to_bytes(&amount_u256_taxed)),
            Event::create_data_struct(utf8(b"fee"), utf8(b"u256"), bcs::to_bytes(&fee)),
            Event::create_data_struct(utf8(b"points"), utf8(b"u256"), bcs::to_bytes(&user_points)),
            Event::create_data_struct(utf8(b"lend_rewards"), utf8(b"u256"), bcs::to_bytes(&user_lend_rewards)),

            Event::create_data_struct(utf8(b"total_rewards"), utf8(b"u256"), bcs::to_bytes(&total_rewards)),
            Event::create_data_struct(utf8(b"total_interest"), utf8(b"u256"), bcs::to_bytes(&total_interest)),
            Event::create_data_struct(utf8(b"total_apr"), utf8(b"u256"), bcs::to_bytes(&total_apr)),
            Event::create_data_struct(utf8(b"borrow_apr"), utf8(b"u256"), bcs::to_bytes(&borrow_apr)),
            Event::create_data_struct(utf8(b"utilization"), utf8(b"u256"), bcs::to_bytes(&utilization)),

            Event::create_data_struct(utf8(b"additional_xp_from_ref_code"), utf8(b"u256"), bcs::to_bytes(&user_xp_increased)),
            Event::create_data_struct(utf8(b"fee_reduced_from_ref_code"), utf8(b"u256"), bcs::to_bytes(&user_gas_reducted)),

            Event::create_data_struct(utf8(b"ratio"), utf8(b"u256"), bcs::to_bytes(&shares_ratio)),

            Event::create_data_struct(utf8(b"total_deposited"), utf8(b"u256"), bcs::to_bytes(&total_deposited)),
            Event::create_data_struct(utf8(b"total_borrowed"), utf8(b"u256"), bcs::to_bytes(&total_borrowed)),
            Event::create_data_struct(utf8(b"total_staked"), utf8(b"u256"), bcs::to_bytes(&total_staked)),
            Event::create_data_struct(utf8(b"price"), utf8(b"u256"), bcs::to_bytes(&price)),
        ];

        if(user_borrow_interest > 0){
            vector::push_back(&mut data, Event::create_data_struct(utf8(b"borrow_interest"), utf8(b"u256"), bcs::to_bytes(&user_borrow_interest)))
        };

        Event::emit_market_event(utf8(b"Withdraw and Convert"), data);
    }

    public entry fun withdraw(signer: &signer, shared: String, token: String, chain: String, provider: String, amount: u64) acquires Permissions {
        let sender = bcs::to_bytes(&signer::address_of(signer));
        let amount_u256 = (amount as u256)*1000000000000000000;

        let (total_liquidity, total_borrowed, total_deposited, total_staked, total_accumulated_rewards,total_native_accumulated_rewards,  total_accumulated_interest, virtual_borrowed, virtual_deposited, total_shares, last_update) = Liquidity::return_raw_vault(token, chain, provider);

        let (_, _fee) = TokensMetadata::impact(token, amount_u256/1000000000000000000, total_deposited/1000000000000000000, true, utf8(b"spot"), TokensMetadata::give_permission(&borrow_global<Permissions>(@dev).tokens_metadata));
      
        let gas_rate = Gas::add_withdraw(token, amount_u256, Gas::give_permission(&borrow_global<Permissions>(@dev).gas));
        
        let (amount_u256_w_fee_taxed, _w_fee) = handle_withdrawal_fee(token, chain, provider,  amount_u256);
        if(amount_u256_w_fee_taxed == 0) { return };

        let (amount_u256_taxed,fee) = assert_minimal_fee(token, chain, provider,  amount_u256_w_fee_taxed, _fee);
        if(amount_u256_taxed == 0) { return };


        assert!(total_deposited >= amount_u256_taxed, ERROR_NOT_ENOUGH_LIQUIDITY);
        let obj = primary_fungible_store::ensure_primary_store_exists(signer::address_of(signer),TokensCore::get_metadata(token));
        
        // 1. Redeems LP shares from shared storage, depositing underlying into shared storage
        let lp_shares_to_redeem = (amount_u256_taxed-fee)/1000000000000000000;
        Liquidity::withdraw_token(shared, token, chain, provider, lp_shares_to_redeem, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));

        // 2. Withdraw from shared storage and transfer directly to signer's personal wallet
        let user_shared_store = Shared::ensure_shared_fungible_storage(shared, TokensCore::get_metadata(token), Shared::give_permission(&borrow_global<Permissions>(@dev).shared_access));
        let fa = TokensCore::withdraw(shared, user_shared_store, ((amount_u256_taxed-fee)/1000000000000000000 as u64), chain);
        TokensCore::deposit(shared, obj, fa, chain);

        Margin::update_reward_index(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider, total_accumulated_rewards, Margin::give_permission(&borrow_global<Permissions>(@dev).margin)); 
        Margin::remove_deposit(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider, amount_u256_taxed, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));

        let (total_rewards, total_interest, user_borrow_interest, user_lend_rewards,  user_points, total_apr, borrow_apr, utilization, price, user_gas_reducted, user_xp_increased, shares_ratio) = new_accrue(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider);
            
        let data = vector[
            Event::create_data_struct(utf8(b"sender"), utf8(b"address"), bcs::to_bytes(&signer::address_of(signer))),
            Event::create_data_struct(utf8(b"shared"), utf8(b"string"), bcs::to_bytes(&shared)),
            Event::create_data_struct(utf8(b"token"), utf8(b"string"), bcs::to_bytes(&token)),
            Event::create_data_struct(utf8(b"chain"), utf8(b"string"), bcs::to_bytes(&chain)),
            Event::create_data_struct(utf8(b"provider"), utf8(b"string"), bcs::to_bytes(&provider)),

            Event::create_data_struct(utf8(b"amount"), utf8(b"u256"), bcs::to_bytes(&amount_u256_taxed)),
            Event::create_data_struct(utf8(b"fee"), utf8(b"u256"), bcs::to_bytes(&fee)),
            Event::create_data_struct(utf8(b"points"), utf8(b"u256"), bcs::to_bytes(&user_points)),
            Event::create_data_struct(utf8(b"lend_rewards"), utf8(b"u256"), bcs::to_bytes(&user_lend_rewards)),

            Event::create_data_struct(utf8(b"total_rewards"), utf8(b"u256"), bcs::to_bytes(&total_rewards)),
            Event::create_data_struct(utf8(b"total_interest"), utf8(b"u256"), bcs::to_bytes(&total_interest)),
            Event::create_data_struct(utf8(b"total_apr"), utf8(b"u256"), bcs::to_bytes(&total_apr)),
            Event::create_data_struct(utf8(b"borrow_apr"), utf8(b"u256"), bcs::to_bytes(&borrow_apr)),
            Event::create_data_struct(utf8(b"utilization"), utf8(b"u256"), bcs::to_bytes(&utilization)),

            Event::create_data_struct(utf8(b"additional_xp_from_ref_code"), utf8(b"u256"), bcs::to_bytes(&user_xp_increased)),
            Event::create_data_struct(utf8(b"fee_reduced_from_ref_code"), utf8(b"u256"), bcs::to_bytes(&user_gas_reducted)),

            Event::create_data_struct(utf8(b"ratio"), utf8(b"u256"), bcs::to_bytes(&shares_ratio)),

            Event::create_data_struct(utf8(b"total_deposited"), utf8(b"u256"), bcs::to_bytes(&total_deposited)),
            Event::create_data_struct(utf8(b"total_borrowed"), utf8(b"u256"), bcs::to_bytes(&total_borrowed)),
            Event::create_data_struct(utf8(b"total_staked"), utf8(b"u256"), bcs::to_bytes(&total_staked)),
            Event::create_data_struct(utf8(b"price"), utf8(b"u256"), bcs::to_bytes(&price)),
        ];

        if(user_borrow_interest > 0){
            vector::push_back(&mut data, Event::create_data_struct(utf8(b"borrow_interest"), utf8(b"u256"), bcs::to_bytes(&user_borrow_interest)))
        };

        Event::emit_market_event(utf8(b"Withdraw"), data);
    }

    public entry fun borrow(signer: &signer, shared: String, token: String, chain: String, provider: String, amount: u64) acquires Permissions {
        let sender = bcs::to_bytes(&signer::address_of(signer));
        let amount_u256 = (amount as u256)*1000000000000000000;

        let (total_liquidity, total_borrowed, total_deposited, total_staked, total_accumulated_rewards, total_native_accumulated_rewards, total_accumulated_interest, virtual_borrowed, virtual_deposited, total_shares, last_update) = Liquidity::return_raw_vault(token, chain, provider);

        let (_, _fee) = TokensMetadata::impact(token, amount_u256/1000000000000000000, total_deposited/1000000000000000000, true, utf8(b"spot"), TokensMetadata::give_permission(&borrow_global<Permissions>(@dev).tokens_metadata));
      
        let gas_rate = Gas::add_borrow(token, amount_u256, Gas::give_permission(&borrow_global<Permissions>(@dev).gas));
        
        let (amount_u256_w_fee_taxed, _w_fee) = handle_withdrawal_fee(token, chain, provider,  amount_u256);
        if(amount_u256_w_fee_taxed == 0) { return };

        let (amount_u256_taxed,fee) = assert_minimal_fee(token, chain, provider,  amount_u256_w_fee_taxed, _fee);
        if(amount_u256_taxed == 0) { return };


        assert!(total_deposited >= amount_u256_taxed, ERROR_NOT_ENOUGH_LIQUIDITY);
        let obj = primary_fungible_store::ensure_primary_store_exists(signer::address_of(signer),TokensCore::get_metadata(token));
        
        // 1. Redeems LP shares from shared storage, depositing underlying into shared storage
        let lp_shares_to_redeem = (amount_u256_taxed-fee)/1000000000000000000;
        Liquidity::withdraw_token(shared, token, chain, provider, lp_shares_to_redeem, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));

        // 2. Withdraw from shared storage and transfer directly to signer's personal wallet
        let user_shared_store = Shared::ensure_shared_fungible_storage(shared, TokensCore::get_metadata(token), Shared::give_permission(&borrow_global<Permissions>(@dev).shared_access));
        let fa = TokensCore::withdraw(shared, user_shared_store, ((amount_u256_taxed-fee)/1000000000000000000 as u64), chain);
        TokensCore::deposit(shared, obj, fa, chain);

        Liquidity::add_borrow(token, chain, provider, amount_u256_taxed, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));
        Margin::update_reward_index(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider, total_accumulated_rewards, Margin::give_permission(&borrow_global<Permissions>(@dev).margin)); 
        Margin::add_borrow(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider, amount_u256_taxed, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));

        let (total_rewards, total_interest, user_borrow_interest, user_lend_rewards,  user_points, total_apr, borrow_apr, utilization, price, user_gas_reducted, user_xp_increased, shares_ratio) = new_accrue(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider);
            
        let data = vector[
            Event::create_data_struct(utf8(b"sender"), utf8(b"address"), bcs::to_bytes(&signer::address_of(signer))),
            Event::create_data_struct(utf8(b"shared"), utf8(b"string"), bcs::to_bytes(&shared)),
            Event::create_data_struct(utf8(b"token"), utf8(b"string"), bcs::to_bytes(&token)),
            Event::create_data_struct(utf8(b"chain"), utf8(b"string"), bcs::to_bytes(&chain)),
            Event::create_data_struct(utf8(b"provider"), utf8(b"string"), bcs::to_bytes(&provider)),

            Event::create_data_struct(utf8(b"amount"), utf8(b"u256"), bcs::to_bytes(&amount_u256_taxed)),
            Event::create_data_struct(utf8(b"fee"), utf8(b"u256"), bcs::to_bytes(&fee)),
            Event::create_data_struct(utf8(b"points"), utf8(b"u256"), bcs::to_bytes(&user_points)),
            Event::create_data_struct(utf8(b"lend_rewards"), utf8(b"u256"), bcs::to_bytes(&user_lend_rewards)),

            Event::create_data_struct(utf8(b"total_rewards"), utf8(b"u256"), bcs::to_bytes(&total_rewards)),
            Event::create_data_struct(utf8(b"total_interest"), utf8(b"u256"), bcs::to_bytes(&total_interest)),
            Event::create_data_struct(utf8(b"total_apr"), utf8(b"u256"), bcs::to_bytes(&total_apr)),
            Event::create_data_struct(utf8(b"borrow_apr"), utf8(b"u256"), bcs::to_bytes(&borrow_apr)),
            Event::create_data_struct(utf8(b"utilization"), utf8(b"u256"), bcs::to_bytes(&utilization)),

            Event::create_data_struct(utf8(b"additional_xp_from_ref_code"), utf8(b"u256"), bcs::to_bytes(&user_xp_increased)),
            Event::create_data_struct(utf8(b"fee_reduced_from_ref_code"), utf8(b"u256"), bcs::to_bytes(&user_gas_reducted)),

            Event::create_data_struct(utf8(b"ratio"), utf8(b"u256"), bcs::to_bytes(&shares_ratio)),

            Event::create_data_struct(utf8(b"total_deposited"), utf8(b"u256"), bcs::to_bytes(&total_deposited)),
            Event::create_data_struct(utf8(b"total_borrowed"), utf8(b"u256"), bcs::to_bytes(&total_borrowed)),
            Event::create_data_struct(utf8(b"total_staked"), utf8(b"u256"), bcs::to_bytes(&total_staked)),
            Event::create_data_struct(utf8(b"price"), utf8(b"u256"), bcs::to_bytes(&price)),
        ];

        if(user_borrow_interest > 0){
            vector::push_back(&mut data, Event::create_data_struct(utf8(b"borrow_interest"), utf8(b"u256"), bcs::to_bytes(&user_borrow_interest)))
        };

        Event::emit_market_event(utf8(b"Borrow"), data);
    }

    public entry fun virtual_borrow(signer: &signer, shared: String, token: String, chain: String, provider: String, amount: u64) acquires Permissions {
        let sender = bcs::to_bytes(&signer::address_of(signer));
        let amount_u256 = (amount as u256)*1000000000000000000;

        let (total_liquidity, total_borrowed, total_deposited, total_staked, total_accumulated_rewards,total_native_accumulated_rewards,  total_accumulated_interest, virtual_borrowed, virtual_deposited, total_shares, last_update) = Liquidity::return_raw_vault(token, chain, provider);

        let (_, _fee) = TokensMetadata::impact(token, amount_u256/1000000000000000000, total_deposited/1000000000000000000, true, utf8(b"spot"), TokensMetadata::give_permission(&borrow_global<Permissions>(@dev).tokens_metadata));
      
        let gas_rate = Gas::add_borrow(token, amount_u256, Gas::give_permission(&borrow_global<Permissions>(@dev).gas));
        
        let (amount_u256_taxed,fee) = assert_minimal_fee(token, chain, provider,  amount_u256, _fee);
        if(amount_u256_taxed == 0) { return };


        Liquidity::add_virtual_borrow(token, chain, provider, amount_u256, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));
        Liquidity::remove_deposit(token, chain, provider, amount_u256, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));
        Margin::update_reward_index(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider, total_accumulated_rewards, Margin::give_permission(&borrow_global<Permissions>(@dev).margin)); 
        Margin::add_virtual_borrow(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider, amount_u256_taxed, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        
        let (total_rewards, total_interest, user_borrow_interest, user_lend_rewards, user_points, total_apr, borrow_apr, utilization, price, user_gas_reducted, user_xp_increased, shares_ratio) = new_accrue(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider);
            
        let data = vector[
            // Items from the event top-level fields
            Event::create_data_struct(utf8(b"sender"), utf8(b"address"), bcs::to_bytes(&signer::address_of(signer))),
            Event::create_data_struct(utf8(b"shared"), utf8(b"string"), bcs::to_bytes(&shared)),
            Event::create_data_struct(utf8(b"token"), utf8(b"string"), bcs::to_bytes(&token)),
            Event::create_data_struct(utf8(b"chain"), utf8(b"string"), bcs::to_bytes(&chain)),
            Event::create_data_struct(utf8(b"provider"), utf8(b"string"), bcs::to_bytes(&provider)),

            // Original items from the data vector
            Event::create_data_struct(utf8(b"amount"), utf8(b"u256"), bcs::to_bytes(&amount_u256_taxed)),
            Event::create_data_struct(utf8(b"fee"), utf8(b"u256"), bcs::to_bytes(&fee)),
            Event::create_data_struct(utf8(b"points"), utf8(b"u256"), bcs::to_bytes(&user_points)),
            Event::create_data_struct(utf8(b"lend_rewards"), utf8(b"u256"), bcs::to_bytes(&user_lend_rewards)),

            Event::create_data_struct(utf8(b"total_rewards"), utf8(b"u256"), bcs::to_bytes(&total_rewards)),
            Event::create_data_struct(utf8(b"total_interest"), utf8(b"u256"), bcs::to_bytes(&total_interest)),
            Event::create_data_struct(utf8(b"total_apr"), utf8(b"u256"), bcs::to_bytes(&total_apr)),
            Event::create_data_struct(utf8(b"borrow_apr"), utf8(b"u256"), bcs::to_bytes(&borrow_apr)),
            Event::create_data_struct(utf8(b"utilization"), utf8(b"u256"), bcs::to_bytes(&utilization)),

            Event::create_data_struct(utf8(b"additional_xp_from_ref_code"), utf8(b"u256"), bcs::to_bytes(&user_xp_increased)),
            Event::create_data_struct(utf8(b"fee_reduced_from_ref_code"), utf8(b"u256"), bcs::to_bytes(&user_gas_reducted)),

             Event::create_data_struct(utf8(b"ratio"), utf8(b"u256"), bcs::to_bytes(&shares_ratio)),

            Event::create_data_struct(utf8(b"total_deposited"), utf8(b"u256"), bcs::to_bytes(&total_deposited)),
            Event::create_data_struct(utf8(b"total_borrowed"), utf8(b"u256"), bcs::to_bytes(&total_borrowed)),
            Event::create_data_struct(utf8(b"total_staked"), utf8(b"u256"), bcs::to_bytes(&total_staked)),
            Event::create_data_struct(utf8(b"price"), utf8(b"u256"), bcs::to_bytes(&price)),
        ];

        if(user_borrow_interest > 0){
            vector::push_back(&mut data, Event::create_data_struct(utf8(b"borrow_interest"), utf8(b"u256"), bcs::to_bytes(&user_borrow_interest)))
        };

        Event::emit_market_event(utf8(b"Virtual Borrow"), data);
    }

    public entry fun virtual_deposit(signer: &signer, shared: String, token: String, chain: String, provider: String, amount: u64) acquires Permissions {
        let sender = bcs::to_bytes(&signer::address_of(signer));
        let amount_u256 = (amount as u256)*1000000000000000000;

        let (total_liquidity, total_borrowed, total_deposited, total_staked, total_accumulated_rewards, total_native_accumulated_rewards, total_accumulated_interest, virtual_borrowed, virtual_deposited, total_shares, last_update) = Liquidity::return_raw_vault(token, chain, provider);

        let (_, _fee) = TokensMetadata::impact(token, amount_u256/1000000000000000000, total_deposited/1000000000000000000, true, utf8(b"spot"), TokensMetadata::give_permission(&borrow_global<Permissions>(@dev).tokens_metadata));
      
        let gas_rate = Gas::add_deposit(token, amount_u256, Gas::give_permission(&borrow_global<Permissions>(@dev).gas));

        
        let (amount_u256_taxed,fee) = assert_minimal_fee(token, chain, provider,  amount_u256, _fee);
        if(amount_u256_taxed == 0) { return };


        Liquidity::add_virtual_deposit(token, chain, provider, amount_u256, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));
        Margin::update_reward_index(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider, total_accumulated_rewards, Margin::give_permission(&borrow_global<Permissions>(@dev).margin)); 
        Margin::add_virtual_deposit(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider, amount_u256_taxed, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        
        let (total_rewards, total_interest, user_borrow_interest, user_lend_rewards,  user_points, total_apr, borrow_apr, utilization, price, user_gas_reducted, user_xp_increased, shares_ratio) = new_accrue(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider);
            
        let data = vector[
            // Items from the event top-level fields
            Event::create_data_struct(utf8(b"sender"), utf8(b"address"), bcs::to_bytes(&signer::address_of(signer))),
            Event::create_data_struct(utf8(b"shared"), utf8(b"string"), bcs::to_bytes(&shared)),
            Event::create_data_struct(utf8(b"token"), utf8(b"string"), bcs::to_bytes(&token)),
            Event::create_data_struct(utf8(b"chain"), utf8(b"string"), bcs::to_bytes(&chain)),
            Event::create_data_struct(utf8(b"provider"), utf8(b"string"), bcs::to_bytes(&provider)),

            // Original items from the data vector
            Event::create_data_struct(utf8(b"amount"), utf8(b"u256"), bcs::to_bytes(&amount_u256_taxed)),
            Event::create_data_struct(utf8(b"fee"), utf8(b"u256"), bcs::to_bytes(&fee)),
            Event::create_data_struct(utf8(b"points"), utf8(b"u256"), bcs::to_bytes(&user_points)),
            Event::create_data_struct(utf8(b"lend_rewards"), utf8(b"u256"), bcs::to_bytes(&user_lend_rewards)),

            Event::create_data_struct(utf8(b"total_rewards"), utf8(b"u256"), bcs::to_bytes(&total_rewards)),
            Event::create_data_struct(utf8(b"total_interest"), utf8(b"u256"), bcs::to_bytes(&total_interest)),
            Event::create_data_struct(utf8(b"total_apr"), utf8(b"u256"), bcs::to_bytes(&total_apr)),
            Event::create_data_struct(utf8(b"borrow_apr"), utf8(b"u256"), bcs::to_bytes(&borrow_apr)),
            Event::create_data_struct(utf8(b"utilization"), utf8(b"u256"), bcs::to_bytes(&utilization)),

            Event::create_data_struct(utf8(b"additional_xp_from_ref_code"), utf8(b"u256"), bcs::to_bytes(&user_xp_increased)),
            Event::create_data_struct(utf8(b"fee_reduced_from_ref_code"), utf8(b"u256"), bcs::to_bytes(&user_gas_reducted)),

            Event::create_data_struct(utf8(b"ratio"), utf8(b"u256"), bcs::to_bytes(&shares_ratio)),

            Event::create_data_struct(utf8(b"total_deposited"), utf8(b"u256"), bcs::to_bytes(&total_deposited)),
            Event::create_data_struct(utf8(b"total_borrowed"), utf8(b"u256"), bcs::to_bytes(&total_borrowed)),
            Event::create_data_struct(utf8(b"total_staked"), utf8(b"u256"), bcs::to_bytes(&total_staked)),
            Event::create_data_struct(utf8(b"price"), utf8(b"u256"), bcs::to_bytes(&price)),
        ];

        if(user_borrow_interest > 0){
            vector::push_back(&mut data, Event::create_data_struct(utf8(b"borrow_interest"), utf8(b"u256"), bcs::to_bytes(&user_borrow_interest)))
        };

        Event::emit_market_event(utf8(b"Virtual Deposit"), data);
    }

    public entry fun virtual_repay(signer: &signer, shared: String, token: String, chain: String, provider: String, amount: u64) acquires Permissions {
        let sender = bcs::to_bytes(&signer::address_of(signer));
        let amount_u256 = (amount as u256)*1000000000000000000;

        let (total_liquidity, total_borrowed, total_deposited, total_staked, total_accumulated_rewards,total_native_accumulated_rewards,  total_accumulated_interest, virtual_borrowed, virtual_deposited, total_shares, last_update) = Liquidity::return_raw_vault(token, chain, provider);

        let (_, _fee) = TokensMetadata::impact(token, amount_u256/1000000000000000000, total_deposited/1000000000000000000, true, utf8(b"spot"), TokensMetadata::give_permission(&borrow_global<Permissions>(@dev).tokens_metadata));
      
        let gas_rate = Gas::add_deposit(token, amount_u256, Gas::give_permission(&borrow_global<Permissions>(@dev).gas));
        
        let (amount_u256_taxed,fee) = assert_minimal_fee(token, chain, provider,  amount_u256, _fee);
        if(amount_u256_taxed == 0) { return };


        Liquidity::remove_virtual_borrow(token, chain, provider, amount_u256, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));
        Liquidity::add_deposit(token, chain, provider, amount_u256, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));
        Margin::update_reward_index(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider, total_accumulated_rewards, Margin::give_permission(&borrow_global<Permissions>(@dev).margin)); 
        Margin::remove_virtual_borrow(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider, amount_u256_taxed, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        
        let (total_rewards, total_interest, user_borrow_interest, user_lend_rewards,  user_points, total_apr, borrow_apr, utilization, price, user_gas_reducted, user_xp_increased, shares_ratio) = new_accrue(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider);
            
        let data = vector[
            // Items from the event top-level fields
            Event::create_data_struct(utf8(b"sender"), utf8(b"address"), bcs::to_bytes(&signer::address_of(signer))),
            Event::create_data_struct(utf8(b"shared"), utf8(b"string"), bcs::to_bytes(&shared)),
            Event::create_data_struct(utf8(b"token"), utf8(b"string"), bcs::to_bytes(&token)),
            Event::create_data_struct(utf8(b"chain"), utf8(b"string"), bcs::to_bytes(&chain)),
            Event::create_data_struct(utf8(b"provider"), utf8(b"string"), bcs::to_bytes(&provider)),

            // Original items from the data vector
            Event::create_data_struct(utf8(b"amount"), utf8(b"u256"), bcs::to_bytes(&amount_u256_taxed)),
            Event::create_data_struct(utf8(b"fee"), utf8(b"u256"), bcs::to_bytes(&fee)),
            Event::create_data_struct(utf8(b"points"), utf8(b"u256"), bcs::to_bytes(&user_points)),
            Event::create_data_struct(utf8(b"lend_rewards"), utf8(b"u256"), bcs::to_bytes(&user_lend_rewards)),

            Event::create_data_struct(utf8(b"total_rewards"), utf8(b"u256"), bcs::to_bytes(&total_rewards)),
            Event::create_data_struct(utf8(b"total_interest"), utf8(b"u256"), bcs::to_bytes(&total_interest)),
            Event::create_data_struct(utf8(b"total_apr"), utf8(b"u256"), bcs::to_bytes(&total_apr)),
            Event::create_data_struct(utf8(b"borrow_apr"), utf8(b"u256"), bcs::to_bytes(&borrow_apr)),
            Event::create_data_struct(utf8(b"utilization"), utf8(b"u256"), bcs::to_bytes(&utilization)),

            Event::create_data_struct(utf8(b"additional_xp_from_ref_code"), utf8(b"u256"), bcs::to_bytes(&user_xp_increased)),
            Event::create_data_struct(utf8(b"fee_reduced_from_ref_code"), utf8(b"u256"), bcs::to_bytes(&user_gas_reducted)),

             Event::create_data_struct(utf8(b"ratio"), utf8(b"u256"), bcs::to_bytes(&shares_ratio)),

            Event::create_data_struct(utf8(b"total_deposited"), utf8(b"u256"), bcs::to_bytes(&total_deposited)),
            Event::create_data_struct(utf8(b"total_borrowed"), utf8(b"u256"), bcs::to_bytes(&total_borrowed)),
            Event::create_data_struct(utf8(b"total_staked"), utf8(b"u256"), bcs::to_bytes(&total_staked)),
            Event::create_data_struct(utf8(b"price"), utf8(b"u256"), bcs::to_bytes(&price)),
        ];

        if(user_borrow_interest > 0){
            vector::push_back(&mut data, Event::create_data_struct(utf8(b"borrow_interest"), utf8(b"u256"), bcs::to_bytes(&user_borrow_interest)))
        };

        Event::emit_market_event(utf8(b"Virtual Repay"), data);
    }


    public fun repay(signer: &signer,shared: String,  token: String, chain: String, provider: String, amount: u64) acquires Permissions {
        let amount_u256 = (amount as u256)*1000000000000000000;

        let (total_liquidity, total_borrowed, total_deposited, total_staked, total_accumulated_rewards,total_native_accumulated_rewards,  total_accumulated_interest, virtual_borrowed, virtual_deposited, total_shares, last_update) = Liquidity::return_raw_vault(token, chain, provider);

        let fa = TokensCore::withdraw(shared, primary_fungible_store::ensure_primary_store_exists(signer::address_of(signer),TokensCore::get_metadata(token)), amount, chain);
        
        // UPGRADE: Deposit repayment directly into vault storage (Do not mint LP shares for repayments)
        let storage = Liquidity::return_storage(token, chain, provider);
        let storage_address_string = non_user_storage_helper(&storage);
        TokensCore::deposit(storage_address_string, storage, fa, chain);

        Margin::remove_borrow(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider, (amount as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        Liquidity::remove_borrow(token, chain, provider, amount_u256, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));
        let (total_rewards, total_interest, user_borrow_interest, user_lend_rewards, user_points, total_apr, borrow_apr, utilization, price, user_gas_reducted, user_xp_increased, shares_ratio) = new_accrue( shared,bcs::to_bytes(&signer::address_of(signer)), token, chain, provider);
        let data = vector[
            // Items from the event top-level fields
            Event::create_data_struct(utf8(b"sender"), utf8(b"address"), bcs::to_bytes(&signer::address_of(signer))),
            Event::create_data_struct(utf8(b"shared"), utf8(b"string"), bcs::to_bytes(&shared)),
            Event::create_data_struct(utf8(b"token"), utf8(b"string"), bcs::to_bytes(&token)),
            Event::create_data_struct(utf8(b"chain"), utf8(b"string"), bcs::to_bytes(&chain)),
            Event::create_data_struct(utf8(b"provider"), utf8(b"string"), bcs::to_bytes(&provider)),

            // Original items from the data vector
            Event::create_data_struct(utf8(b"amount"), utf8(b"u256"), bcs::to_bytes(&amount_u256)),
            Event::create_data_struct(utf8(b"points"), utf8(b"u256"), bcs::to_bytes(&user_points)),
            Event::create_data_struct(utf8(b"lend_rewards"), utf8(b"u256"), bcs::to_bytes(&user_lend_rewards)),

            Event::create_data_struct(utf8(b"total_rewards"), utf8(b"u256"), bcs::to_bytes(&total_rewards)),
            Event::create_data_struct(utf8(b"total_interest"), utf8(b"u256"), bcs::to_bytes(&total_interest)),
            Event::create_data_struct(utf8(b"total_apr"), utf8(b"u256"), bcs::to_bytes(&total_apr)),
            Event::create_data_struct(utf8(b"borrow_apr"), utf8(b"u256"), bcs::to_bytes(&borrow_apr)),
            Event::create_data_struct(utf8(b"utilization"), utf8(b"u256"), bcs::to_bytes(&utilization)),

            Event::create_data_struct(utf8(b"additional_xp_from_ref_code"), utf8(b"u256"), bcs::to_bytes(&user_xp_increased)),
            Event::create_data_struct(utf8(b"fee_reduced_from_ref_code"), utf8(b"u256"), bcs::to_bytes(&user_gas_reducted)),

            Event::create_data_struct(utf8(b"ratio"), utf8(b"u256"), bcs::to_bytes(&shares_ratio)),

            Event::create_data_struct(utf8(b"total_deposited"), utf8(b"u256"), bcs::to_bytes(&total_deposited)),
            Event::create_data_struct(utf8(b"total_borrowed"), utf8(b"u256"), bcs::to_bytes(&total_borrowed)),
            Event::create_data_struct(utf8(b"total_staked"), utf8(b"u256"), bcs::to_bytes(&total_staked)),
            Event::create_data_struct(utf8(b"price"), utf8(b"u256"), bcs::to_bytes(&price)),
        ];

        if (user_borrow_interest > 0) {
            vector::push_back(&mut data, Event::create_data_struct(utf8(b"borrow_interest"), utf8(b"u256"), bcs::to_bytes(&user_borrow_interest)));
        };

        Event::emit_market_event(utf8(b"Repay"), data);
    }

    public entry fun claim_rewards(signer: &signer, shared: String, token: String, chain: String, provider: String) acquires Permissions {

        let (total_liquidity, total_borrowed, total_deposited, total_staked, total_accumulated_rewards, total_native_accumulated_rewards, total_accumulated_interest, virtual_borrowed, virtual_deposited, total_shares, last_update) = Liquidity::return_raw_vault(token, chain, provider);

        let (total_rewards, total_interest, user_borrow_interest, user_lend_rewards,  user_points, total_apr, borrow_apr, utilization, price, user_gas_reducted, user_xp_increased, shares_ratio) = new_accrue(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider);
        let (_,_,user_deposited, user_borrowed, _, user_rewards, _, user_interest, _, _, _, _, _, _,_) = Margin::get_user_raw_balance(shared, token, chain, provider);

        let reward_amount = user_rewards;
        let interest_amount = user_interest;


        let data = vector[
            Event::create_data_struct(utf8(b"sender"), utf8(b"address"), bcs::to_bytes(&signer::address_of(signer))),
            Event::create_data_struct(utf8(b"token"), utf8(b"string"), bcs::to_bytes(&token)),
            Event::create_data_struct(utf8(b"chain"), utf8(b"string"), bcs::to_bytes(&chain)),
            Event::create_data_struct(utf8(b"provider"), utf8(b"string"), bcs::to_bytes(&provider)),

            Event::create_data_struct(utf8(b"points"), utf8(b"u256"), bcs::to_bytes(&user_points)),
            Event::create_data_struct(utf8(b"lend_rewards"), utf8(b"u256"), bcs::to_bytes(&user_lend_rewards)),

            Event::create_data_struct(utf8(b"total_rewards"), utf8(b"u256"), bcs::to_bytes(&total_rewards)),
            Event::create_data_struct(utf8(b"total_interest"), utf8(b"u256"), bcs::to_bytes(&total_interest)),
            Event::create_data_struct(utf8(b"total_apr"), utf8(b"u256"), bcs::to_bytes(&total_apr)),
            Event::create_data_struct(utf8(b"borrow_apr"), utf8(b"u256"), bcs::to_bytes(&borrow_apr)),
            Event::create_data_struct(utf8(b"utilization"), utf8(b"u256"), bcs::to_bytes(&utilization)),

            Event::create_data_struct(utf8(b"additional_xp_from_ref_code"), utf8(b"u256"), bcs::to_bytes(&user_xp_increased)),
            Event::create_data_struct(utf8(b"fee_reduced_from_ref_code"), utf8(b"u256"), bcs::to_bytes(&user_gas_reducted)),

             Event::create_data_struct(utf8(b"ratio"), utf8(b"u256"), bcs::to_bytes(&shares_ratio)),

            Event::create_data_struct(utf8(b"total_deposited"), utf8(b"u256"), bcs::to_bytes(&total_deposited)),
            Event::create_data_struct(utf8(b"total_borrowed"), utf8(b"u256"), bcs::to_bytes(&total_borrowed)),
            Event::create_data_struct(utf8(b"total_staked"), utf8(b"u256"), bcs::to_bytes(&total_staked)),
            Event::create_data_struct(utf8(b"price"), utf8(b"u256"), bcs::to_bytes(&price)),
        ];


        if(reward_amount > interest_amount){
            let reward = (reward_amount - interest_amount);
            vector::push_back(&mut data, Event::create_data_struct(utf8(b"amount"), utf8(b"u256"), bcs::to_bytes(&reward)));
            
            // Redeem shares and deposit underlying into shared storage
            Liquidity::withdraw_token(shared, token, chain, provider, reward, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));
            
            // Transfer from shared storage to the signer's personal wallet
            let user_shared_store = Shared::ensure_shared_fungible_storage(shared, TokensCore::get_metadata(token), Shared::give_permission(&borrow_global<Permissions>(@dev).shared_access));
            let fa = TokensCore::withdraw(shared, user_shared_store, (reward as u64), chain);
            TokensCore::deposit(shared, primary_fungible_store::ensure_primary_store_exists(signer::address_of(signer), TokensCore::get_metadata(token)), fa, chain);
            
            assert!(total_deposited >= (reward as u256), ERROR_NOT_ENOUGH_LIQUIDITY);
            Event::emit_market_event(utf8(b"Claim Rewards"), data);
        } else{
            let interest = (interest_amount - reward_amount);
            vector::push_back(&mut data, Event::create_data_struct(utf8(b"amount"), utf8(b"u256"), bcs::to_bytes(&interest)));

            Margin::remove_deposit(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider, interest, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
            let fa = TokensCore::withdraw(shared, primary_fungible_store::ensure_primary_store_exists(signer::address_of(signer),TokensCore::get_metadata(token)), (interest as u64), chain);

            // UPGRADE: Deposit interest/yield directly into vault storage (Do not mint LP shares for yield payments)
            let storage = Liquidity::return_storage(token, chain, provider);
            let storage_address_string = non_user_storage_helper(&storage);
            TokensCore::deposit(storage_address_string, storage, fa, chain);

            Liquidity::add_deposit(token, chain, provider, (interest as u256), Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));
            Event::emit_market_event(utf8(b"Pay Interest"), data);
        };
        Margin::remove_interest(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider, (reward_amount as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        Margin::remove_rewards(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider, (interest_amount as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
    }


    fun tttta(number: u64){
        abort(number);
    }


// === HELPERS === //

   public fun new_accrue(shared: String, user: vector<u8>, token: String, chain: String, provider: String): (u256,u256, u256, u256, u256, u256, u256, u256, u256, u256,u256,u256) acquires Permissions {
        
        // 1. FETCH CURRENT BALANCES AND GLOBAL VAULT STATES
        // FIXED: Destructure the updated 15-element balance tuple from Margin [1]
        let (
            user_deposited, 
            user_borrowed, 
            user_virtual_deposited, 
            user_virtual_borrowed, 
            user_staked, 
            user_rewards, 
            user_accumulated_rewards_index, 
            user_interest, 
            user_accumulated_interest_index, 
            user_native_accumulated_rewards_index,
            user_incentive_deposit_index,       // <--- FIXED: Split Lender Checkpoint
            user_incentive_borrow_index,        // <--- FIXED: Split Borrower Checkpoint
            user_accumulated_rewards_index_snapshot, // <--- FIXED: Gated Checkpoint
            user_locked_fee, 
            user_last_interacted
        ) = Margin::get_user_raw_balance(shared, token, chain, provider);


        // FIXED: Destructure the updated 11-element raw vault tuple from Liquidity [1]
        let (
            total_liquidity,
            total_borrowed, 
            total_deposited, 
            total_staked, 
            total_accumulated_rewards, 
            total_native_accumulated_rewards,
            total_accumulated_interest, 
            virtual_borrowed, 
            virtual_deposited, 
            total_shares,                       // <--- FIXED: Return LP share supply
            last_update
        ) = Liquidity::return_raw_vault(token, chain, provider);

        let utilization = Liquidity::get_utilization_ratio(
            total_deposited, 
            virtual_deposited, 
            total_borrowed, 
            virtual_borrowed, 
            total_staked
        );

        let metadata = TokensMetadata::get_coin_metadata_by_symbol(token);
        let id = (TokensMetadata::get_coin_metadata_tier(&metadata) as u8);
        let price = TokensMetadata::get_coin_metadata_price(&metadata);
        
        //let (native_chain_lend_apr, _) = TokensRates::get_vault_raw(token, chain, provider);
        let (qiara_base_apr, total_apr, borrow_apr) = Liquidity::calculate_minimal_apr(id, utilization);

        let current_time = timestamp::now_seconds();
        let time_diff = current_time - last_update;
        let user_time_diff = current_time - user_last_interacted;

        Liquidity::update(token, chain, provider, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));

        // Sync Global Virtual Credit Index using the updated dual-incentive indexing logic
        Liquidity::update_incentive_index(token, chain, provider, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));

        let native_accumulated_rewards = calculate_global_rewards(total_deposited, total_apr, (time_diff as u256));
        Liquidity::add_native_accumulated_rewards(token, chain, provider, native_accumulated_rewards, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));
        Liquidity::add_accumulated_rewards(token, chain, provider, native_accumulated_rewards, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));

        let global_accrued_interest = 0;
        if (total_borrowed > 0) {
            global_accrued_interest = calculate_global_interest(total_borrowed, borrow_apr,(time_diff as u256));
        };

        if (global_accrued_interest > 0) {
            //Liquidity::add_accumulated_rewards(token, chain, provider, global_accrued_interest, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));
            Liquidity::add_accumulated_interest(token, chain, provider, global_accrued_interest/1000000000000000000, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));
        };

        let user_total_supply = user_deposited + user_staked + user_virtual_deposited;
        let user_total_debt = user_borrowed + user_virtual_borrowed;
        let net_deposited = if (user_total_supply > user_total_debt) { user_total_supply - user_total_debt } else { 0 };

        let (_, _, enoughLocked) = BurnedQiara::calculate_required_locked_tokens_u256(shared, total_deposited);
       
        let user_interest_accrued = 0;
        if (user_total_debt > 0) {
            user_interest_accrued = calculate_user_borrow_interest(total_accumulated_interest, user_accumulated_interest_index, user_total_debt, total_borrowed);
        };

        if (user_interest_accrued > 0) {
            Margin::add_borrow(shared, user, token, chain, provider, user_interest_accrued, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        };

        let user_interest_reward;
        if (enoughLocked) {
            user_interest_reward = calculate_user_burned_qiara_interest_rewards(total_accumulated_rewards, user_accumulated_rewards_index, net_deposited, total_deposited);
            Margin::add_rewards(shared, user, token, chain, provider, user_interest_reward, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));   
        } else {
            user_interest_reward = calculate_user_native_rewards(total_native_accumulated_rewards, user_native_accumulated_rewards_index, net_deposited, total_deposited);
            Margin::add_rewards(shared, user, token, chain, provider, user_interest_reward, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        };

        // FIXED: Gated checking for the accumulated fee rewards (for burned Qiara holders)
        let new_user_fee_index = Liquidity::claim_accumulated_fee_rewards(
            shared,
            user,
            token,
            chain,
            provider,
            user_deposited,                 // LP shares represent current deposits
            (user_accumulated_rewards_index_snapshot as u128),
            Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity)
        );

        // FIXED: Dual-Index virtual credit incentive distribution
        let (new_user_incentive_deposit_index, new_user_incentive_borrow_index) = Liquidity::distribute_rewards(
            shared, 
            user, 
            token, 
            chain, 
            provider, 
            user_deposited,                 // user_shares
            user_borrowed,                  // user_borrowed
            (user_incentive_deposit_index as u128), 
            (user_incentive_borrow_index as u128), 
            Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity)
        );

        let (total_user_usd, _, _, _, _, _, _, _, _, _, _) = Margin::get_user_total_usd(shared);
        let (user_gas_index, user_last_time_interacted) = Shared::extract_raw_gas_relations(Shared::return_shared_ownership_new(shared));
        let (gas_fee, gas_index) = Gas::calculate_gas_fee_from_index(user_gas_index, total_user_usd);

        Shared::update_gas_index(shared, gas_index, Shared::give_permission(&borrow_global<Permissions>(@dev).shared_access));
        
        let base_points_reward = calculate_deposit_points(TokensMetadata::getValue(token, user_deposited), user_last_interacted);
        
        let ownership = Shared::return_shared_ownership_new(shared);
        let (xp_tax, fee_tax) = Shared::extract_raw_params(ownership);
        let used_ref_code = Shared::extract_used_ref_code(ownership);

        let (actual_gas_reduction_for_ref_code_user, actual_xp_earned_for_ref_code_user, actual_final_gas) = if (used_ref_code != utf8(b"")) {
            let (gas_reduced, xp_earned, actual_taxed_gas_fees, actual_taxed_xp) = Points::calculate_ref_code_taxes(
                fee_tax, 
                xp_tax, 
                (gas_fee), 
                (base_points_reward)
            );

            let data = vector[
                Event::create_data_struct(utf8(b"used_ref_code"), utf8(b"string"), bcs::to_bytes(&used_ref_code)),
                Event::create_data_struct(utf8(b"taxed_gas"), utf8(b"u256"), bcs::to_bytes(&actual_taxed_gas_fees)),
                Event::create_data_struct(utf8(b"taxed_xp"), utf8(b"u256"), bcs::to_bytes(&actual_taxed_xp)),
            ];
            Event::emit_qiara_shared_stats(data);

            let final_gas = gas_fee - (gas_reduced + (actual_taxed_gas_fees as u256));

            // Gas goes to protocol, not toward any vault rewards
            //Liquidity::add_accumulated_rewards(token, chain, provider, final_gas, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));
            //Liquidity::add_accumulated_interest(token, chain, provider, final_gas, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));
            Margin::add_borrow(shared, user, token, chain, provider, final_gas, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
            
            (gas_reduced, xp_earned, gas_fee - gas_reduced)
        } else {
            (0, 0, gas_fee)
        };

        Margin::remove_credit(shared, user, actual_final_gas, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        TokenVaults::fast_add_accumulated_rewards(token, actual_final_gas, TokenVaults::give_permission(&borrow_global<Permissions>(@dev).token_vaults));

        let points_reward = actual_xp_earned_for_ref_code_user;

        Points::add_experience(shared, points_reward, Points::give_permission(&borrow_global<Permissions>(@dev).points));

        Margin::update_reward_index(shared, user, token, chain, provider, total_accumulated_rewards, Margin::give_permission(&borrow_global<Permissions>(@dev).margin)); 
        Margin::update_interest_index(shared, user, token, chain, provider, total_accumulated_interest, Margin::give_permission(&borrow_global<Permissions>(@dev).margin)); 

        // FIXED: Update dual-index incentive checkpoints in the Margin module
        Margin::update_incentive_indices(
            shared, 
            user, 
            token, 
            chain, 
            provider, 
            (new_user_incentive_deposit_index as u256), 
            (new_user_incentive_borrow_index as u256), 
            Margin::give_permission(&borrow_global<Permissions>(@dev).margin)
        );

        // FIXED: Update gated fee reward index checkpoint in the Margin module
        Margin::update_accumulated_rewards_index(
            shared, 
            user, 
            token, 
            chain, 
            provider, 
            (new_user_fee_index as u256), 
            Margin::give_permission(&borrow_global<Permissions>(@dev).margin)
        );

        Margin::update_time(shared, user, token, chain, provider, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));

    
        return (
            total_accumulated_rewards, 
            total_accumulated_interest, 
            user_interest_accrued, 
            user_interest_reward, 
            points_reward,
            total_apr,
            borrow_apr,
            utilization,
            price,
            actual_gas_reduction_for_ref_code_user,
            actual_xp_earned_for_ref_code_user,
            calculate_mint_ratio(total_deposited, total_accumulated_interest, total_native_accumulated_rewards, total_shares)
        )
    }
    
    fun non_user_storage_helper<T: key>(obj: &Object<T>): String{
        let storage_address_bytes = string_utils::to_string(&object::object_address(obj));
            if(!Shared::assert_shared_storage((storage_address_bytes))){
                Shared::create_non_user_shared_storage((storage_address_bytes));
            };
        return (storage_address_bytes)
    }
    // FEE MUST be atleast 1 FRACTION of a token (1/1e6)
    fun assert_minimal_fee(token: String, chain: String, provider: String, amount: u256, fee: u256): (u256, u256) acquires Permissions{
        let combined_fee = fee;
        if (combined_fee < 1 * 1000000000000000000) {
            combined_fee =  1 * 1000000000000000000;
        };
        
        Liquidity::add_accumulated_rewards(token, chain, provider, combined_fee, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));
        let taxed_amount = if (amount > combined_fee) { amount - combined_fee } else { 0 };
        
        return (taxed_amount, combined_fee)
    }

    // FEE MUST be atleast 1 FRACTION of a token (1/1e6)
    fun handle_withdrawal_fee(token: String, chain: String, provider: String, amount: u256): (u256, u256) acquires Permissions{
        let metadata = TokensMetadata::get_coin_metadata_by_symbol(token);
        let w_fee = TokensMetadata::get_coin_metadata_market_w_fee(&metadata);
        let fee = (amount*(w_fee as u256))/100_000_000;
        if (fee < 1 * 1000000000000000000) {
            fee =  1 * 1000000000000000000;
        };
        
        Liquidity::add_accumulated_rewards(token, chain, provider, fee, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));
        let taxed_amount = if (amount > fee) { amount - fee } else { 0 };
        
        return (taxed_amount, fee)
    }

    /// Converts a hex string representation of an address (with or without '0x') to an actual address type.
    fun string_to_address(s: &String): address {
        let bytes = String::bytes(s);
        let len = vector::length(bytes);
        let start = 0;
        
        if (len > 2 && *vector::borrow(bytes, 0) == 48 && (*vector::borrow(bytes, 1) == 120 || *vector::borrow(bytes, 1) == 88)) {
            start = 2;
        };
        
        let hex_bytes = vector::empty<u8>();
        let i = start;
        while (i < len) {
            vector::push_back(&mut hex_bytes, *vector::borrow(bytes, i));
            i = i + 1;
        };

        if (vector::length(&hex_bytes) % 2 != 0) {
            vector::insert(&mut hex_bytes, 0, 48);
        };

        while (vector::length(&hex_bytes) < 64) {
            vector::insert(&mut hex_bytes, 0, 48);
        };

        let addr_bytes = vector::empty<u8>();
        let k = 0;
        let hex_len = vector::length(&hex_bytes);
        while (k < hex_len) {
            let high = hex_char_to_val(*vector::borrow(&hex_bytes, k));
            let low = hex_char_to_val(*vector::borrow(&hex_bytes, k + 1));
            vector::push_back(&mut addr_bytes, (high << 4) | low);
            k = k + 2;
        };

        from_bcs::to_address(addr_bytes)
    }

    fun hex_char_to_val(c: u8): u8 {
        if (c >= 48 && c <= 57) { c - 48 } // '0'..'9'
        else if (c >= 97 && c <= 102) { c - 97 + 10 } // 'a'..'f'
        else if (c >= 65 && c <= 70) { c - 65 + 10 } // 'A'..'F'
        else { 0 }
    }

// === VIEWS === //
    #[view]
    public fun calculate_mint_ratio(total_deposited: u256, total_accumulated_interest: u256,  total_native_accumulated_rewards: u256, shares: u256): u256 {
         shares / (total_deposited + total_accumulated_interest + total_native_accumulated_rewards)
    }

    #[view]
    public fun get_withdraw_fee(multiply: u256, limit: u256, amount: u256): u256 {


        let base_fee = 100; // 0.01% base fee
        let utilization = ((amount*1_000_000) / limit)*100;

        let bonus = (multiply / 10); // utilization has 50% effect

        if(utilization == 0){
            utilization = 100;
        };

        return ((base_fee + ((bonus*base_fee)/100))*(utilization/2)/100_000_000) + (base_fee + ((bonus*base_fee)/100))
    }

    #[view] 
    public fun calculate_deposit_points(user_deposited: u256, last_update: u64): u256 {
        let base_points = Points::return_market_liquidity_provision_points_conversion();

        let precision_factor: u256 = 1_000_000; 

        let now = (timestamp::now_seconds() as u256);
        let last = (last_update as u256);
        
        let time = now - last;
        let incentive_points_reward = (user_deposited * time * base_points) / precision_factor / precision_factor;

        return incentive_points_reward 
    }

    #[view]
    public fun calculate_global_rewards(total_deposited: u256, total_apr: u256, time_diff: u256): u256 {
        return (total_deposited * total_apr * time_diff) / 31_556_926 / 100000 
    }
    #[view]
    public fun calculate_global_interest(total_borrowed: u256, borrow_apr: u256, time_diff: u256): u256 {
        return (total_borrowed * borrow_apr * time_diff) / 31_556_926 / 100000 
    }

    #[view]
    public fun calculate_user_burned_qiara_interest_rewards(total_accumulated_rewards: u256, user_accumulated_rewards_index: u256, user_deposited: u256, total_deposited: u256): u256 {
        return (total_accumulated_rewards - user_accumulated_rewards_index) * user_deposited / total_deposited
    }

    #[view]
    public fun calculate_user_borrow_interest(total_accumulated_interest: u256, user_accumulated_interest_index: u256, user_total_debt: u256, total_borrowed: u256): u256 {
        if (total_borrowed == 0 || total_accumulated_interest <= user_accumulated_interest_index) {
            return 0
        };
        
        let index_diff = total_accumulated_interest - user_accumulated_interest_index;
        (index_diff * user_total_debt) / total_borrowed
    }

    #[view]
    public fun calculate_user_native_rewards(total_native_accumulated_rewards: u256, user_native_accumulated_rewards_index: u256, user_total_deposited: u256, total_deposited: u256): u256 {        
        let index_diff = total_native_accumulated_rewards - user_native_accumulated_rewards_index;
        (index_diff * user_total_deposited) / total_deposited
    }

}
