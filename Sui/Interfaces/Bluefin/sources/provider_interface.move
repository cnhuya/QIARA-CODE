module 0x0::QiaraBluefinInterfaceV1 {
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::object::{Self, UID, ID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::dynamic_field as df;
    use std::string::{Self, String};
    use std::type_name::{Self, TypeName};
    use sui::table::{Self, Table};
    use sui::event;
    use sui::bcs;
    use sui::clock::{Self, Clock}; 
    use sui::hash; // Added hash import [2]
    
    use Qiara::QiaraDelegatorV1::{Self as delegator, AdminCap, Vault, SupportedTokenKey, Nullifiers, ProviderManager};
    use Qiara::QiaraEventsV1::{Self as Event};
    use Qiara::QiaraValidatorsV1::{Self as validators, ValidatorState};

    // --- Errors ---
    const ENotSupported: u64 = 0;
    const EInsufficientPermission: u64 = 1;
    const ENotAuthorized: u64 = 2;
    const EAssetNotMatchedByRegistry: u64 = 3;
    const EDelegatorAlreadySet: u64 = 4;
    const EDelegatorNotSet: u64 = 5;
    const EInsufficientBalance: u64 = 6;
    const EVaultAlreadyExists: u64 = 7;
    const EWrongProviderProvided: u64 = 8;

    const PROVIDER_NAME: vector<u8> = b"Bluefin";

    // --- Range Constants [1] ---
    const MIN_RATE: u64 = 2_750_000;
    const MAX_RATE: u64 = 11_275_000;

    /// This key is native to THIS module.
    /// Only this module can add/borrow/remove DFs using this key type.
    public struct AllowanceKey has copy, drop, store { 
        user: address, 
        token_type: TypeName 
    }

    // --- Initialization ---

    fun init(_ctx: &mut TxContext) {
    }

    // --- User Functions ---
    public entry fun deposit<T>(
        vault: &mut Vault, 
        mut coin: Coin<T>, 
        addr: String, 
        shared: String, 
        amount: u64, 
        clock: &sui::clock::Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        
        // 1. Safety Check: Ensure the coin has enough balance
        assert!(coin::value(&coin) >= amount, EInsufficientBalance);

        // 2. Handle the amount splitting
        let deposit_coin = if (coin::value(&coin) == amount) {
            coin
        } else {
            let split_off = coin::split(&mut coin, amount, ctx);
            transfer::public_transfer(coin, sender); // Send leftover back to user
            split_off
        };

        // 3. Hand over the balance to the Delegator
        delegator::increase_reserve<T>(vault, deposit_coin);

        // 4. Generate the pseudo-random rate [1, 2]
        let rate = get_pseudo_random_range(clock, ctx);

        // 5. Emit the event including the rate [1, 2]
        let mut data = vector[
            Event::create_data_struct(std::string::utf8(b"sender"), std::string::utf8(b"address"), bcs::to_bytes(&sender)),
            Event::create_data_struct(std::string::utf8(b"addr"), std::string::utf8(b"string"), bcs::to_bytes(&addr)),
            Event::create_data_struct(std::string::utf8(b"shared"), std::string::utf8(b"string"), bcs::to_bytes(&shared)),
            Event::create_data_struct(std::string::utf8(b"token"), std::string::utf8(b"string"), bcs::to_bytes(&string::from_ascii(type_name::into_string(type_name::get<T>())))),
            Event::create_data_struct(std::string::utf8(b"provider"), std::string::utf8(b"string"), bcs::to_bytes(&std::string::utf8(PROVIDER_NAME))),
            Event::create_data_struct(std::string::utf8(b"amount"), std::string::utf8(b"u64"), bcs::to_bytes(&amount)),
            Event::create_data_struct(std::string::utf8(b"rate"), std::string::utf8(b"u64"), bcs::to_bytes(&rate)),
        ];

        Event::emit_event(clock, std::string::utf8(b"Deposit"), data);
    }

    public entry fun m_withdraw<T>(vault: &Vault, user: address, shared: String, asset_name: String, amount: u64, clock: &sui::clock::Clock) {
        assert!(delegator::is_token_supported<T>(vault), ENotSupported);
       
        let data = vector[
            Event::create_data_struct(string::utf8(b"user"), string::utf8(b"address"), bcs::to_bytes(&user)),
            Event::create_data_struct(string::utf8(b"shared"), string::utf8(b"string"), bcs::to_bytes(&shared)),
            Event::create_data_struct(string::utf8(b"amount"), string::utf8(b"u64"), bcs::to_bytes(&amount)),
            Event::create_data_struct(string::utf8(b"chain"), string::utf8(b"string"), bcs::to_bytes(&string::utf8(b"sui"))),
            Event::create_data_struct(string::utf8(b"provider"), string::utf8(b"string"), bcs::to_bytes(&delegator::provider_name(vault))),
            Event::create_data_struct(string::utf8(b"token"), string::utf8(b"string"), bcs::to_bytes(&asset_name)),
        ];

        Event::emit_event(clock,string::utf8(b"Modular Withdraw"), data);
    }

    public entry fun direct_withdraw<T>(vault: &mut Vault, state: &ValidatorState, manager: &ProviderManager, nullifiers: &mut Nullifiers, public_inputs: vector<u8>,proof_points: vector<u8>, signatures: vector<vector<u8>>,clock: &sui::clock::Clock,ctx: &mut TxContext) {
        let (user_address, amount, _nullifier, proof_provider_name) = delegator::grant_permission<T>(
            manager, 
            state, 
            nullifiers, 
            public_inputs, 
            proof_points, 
            signatures
        );

        assert!(delegator::provider_name(vault) == proof_provider_name, EWrongProviderProvided);
        assert!(delegator::is_token_supported<T>(vault), ENotSupported);

        let withdrawn_balance = delegator::decrease_reserve<T>(vault, amount);
        
        transfer::public_transfer(
            coin::from_balance(withdrawn_balance, ctx), 
            user_address
        );

        let data = vector[
            Event::create_data_struct(std::string::utf8(b"addr"), std::string::utf8(b"address"), bcs::to_bytes(&user_address)),
            Event::create_data_struct(std::string::utf8(b"token"), std::string::utf8(b"string"), bcs::to_bytes(&string::from_ascii(type_name::into_string(type_name::get<T>())))),
            Event::create_data_struct(std::string::utf8(b"provider"), std::string::utf8(b"string"), bcs::to_bytes(&proof_provider_name)),
            Event::create_data_struct(std::string::utf8(b"amount"), std::string::utf8(b"u64"), bcs::to_bytes(&amount)),
        ];
        Event::emit_event(clock,std::string::utf8(b"DirectWithdraw"), data);
    }

    // --- Internal Helpers ---

    /// Generates a pseudo-random range from clock and transaction digest details [1, 2]
    fun get_pseudo_random_range(clock: &Clock, ctx: &TxContext): u64 {
        let mut msg_bytes = vector::empty<u8>();

        // 1. Pack current clock timestamp in milliseconds [2]
        let timestamp = clock::timestamp_ms(clock);
        vector::append(&mut msg_bytes, bcs::to_bytes(&timestamp));

        // 2. Pack unique transaction digest bytes [2]
        let digest = tx_context::digest(ctx);
        vector::append(&mut msg_bytes, *digest);

        // 3. Pack message sender address [2]
        let sender = tx_context::sender(ctx);
        vector::append(&mut msg_bytes, bcs::to_bytes(&sender));

        // 4. Generate Keccak256 hash [2]
        let hash_bytes = hash::keccak256(&msg_bytes);

        // 5. Convert first 8 bytes of the hash into a u64 value [2]
        let mut val_u64: u64 = 0;
        let mut i = 0;
        while (i < 8) {
            let byte = *vector::borrow(&hash_bytes, i);
            val_u64 = (val_u64 << 8) | (byte as u64);
            i = i + 1;
        };

        // 6. Map the value into the range [MIN_RATE, MAX_RATE] [1]
        let range_span = MAX_RATE - MIN_RATE + 1;
        MIN_RATE + (val_u64 % range_span)
    }

    fun internal_grant<T>(vault: &mut Vault, user: address, amount: u64) {
        let _token_type = type_name::get<T>();
        let _vault_uid = delegator::borrow_id(vault);
        assert!(delegator::is_token_supported<T>(vault), ENotSupported);
        
        update_allowance<T>(vault, user, amount);
    }

    fun update_allowance<T>(vault: &mut Vault, user: address, amount: u64) {
        let token_type = type_name::get<T>();
        let key = AllowanceKey { user, token_type };
        
        let vault_uid_mut = delegator::borrow_id_mut(vault);

        if (df::exists_(vault_uid_mut, key)) {
            let current = df::borrow_mut<AllowanceKey, u64>(vault_uid_mut, key);
            *current = *current + amount;
        } else {
            df::add(vault_uid_mut, key, amount);
        };
    }
}