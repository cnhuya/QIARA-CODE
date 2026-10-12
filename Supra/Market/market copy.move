module dev::QiaraVaultsV3 {
    use std::signer;
    use std::string::{Self as String, String, utf8};
    use std::timestamp;
    use std::option::{Option};
    use std::vector;
    use std::type_info::{Self, TypeInfo};
    use std::table;
    use supra_oracle::supra_oracle_storage;
    use supra_framework::coin::{Self, Coin};
    use supra_framework::supra_coin::{Self, SupraCoin};
    use supra_framework::event;

    use dev::QiaraVerifiedTokensV2::{Self as VerifiedTokens, Tier, CoinData, Metadata};
    use dev::QiaraMarginV6::{Self as Margin, Access as MarginAccess};

    use dev::QiaraCoinTypesV3::{Self as CoinTypes, SuiBitcoin, SuiEthereum, SuiSui, SuiUSDC, SuiUSDT, BaseEthereum, BaseUSDC};
    use dev::QiaraChainTypesV3::{Self as ChainTypes};
    use dev::QiaraVaultTypesV3::{Self as VaultTypes, Access as VaultTypesAccess};
    use dev::QiaraFeatureTypesV3::{Market};

    use dev::QiaraMath::{Self as QiaraMath};


    use dev::QiaraStorageV24::{Self as storage, Access as StorageAccess};
    use dev::QiaraCapabilitiesV24::{Self as capabilities, Access as CapabilitiesAccess};


// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_VAULT_NOT_INITIALIZED: u64 = 2;
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


// === CONSTANTS === //
    const SECONDS_IN_YEAR: u64 = 31_536_000; // 365 days

    const MAX_COLLATERAL_RATIO: u64 = 80; // Safe borrowing limit (%)
    const LIQUIDATION_THRESHOLD: u64 = 85; // Liquidation trigger (%)
    const LIQUIDATION_BONUS_BPS: u64 = 500; // 5% bonus to liquidator

// === ACCESS === //
    struct Access has store, key, drop {}
    struct Permission has store, key, drop, copy {}

    public fun give_access(s: &signer): Access {
        assert!(signer::address_of(s) == @dev, ERROR_NOT_ADMIN);
        Access {}
    }

    public fun give_permission(s: &signer, access: &Access): Permission {
        Permission {}
    }

    struct Permissions has key, store, drop {
        margin: MarginAccess,
        vault_types: VaultTypesAccess,
        storage: StorageAccess,
        capabilities: CapabilitiesAccess,
    }

// === STRUCTS === //
    struct TableUnclaimedUserVaultList has key {
        list: table::Table<address, table::Table<String, vector<PendingDeposit>>>,
    }

    struct PendingDeposit has copy, key, store {
        resource: String,
        deposited: u64,
    }


    struct GlobalVault<phantom T> has key {
        tier: u8,
        balance: coin::Coin<T>,
    }

    struct VaultUSD has store, copy, drop {
        tier: u8,
        oracle_price: u128,
        oracle_decimals: u8,
        total_deposited: u128,
        balance: u64,
        borrowed: u128,
        utilization: u64,
        rewards: u256,
        interest: u256,
        fee: u64,
    }


    struct CompleteVault has key{
        vault: VaultUSD,
        coin: CoinData,
        tier: Tier,
        Metadata: Metadata,
    }


    #[event]
    struct BridgeEvent has copy, drop, store {
        validator: address,
        amount: u64,
        to: vector<u8>,
        token: String,
        chain: String,
        time: u64
    }

    #[event]
    struct BridgedDepositEvent has copy, drop, store {
        validator: address,
        amount: u64,
        from: address,
        token: String,
        chain: String,
        time: u64
    }

    #[event]
    struct VaultEvent has copy, drop, store {
        type: String,
        amount: u64,
        address: address,
        token: String,
        time: u64
    }

    #[event]
    struct LiquidationEvent has copy, drop, store {
        borrower: address,
        liquidator: address,
        repaid: u64,
        collateral_seized: u64,
        token: String,
        time: u64
    }

// === FUNCTIONS === //
    fun init_module(address: &signer){
        move_to(address, TableUnclaimedUserVaultList {list: table::new<address, table::Table<String, vector<PendingDeposit>>>(),});
        init_all_vaults(address)
    }

    public entry fun init_all_vaults(address: &signer){
        init_vault<BaseEthereum>(address, 1, 1, utf8(b"Base"));
        init_vault<BaseUSDC>(address, 0, 47,  utf8(b"Base"));

        init_vault<SuiEthereum>(address, 1, 1,  utf8(b"Sui"));
        init_vault<SuiUSDC>(address, 0, 47, utf8(b"Sui"));
        init_vault<SuiUSDT>(address, 0, 47, utf8(b"Sui"));
        init_vault<SuiSui>(address, 2, 90, utf8(b"Sui"));
        init_vault<SuiBitcoin>(address, 1, 0, utf8(b"Sui"));

        init_vault<SupraCoin>(address, 3, 500, utf8(b"Supra"));
    }

    public entry fun init_vault<T>(admin: &signer, tier: u8, oracleID: u32, chain: String){
        assert!(signer::address_of(admin) == @dev, ERROR_NOT_ADMIN);
        if (!exists<GlobalVault<T>>(@dev)) {
            //capabilities::assert_wallet_capability(utf8(b"QiaraVault"), utf8(b"PERMISSION_TO_INITIALIZE_VAULTS"));
            let type = type_info::type_name<T>();
            move_to(admin, GlobalVault {
                tier: tier,
                balance: coin::zero<T>(),
            });
            VerifiedTokens::allow_coin<T>(admin, tier, oracleID, chain);
        }
    }

    public entry fun claim_bridged_deposits<T, X>(user: &signer) acquires TableUnclaimedUserVaultList,Permissions{
        let tbl = borrow_global_mut<TableUnclaimedUserVaultList>(@dev);

        let type_str = type_info::type_name<T>();

        let pending_list = table::borrow_mut(&mut tbl.list, signer::address_of(user));
        let coin_pending_list = table::borrow_mut(pending_list, type_str);
        let pending_deposit_by_vault_provider = find_pending_deposit(coin_pending_list, type_info::type_name<X>());

        let amount = pending_deposit_by_vault_provider.deposited;
        pending_deposit_by_vault_provider.deposited = 0;

        Margin::add_deposit<T, X, Market>(signer::address_of(user), amount, Margin::give_permission(user, &borrow_global<Permissions>(@dev).margin));
    }

    /// Deposit on behalf of `recipient`
    /// No need for recipient to have signed anything.
    /// 
    /// Security:
    /// 1.Tato funkce muze byt zavolana pouze z smart modulu "bridge"
    /// 2.Signer musi minimalne X Qiara Tokenu stakovat
    public fun bridge_deposit<T, E, X:store, A>(user: &signer, access: &Access, permission: Permission, recipient: address,amount: u64,coins: Coin<T>, lend_rate: u64, borrow_rate: u64) acquires GlobalVault, Permissions, TableUnclaimedUserVaultList {
        assert!(exists<GlobalVault<T>>(@dev), ERROR_VAULT_NOT_INITIALIZED);

        let vault = borrow_global_mut<GlobalVault<T>>(@dev);
        coin::merge(&mut vault.balance, coins);
        let type_str = type_info::type_name<T>();

        if(Margin::is_user_registered(recipient)){
            VaultTypes::change_rates<X>(lend_rate, borrow_rate, VaultTypes::give_permission(user, &borrow_global<Permissions>(@dev).vault_types));
            Margin::add_deposit<T, X, Market>(signer::address_of(user), amount, Margin::give_permission(user, &borrow_global<Permissions>(@dev).margin));
        } else {
            let tbl = borrow_global_mut<TableUnclaimedUserVaultList>(@dev);

            if (!table::contains(&tbl.list, recipient)) {
                let inner_table = table::new<String, vector<PendingDeposit>>();
                table::add(&mut tbl.list, recipient, inner_table);
            };

            let pending_list = table::borrow_mut(&mut tbl.list, recipient);
            let coin_pending_list = table::borrow_mut(pending_list, type_str);
            let pending_deposit_by_vault_provider = find_pending_deposit(coin_pending_list, type_info::type_name<X>());

            pending_deposit_by_vault_provider.deposited = pending_deposit_by_vault_provider.deposited + amount;

        };

        event::emit(BridgedDepositEvent {
            validator: signer::address_of(user),
            amount,
            from: recipient,
            token: type_str,
            chain: ChainTypes::convert_chainType_to_string<E>(),
            time: timestamp::now_seconds(),
        });}


    public entry fun swap<T, X: store, Y, A, B>(user: &signer,amount_in: u64) acquires GlobalVault, Permissions {
        assert!(exists<GlobalVault<T>>(@dev), ERROR_VAULT_NOT_INITIALIZED);
        assert!(exists<GlobalVault<Y>>(@dev), ERROR_VAULT_NOT_INITIALIZED);


        // Step 1: withdraw tokens of type T from user
        withdraw<T, X, A, B>(user, amount_in); // handle accounting/fees etc.
        let coins_in = coin::withdraw<T>(user, amount_in);


        // Step 2: deposit them into the vault for token T
        let vault_in = borrow_global_mut<GlobalVault<T>>(@dev);
        coin::merge(&mut vault_in.balance, coins_in);
        // Step 3: calculate output amount in Y (simple price * ratio example)
        let metadata_in = VerifiedTokens::get_coin_metadata_by_res(&type_info::type_name<T>());
        let metadata_out = VerifiedTokens::get_coin_metadata_by_res(&type_info::type_name<Y>());

        let price_in =  VerifiedTokens::get_coin_metadata_price(&metadata_in);   // assumed in USD
        let price_out =  VerifiedTokens::get_coin_metadata_price(&metadata_out); // assumed in USD

        let amount_out = ((amount_in as u128) * price_in) / price_out;

        // Step 4: withdraw from vault_out to send to user
        let vault_out = borrow_global_mut<GlobalVault<Y>>(@dev);
        let coins_out = coin::extract(&mut vault_out.balance, (amount_out as u64));
        coin::deposit<Y>(signer::address_of(user), coins_out);

        // Step 5: update margin/tracking if necessary
        Margin::add_deposit<Y, X, Market>(signer::address_of(user), (amount_out as u64), Margin::give_permission(user, &borrow_global<Permissions>(@dev).margin));

        accrue<T, X, A, B>(user);
    }


    public entry fun deposit<T, X:store, A, B>(user: &signer, amount: u64) acquires GlobalVault, Permissions {
        assert!(exists<GlobalVault<T>>(@dev), ERROR_VAULT_NOT_INITIALIZED);
        let vault = borrow_global_mut<GlobalVault<T>>(@dev);

        let coins = coin::withdraw<T>(user, amount);
        coin::merge(&mut vault.balance, coins);

        Margin::add_deposit<T, X, Market>(signer::address_of(user), amount, Margin::give_permission(user, &borrow_global<Permissions>(@dev).margin));

        accrue<T,X, A, B>(user);

        event::emit(VaultEvent { 
            type: utf8(b"Deposit"),
            amount, 
            address: signer::address_of(user), 
            token: type_info::type_name<T>(),
            time: timestamp::now_seconds(),
        });
    }



    /// log event emmited in this function in backend and add it to registered events in chains.move
    /// this is needed in case validators could overfetch multiple times this event and that way unlock multiple times on other chains
    /// from locked vaults
    public entry fun bridge<T, E, X:store, A, B>(user: &signer, destination_address: vector<u8>, amount: u64) acquires GlobalVault, Permissions {
        assert!(exists<GlobalVault<T>>(@dev), ERROR_VAULT_NOT_INITIALIZED);
       // let vault = borrow_global_mut<GlobalVault<T>>(ADMIN);
 

        //let type_str = type_info::type_name<T>();
        //let user_vault = find_or_insert(&mut user_vault_list.list, type_str);


        withdraw<T, X, A, B>(user, amount);
        CoinTypes::deposit<T>(user, amount);
        
       // assert!(user_vault.deposited >= amount, ERROR_INSUFFICIENT_BALANCE);
       // assert!(coin::value(&vault.balance) >= amount, ERROR_NOT_ENOUGH_LIQUIDITY);

       // let coins = coin::extract(&mut vault.balance, amount);
       // coin::deposit(signer::address_of(user), coins);

       // vault.total_deposited = vault.total_deposited - amount;
       // user_vault.deposited = user_vault.deposited - amount;

       // accrue<T>(user_vault);
        event::emit(BridgeEvent { amount, validator: signer::address_of(user), token: type_info::type_name<T>(), to: destination_address, chain: ChainTypes::convert_chainType_to_string<E>(), time: timestamp::now_seconds() });
    }

    public entry fun withdraw<T, X:store, A, B>(user: &signer, amount: u64) acquires GlobalVault, Permissions {
        assert!(exists<GlobalVault<T>>(@dev), ERROR_VAULT_NOT_INITIALIZED);
        let vault = borrow_global_mut<GlobalVault<T>>(@dev);
        assert!(coin::value(&vault.balance) >= amount, ERROR_NOT_ENOUGH_LIQUIDITY);

        let coins = coin::extract(&mut vault.balance, amount);
        coin::deposit(signer::address_of(user), coins);

        Margin::remove_deposit<T, X, Market>(signer::address_of(user), amount, Margin::give_permission(user, &borrow_global<Permissions>(@dev).margin));

        accrue<T,X, A, B>(user);
        event::emit(VaultEvent { type: utf8(b"Withdraw"), amount, address: signer::address_of(user), token: type_info::type_name<T>(), time: timestamp::now_seconds() });
    }

    public entry fun borrow<T, X:store, A, B>(user: &signer, amount: u64) acquires GlobalVault, Permissions {
        assert!(exists<GlobalVault<T>>(@dev), ERROR_VAULT_NOT_INITIALIZED);

        let vault = borrow_global_mut<GlobalVault<T>>(@dev);

        let valueUSD = getValue(type_info::type_name<T>(), (amount as u256));
        let (depoUSD, borrowUSD, _, _, _, _) = Margin::get_user_total_usd(signer::address_of(user));

        assert!(coin::value(&vault.balance) >= amount, ERROR_NOT_ENOUGH_LIQUIDITY);
        assert!(depoUSD >= (valueUSD+borrowUSD), ERROR_BORROW_COLLATERAL_OVERFLOW);

        let coins = coin::extract(&mut vault.balance, amount);
        coin::deposit(signer::address_of(user), coins);

        Margin::add_deposit<T, X, Market>(signer::address_of(user), amount, Margin::give_permission(user, &borrow_global<Permissions>(@dev).margin));
        accrue<T, X, A, B>(user);
        event::emit(VaultEvent { type: utf8(b"Borrow"), amount, address: signer::address_of(user), token: type_info::type_name<T>(), time: timestamp::now_seconds() });
    }

    public entry fun claim_rewards<T, X:store, A, B>(user: &signer) acquires GlobalVault, Permissions {
        let addr = signer::address_of(user);
        let type_str = type_info::type_name<T>();

        accrue<T, X, A, B>(user);
        let (rate, reward_index, interest_index, last_updated) = VaultTypes::get_vault_raw<X>();
        let (_,user_deposited, user_borrowed, user_rewards, user_interest, _, _) = Margin::get_user_raw_vault<T,X, Market>(signer::address_of(user));


        let reward_amount = user_rewards;
        let interest_amount = user_interest;

        Margin::remove_interest<T>(signer::address_of(user), (interest_amount as u64), Margin::give_permission(user, &borrow_global<Permissions>(@dev).margin));
        Margin::remove_rewards<T>(signer::address_of(user), (reward_amount as u64), Margin::give_permission(user, &borrow_global<Permissions>(@dev).margin));

        let global_vault = borrow_global_mut<GlobalVault<T>>(@dev);

        if(reward_amount > interest_amount){
            let reward = (reward_amount - interest_amount);
            assert!(coin::value(&global_vault.balance) >= (reward as u64), ERROR_NOT_ENOUGH_LIQUIDITY);
            let coins = coin::extract(&mut global_vault.balance, (reward as u64));
            coin::deposit(addr, coins);
            event::emit(VaultEvent { type: utf8(b"Claim Rewards"), amount: (reward as u64), address: signer::address_of(user), token: type_info::type_name<T>(), time: timestamp::now_seconds() });
        } else{
            let interest = (interest_amount - reward_amount);
            // mby pridat like accumulated_interest do vaultu, pro "pricitavani" interstu, ale teoreticky se to
            // uz ted pricita akorat "neviditelne jelikoz uzivatel bude moct withdraw mene tokenu...
            //Margin::remove_balance<T, X, Market>(signer::address_of(user), amount, Margin::give_permission(user, &borrow_global<Permissions>(@dev).margin));
            //deposited.deposited = deposited.deposited - interest;

            event::emit(VaultEvent {  type: utf8(b"Pay Rewards"), amount: (interest as u64), address: signer::address_of(user), token: type_info::type_name<T>(), time: timestamp::now_seconds() }); 
        }

    }
/*
    public entry fun liquidate<T, X: store,>(liquidator: &signer, borrower_addr: address) acquires GlobalVault {

        if(VaultTypes::convert_vaultProvider_to_string<X>() == utf8(b"Unknown")){
            abort(ERROR_CANT_LIQUIDATE_THIS_VAULT)
        };

        let (depoUSD, borrowUSD, _, _, _, _) = Margin::get_user_total_usd(borrower_addr);

        assert!(depoUSD < borrowUSD, ERROR_NOT_ELIGIBLE_FOR_LIQUIDATION);

        let repayUSD = borrowUSD - depoUSD;
        let repayCoin = getValueByCoin(type_info::type_name<T>(), repayUSD);

        assert!(exists<GlobalVault<T>>(@dev), ERROR_VAULT_NOT_INITIALIZED);

        let global_vault = borrow_global_mut<GlobalVault<T>>(@dev);

        // bonus = 5% of repay
        let bonus = (repayCoin * (LIQUIDATION_BONUS_BPS as u256)) / 10000;
        let total_deduction = repayCoin + bonus;

        Margin::remove_balance<T, X>(user, signer::address_of(user), total_deduction, true, Margin::give_permission(borrow_global<Permissions>(@dev).margin));

        // bonus goes to liquidator
        let collateral_bonus = coin::extract(&mut global_vault.balance, (bonus as u64));
        coin::deposit(signer::address_of(liquidator), collateral_bonus);

        event::emit(LiquidationEvent {
            borrower: borrower_addr,
            liquidator: signer::address_of(liquidator),
            repaid: (repayCoin as u64),
            collateral_seized: (bonus as u64),
            token: type_info::type_name<T>(),
            time: timestamp::now_seconds(),
        });
    }
*/
    // gets value by usd
    fun getValue(resource: String, amount: u256): u256{
        let metadata = VerifiedTokens::get_coin_metadata_by_res(&resource);
        let (price, price_decimals, _, _) = supra_oracle_storage::get_price(VerifiedTokens::get_coin_metadata_oracle(&metadata));
       // let denom = pow10_u256(VerifiedTokens::get_coin_metadata_decimals(&metadata) + (price_decimals as u8));
        return ((amount as u256) * (price as u256)) / VerifiedTokens::get_coin_metadata_denom(&metadata)
    }

    // converts usd back to coin value
    fun getValueByCoin(resource: String, amount: u256): u256{
        let metadata = VerifiedTokens::get_coin_metadata_by_res(&resource);
        let (price, price_decimals, _, _) = supra_oracle_storage::get_price(VerifiedTokens::get_coin_metadata_oracle(&metadata));
       // let denom = pow10_u256(VerifiedTokens::get_coin_metadata_decimals(&metadata) + (price_decimals as u8));
        return ((amount as u256) / (price as u256)) / VerifiedTokens::get_coin_metadata_denom(&metadata)
    }

    fun get_utilization_ratio(deposited: u128, borrowed: u128): u64 {
        if (deposited== 0) {
            0
        } else {
            ((borrowed * 100) / deposited as u64)
        }
    }

    #[view]
    fun get_balance_amount<T>(): u64 acquires GlobalVault {
        assert!(exists<GlobalVault<T>>(@dev), ERROR_VAULT_NOT_INITIALIZED);
        let vault = borrow_global<GlobalVault<T>>(@dev);
        coin::value(&vault.balance)
    }

    #[view]
    public fun get_complete_vault<T, X:store>(): CompleteVault acquires GlobalVault {
        let vault = get_vault<T, X>();
        CompleteVault { vault: vault, coin: VerifiedTokens::get_coin_data<T>(), tier: VerifiedTokens::get_tier(vault.tier), Metadata: VerifiedTokens::get_coin_metadata<T>()  }
    }

    #[view]
    public fun get_vault<T, X: store>(): VaultUSD acquires GlobalVault {
        assert!(exists<GlobalVault<T>>(@dev), ERROR_VAULT_NOT_INITIALIZED);
        let vault = borrow_global<GlobalVault<T>>(@dev);
        let balance = coin::value(&vault.balance);
        let metadata = VerifiedTokens::get_coin_metadata_by_res(&type_info::type_name<T>());

        let (total_deposited, total_borrowed, _) = Margin::get_raw_vault<T,X>();
        let utilization = get_utilization_ratio(total_deposited, total_borrowed);

        let (price, price_decimals, _, _) = supra_oracle_storage::get_price(VerifiedTokens::get_coin_metadata_oracle(&metadata));
        let lend_apy = QiaraMath::compute_rate((VaultTypes::get_vault_lend_rate(VaultTypes::get_vault_rate<X>()) as u256), (utilization as u256), ((VerifiedTokens::lend_scale(VerifiedTokens::get_coin_metadata_tier(&metadata))) as u256), 5);
        let borrow_apy = QiaraMath::compute_rate((VaultTypes::get_vault_lend_rate(VaultTypes::get_vault_rate<X>()) as u256), (utilization as u256), ((VerifiedTokens::borrow_scale(VerifiedTokens::get_coin_metadata_tier(&metadata))) as u256), 5);
        VaultUSD {tier: vault.tier, oracle_price: (price as u128), oracle_decimals: (price_decimals as u8), total_deposited: total_deposited,balance: balance, borrowed: total_borrowed, utilization: utilization, rewards: lend_apy, interest: borrow_apy, fee: get_withdraw_fee(utilization)}
    }

    #[view]
    public fun get_withdraw_fee(utilization: u64): u64 {
        let u_bps = utilization * 100; // convert % to basis points
        let u_bps2 = u_bps;
        if(u_bps2 > 10000){
            u_bps2 = 10000;
        };
        let bonus = ((u_bps) * 4_000) / (20000 - u_bps2);
        return (bonus)
    }

    public fun accrue<T, X: store, A, B>(user: &signer) acquires GlobalVault, Permissions {

        let scale: u128 = 1000000000000000000;
        let vault = get_vault<T, X>();

        let (lend_rate, reward_index, interest_index, last_updated) = VaultTypes::get_vault_raw<X>();
        let (_,user_deposited, user_borrowed, user_rewards, user_interest, _, _) = Margin::get_user_raw_vault<T,X, Market>(signer::address_of(user));

        VaultTypes::accrue_global<X>((lend_rate as u256), (VerifiedTokens::borrow_scale(vault.tier) as u256), (vault.utilization as u256), (get_balance_amount<T>() as u256), (((get_balance_amount<T>() as u128) - vault.total_deposited) as u256), VaultTypes::give_permission(user,&borrow_global<Permissions>(@dev).vault_types));
    
        // Apply rewards based on reward index delta
        let delta_reward = reward_index - user_rewards;
        let user_delta_reward_value  = ((((user_deposited as u128) * delta_reward) / scale) as u64);
        Margin::add_rewards<A>(signer::address_of(user), user_delta_reward_value, Margin::give_permission(user, &borrow_global<Permissions>(@dev).margin));
        Margin::update_reward_index<T, X, Market>(signer::address_of(user), reward_index, Margin::give_permission(user, &borrow_global<Permissions>(@dev).margin));

        // Apply interest based on interest index delta
        let delta_interest = interest_index - user_interest;
        let user_delta_interest_value = ((((user_borrowed as u128) * delta_interest) / scale    ) as u64);
        Margin::add_interest<B>(signer::address_of(user), user_delta_interest_value , Margin::give_permission(user, &borrow_global<Permissions>(@dev).margin));
        Margin::update_interest_index<T, X, Market>(signer::address_of(user), interest_index, Margin::give_permission(user, &borrow_global<Permissions>(@dev).margin));

    }

    fun find_pending_deposit(pending_deposits: &mut vector<PendingDeposit>, res: String): &mut PendingDeposit  {
        let len = vector::length(pending_deposits);
        while(len>0){
            let pending_deposit = vector::borrow_mut(pending_deposits, len-1);
            if(pending_deposit.resource == res){
                return pending_deposit
            };
            len=len-1;            
        };
        abort ERROR_NO_PENDING_DEPOSITS_FOR_THIS_VAULT_PROVIDER
    }
}
