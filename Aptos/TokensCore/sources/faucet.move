module dev::QiaraTokensFaucetV49 {
    use std::string::{Self as string, String, utf8};
    use std::type_info::{Self, TypeInfo};
    use std::signer;
    use std::table::{Self as table, Table};
    use std::timestamp;
    use std::bcs;
    use std::vector;
    use dev::QiaraChainTypesV49::{Self as ChainTypes};
    use dev::QiaraTokenTypesV49::{Self as TokensType};
    use aptos_std::simple_map::{Self as simple_map, SimpleMap as Map};
    use dev::QiaraProviderTypesV49::{Self as ProviderTypes};

    use dev::QiaraTokensCoreV49::{Self as TokensCore, Access as TokensCoreAccess};
    use dev::QiaraTokensMetadataV49::{Self as TokensMetadata};
    use dev::QiaraSharedV17::{Self as Shared};
    use dev::QiaraStorageV20::{Self as storage};

// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_SENDER_ADDR_DOESNT_MATCH_SIGNER: u64 = 2;
    const ERROR_ALREADY_CLAIMED_THIS_PERIOD: u64 = 3;
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
// === STRUCTS === //
    struct FaucetTracker has key {
        claimed: Table<u64, vector<String>>
    }

    struct Permissions has key {
        token_core: TokensCoreAccess,
    }



// === INIT === //
    fun init_module(address: &signer){
        if (!exists<FaucetTracker>(signer::address_of(address))) {
            move_to(address, FaucetTracker {claimed: table::new<u64, vector<String>>()});
        };

        if (!exists<Permissions>(@dev)) {
            move_to(address, Permissions { token_core: TokensCore::give_access(address)});
        };
    }


// === HELPER FUNCTIONS === //

    public entry fun faucet(signer: &signer, shared: String, chain: String, user: vector<u8>) acquires FaucetTracker, Permissions {
        assert!(bcs::to_bytes(&signer::address_of(signer)) == user, ERROR_SENDER_ADDR_DOESNT_MATCH_SIGNER);
        Shared::assert_is_sub_owner(shared, bcs::to_bytes(&signer::address_of(signer)));
        let today  = timestamp::now_seconds() / 86400;

        let x = borrow_global_mut<FaucetTracker>(@dev);

        if (!table::contains(&x.claimed, today)) {
            table::add(&mut x.claimed, today, vector::empty<String>());
        };

        // Combine shared and chain to allow claiming once per day per chain
        let claim_id = copy shared;
        string::append(&mut claim_id, copy chain);

        let vect = table::borrow_mut(&mut x.claimed, today);
        if (!vector::contains(vect, &claim_id)) {
            vector::push_back(vect, claim_id);

            // Fetch the nested providers map dynamically
            let providers_map = ProviderTypes::return_all_providers();
            let provider_keys = simple_map::keys(&providers_map);
            let i = 0;
            let num_providers = vector::length(&provider_keys);

            while (i < num_providers) {
                let provider_key = vector::borrow(&provider_keys, i);
                let chains_map = simple_map::borrow(&providers_map, provider_key);
                
                // Only process the specific chain requested if the provider has it
                if (simple_map::contains_key(chains_map, &chain)) {
                    // Use your working Option B getter function
                    let tokens = ProviderTypes::get_tokens(*provider_key, copy chain);

                    let k = 0;
                    let num_tokens = vector::length(&tokens);
                    while (k < num_tokens) {
                        let token_name = vector::borrow(&tokens, k);
                        
                        // Ignore checklist for "Burned Qiara", "BQiara", "Deepbook", "QDEEP"
                        if (*token_name != utf8(b"Burned Qiara") && 
                            *token_name != utf8(b"BQiara") && 
                            *token_name != utf8(b"BQIARA") && 
                            *token_name != utf8(b"Deepbook") && 
                            *token_name != utf8(b"QDEEP")) {
                            
                            // Dynamically trigger the internal faucet for the specific chain
                            internal_faucet(copy shared, *token_name, copy chain);
                        };
                        k = k + 1;
                    };
                };
                i = i + 1;
            };

        } else {
            abort ERROR_ALREADY_CLAIMED_THIS_PERIOD;
        }
    }

    fun internal_faucet(shared: String, token: String, chain: String) acquires Permissions{
        ensure_safety(token, chain);
        let store = Shared::return_fungible_store(shared, TokensCore::get_metadata(token));
        let amount = TokensMetadata::getValueByCoin(token, (return_claim_usd_value() as u256));
        let fa = TokensCore::mint(token, chain, (amount as u64), TokensCore::give_permission(&borrow_global<Permissions>(@dev).token_core));
        TokensCore::deposit(shared, store, fa, chain);
    }

    fun ensure_safety(token: String, chain: String){
        ChainTypes::ensure_valid_chain_name(chain);
        TokensType::ensure_token_supported_for_chain(TokensType::convert_token_nickName_to_name(token), chain)
    }

// === GETS === //

    #[view]
    public fun user_today_claim(shared: String): bool acquires FaucetTracker{

        let today  = timestamp::now_seconds() / 86400;

        let x = borrow_global_mut<FaucetTracker>(@dev);
        if (!table::contains(&x.claimed, today)) {
            return false
        } else {
            let vect = table::borrow_mut(&mut x.claimed, today);
            if (vector::contains(vect, &shared)) {
                return true
            } else {
                return false
            }
        }
    }


    #[view]
    public fun return_claim_period(): u64 {
        storage::expect_u64(storage::viewConstant(utf8(b"QiaraFaucet"), utf8(b"TIME_PERIOD")))
    }

    #[view]
    public fun return_claim_usd_value(): u64 {
        storage::expect_u64(storage::viewConstant(utf8(b"QiaraFaucet"), utf8(b"USD_VALUE")))
    }

}
