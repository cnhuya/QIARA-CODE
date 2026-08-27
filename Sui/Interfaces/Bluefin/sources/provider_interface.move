module 0x0::QiaraVaultInterfaceV1 {
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::tx_context::{Self, TxContext};
    use sui::dynamic_field as df;
    use std::string::{Self, String};
    use std::type_name::{Self, TypeName};
    use sui::bcs;
    use sui::clock::{Self, Clock}; 
    use sui::hash; 
    use sui::transfer;
    
    use Qiara::QiaraDelegatorV1::{Self as delegator, Vault, Nullifiers, ProviderManager};
    use Qiara::QiaraVariablesV1::Registry; // 👈 Imported Registry
    use Qiara::QiaraEventsV1::{Self as Event};
    use Qiara::QiaraValidatorsV1::ValidatorState;

    // --- Errors ---
    const ENotSupported: u64 = 0;
    const EInsufficientBalance: u64 = 6;
    const EWrongProviderProvided: u64 = 8;

    // --- Range Constants ---
    const MIN_RATE: u64 = 2_750_000;
    const MAX_RATE: u64 = 11_275_000;

    public struct UserBalanceKey has copy, drop, store {
        user: address,
        token_type: TypeName
    }
    public struct LastInteractedKey has copy, drop, store {
        user: address,
        token_type: TypeName
    }

    fun init(_ctx: &mut TxContext) {}

    // --- User Functions ---
    public fun deposit<T>(
        vault: &mut Vault, 
        mut coin: Coin<T>, 
        shared: String, 
        amount: u64, 
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(coin::value(&coin) >= amount, EInsufficientBalance);

        let rate = get_pseudo_random_range(clock, ctx);
        let rewards = accrue_user_yield<T>(vault, sender, rate, clock);

        let deposit_coin = if (coin::value(&coin) == amount) {
            coin
        } else {
            let split_off = coin::split(&mut coin, amount, ctx);
            transfer::public_transfer(coin, sender);
            split_off
        };

        delegator::increase_reserve<T>(vault, deposit_coin);

        let token_type = type_name::with_defining_ids<T>();
        let balance_key = UserBalanceKey { user: sender, token_type };
        let time_key = LastInteractedKey { user: sender, token_type };
        let vault_uid_mut = delegator::borrow_id_mut(vault);
        let current_time_seconds = clock::timestamp_ms(clock) / 1000;

        if (df::exists(vault_uid_mut, balance_key)) {
            let current_balance = df::borrow_mut<UserBalanceKey, u64>(vault_uid_mut, balance_key);
            *current_balance = *current_balance + amount + rewards;
        } else {
            df::add(vault_uid_mut, balance_key, amount + rewards);
        };

        if (df::exists(vault_uid_mut, time_key)) {
            let last_time = df::borrow_mut<LastInteractedKey, u64>(vault_uid_mut, time_key);
            *last_time = current_time_seconds;
        } else {
            df::add(vault_uid_mut, time_key, current_time_seconds);
        };

        let data = vector[
            Event::create_data_struct(string::utf8(b"sender"), string::utf8(b"address"), bcs::to_bytes(&sender)),
            Event::create_data_struct(string::utf8(b"shared"), string::utf8(b"string"), bcs::to_bytes(&shared)),
            Event::create_data_struct(string::utf8(b"token"), string::utf8(b"string"), bcs::to_bytes(&string::from_ascii(type_name::into_string(type_name::with_defining_ids<T>())))),
            Event::create_data_struct(string::utf8(b"provider"), string::utf8(b"string"), bcs::to_bytes(&delegator::provider_name(vault))),
            Event::create_data_struct(string::utf8(b"amount"), string::utf8(b"u64"), bcs::to_bytes(&amount)),
            Event::create_data_struct(string::utf8(b"rate"), string::utf8(b"u64"), bcs::to_bytes(&rate)),
            Event::create_data_struct(string::utf8(b"rewards"), string::utf8(b"u64"), bcs::to_bytes(&rewards)),
        ];

        Event::emit_event(clock, string::utf8(b"Deposit"), data);
    }

    public fun m_withdraw<T>(
        vault: &Vault, 
        shared: String, 
        asset_name: String, 
        amount: u64, 
        clock: &Clock,
        ctx: &TxContext
    ) {
        assert!(delegator::is_token_supported<T>(vault), ENotSupported);
        let sender = tx_context::sender(ctx);
       
        let data = vector[
            Event::create_data_struct(string::utf8(b"user"), string::utf8(b"address"), bcs::to_bytes(&sender)),
            Event::create_data_struct(string::utf8(b"shared"), string::utf8(b"string"), bcs::to_bytes(&shared)),
            Event::create_data_struct(string::utf8(b"amount"), string::utf8(b"u64"), bcs::to_bytes(&amount)),
            Event::create_data_struct(string::utf8(b"provider"), string::utf8(b"string"), bcs::to_bytes(&delegator::provider_name(vault))),
            Event::create_data_struct(string::utf8(b"token"), string::utf8(b"string"), bcs::to_bytes(&asset_name)),
        ];

        Event::emit_event(clock, string::utf8(b"Modular Withdraw"), data);
    }

    public fun direct_withdraw<T>(
        vault: &mut Vault, 
        state: &ValidatorState, 
        manager: &ProviderManager, 
        registry: &Registry, // 👈 Added Registry
        nullifiers: &mut Nullifiers, 
        public_inputs: vector<u8>,
        proof_points: vector<u8>, 
        signatures: vector<vector<u8>>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        let (user_address, amount, _nullifier, proof_provider_name) = delegator::grant_permission<T>(
            manager, 
            state, 
            registry, // 👈 Forwarded to delegator
            nullifiers, 
            public_inputs, 
            proof_points, 
            signatures
        );

        assert!(delegator::provider_name(vault) == proof_provider_name, EWrongProviderProvided);
        assert!(delegator::is_token_supported<T>(vault), ENotSupported);

        let rate = get_pseudo_random_range(clock, ctx);
        let rewards = accrue_user_yield<T>(vault, user_address, rate, clock);

        let token_type = type_name::with_defining_ids<T>();
        let balance_key = UserBalanceKey { user: user_address, token_type };
        let time_key = LastInteractedKey { user: user_address, token_type };
        let vault_uid_mut = delegator::borrow_id_mut(vault);
        let current_time_seconds = clock::timestamp_ms(clock) / 1000;

        assert!(df::exists(vault_uid_mut, balance_key), EInsufficientBalance);
        
        let previous_balance = *df::borrow<UserBalanceKey, u64>(vault_uid_mut, balance_key);
        let total_available = previous_balance + rewards;
        assert!(total_available >= amount, EInsufficientBalance);

        let current_balance = df::borrow_mut<UserBalanceKey, u64>(vault_uid_mut, balance_key);
        *current_balance = total_available - amount;

        if (df::exists(vault_uid_mut, time_key)) {
            let last_time = df::borrow_mut<LastInteractedKey, u64>(vault_uid_mut, time_key);
            *last_time = current_time_seconds;
        } else {
            df::add(vault_uid_mut, time_key, current_time_seconds);
        };

        let withdrawn_balance = delegator::decrease_reserve<T>(vault, amount);
        
        transfer::public_transfer(
            coin::from_balance(withdrawn_balance, ctx), 
            user_address
        );

        let data = vector[
            Event::create_data_struct(string::utf8(b"sender"), string::utf8(b"address"), bcs::to_bytes(&sender)),
            Event::create_data_struct(string::utf8(b"user"), string::utf8(b"address"), bcs::to_bytes(&user_address)),
            Event::create_data_struct(string::utf8(b"token"), string::utf8(b"string"), bcs::to_bytes(&string::from_ascii(type_name::into_string(type_name::with_defining_ids<T>())))),
            Event::create_data_struct(string::utf8(b"provider"), string::utf8(b"string"), bcs::to_bytes(&proof_provider_name)),
            Event::create_data_struct(string::utf8(b"amount"), string::utf8(b"u64"), bcs::to_bytes(&amount)),
            Event::create_data_struct(string::utf8(b"rewards"), string::utf8(b"u64"), bcs::to_bytes(&rewards)),
        ];
        Event::emit_event(clock, string::utf8(b"DirectWithdraw"), data);
    }

    public fun stake<T>(
        vault: &mut Vault,
        mut coin: Coin<T>,
        shared: String,
        amount: u64,
        epoch: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(delegator::is_token_supported<T>(vault), ENotSupported);
        assert!(coin::value(&coin) >= amount, EInsufficientBalance);

        let stake_coin = if (coin::value(&coin) == amount) {
            coin
        } else {
            let split_off = coin::split(&mut coin, amount, ctx);
            transfer::public_transfer(coin, sender);
            split_off
        };

        delegator::increase_reserve<T>(vault, stake_coin);

        let data = vector[
            Event::create_data_struct(string::utf8(b"user"), string::utf8(b"address"), bcs::to_bytes(&sender)),
            Event::create_data_struct(string::utf8(b"shared"), string::utf8(b"string"), bcs::to_bytes(&shared)),
            Event::create_data_struct(string::utf8(b"token"), string::utf8(b"string"), bcs::to_bytes(&string::from_ascii(type_name::into_string(type_name::with_defining_ids<T>())))),
            Event::create_data_struct(string::utf8(b"provider"), string::utf8(b"string"), bcs::to_bytes(&delegator::provider_name(vault))),
            Event::create_data_struct(string::utf8(b"amount"), string::utf8(b"u64"), bcs::to_bytes(&amount)),
            Event::create_data_struct(string::utf8(b"epoch"), string::utf8(b"u64"), bcs::to_bytes(&epoch)),
        ];

        Event::emit_event(clock, string::utf8(b"Stake"), data);
    }

    public fun unstake<T>(
        vault: &mut Vault,
        shared: String,
        amount: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(delegator::is_token_supported<T>(vault), ENotSupported);

        let withdrawn_balance = delegator::decrease_reserve<T>(vault, amount);
        transfer::public_transfer(
            coin::from_balance(withdrawn_balance, ctx), 
            sender
        );

        let data = vector[
            Event::create_data_struct(string::utf8(b"user"), string::utf8(b"address"), bcs::to_bytes(&sender)),
            Event::create_data_struct(string::utf8(b"shared"), string::utf8(b"string"), bcs::to_bytes(&shared)),
            Event::create_data_struct(string::utf8(b"token"), string::utf8(b"string"), bcs::to_bytes(&string::from_ascii(type_name::into_string(type_name::with_defining_ids<T>())))),
            Event::create_data_struct(string::utf8(b"provider"), string::utf8(b"string"), bcs::to_bytes(&delegator::provider_name(vault))),
            Event::create_data_struct(string::utf8(b"amount"), string::utf8(b"u64"), bcs::to_bytes(&amount)),
        ];

        Event::emit_event(clock, string::utf8(b"Unstake"), data);
    }

    public fun borrow<T>(
        vault: &mut Vault,
        shared: String,
        amount: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(delegator::is_token_supported<T>(vault), ENotSupported);

        let withdrawn_balance = delegator::decrease_reserve<T>(vault, amount);
        transfer::public_transfer(
            coin::from_balance(withdrawn_balance, ctx), 
            sender
        );

        let data = vector[
            Event::create_data_struct(string::utf8(b"user"), string::utf8(b"address"), bcs::to_bytes(&sender)),
            Event::create_data_struct(string::utf8(b"shared"), string::utf8(b"string"), bcs::to_bytes(&shared)),
            Event::create_data_struct(string::utf8(b"token"), string::utf8(b"string"), bcs::to_bytes(&string::from_ascii(type_name::into_string(type_name::with_defining_ids<T>())))),
            Event::create_data_struct(string::utf8(b"provider"), string::utf8(b"string"), bcs::to_bytes(&delegator::provider_name(vault))),
            Event::create_data_struct(string::utf8(b"amount"), string::utf8(b"u64"), bcs::to_bytes(&amount)),
        ];

        Event::emit_event(clock, string::utf8(b"Borrow"), data);
    }

    fun accrue_user_yield<T>(vault: &mut Vault, user: address, rate: u64, clock: &Clock): u64 {
        let token_type = type_name::with_defining_ids<T>();
        let balance_key = UserBalanceKey { user, token_type };
        let time_key = LastInteractedKey { user, token_type };
        
        let vault_uid_mut = delegator::borrow_id_mut(vault);
        let current_time_seconds = clock::timestamp_ms(clock) / 1000;

        let mut rewards = 0;

        if (df::exists(vault_uid_mut, balance_key) && df::exists(vault_uid_mut, time_key)) {
            let last_time = *df::borrow<LastInteractedKey, u64>(vault_uid_mut, time_key);
            let previous_balance = *df::borrow<UserBalanceKey, u64>(vault_uid_mut, balance_key);

            if (previous_balance > 0 && current_time_seconds > last_time) {
                let elapsed = current_time_seconds - last_time;
                let scale: u128 = 100_000_000;
                let seconds_per_hour: u128 = 3_600;
                rewards = (((previous_balance as u128) * (rate as u128) * (elapsed as u128)) / (scale * seconds_per_hour) as u64);
            };
        };

        rewards
    }

    fun get_pseudo_random_range(clock: &Clock, ctx: &TxContext): u64 {
        let mut msg_bytes = vector[];
        let timestamp = clock::timestamp_ms(clock);
        vector::append(&mut msg_bytes, bcs::to_bytes(&timestamp));
        vector::append(&mut msg_bytes, *tx_context::digest(ctx));
        vector::append(&mut msg_bytes, bcs::to_bytes(&tx_context::sender(ctx)));

        let hash_bytes = hash::keccak256(&msg_bytes);

        let mut val_u64: u64 = 0;
        let mut i = 0;
        while (i < 8) {
            let byte = *vector::borrow(&hash_bytes, i);
            val_u64 = (val_u64 << 8) | (byte as u64);
            i = i + 1;
        };

        let range_span = MAX_RATE - MIN_RATE + 1;
        MIN_RATE + (val_u64 % range_span)
    }
}