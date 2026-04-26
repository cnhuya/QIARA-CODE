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
    
    use Qiara::QiaraDelegatorV1::{Self as delegator, AdminCap, Vault, SupportedTokenKey, Nullifiers, ProviderManager};
    use Qiara::QiaraEventsV1::{Self as Event};


// --- Errors ---
    const ENotSupported: u64 = 0;
    const EInsufficientPermission: u64 = 1;
    const ENotAuthorized: u64 = 2;
    const EAssetNotMatchedByRegistry: u64 = 3;
    const EDelegatorAlreadySet: u64 = 4;
    const EDelegatorNotSet: u64 = 5;
    const EInsufficientBalance: u64 = 6;
    const EVaultAlreadyExists: u64 = 7;


    const PROVIDER_NAME: vector<u8> = b"Bluefin";


    /// This key is native to THIS module.
    /// Only this module can add/borrow/remove DFs using this key type.
    public struct AllowanceKey has copy, drop, store { 
        user: address, 
        token_type: TypeName 
    }

// --- Initialization ---

    fun init(ctx: &mut TxContext) {
    }

// --- Permissionless Asset Listing ---
    // --- Administrative Functions ---
    /// Only the Delegator (holding AdminCap) can grant specific withdrawal rights
    public entry fun grant_withdrawal_permission<T>(vault: &mut Vault, manager: &ProviderManager, nullifiers: &mut Nullifiers, public_inputs: vector<u8>,proof_points: vector<u8>, pubkeys: vector<vector<u8>>, signatures: vector<vector<u8>>) {
        let (user, amount, nullifier) = delegator::grant_permission<T>(manager,nullifiers, public_inputs, proof_points, pubkeys, signatures);
        let vault_uid = delegator::borrow_id(vault); // For read-only (exists_)
        assert!(object::uid_to_inner(vault_uid) == object::id(vault), ENotAuthorized);
        internal_grant<T>(vault, user, amount);

        let data = vector[
            // Items from the event top-level fields
            Event::create_data_struct(std::string::utf8(b"addr"), std::string::utf8(b"address"), bcs::to_bytes(&user)),
            Event::create_data_struct(std::string::utf8(b"token"), std::string::utf8(b"string"), bcs::to_bytes(&string::from_ascii(type_name::into_string(type_name::get<T>())))),
            Event::create_data_struct(std::string::utf8(b"provider"), std::string::utf8(b"string"), bcs::to_bytes(&std::string::utf8(PROVIDER_NAME))),
            Event::create_data_struct(std::string::utf8(b"amount"), std::string::utf8(b"u64"), bcs::to_bytes(&amount)),
        ];

        Event::emit_withdraw_grant_event(std::string::utf8(b"Grant Withdraw Permission"), data);
    }
    // --- User Functions ---
    public entry fun deposit<T>(vault: &mut Vault, mut coin: Coin<T>, addr: String, shared: String, amount: u64, ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);
        
        // 1. Safety Check: Ensure the coin has enough balance
        assert!(coin::value(&coin) >= amount, EInsufficientBalance);

        // 2. Handle the amount splitting
        let deposit_coin = if (coin::value(&coin) == amount) {
            coin
        } else {
            // split(original, amount) returns a new coin with 'amount'
            // 'coin' remains with the leftover balance
            let split_off = coin::split(&mut coin, amount, ctx);
            transfer::public_transfer(coin, sender); // Send the leftover back to user
            split_off
        };

        // 3. Hand over the balance to the Delegator
        // This moves the 'deposit_coin' into the Vault's reserves
        delegator::increase_reserve<T>(vault, deposit_coin);

        // 4. Emit the event using the sender's address
        let data = vector[
            // Items from the event top-level fields
            Event::create_data_struct(std::string::utf8(b"sender"), std::string::utf8(b"address"), bcs::to_bytes(&sender)),
            Event::create_data_struct(std::string::utf8(b"addr"), std::string::utf8(b"string"), bcs::to_bytes(&addr)),
            Event::create_data_struct(std::string::utf8(b"shared"), std::string::utf8(b"string"), bcs::to_bytes(&shared)),
            Event::create_data_struct(std::string::utf8(b"token"), std::string::utf8(b"string"), bcs::to_bytes(&string::from_ascii(type_name::into_string(type_name::get<T>())))),
            Event::create_data_struct(std::string::utf8(b"provider"), std::string::utf8(b"string"), bcs::to_bytes(&std::string::utf8(PROVIDER_NAME))),
            Event::create_data_struct(std::string::utf8(b"amount"), std::string::utf8(b"u64"), bcs::to_bytes(&amount)),
        ];

        Event::emit_deposit_event(std::string::utf8(b"Deposit"), data);
    }

    public entry fun withdraw<T>(vault: &mut Vault, amount: u64, receiver: address, ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);
        let token_type = type_name::get<T>();
        let key = AllowanceKey { user: sender, token_type };

        // 1. Check native allowance (this works because AllowanceKey is defined here)
        let vault_uid = delegator::borrow_id(vault); // For read-only (exists_)
        assert!(df::exists_(vault_uid, key), EInsufficientPermission);
        let vault_uid_mut = delegator::borrow_id_mut(vault);
        let allowance = df::borrow_mut<AllowanceKey, u64>(vault_uid_mut, key);
        assert!(*allowance >= amount, EInsufficientPermission);
        
        // 2. Update allowance
        *allowance = *allowance - amount;

        // 3. Call delegator to get the actual funds
        let withdrawn_balance = delegator::decrease_reserve<T>(vault, amount);
        
        // 4. Send to user
        transfer::public_transfer(coin::from_balance(withdrawn_balance, ctx), receiver);

        let data = vector[
            // Items from the event top-level fields
            Event::create_data_struct(std::string::utf8(b"addr"), std::string::utf8(b"address"), bcs::to_bytes(&sender)),
            Event::create_data_struct(std::string::utf8(b"receiver"), std::string::utf8(b"address"), bcs::to_bytes(&receiver)),
            Event::create_data_struct(std::string::utf8(b"token"), std::string::utf8(b"string"), bcs::to_bytes(&string::from_ascii(type_name::into_string(type_name::get<T>())))),
            Event::create_data_struct(std::string::utf8(b"provider"), std::string::utf8(b"string"), bcs::to_bytes(&std::string::utf8(PROVIDER_NAME))),
            Event::create_data_struct(std::string::utf8(b"amount"), std::string::utf8(b"u64"), bcs::to_bytes(&amount)),
        ];

        Event::emit_withdraw_event(std::string::utf8(b"Withdraw"), data);
    }

// --- Internal Helpers ---
    fun internal_grant<T>(vault: &mut Vault, user: address, amount: u64) {
        let token_type = type_name::get<T>();
        
        // FIX: Use delegator::borrow_id(vault)
        let vault_uid = delegator::borrow_id(vault);
        assert!(delegator::is_token_supported<T>(vault), ENotSupported);
        
        update_allowance<T>(vault, user, amount);
    }

    fun update_allowance<T>(vault: &mut Vault, user: address, amount: u64) {
        let token_type = type_name::get<T>();
        let key = AllowanceKey { user, token_type };
        
        // FIX: Use delegator::borrow_id_mut(vault)
        let vault_uid_mut = delegator::borrow_id_mut(vault);

        if (df::exists_(vault_uid_mut, key)) {
            let current = df::borrow_mut<AllowanceKey, u64>(vault_uid_mut, key);
            *current = *current + amount;
        } else {
            df::add(vault_uid_mut, key, amount);
        };
    }
}