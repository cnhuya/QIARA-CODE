module dev::QiaraTokensBurnedQiaraV7 {
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
    use aptos_std::smart_table::{Self, SmartTable};

    use dev::QiaraSharedV1::{Self as Shared};
    use dev::QiaraTokensCoreV7::{Self as TokensCore, Access as TokensCoreAccess};
    use dev::QiaraStorageV3::{Self as storage};

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
    // Stores the secure custom fee store and tracks balance updates per shared name
    struct BurnedQiara has key {
        balances: Object<FungibleStore>,
        tracked_amounts: SmartTable<String, u64>
    }

    struct Permissions has key {
        token_core: TokensCoreAccess,
    }

// === INIT === //

    fun init_module(admin: &signer){
        let deploy_addr = signer::address_of(admin);

        if (!exists<Permissions>(@dev)) {
            move_to(admin, Permissions { token_core: TokensCore::give_access(admin)});
        };
    }

    public entry fun init_burned_qiara(admin: &signer){
        let deploy_addr = signer::address_of(admin);


        // Initialize BurnedQiara storage & SmartTable tracking
        if (!exists<BurnedQiara>(@dev)) {
            // 1. Create a non-deletable (sticky) object to host the custom store.
            let constructor_ref = &object::create_sticky_object(signer::address_of(admin));
            let metadata =  TokensCore::get_metadata(utf8(b"Qiara"));
            // 2. Create the custom FungibleStore for your token.
            // By passing the specific token's metadata, the Aptos Fungible Asset framework 
            // strictly guarantees that this store can ONLY ever accept and hold this specific token type.
            let store = fungible_asset::create_store(constructor_ref, metadata);
            
            move_to(admin, BurnedQiara {
                balances: store,
                tracked_amounts: smart_table::new<String, u64>()
            });
        };
    }


// === ENTRY FUNCTIONS === //

    /// Deposits tokens from the user's primary store into our custom store and 
    /// tracks the accumulated amount sent by a specific 'shared_name' (string).
    public entry fun deposit_and_burn_qiara(sender: &signer, shared: String, amount: u64) acquires BurnedQiara, Permissions  {
        Shared::assert_is_sub_owner(shared, bcs::to_bytes(&signer::address_of(sender)));
        let burn_qiara = borrow_global_mut<BurnedQiara>(@dev);
        let to_store = burn_qiara.balances;
        
        // Get the metadata of your token from our custom store
        let metadata = fungible_asset::store_metadata(to_store);
        let sender_addr = signer::address_of(sender);
        
        // Find the sender's primary fungible store
        let from_store = primary_fungible_store::primary_store(sender_addr, metadata);
        
        // Transfer the tokens from sender's primary store to our custom BurnedQiara store.
        // (Using dispatchable_fungible_asset ensures any potential transfer hooks/dispatch logic runs safely)
        dispatchable_fungible_asset::transfer(sender, from_store, to_store, amount);
        
        // Record the transferred amount in our tracking table per shared name
        if (smart_table::contains(&burn_qiara.tracked_amounts, shared)) {
            let current_amount = smart_table::borrow_mut(&mut burn_qiara.tracked_amounts, shared);
            *current_amount = *current_amount + amount;
        } else {
            smart_table::add(&mut burn_qiara.tracked_amounts, shared, amount);
        };
        let fa = TokensCore::mint(utf8(b"Qiara"), utf8(b"Aptos"), amount, TokensCore::give_permission(&borrow_global<Permissions>(@dev).token_core));
        TokensCore::deposit(shared, to_store, fa, utf8(b"Aptos"));
    }


// === HELPER FUNCTIONS === //
    /// View function to query the total tracked deposited amount for a specific shared name.
    #[view]
    public fun get_tracked_burned_amount(shared_name: String): u64 acquires BurnedQiara {
        let burn_qiara = borrow_global<BurnedQiara>(@dev);
        if (smart_table::contains(&burn_qiara.tracked_amounts, shared_name)) {
            *smart_table::borrow(&burn_qiara.tracked_amounts, shared_name)
        } else {
            0
        }
    }

    /// View function to query the metadata of the token that this store tracks.
    #[view]
    public fun get_tracked_token_metadata(): Object<Metadata> acquires BurnedQiara {
        let burn_qiara = borrow_global<BurnedQiara>(@dev);
        fungible_asset::store_metadata(burn_qiara.balances)
    }
}