module dev::QiaraTokensFaucetV29 {
    use std::string::{Self as string, String, utf8};
    use std::type_info::{Self, TypeInfo};
    use std::signer;
    use std::table::{Self as table, Table};
    use std::timestamp;

    use dev::QiaraChainTypesV29::{Self as ChainTypes};
    use dev::QiaraTokenTypesV29::{Self as TokensType};

    use dev::QiaraStorageV11::{Self as storage};

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
    public entry fun faucet(addr: &signer, shared: String, user: vector<u8>) acquires FaucetTracker {
        assert!(signer::address_of(addr) == user, ERROR_SENDER_ADDR_DOESNT_MATCH_SIGNER);
        Shared::assert_is_sub_owner(shared, bcs::to_bytes(&signer::address_of(signer)));
        let today  = timestamp::now_seconds() / 86400;

        let x = borrow_global_mut<FaucetTracker>(@dev);

        if (!table::contains(&x.claimed, today)) {
            table::add(&mut x.claimed, today, vector::new<String>());
        };

        let vect = table::borrow_mut(&mut x.claimed, today);
        if (!vector::contains(vect, shared)) {
            vector::push_back(vect, shared);

            internal_faucet(signer::address_of(addr), shared, utf8(b"Qiara"), utf8(b"Sui"));

        } else {
            abort ERROR_ALREADY_CLAIMED_THIS_PERIOD;
        }

    }


    fun internal_faucet(address, shared: String, token: String, chain: String) acquires Permissions{
        ensure_safety(token, chain);
        let amount = TokensMetadata::getValueByCoin(token, return_claim_usd_value());
        TokensCore::mint_to(address, shared, token, chain, amount, TokensCore::give_permission(&borrow_global<Permissions>(@dev).token_core));
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
            return false;
        } else {
            let vect = (table::borrow_mut(&mut x.claimed, today);
            if (vector::contains(vect, shared)) {
                return true;
            } else {
                return false;
            };
        };
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
