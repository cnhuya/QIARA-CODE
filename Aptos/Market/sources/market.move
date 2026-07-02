module dev::QiaraVaultsV32 {
    use std::signer;
    use std::string::{Self as String, String, utf8};
    use std::timestamp;
    use std::vector;
    use std::type_info::{Self, TypeInfo};
    use std::table::{Self as table, Table};
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    use aptos_std::string_utils ::{Self as string_utils};
    use std::bcs;

    use aptos_framework::fungible_asset::{Self, MintRef, TransferRef, BurnRef, Metadata, FungibleAsset, FungibleStore};
    use aptos_framework::dispatchable_fungible_asset;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::account;

    use dev::QiaraTokensCoreV27::{Self as TokensCore, CoinMetadata, Access as TokensCoreAccess};
    use dev::QiaraTokensMetadataV27::{Self as TokensMetadata, VMetadata, Access as TokensMetadataAccess};
    use dev::QiaraTokensRatesV27::{Self as TokensRates, Access as TokensRatesAccess};
    use dev::QiaraTokensTiersV27::{Self as TokensTiers};
    use dev::QiaraTokensOmnichainV27::{Self as TokensOmnichain, Access as TokensOmnichainAccess};
    use dev::QiaraMarginV23::{Self as Margin, Access as MarginAccess};
    use dev::QiaraRanksV23::{Self as Points, Access as PointsAccess};
    use dev::QiaraRIV23::{Self as RI};
    use dev::QiaraBurnedQiaraV23::{Self as BurnedQiara};

    use dev::QiaraTokenTypesV27::{Self as TokensTypes};
    use dev::QiaraChainTypesV27::{Self as ChainTypes};
    use dev::QiaraProviderTypesV27::{Self as ProviderTypes};

    use dev::QiaraStorageV11::{Self as storage, Access as StorageAccess};
    use dev::QiaraCapabilitiesV11::{Self as capabilities, Access as CapabilitiesAccess};

    use dev::QiaraSharedV8::{Self as Shared, Access as SharedAccess};

    use dev::QiaraGasV9::{Self as Gas, Access as GasAccess};

    use dev::QiaraLiquidityV35::{Self as Liquidity, Access as LiquidityAccess};
    use dev::QiaraTokenVaultsV35::{Self as TokenVaults, Access as TokenVaultsAccess};

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
        //capabilities::assert_wallet_capability(utf8(b"QiaraVault"), utf8(b"PERMISSION_TO_INITIALIZE_VAULTS"));
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
        tokens_rates: TokensRatesAccess,
        tokens_omnichain: TokensOmnichainAccess,
        tokens_core: TokensCoreAccess,
        tokens_metadata: TokensMetadataAccess,
        storage: StorageAccess,
        capabilities: CapabilitiesAccess,
        gas: GasAccess,
        shared: SharedAccess
    }

// === STRUCTS === //

// === FUNCTIONS === //
    fun init_module(admin: &signer){
        if (!exists<Permissions>(@dev)) {
            move_to(admin, Permissions {shared: Shared::give_access(admin), gas: Gas::give_access(admin), token_vaults: TokenVaults::give_access(admin), liquidity: Liquidity::give_access(admin), margin: Margin::give_access(admin), points: Points::give_access(admin), tokens_rates:  TokensRates::give_access(admin), tokens_omnichain: TokensOmnichain::give_access(admin), tokens_core: TokensCore::give_access(admin),tokens_metadata: TokensMetadata::give_access(admin), storage:  storage::give_access(admin), capabilities:  capabilities::give_access(admin)});
        };
    //    init_all_vaults(admin);

    }

// === CONSENSUS INTERFACE === //
    /// Deposit on behalf of `recipient`
    /// No need for recipient to have signed anything.

    public fun c_bridge_deposit(validator: &signer, shared: String, sender: vector<u8>, token: String, chain: String, provider: String, amount: u64, lend_rate: u64, permission: Permission) acquires Permissions {
        Shared::assert_is_sub_owner(shared, sender);
        TokensOmnichain::change_UserTokenSupply(token, chain, shared, amount, false, TokensOmnichain::give_permission(&borrow_global<Permissions>(@dev).tokens_omnichain)); 
        let amount_u256 = (amount as u256)*1000000000000000000;

        let (total_borrowed, total_deposited, total_staked, total_accumulated_rewards, total_accumulated_interest, virtual_borrowed, virtual_deposited, last_update) = Liquidity::return_raw_vault(token, chain, provider);
        let (_, _fee) = TokensMetadata::impact(token, amount_u256/1000000000000000000, total_deposited/1000000000000000000, true, utf8(b"spot"), TokensMetadata::give_permission(&borrow_global<Permissions>(@dev).tokens_metadata));
      
        let gas_rate = Gas::add_deposit(token, amount_u256, Gas::give_permission(&borrow_global<Permissions>(@dev).gas));
        handle_gas_fee(shared, sender, token);
        
        let (amount_u256_taxed,fee) = assert_minimal_fee(token, chain, provider,  amount_u256, _fee);
        if(amount_u256_taxed == 0) { return };

        TokensRates::update_rate(token, chain, provider, lend_rate, TokensRates::give_permission(&borrow_global<Permissions>(@dev).tokens_rates));
        
        let fa = TokensCore::mint(token, chain, amount, TokensCore::give_permission(&borrow_global<Permissions>(@dev).tokens_core)); 
       
        let storage = Liquidity::return_storage(token, chain, provider);
        let storage_address_string = non_user_storage_helper(&storage);

        TokensCore::deposit(storage_address_string, storage, fa, chain);
        Liquidity::add_deposit(token, chain, provider, amount_u256, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));

        Margin::update_reward_index(shared, sender, token, chain, provider, total_accumulated_rewards, Margin::give_permission(&borrow_global<Permissions>(@dev).margin)); 
        Margin::add_deposit(shared, sender, token, chain, provider, amount_u256_taxed, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));

        let (total_rewards, total_interest, user_borrow_interest, user_lend_rewards, user_points, qiara_base_apr, borrow_apr) = new_accrue(shared, sender, token, chain, provider);

        let data = vector[
            // Items from the event top-level fields
            Event::create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&utf8(b"zk"))),
            Event::create_data_struct(utf8(b"validator"), utf8(b"vector<u8>"), bcs::to_bytes(&signer::address_of(validator))),
            Event::create_data_struct(utf8(b"recipient"), utf8(b"vector<u8>"), bcs::to_bytes(&sender)),
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
            Event::create_data_struct(utf8(b"qiara_base_apr"), utf8(b"u256"), bcs::to_bytes(&qiara_base_apr)),
            Event::create_data_struct(utf8(b"borrow_apr"), utf8(b"u256"), bcs::to_bytes(&borrow_apr))

            
        ];

        if(user_borrow_interest > 0){
            vector::push_back(&mut data, Event::create_data_struct(utf8(b"borrow_interest"), utf8(b"u256"), bcs::to_bytes(&user_borrow_interest)))
        };
       // tttta(0);
        Event::emit_market_event(utf8(b"Bridge Deposit"), data);
    }

    // Recipient needs to be address here, in case permissioneless user wants to withdraw to existing Supra wallet.
    public fun c_bridge_withdraw(validator: &signer, shared: String, sender: vector<u8>, recipient: address, token: String, chain: String, provider: String, amount: u64, lend_rate: u64, permission: Permission) acquires Permissions {
        let (total_borrowed, total_deposited, total_staked, total_accumulated_rewards, total_accumulated_interest, virtual_borrowed, virtual_deposited, last_update) = Liquidity::return_raw_vault(token, chain, provider);
        TokensRates::update_rate(token, chain, provider, lend_rate, TokensRates::give_permission(&borrow_global<Permissions>(@dev).tokens_rates));
        // Yes it is intentional that recipient is first, because thats the shared storage. (in case i forget again)

        let amount_u256 = (amount as u256)*1000000000000000000;
        
        let (_, _fee) = TokensMetadata::impact(token, amount_u256/1000000000000000000, total_deposited/1000000000000000000, true, utf8(b"spot"), TokensMetadata::give_permission(&borrow_global<Permissions>(@dev).tokens_metadata));
      
        let gas_rate = Gas::add_withdraw(token, amount_u256, Gas::give_permission(&borrow_global<Permissions>(@dev).gas));
        handle_gas_fee(shared, sender, token);
        
        let (amount_u256_taxed,fee) = assert_minimal_fee(token, chain, provider,  amount_u256, _fee);
        if(amount_u256_taxed == 0) { return };

        Margin::update_reward_index(shared, sender, token, chain, provider, fee, Margin::give_permission(&borrow_global<Permissions>(@dev).margin)); 
        Margin::remove_deposit(shared, sender, token, chain, provider, amount_u256_taxed, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));

      
        let storage = Liquidity::return_storage(token, chain, provider);
        let storage_address_string = non_user_storage_helper(&storage);

        let fa = TokensCore::withdraw(storage_address_string, storage, amount, chain); 

        let user_storage = primary_fungible_store::ensure_primary_store_exists(recipient,TokensCore::get_metadata(token));
        TokensCore::deposit(shared, user_storage, fa, chain);

        assert!(total_deposited >= amount_u256_taxed, ERROR_NOT_ENOUGH_LIQUIDITY);
        Liquidity::remove_deposit(token, chain, provider, amount_u256_taxed, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));

        let (total_rewards, total_interest, user_borrow_interest, user_lend_rewards, user_points, qiara_base_apr, borrow_apr) = new_accrue(shared, sender, token, chain, provider);

        let data = vector[
            // Items from the event top-level fields
            Event::create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&utf8(b"zk"))),
            Event::create_data_struct(utf8(b"validator"), utf8(b"vector<u8>"), bcs::to_bytes(&signer::address_of(validator))),
            Event::create_data_struct(utf8(b"recipient"), utf8(b"vector<u8>"), bcs::to_bytes(&sender)),
            Event::create_data_struct(utf8(b"token"), utf8(b"string"), bcs::to_bytes(&token)),
            Event::create_data_struct(utf8(b"chain"), utf8(b"string"), bcs::to_bytes(&chain)),
            Event::create_data_struct(utf8(b"provider"), utf8(b"string"), bcs::to_bytes(&provider)),
            Event::create_data_struct(utf8(b"recipient"), utf8(b"address"), bcs::to_bytes(&recipient)),

            // Original items from the data vector
            Event::create_data_struct(utf8(b"amount"), utf8(b"u256"), bcs::to_bytes(&amount_u256_taxed)),
            Event::create_data_struct(utf8(b"fee"), utf8(b"u256"), bcs::to_bytes(&fee)),
            Event::create_data_struct(utf8(b"points"), utf8(b"u256"), bcs::to_bytes(&user_points)),
            Event::create_data_struct(utf8(b"lend_rewards"), utf8(b"u256"), bcs::to_bytes(&user_lend_rewards)),

            Event::create_data_struct(utf8(b"total_rewards"), utf8(b"u256"), bcs::to_bytes(&total_rewards)),
            Event::create_data_struct(utf8(b"total_interest"), utf8(b"u256"), bcs::to_bytes(&total_interest)),
            Event::create_data_struct(utf8(b"qiara_base_apr"), utf8(b"u256"), bcs::to_bytes(&qiara_base_apr)),
            Event::create_data_struct(utf8(b"borrow_apr"), utf8(b"u256"), bcs::to_bytes(&borrow_apr))
        ];

        if(user_borrow_interest > 0){
            vector::push_back(&mut data, Event::create_data_struct(utf8(b"borrow_interest"), utf8(b"u256"), bcs::to_bytes(&user_borrow_interest)))
        };

        Event::emit_market_event(utf8(b"Bridge Withdraw"),data);
    }

    // Recipient needs to be address here, in case permissioneless user wants to borrow to existing Supra wallet.
    public fun c_bridge_borrow(validator: &signer, shared: String, sender: vector<u8>, recipient: address, token: String, chain: String, provider: String, amount: u64, lend_rate: u64, permission: Permission) acquires Permissions {
        TokensOmnichain::change_UserTokenSupply(token, chain, shared, amount, true, TokensOmnichain::give_permission(&borrow_global<Permissions>(@dev).tokens_omnichain)); 
        let amount_u256 = (amount as u256)*1000000000000000000;

        let (total_borrowed, total_deposited, total_staked, total_accumulated_rewards, total_accumulated_interest, virtual_borrowed, virtual_deposited, last_update) = Liquidity::return_raw_vault(token, chain, provider);

        let (_, _fee) = TokensMetadata::impact(token, amount_u256/1000000000000000000, total_deposited/1000000000000000000, true, utf8(b"spot"), TokensMetadata::give_permission(&borrow_global<Permissions>(@dev).tokens_metadata));
      
        let gas_rate = Gas::add_borrow(token, amount_u256, Gas::give_permission(&borrow_global<Permissions>(@dev).gas));
        handle_gas_fee(shared, sender, token);
        
        let (amount_u256_taxed,fee) = assert_minimal_fee(token, chain, provider,  amount_u256, _fee);
        if(amount_u256_taxed == 0) { return };


        Margin::update_reward_index(shared, sender, token, chain, provider, fee, Margin::give_permission(&borrow_global<Permissions>(@dev).margin)); 
    
        TokensRates::update_rate(token, chain, provider, lend_rate, TokensRates::give_permission(&borrow_global<Permissions>(@dev).tokens_rates));

        let storage = Liquidity::return_storage(token, chain, provider);
        let storage_address_string = non_user_storage_helper(&storage);

        let fa = TokensCore::withdraw(storage_address_string, storage, amount, chain);
        TokensCore::deposit(shared, primary_fungible_store::ensure_primary_store_exists(recipient,TokensCore::get_metadata(token)), fa, chain);

        assert!(total_deposited >= (amount as u256), ERROR_NOT_ENOUGH_LIQUIDITY);
        Liquidity::remove_deposit(token, chain, provider, amount_u256, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));

        Margin::add_borrow(shared, sender, token, chain, provider, (amount as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        Liquidity::add_borrow(token, chain, provider, amount_u256, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));
        let (total_rewards, total_interest, user_borrow_interest, user_lend_rewards, user_points, qiara_base_apr, borrow_apr) = new_accrue(shared,  sender, token, chain, provider);
        let data = vector[
            // Items from the event top-level fields
            Event::create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&utf8(b"zk"))),
            Event::create_data_struct(utf8(b"validator"), utf8(b"vector<u8>"), bcs::to_bytes(&signer::address_of(validator))),
            Event::create_data_struct(utf8(b"sender"), utf8(b"vector<u8>"), bcs::to_bytes(&sender)),
            Event::create_data_struct(utf8(b"token"), utf8(b"string"), bcs::to_bytes(&token)),
            Event::create_data_struct(utf8(b"chain"), utf8(b"string"), bcs::to_bytes(&chain)),
            Event::create_data_struct(utf8(b"provider"), utf8(b"string"), bcs::to_bytes(&provider)),
            Event::create_data_struct(utf8(b"recipient"), utf8(b"address"), bcs::to_bytes(&recipient)),

            // Original items from the data vector
            Event::create_data_struct(utf8(b"amount"), utf8(b"u256"), bcs::to_bytes(&amount_u256_taxed)),
            Event::create_data_struct(utf8(b"fee"), utf8(b"u256"), bcs::to_bytes(&fee)),
            Event::create_data_struct(utf8(b"points"), utf8(b"u256"), bcs::to_bytes(&user_points)),
            Event::create_data_struct(utf8(b"lend_rewards"), utf8(b"u256"), bcs::to_bytes(&user_lend_rewards)),

            Event::create_data_struct(utf8(b"total_rewards"), utf8(b"u256"), bcs::to_bytes(&total_rewards)),
            Event::create_data_struct(utf8(b"total_interest"), utf8(b"u256"), bcs::to_bytes(&total_interest)),
            Event::create_data_struct(utf8(b"qiara_base_apr"), utf8(b"u256"), bcs::to_bytes(&qiara_base_apr)),
            Event::create_data_struct(utf8(b"borrow_apr"), utf8(b"u256"), bcs::to_bytes(&borrow_apr))
        ];

        if(user_borrow_interest > 0){
            vector::push_back(&mut data, Event::create_data_struct(utf8(b"borrow_interest"), utf8(b"u256"), bcs::to_bytes(&user_borrow_interest)))
        };

        Event::emit_market_event(utf8(b"Bridge Borrow"),data);
    }

    public fun c_bridge_repay(validator: &signer, shared: String, sender: vector<u8>,token: String, chain: String, provider: String, amount: u64, lend_rate: u64, permission: Permission) acquires Permissions {
        let amount_u256 = (amount as u256)*1000000000000000000;
        let (total_borrowed, total_deposited, total_staked, total_accumulated_rewards, total_accumulated_interest, virtual_borrowed, virtual_deposited, last_update) = Liquidity::return_raw_vault(token, chain, provider);
        let (_, fee) = TokensMetadata::impact(token, amount_u256, total_deposited, false, utf8(b"spot"), TokensMetadata::give_permission(&borrow_global<Permissions>(@dev).tokens_metadata));
        
        Margin::update_reward_index(shared, sender, token, chain, provider, fee, Margin::give_permission(&borrow_global<Permissions>(@dev).margin)); 
    
        let fa = TokensCore::mint(token, chain, amount, TokensCore::give_permission(&borrow_global<Permissions>(@dev).tokens_core)); 
        
        let storage = Liquidity::return_storage(token, chain, provider);
        let storage_address_string = non_user_storage_helper(&storage);

        TokensCore::deposit(storage_address_string, storage, fa, chain);

        TokensOmnichain::change_UserTokenSupply(token, chain, shared, amount, false, TokensOmnichain::give_permission(&borrow_global<Permissions>(@dev).tokens_omnichain)); 
        Margin::remove_borrow(shared, sender, token, chain, provider, (amount as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        
        Liquidity::add_deposit(token, chain, provider, amount_u256, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));
        Liquidity::remove_borrow(token, chain, provider, amount_u256, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));

        let (total_rewards, total_interest, user_borrow_interest, user_lend_rewards,user_points, qiara_base_apr, borrow_apr) = new_accrue(shared, sender, token, chain, provider);
        let data = vector[
            // Items from the event top-level fields
            Event::create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&utf8(b"zk"))),
            Event::create_data_struct(utf8(b"validator"), utf8(b"vector<u8>"), bcs::to_bytes(&signer::address_of(validator))),
            Event::create_data_struct(utf8(b"sender"), utf8(b"vector<u8>"), bcs::to_bytes(&sender)),
            Event::create_data_struct(utf8(b"token"), utf8(b"string"), bcs::to_bytes(&token)),
            Event::create_data_struct(utf8(b"chain"), utf8(b"string"), bcs::to_bytes(&chain)),
            Event::create_data_struct(utf8(b"provider"), utf8(b"string"), bcs::to_bytes(&provider)),

            // Original items from the data vector
            Event::create_data_struct(utf8(b"amount"), utf8(b"u256"), bcs::to_bytes(&amount_u256)),
            Event::create_data_struct(utf8(b"fee"), utf8(b"u256"), bcs::to_bytes(&fee)),
            Event::create_data_struct(utf8(b"points"), utf8(b"u256"), bcs::to_bytes(&user_points)),
            Event::create_data_struct(utf8(b"lend_rewards"), utf8(b"u256"), bcs::to_bytes(&user_lend_rewards)),

            Event::create_data_struct(utf8(b"total_rewards"), utf8(b"u256"), bcs::to_bytes(&total_rewards)),
            Event::create_data_struct(utf8(b"total_interest"), utf8(b"u256"), bcs::to_bytes(&total_interest)),
            Event::create_data_struct(utf8(b"qiara_base_apr"), utf8(b"u256"), bcs::to_bytes(&qiara_base_apr)),
            Event::create_data_struct(utf8(b"borrow_apr"), utf8(b"u256"), bcs::to_bytes(&borrow_apr))
        ];

        if(user_borrow_interest > 0){
            vector::push_back(&mut data, Event::create_data_struct(utf8(b"borrow_interest"), utf8(b"u256"), bcs::to_bytes(&user_borrow_interest)))
        };

        Event::emit_market_event(utf8(b"Bridge Repay"),data);

    }

    public entry fun c_bridge_claim_rewards(validator: &signer,  shared: String, sender: vector<u8>,  token: String, chain: String, provider: String) acquires Permissions {
        let (total_borrowed, total_deposited, total_staked, total_accumulated_rewards, total_accumulated_interest, virtual_borrowed, virtual_deposited, last_update) = Liquidity::return_raw_vault(token, chain, provider);
        let (_,_,user_deposited, user_borrowed, _, user_rewards, _, user_interest, _, _,_) = Margin::get_user_raw_balance(shared, token, chain, provider);

        let reward_amount = user_rewards;
        let interest_amount = user_interest;

        let storage = Liquidity::return_storage(token, chain, provider);
        let storage_address_string = non_user_storage_helper(&storage);

        let (total_rewards, total_interest, user_borrow_interest, user_lend_rewards, user_points, qiara_base_apr, borrow_apr) = new_accrue(shared, sender, token, chain, provider);
        let data = vector[
            // Items from the event top-level fields
            Event::create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&utf8(b"zk"))),
            Event::create_data_struct(utf8(b"validator"), utf8(b"vector<u8>"), bcs::to_bytes(&signer::address_of(validator))),
            Event::create_data_struct(utf8(b"sender"), utf8(b"vector<u8>"), bcs::to_bytes(&sender)),
            Event::create_data_struct(utf8(b"shared"), utf8(b"string"), bcs::to_bytes(&shared)),
            Event::create_data_struct(utf8(b"token"), utf8(b"string"), bcs::to_bytes(&token)),
            Event::create_data_struct(utf8(b"chain"), utf8(b"string"), bcs::to_bytes(&chain)),
            Event::create_data_struct(utf8(b"provider"), utf8(b"string"), bcs::to_bytes(&provider)),

            // Original items from the data vector
            Event::create_data_struct(utf8(b"points"), utf8(b"u256"), bcs::to_bytes(&user_points)),
            Event::create_data_struct(utf8(b"lend_rewards"), utf8(b"u256"), bcs::to_bytes(&user_lend_rewards)),

            Event::create_data_struct(utf8(b"total_rewards"), utf8(b"u256"), bcs::to_bytes(&total_rewards)),
            Event::create_data_struct(utf8(b"total_interest"), utf8(b"u256"), bcs::to_bytes(&total_interest)),
            Event::create_data_struct(utf8(b"qiara_base_apr"), utf8(b"u256"), bcs::to_bytes(&qiara_base_apr)),
            Event::create_data_struct(utf8(b"borrow_apr"), utf8(b"u256"), bcs::to_bytes(&borrow_apr))
        ];

        if(user_borrow_interest > 0){
            vector::push_back(&mut data, Event::create_data_struct(utf8(b"borrow_interest"), utf8(b"u256"), bcs::to_bytes(&user_borrow_interest)))
        };


        if(reward_amount > interest_amount){
            let reward = (reward_amount - interest_amount);
            Event::create_data_struct(utf8(b"amount"), utf8(b"u256"), bcs::to_bytes(&reward));
            let fa = TokensCore::withdraw(storage_address_string, storage, (reward as u64), chain);
            TokensCore::burn_fa(token, chain, fa, TokensCore::give_permission(&borrow_global<Permissions>(@dev).tokens_core));
            TokensOmnichain::change_UserTokenSupply(token, chain, shared, (reward as u64), true, TokensOmnichain::give_permission(&borrow_global<Permissions>(@dev).tokens_omnichain)); 
          
            assert!(total_deposited >= (reward as u256), ERROR_NOT_ENOUGH_LIQUIDITY);
            Liquidity::remove_deposit(token, chain, provider, (reward as u256), Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));
            Event::emit_market_event(utf8(b"Bridge Claim Rewards"), data);
        } else{
            let interest = (interest_amount - reward_amount);
            Event::create_data_struct(utf8(b"amount"), utf8(b"u256"), bcs::to_bytes(&interest));

            Margin::remove_deposit(shared, sender, token, chain, provider, interest, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
            TokensOmnichain::change_UserTokenSupply(token, chain, shared, (interest as u64), false, TokensOmnichain::give_permission(&borrow_global<Permissions>(@dev).tokens_omnichain)); 

            let fa = TokensCore::mint(token, chain, (interest as u64), TokensCore::give_permission(&borrow_global<Permissions>(@dev).tokens_core)); 
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
        let (total_borrowed, total_deposited, total_staked, total_accumulated_rewards, total_accumulated_interest, virtual_borrowed, virtual_deposited, last_update) = Liquidity::return_raw_vault(token, chain, provider);

        let obj = primary_fungible_store::ensure_primary_store_exists(signer::address_of(signer),TokensCore::get_metadata(token));

        let (_, _fee) = TokensMetadata::impact(token, amount_u256/1000000000000000000, total_deposited/1000000000000000000, true, utf8(b"spot"), TokensMetadata::give_permission(&borrow_global<Permissions>(@dev).tokens_metadata));
      
        let gas_rate = Gas::add_deposit(token, amount_u256, Gas::give_permission(&borrow_global<Permissions>(@dev).gas));
        handle_gas_fee(shared, sender, token);
        
        let (amount_u256_taxed,fee) = assert_minimal_fee(token, chain, provider,  amount_u256, _fee);
        if(amount_u256_taxed == 0) { return };


        let fa = TokensCore::withdraw(shared, obj, amount, chain);
        Liquidity::deposit_token(token, chain, provider, fa, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));

        Margin::update_reward_index(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider, total_accumulated_rewards, Margin::give_permission(&borrow_global<Permissions>(@dev).margin)); 
        Margin::add_stake(shared,bcs::to_bytes(&signer::address_of(signer)), token, chain, provider, amount_u256, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        
        let data = vector[
            Event::create_data_struct(utf8(b"sender"), utf8(b"address"), bcs::to_bytes(&signer::address_of(signer))),
            Event::create_data_struct(utf8(b"shared"), utf8(b"string"), bcs::to_bytes(&shared)),
            Event::create_data_struct(utf8(b"token"), utf8(b"string"), bcs::to_bytes(&token)),
            Event::create_data_struct(utf8(b"chain"), utf8(b"string"), bcs::to_bytes(&chain)),
            Event::create_data_struct(utf8(b"provider"), utf8(b"string"), bcs::to_bytes(&provider)),
            Event::create_data_struct(utf8(b"amount"), utf8(b"u256"), bcs::to_bytes(&amount_u256)),
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
            let (total_borrowed, total_deposited, total_staked, total_accumulated_rewards, total_accumulated_interest, virtual_borrowed, virtual_deposited, last_update) = Liquidity::return_raw_vault(_token, _chain, _provider);

            let (_, _fee) = TokensMetadata::impact(_token, amount_u256/1000000000000000000, total_deposited/1000000000000000000, true, utf8(b"spot"), TokensMetadata::give_permission(&borrow_global<Permissions>(@dev).tokens_metadata));
        
            let gas_rate = Gas::add_withdraw(_token, amount_u256, Gas::give_permission(&borrow_global<Permissions>(@dev).gas));
            handle_gas_fee(shared,sender, _token);
            
            let (amount_u256_taxed,fee) = assert_minimal_fee(_token, _chain, _provider,  amount_u256, _fee);
            if(amount_u256_taxed == 0) { return };


            len=len-1;

            let obj = primary_fungible_store::ensure_primary_store_exists(signer::address_of(signer),TokensCore::get_metadata(_token));

            let fa = Liquidity::withdraw_token(_token, _chain, _provider, amount_u256, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));
            TokensCore::deposit(shared, primary_fungible_store::ensure_primary_store_exists(signer::address_of(signer),TokensCore::get_metadata(_token)), fa, _chain);
            vector::push_back(&mut vect_amnt, amount_u256);
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

        let (total_borrowed, total_deposited, total_staked, total_accumulated_rewards, total_accumulated_interest, virtual_borrowed, virtual_deposited, last_update) = Liquidity::return_raw_vault(token, chain, provider);

        let (_, _fee) = TokensMetadata::impact(token, amount_u256/1000000000000000000, total_deposited/1000000000000000000, true, utf8(b"spot"), TokensMetadata::give_permission(&borrow_global<Permissions>(@dev).tokens_metadata));
      
        let gas_rate = Gas::add_deposit(token, amount_u256, Gas::give_permission(&borrow_global<Permissions>(@dev).gas));
        let gas_fee = handle_gas_fee(shared, sender, token);
        
        let (amount_u256_taxed,fee) = assert_minimal_fee(token, chain, provider,  amount_u256, _fee);
        if(amount_u256_taxed == 0) { return };


        let obj = primary_fungible_store::ensure_primary_store_exists(signer::address_of(signer),TokensCore::get_metadata(token));
        let fa = TokensCore::withdraw(shared, obj, amount, chain);

        Liquidity::deposit_token(token, chain, provider, fa, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));

        Margin::update_reward_index(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider, total_accumulated_rewards, Margin::give_permission(&borrow_global<Permissions>(@dev).margin)); 
        Margin::add_deposit(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider, amount_u256_taxed, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
 
        Margin::add_locked_fee(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider, ((fee-1000000000000000000)*99)/100, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        let (total_rewards, total_interest, user_borrow_interest, user_lend_rewards, user_points, qiara_base_apr, borrow_apr) = new_accrue(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider);
        //            tttta(100);
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

            Event::create_data_struct(utf8(b"gas_rate"), utf8(b"u256"), bcs::to_bytes(&gas_rate)),
            Event::create_data_struct(utf8(b"gas_fee"), utf8(b"u256"), bcs::to_bytes(&gas_fee)),

            Event::create_data_struct(utf8(b"total_rewards"), utf8(b"u256"), bcs::to_bytes(&total_rewards)),
            Event::create_data_struct(utf8(b"total_interest"), utf8(b"u256"), bcs::to_bytes(&total_interest)),
            Event::create_data_struct(utf8(b"qiara_base_apr"), utf8(b"u256"), bcs::to_bytes(&qiara_base_apr)),
            Event::create_data_struct(utf8(b"borrow_apr"), utf8(b"u256"), bcs::to_bytes(&borrow_apr))
        ];

        if(user_borrow_interest > 0){
            vector::push_back(&mut data, Event::create_data_struct(utf8(b"borrow_interest"), utf8(b"u256"), bcs::to_bytes(&user_borrow_interest)))
        };

        Event::emit_market_event(utf8(b"Deposit"), data);
    }

    public entry fun withdraw(signer: &signer, shared: String, token: String, chain: String, provider: String, amount: u64) acquires Permissions {
        let sender = bcs::to_bytes(&signer::address_of(signer));
        let amount_u256 = (amount as u256)*1000000000000000000;

        let (total_borrowed, total_deposited, total_staked, total_accumulated_rewards, total_accumulated_interest, virtual_borrowed, virtual_deposited, last_update) = Liquidity::return_raw_vault(token, chain, provider);

        let (_, _fee) = TokensMetadata::impact(token, amount_u256/1000000000000000000, total_deposited/1000000000000000000, true, utf8(b"spot"), TokensMetadata::give_permission(&borrow_global<Permissions>(@dev).tokens_metadata));
      
        let gas_rate = Gas::add_withdraw(token, amount_u256, Gas::give_permission(&borrow_global<Permissions>(@dev).gas));
        let gas_fee = handle_gas_fee(shared, sender, token);
        
        let (amount_u256_taxed,fee) = assert_minimal_fee(token, chain, provider,  amount_u256, _fee);
        if(amount_u256_taxed == 0) { return };


        assert!(total_deposited >= amount_u256_taxed, ERROR_NOT_ENOUGH_LIQUIDITY);
        let obj = primary_fungible_store::ensure_primary_store_exists(signer::address_of(signer),TokensCore::get_metadata(token));
        let fa = Liquidity::withdraw_token(token, chain, provider, (amount_u256-fee)/1000000000000000000, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));

        TokensCore::deposit(shared, obj, fa, chain);

        Margin::update_reward_index(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider, total_accumulated_rewards, Margin::give_permission(&borrow_global<Permissions>(@dev).margin)); 
        Margin::remove_deposit(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider, amount_u256_taxed, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));

        let (total_rewards, total_interest, user_borrow_interest, user_lend_rewards,  user_points, qiara_base_apr, borrow_apr) = new_accrue(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider);
            
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

            Event::create_data_struct(utf8(b"gas_rate"), utf8(b"u256"), bcs::to_bytes(&gas_rate)),
            Event::create_data_struct(utf8(b"gas_fee"), utf8(b"u256"), bcs::to_bytes(&gas_fee)),

            Event::create_data_struct(utf8(b"total_rewards"), utf8(b"u256"), bcs::to_bytes(&total_rewards)),
            Event::create_data_struct(utf8(b"total_interest"), utf8(b"u256"), bcs::to_bytes(&total_interest)),
            Event::create_data_struct(utf8(b"qiara_base_apr"), utf8(b"u256"), bcs::to_bytes(&qiara_base_apr)),
            Event::create_data_struct(utf8(b"borrow_apr"), utf8(b"u256"), bcs::to_bytes(&borrow_apr))
        ];

        if(user_borrow_interest > 0){
            vector::push_back(&mut data, Event::create_data_struct(utf8(b"borrow_interest"), utf8(b"u256"), bcs::to_bytes(&user_borrow_interest)))
        };

        Event::emit_market_event(utf8(b"Withdraw"), data);
    }

    public entry fun borrow(signer: &signer, shared: String, token: String, chain: String, provider: String, amount: u64) acquires Permissions {
        let sender = bcs::to_bytes(&signer::address_of(signer));
        let amount_u256 = (amount as u256)*1000000000000000000;

        let (total_borrowed, total_deposited, total_staked, total_accumulated_rewards, total_accumulated_interest, virtual_borrowed, virtual_deposited, last_update) = Liquidity::return_raw_vault(token, chain, provider);

        let (_, _fee) = TokensMetadata::impact(token, amount_u256/1000000000000000000, total_deposited/1000000000000000000, true, utf8(b"spot"), TokensMetadata::give_permission(&borrow_global<Permissions>(@dev).tokens_metadata));
      
        let gas_rate = Gas::add_borrow(token, amount_u256, Gas::give_permission(&borrow_global<Permissions>(@dev).gas));
        let gas_fee = handle_gas_fee(shared, sender, token);
        
        let (amount_u256_taxed,fee) = assert_minimal_fee(token, chain, provider,  amount_u256, _fee);
        if(amount_u256_taxed == 0) { return };


        let obj = primary_fungible_store::ensure_primary_store_exists(signer::address_of(signer),TokensCore::get_metadata(token));
        let fa = Liquidity::withdraw_token(token, chain, provider, (amount_u256-fee)/1000000000000000000, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));

        TokensCore::deposit(shared, obj, fa, chain);

        Liquidity::add_borrow(token, chain, provider, amount_u256, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));
        Margin::update_reward_index(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider, total_accumulated_rewards, Margin::give_permission(&borrow_global<Permissions>(@dev).margin)); 
        Margin::add_borrow(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider, amount_u256_taxed, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));

        let (total_rewards, total_interest, user_borrow_interest, user_lend_rewards,  user_points, qiara_base_apr, borrow_apr) = new_accrue(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider);
            
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

            Event::create_data_struct(utf8(b"gas_rate"), utf8(b"u256"), bcs::to_bytes(&gas_rate)),
            Event::create_data_struct(utf8(b"gas_fee"), utf8(b"u256"), bcs::to_bytes(&gas_fee)),

            Event::create_data_struct(utf8(b"total_rewards"), utf8(b"u256"), bcs::to_bytes(&total_rewards)),
            Event::create_data_struct(utf8(b"total_interest"), utf8(b"u256"), bcs::to_bytes(&total_interest)),
            Event::create_data_struct(utf8(b"qiara_base_apr"), utf8(b"u256"), bcs::to_bytes(&qiara_base_apr)),
            Event::create_data_struct(utf8(b"borrow_apr"), utf8(b"u256"), bcs::to_bytes(&borrow_apr))
        ];

        if(user_borrow_interest > 0){
            vector::push_back(&mut data, Event::create_data_struct(utf8(b"borrow_interest"), utf8(b"u256"), bcs::to_bytes(&user_borrow_interest)))
        };

        Event::emit_market_event(utf8(b"Borrow"), data);
    }

    public entry fun virtual_borrow(signer: &signer, shared: String, token: String, chain: String, provider: String, amount: u64) acquires Permissions {
        let sender = bcs::to_bytes(&signer::address_of(signer));
        let amount_u256 = (amount as u256)*1000000000000000000;

        let (total_borrowed, total_deposited, total_staked, total_accumulated_rewards, total_accumulated_interest, virtual_borrowed, virtual_deposited, last_update) = Liquidity::return_raw_vault(token, chain, provider);

        let (_, _fee) = TokensMetadata::impact(token, amount_u256/1000000000000000000, total_deposited/1000000000000000000, true, utf8(b"spot"), TokensMetadata::give_permission(&borrow_global<Permissions>(@dev).tokens_metadata));
      
        let gas_rate = Gas::add_borrow(token, amount_u256, Gas::give_permission(&borrow_global<Permissions>(@dev).gas));
        handle_gas_fee(shared, sender, token);
        
        let (amount_u256_taxed,fee) = assert_minimal_fee(token, chain, provider,  amount_u256, _fee);
        if(amount_u256_taxed == 0) { return };


        Liquidity::add_virtual_borrow(token, chain, provider, amount_u256, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));
        Liquidity::remove_deposit(token, chain, provider, amount_u256, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));
        Margin::update_reward_index(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider, total_accumulated_rewards, Margin::give_permission(&borrow_global<Permissions>(@dev).margin)); 
        Margin::add_virtual_borrow(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider, amount_u256_taxed, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        
        let (total_rewards, total_interest, user_borrow_interest, user_lend_rewards, user_points, qiara_base_apr, borrow_apr) = new_accrue(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider);
            
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
            Event::create_data_struct(utf8(b"qiara_base_apr"), utf8(b"u256"), bcs::to_bytes(&qiara_base_apr)),
            Event::create_data_struct(utf8(b"borrow_apr"), utf8(b"u256"), bcs::to_bytes(&borrow_apr))
        ];

        if(user_borrow_interest > 0){
            vector::push_back(&mut data, Event::create_data_struct(utf8(b"borrow_interest"), utf8(b"u256"), bcs::to_bytes(&user_borrow_interest)))
        };

        Event::emit_market_event(utf8(b"Virtual Borrow"), data);
    }

    public entry fun virtual_deposit(signer: &signer, shared: String, token: String, chain: String, provider: String, amount: u64) acquires Permissions {
        let sender = bcs::to_bytes(&signer::address_of(signer));
        let amount_u256 = (amount as u256)*1000000000000000000;

        let (total_borrowed, total_deposited, total_staked, total_accumulated_rewards, total_accumulated_interest, virtual_borrowed, virtual_deposited, last_update) = Liquidity::return_raw_vault(token, chain, provider);

        let (_, _fee) = TokensMetadata::impact(token, amount_u256/1000000000000000000, total_deposited/1000000000000000000, true, utf8(b"spot"), TokensMetadata::give_permission(&borrow_global<Permissions>(@dev).tokens_metadata));
      
        let gas_rate = Gas::add_deposit(token, amount_u256, Gas::give_permission(&borrow_global<Permissions>(@dev).gas));
        handle_gas_fee(shared, sender, token);
        
        let (amount_u256_taxed,fee) = assert_minimal_fee(token, chain, provider,  amount_u256, _fee);
        if(amount_u256_taxed == 0) { return };


        Liquidity::add_virtual_deposit(token, chain, provider, amount_u256, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));
        Margin::update_reward_index(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider, total_accumulated_rewards, Margin::give_permission(&borrow_global<Permissions>(@dev).margin)); 
        Margin::add_virtual_deposit(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider, amount_u256_taxed, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        
        let (total_rewards, total_interest, user_borrow_interest, user_lend_rewards,  user_points, qiara_base_apr, borrow_apr) = new_accrue(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider);
            
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
            Event::create_data_struct(utf8(b"qiara_base_apr"), utf8(b"u256"), bcs::to_bytes(&qiara_base_apr)),
            Event::create_data_struct(utf8(b"borrow_apr"), utf8(b"u256"), bcs::to_bytes(&borrow_apr))
        ];

        if(user_borrow_interest > 0){
            vector::push_back(&mut data, Event::create_data_struct(utf8(b"borrow_interest"), utf8(b"u256"), bcs::to_bytes(&user_borrow_interest)))
        };

        Event::emit_market_event(utf8(b"Virtual Deposit"), data);
    }

    public entry fun virtual_repay(signer: &signer, shared: String, token: String, chain: String, provider: String, amount: u64) acquires Permissions {
        let sender = bcs::to_bytes(&signer::address_of(signer));
        let amount_u256 = (amount as u256)*1000000000000000000;

        let (total_borrowed, total_deposited, total_staked, total_accumulated_rewards, total_accumulated_interest, virtual_borrowed, virtual_deposited, last_update) = Liquidity::return_raw_vault(token, chain, provider);

        let (_, _fee) = TokensMetadata::impact(token, amount_u256/1000000000000000000, total_deposited/1000000000000000000, true, utf8(b"spot"), TokensMetadata::give_permission(&borrow_global<Permissions>(@dev).tokens_metadata));
      
        let gas_rate = Gas::add_deposit(token, amount_u256, Gas::give_permission(&borrow_global<Permissions>(@dev).gas));
        handle_gas_fee(shared, sender, token);
        
        let (amount_u256_taxed,fee) = assert_minimal_fee(token, chain, provider,  amount_u256, _fee);
        if(amount_u256_taxed == 0) { return };


        Liquidity::remove_virtual_borrow(token, chain, provider, amount_u256, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));
        Liquidity::add_deposit(token, chain, provider, amount_u256, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));
        Margin::update_reward_index(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider, total_accumulated_rewards, Margin::give_permission(&borrow_global<Permissions>(@dev).margin)); 
        Margin::remove_virtual_borrow(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider, amount_u256_taxed, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        
        let (total_rewards, total_interest, user_borrow_interest, user_lend_rewards,  user_points, qiara_base_apr, borrow_apr) = new_accrue(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider);
            
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
            Event::create_data_struct(utf8(b"qiara_base_apr"), utf8(b"u256"), bcs::to_bytes(&qiara_base_apr)),
            Event::create_data_struct(utf8(b"borrow_apr"), utf8(b"u256"), bcs::to_bytes(&borrow_apr))
        ];

        if(user_borrow_interest > 0){
            vector::push_back(&mut data, Event::create_data_struct(utf8(b"borrow_interest"), utf8(b"u256"), bcs::to_bytes(&user_borrow_interest)))
        };

        Event::emit_market_event(utf8(b"Virtual Repay"), data);
    }


    public entry fun repay(signer: &signer,shared: String,  token: String, chain: String, provider: String, amount: u64) acquires Permissions {
        let amount_u256 = (amount as u256)*1000000000000000000;

        let (total_borrowed, total_deposited, total_staked, total_accumulated_rewards, total_accumulated_interest, virtual_borrowed, virtual_deposited, last_update) = Liquidity::return_raw_vault(token, chain, provider);

        let fa = TokensCore::withdraw(shared, primary_fungible_store::ensure_primary_store_exists(signer::address_of(signer),TokensCore::get_metadata(token)), amount, chain);
        Liquidity::deposit_token(token, chain, provider, fa, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));

        Margin::remove_borrow(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider, (amount as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        Liquidity::remove_borrow(token, chain, provider, amount_u256, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));
        let (total_rewards, total_interest, user_borrow_interest, user_lend_rewards, user_points, qiara_base_apr, borrow_apr) = new_accrue( shared,bcs::to_bytes(&signer::address_of(signer)), token, chain, provider);
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
            Event::create_data_struct(utf8(b"qiara_base_apr"), utf8(b"u256"), bcs::to_bytes(&qiara_base_apr)),
            Event::create_data_struct(utf8(b"borrow_apr"), utf8(b"u256"), bcs::to_bytes(&borrow_apr))
        ];

        if (user_borrow_interest > 0) {
            vector::push_back(&mut data, Event::create_data_struct(utf8(b"borrow_interest"), utf8(b"u256"), bcs::to_bytes(&user_borrow_interest)));
        };

        Event::emit_market_event(utf8(b"Repay"), data);
    }

    public entry fun claim_rewards(signer: &signer, shared: String, token: String, chain: String, provider: String) acquires Permissions {

        let (total_borrowed, total_deposited, total_staked, total_accumulated_rewards, total_accumulated_interest, virtual_borrowed, virtual_deposited, last_update) = Liquidity::return_raw_vault(token, chain, provider);

        let (total_rewards, total_interest, user_borrow_interest, user_lend_rewards,  user_points, qiara_base_apr, borrow_apr) = new_accrue(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider);
        let (_,_,user_deposited, user_borrowed, _, user_rewards, _, user_interest, _, _,_) = Margin::get_user_raw_balance(shared, token, chain, provider);

        let reward_amount = user_rewards;
        let interest_amount = user_interest;


        let data = vector[
            Event::create_data_struct(utf8(b"sender"), utf8(b"address"), bcs::to_bytes(&signer::address_of(signer))),
            Event::create_data_struct(utf8(b"token"), utf8(b"string"), bcs::to_bytes(&token)),
            Event::create_data_struct(utf8(b"chain"), utf8(b"string"), bcs::to_bytes(&chain)),
            Event::create_data_struct(utf8(b"provider"), utf8(b"string"), bcs::to_bytes(&provider)),

            // Original items from the data vector
            Event::create_data_struct(utf8(b"points"), utf8(b"u256"), bcs::to_bytes(&user_points)),
            Event::create_data_struct(utf8(b"lend_rewards"), utf8(b"u256"), bcs::to_bytes(&user_lend_rewards)),


            Event::create_data_struct(utf8(b"total_rewards"), utf8(b"u256"), bcs::to_bytes(&total_rewards)),
            Event::create_data_struct(utf8(b"total_interest"), utf8(b"u256"), bcs::to_bytes(&total_interest)),
            Event::create_data_struct(utf8(b"qiara_base_apr"), utf8(b"u256"), bcs::to_bytes(&qiara_base_apr)),
            Event::create_data_struct(utf8(b"borrow_apr"), utf8(b"u256"), bcs::to_bytes(&borrow_apr))
        ];


        if(reward_amount > interest_amount){
            let reward = (reward_amount - interest_amount);
            vector::push_back(&mut data, Event::create_data_struct(utf8(b"amount"), utf8(b"u256"), bcs::to_bytes(&reward)));
            let fa = Liquidity::withdraw_token(token, chain, provider, reward_amount, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));
            assert!(total_deposited >= (reward as u256), ERROR_NOT_ENOUGH_LIQUIDITY);
            TokensCore::deposit(shared, primary_fungible_store::ensure_primary_store_exists(signer::address_of(signer),TokensCore::get_metadata(token)), fa, chain);
            Event::emit_market_event(utf8(b"Claim Rewards"), data);
        } else{
            let interest = (interest_amount - reward_amount);
            vector::push_back(&mut data, Event::create_data_struct(utf8(b"amount"), utf8(b"u256"), bcs::to_bytes(&interest)));
            // mby pridat like accumulated_interest do vaultu, pro "pricitavani" interstu, ale teoreticky se to
            // uz ted pricita akorat "neviditelne jelikoz uzivatel bude moct withdraw mene tokenu...
            Margin::remove_deposit(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider, interest, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
            let fa = TokensCore::withdraw(shared, primary_fungible_store::ensure_primary_store_exists(signer::address_of(signer),TokensCore::get_metadata(token)), (interest as u64), chain);

            Liquidity::deposit_token(token, chain, provider, fa, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));
            Event::emit_market_event(utf8(b"Pay Interest"), data);
        };
        Margin::remove_interest(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider, (reward_amount as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        Margin::remove_rewards(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider, (interest_amount as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
    }


    fun tttta(number: u64){
        abort(number);
    }


// === HELPERS === //

    public fun new_accrue(shared: String, user: vector<u8>, token: String, chain: String, provider: String): (u256, u256, u256, u256, u256, u256, u256) acquires Permissions {
        
        // 1. FETCH CURRENT BALANCES AND GLOBAL VAULT STATES
        // Mapping the 8th wildcard slot to 'user_incentive_index' to track your Credits Index checkpoint
        let (
            user_deposited, 
            user_borrowed, 
            user_virtual_deposited, 
            user_virtual_borrowed, 
            user_staked, 
            _, 
            user_accumulated_rewards_index, 
            user_incentive_index, 
            user_accumulated_interest_index, 
            _, 
            user_last_interacted
        ) = Margin::get_user_raw_balance(shared, token, chain, provider);

        let (
            total_borrowed, 
            total_deposited, 
            total_staked, 
            total_accumulated_rewards, 
            total_accumulated_interest, 
            virtual_borrowed, 
            virtual_deposited, 
            last_update
        ) = Liquidity::return_raw_vault(token, chain, provider);

        // Calculate utilization ratio using all 5 required parameters (correctly includes virtual balances)
        let utilization = Liquidity::get_utilization_ratio(
            total_deposited, 
            virtual_deposited, 
            total_borrowed, 
            virtual_borrowed, 
            total_staked
        );
        
        let metadata = TokensMetadata::get_coin_metadata_by_symbol(token);
        let id = (TokensMetadata::get_coin_metadata_tier(&metadata) as u8);

        // 2. CALCULATE GLOBAL INTERACTIVE INTEREST RATES (APRs)
        let (native_chain_lend_apr, _) = TokensRates::get_vault_raw(token, chain, provider);
        // 25% of the native provider APR is directed to the minimal APR model
        let (qiara_base_apr, provider_native_apr, total_apr, borrow_apr) = Liquidity::calculate_minimal_apr(id, utilization, (native_chain_lend_apr / 4) as u256);

        // 3. TRACK ELAPSED TIME GAP FOR ACCRUALS
        let current_time = timestamp::now_seconds();
        let time_diff = current_time - last_update;
        let user_time_diff = current_time - user_last_interacted;

        // Sync global vault state first (releasing expired incentives, updating timestamp)
        Liquidity::update(token, chain, provider, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));

        // FIX: Define total global supply as the sum of physical, staked, and virtual deposits to serve as the true economic denominator
        let global_total_supply = total_deposited + total_staked + virtual_deposited;

        // Sync the Global Virtual Credit Index using the complete global supply definition
        Liquidity::update_incentive_index(token, chain, provider, global_total_supply, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));

        // 4. ACCRUE GLOBAL POOL INTEREST & REWARDS SINCE LAST GLOBAL UPDATE
        // Accumulate native pool rewards over the time gap using the complete global supply base
        let native_accumulated_rewards = calculate_rewards(global_total_supply, total_apr, (time_diff as u256));
        Liquidity::add_native_accumulated_rewards(token, chain, provider, native_accumulated_rewards, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));

        // Calculate user net deposits (assets supplied minus assets borrowed)
        let user_total_supply = user_deposited + user_staked + user_virtual_deposited;
        let user_total_debt = user_borrowed + user_virtual_borrowed;
        let net_deposited = if (user_total_supply > user_total_debt) { user_total_supply - user_total_debt } else { 0 };

        // Check if user has locked enough utility tokens to qualify for premium interest rewards
        let (_, _, enoughLocked) = BurnedQiara::calculate_required_locked_tokens_u256(shared, total_deposited);
       
        // 5. USER INTEREST ACCRUAL (DEBT FEE)
        let user_interest = 0;
        if (user_total_debt > 0) {
            // Scaled calculation based on user's total debt (correctly includes virtual borrows)
            user_interest = (user_total_debt * borrow_apr * (time_diff as u256)) / 1_000_000_000; // Scaled to prevent decimal overflow
            
            Liquidity::add_accumulated_rewards(token, chain, provider, user_interest, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));
            Liquidity::add_accumulated_interest(token, chain, provider, user_interest, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));
            Margin::add_borrow(shared, user, token, chain, provider, user_interest, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        };

        // 6. USER REWARDS DISTRIBUTION (INTEREST PAYMENTS & NATIVE STAKING)
        let user_interest_reward;
        if (enoughLocked) {
            // FIX: Using global_total_supply as the denominator to prevent math inflation and protect pool rewards
            user_interest_reward = calculate_interest(total_accumulated_rewards, user_accumulated_rewards_index, net_deposited, global_total_supply);
            Margin::add_rewards(shared, user, token, chain, provider, user_interest_reward, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));   
        } else {
            // FIX: Non-index fallback rewards are now correctly calculated using the individual user's net_deposited position
            user_interest_reward = calculate_rewards(net_deposited, total_apr, (user_time_diff as u256));
            Margin::add_rewards(shared, user, token, chain, provider, user_interest_reward, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        };

        // 6b. VIRTUAL CREDIT INCENTIVE DISTRIBUTION
        // Note: If you want virtual/staked deposits to earn virtual credit incentives in the ledger, 
        // you would pass global_total_supply and user_total_supply here instead.
        let new_user_incentive_index = Liquidity::distribute_rewards(shared, user, token, chain, provider, total_deposited, user_deposited, (user_incentive_index as u128), Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));

        // 7. USER ENGAGEMENT POINTS (GAMEFI EXPERIENCE)
        let points_reward = calculate_deposit_points(user_deposited, user_last_interacted);
        Points::add_experience(shared, points_reward, Points::give_permission(&borrow_global<Permissions>(@dev).points));
        
        // 8. UPDATE CHECKPOINT INDEXES FOR THE USER TO PREVENT DOUBLE-CLAIMING
        Margin::update_reward_index(shared, user, token, chain, provider, total_accumulated_rewards, Margin::give_permission(&borrow_global<Permissions>(@dev).margin)); 
        Margin::update_interest_index(shared, user, token, chain, provider, total_accumulated_rewards, Margin::give_permission(&borrow_global<Permissions>(@dev).margin)); 

        // Update the user's personal virtual credit index checkpoint to the newly returned index
        Margin::update_native_reward_index(shared, user, token, chain, provider, (new_user_incentive_index as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin)); 

        // Update the timestamp tracking the user's last interaction
        Margin::update_time(shared, user, token, chain, provider, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));

        return (
            total_accumulated_rewards, 
            total_accumulated_interest, 
            user_interest, 
            user_interest_reward, 
            points_reward,
            total_apr,
            borrow_apr,
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
        
        Liquidity::add_accumulated_rewards(token, chain, provider, fee, Liquidity::give_permission(&borrow_global<Permissions>(@dev).liquidity));
        // Safety check to prevent negative amount if deposit amount is less than the minimum fee
        let taxed_amount = if (amount > combined_fee) { amount - combined_fee } else { 0 };
        
        return (taxed_amount, combined_fee)
    }

    fun handle_gas_fee(shared: String, user: vector<u8>, token: String): u256 acquires Permissions{
        let (total_user_usd, _, _, _, _, _, _, _, _, _, _) = Margin::get_user_total_usd(shared);
        let (user_gas_index, user_last_time_interacted) = Shared::extract_raw_gas_relations(Shared::return_shared_ownership_new(shared));
        let (gas_fee, gas_index) = Gas::calculate_gas_fee_from_index(user_gas_index, total_user_usd);

        Shared::update_gas_index(shared, gas_index, Shared::give_permission(&borrow_global<Permissions>(@dev).shared));
        Margin::remove_credit(shared, user, gas_fee, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        TokenVaults::fast_add_accumulated_rewards(token, gas_fee, TokenVaults::give_permission(&borrow_global<Permissions>(@dev).token_vaults));
        return gas_fee
    }

// === VIEWS === //
    
    #[view]
    public fun get_withdraw_fee(multiply: u256, limit: u256, amount: u256): u256 {


        let base_fee = 100; // 0.01% base fee
        let utilization = ((amount*1_000_000) / limit)*100;

        let bonus = (multiply / 10); // utilization has 50% effect


        //(base_fee * (multiply/10) + bonus)

        // 100 + 5
        if(utilization == 0){
            utilization = 100;
        };

        return ((base_fee + ((bonus*base_fee)/100))*(utilization/2)/100_000_000) + (base_fee + ((bonus*base_fee)/100))
    }

    #[view] 
    public fun calculate_deposit_points(user_deposited: u256, last_update: u64): u256 {
        let base_points = Points::return_market_liquidity_provision_points_conversion();

        let precision_factor: u256 = 1000000; 

        let now = (timestamp::now_seconds() as u256);
        let last = (last_update as u256);
        
       // if (now <= last) return 0;
        let time = now - last;

        // Calculation: (Amount * Time * Rate) / Precision
        // This ensures: ($1.00) * (1 sec) * (1.0 rate) = 1 point
        let incentive_points_reward = (user_deposited * time * base_points) / precision_factor;

        return incentive_points_reward 
    }

    #[view]
    public fun calculate_rewards(total_deposited: u256, total_apr: u256, time_diff: u256): u256 {
        return (total_deposited * total_apr * time_diff) / 31_556_926 / 100000 // (/100 - convert from percentage + /1000 - apr scale)
    }
    #[view]
    public fun calculate_interest(total_accumulated_rewards: u256, user_accumulated_rewards_index: u256, user_deposited: u256, total_deposited: u256): u256 {
        return (total_accumulated_rewards - user_accumulated_rewards_index) * user_deposited / total_deposited
    }

}
