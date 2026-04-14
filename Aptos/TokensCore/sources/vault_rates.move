module dev::QiaraTokensRatesV2 {
    use std::string::{Self as string, String, utf8};
    use std::type_info::{Self, TypeInfo};
    use std::signer;
    use std::table::{Self as table, Table};
    use std::timestamp;
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    use dev::QiaraMathV2::{Self as Math};

    use dev::QiaraChainTypesV3::{Self as ChainTypes};
    use dev::QiaraTokenTypesV3::{Self as TokensType};
    use dev::QiaraProviderTypesV3::{Self as ProviderTypes};

// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 1;
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

    // Tracks Lending Rates across chains for each token & its supported chains
    // i.e Ethereum (token) -> Base/Sui/Solana (chains)... -> Rate
    struct RateList has key {
        rates: Table<String, Map<String, Map<String,Rate>>>
    }

    struct Rate has key, store, copy, drop {
        lend_rate: u64,       // per-second or per-block reward APR
        last_update: u64,     // last timestamp or block height
    }

// === INIT === //
    fun init_module(address: &signer){
        if (!exists<RateList>(signer::address_of(address))) {
            move_to(address, RateList {rates: table::new<String,Map<String, Map<String,Rate>>>()});
        };
    }


// === HELPER FUNCTIONS === //
    public entry fun change_rate(addr: &signer) acquires RateList {
        update_rate(utf8(b"Bitcoin"), utf8(b"Sui"), utf8(b"Suilend"), 2100, give_permission(&give_access(addr)));
        update_rate(utf8(b"USDC"), utf8(b"Sui"), utf8(b"Suilend"), 4792, give_permission(&give_access(addr)));
        update_rate(utf8(b"USDT"), utf8(b"Sui"), utf8(b"Suilend"), 3122, give_permission(&give_access(addr)));
        update_rate(utf8(b"Deepbook"), utf8(b"Sui"), utf8(b"Suilend"), 25129, give_permission(&give_access(addr)));
        update_rate(utf8(b"Sui"), utf8(b"Sui"), utf8(b"Suilend"), 5171, give_permission(&give_access(addr)));

        update_rate(utf8(b"Bitcoin"), utf8(b"Sui"), utf8(b"Navi"), 2722, give_permission(&give_access(addr)));
        update_rate(utf8(b"USDC"), utf8(b"Sui"), utf8(b"Navi"), 5090, give_permission(&give_access(addr)));
        update_rate(utf8(b"USDT"), utf8(b"Sui"), utf8(b"Navi"), 3497, give_permission(&give_access(addr)));
        update_rate(utf8(b"Deepbook"), utf8(b"Sui"), utf8(b"Navi"), 27001, give_permission(&give_access(addr)));
        update_rate(utf8(b"Sui"), utf8(b"Sui"), utf8(b"Navi"), 4994, give_permission(&give_access(addr)));

        update_rate(utf8(b"Bitcoin"), utf8(b"Sui"), utf8(b"Alphalend"), 2510, give_permission(&give_access(addr)));
        update_rate(utf8(b"USDC"), utf8(b"Sui"), utf8(b"Alphalend"), 4657, give_permission(&give_access(addr)));
        update_rate(utf8(b"USDT"), utf8(b"Sui"), utf8(b"Alphalend"), 3312, give_permission(&give_access(addr)));
        update_rate(utf8(b"Deepbook"), utf8(b"Sui"), utf8(b"Alphalend"), 26041, give_permission(&give_access(addr)));
        update_rate(utf8(b"Sui"), utf8(b"Sui"), utf8(b"Alphalend"), 5378, give_permission(&give_access(addr)));

        update_rate(utf8(b"USDC"), utf8(b"Base"), utf8(b"Moonwell"), 6018, give_permission(&give_access(addr)));
        update_rate(utf8(b"Virtuals"), utf8(b"Base"), utf8(b"Moonwell"), 3178, give_permission(&give_access(addr)));
        update_rate(utf8(b"Ethereum"), utf8(b"Base"), utf8(b"Moonwell"), 2015, give_permission(&give_access(addr)));

        update_rate(utf8(b"USDC"), utf8(b"Base"), utf8(b"Morpho"), 5737, give_permission(&give_access(addr)));
        update_rate(utf8(b"Virtuals"), utf8(b"Base"), utf8(b"Morpho"), 2149, give_permission(&give_access(addr)));
        update_rate(utf8(b"Ethereum"), utf8(b"Base"), utf8(b"Morpho"), 2388, give_permission(&give_access(addr)));

        update_rate(utf8(b"Supra"), utf8(b"Supra"), utf8(b"Supralend"), 3333, give_permission(&give_access(addr)));
        update_rate(utf8(b"Qiara"), utf8(b"Supra"), utf8(b"Supralend"), 633, give_permission(&give_access(addr)));

        update_rate(utf8(b"Solana"), utf8(b"Solana"), utf8(b"Juplend"), 7130, give_permission(&give_access(addr)));

        update_rate(utf8(b"Solana"), utf8(b"Solana"), utf8(b"Kamino"), 7321, give_permission(&give_access(addr)));

        update_rate(utf8(b"Injective"), utf8(b"Injective"), utf8(b"Kamino"), 12421, give_permission(&give_access(addr)));
    }


    public fun update_rate(token: String, chain: String, provider: String, lend_rate: u64, cap: Permission) acquires RateList {
        let rate = find_rate(borrow_global_mut<RateList>(@dev), token, chain, provider);
        rate.lend_rate = (rate.lend_rate + lend_rate) / 2;
        rate.last_update = timestamp::now_seconds();
    }

    // deprecated
    /*public fun accrue_global(token: String, chain: String, provider: String, lend_rate: u256,exp_scale: u256,utilization: u256,total_deposits: u256,total_borrows: u256,_cap: Permission) acquires RateList {
        let rate = find_rate(borrow_global_mut<RateList>(@dev), token, chain);

        let now = timestamp::now_seconds();
        if (now <= rate.last_update) return;
        let elapsed = now - rate.last_update;
        if (elapsed == 0) return;

        if (total_deposits > 0) {
            let (lend_rate_decimal, _, _) = Math::compute_rate(utilization, lend_rate, exp_scale, true, 5);
            let reward_per_unit = ((((lend_rate_decimal / 1000) * 1_000_000) * (elapsed as u256)) / 31_536_000) / total_deposits;
            assert!((rate.reward_index as u256) + reward_per_unit <= (340282366920938463463374607431768211455u128 as u256), 1001);
            rate.reward_index = (((rate.reward_index as u256) + reward_per_unit) as u128);

            let (borrow_rate_decimal, _, _) = Math::compute_rate(utilization, lend_rate, exp_scale, false, 5);
            if (total_borrows > 0) {
                let interest_per_unit = (((borrow_rate_decimal / 1000) * 1_000_000) * (elapsed as u256) / 31_536_000) / total_borrows;
                assert!((rate.interest_index as u256) + interest_per_unit <= (340282366920938463463374607431768211455u128 as u256), 1002);
                rate.interest_index = (((rate.interest_index as u256) + interest_per_unit) as u128);
            };
        };

        rate.last_update = now;
    }*/

    public fun find_rate(x: &mut RateList, token: String, chain: String, provider: String): &mut Rate {
        ChainTypes::ensure_valid_chain_name(chain);
        ProviderTypes::ensure_valid_provider(provider, chain);
        TokensType::ensure_token_supported_for_chain(TokensType::convert_token_nickName_to_name(token), chain);
        if (!table::contains(&x.rates, token)) {
            table::add(&mut x.rates, token, map::new<String,Map<String, Rate>>());
        };
        
        let map = table::borrow_mut(&mut x.rates, token);
        if (!map::contains_key(map, &chain)) {
            map::upsert(map, chain, map::new<String, Rate>());
        };

        // Get mutable reference to the inner map directly
        let rates = map::borrow_mut(map, &chain); 
        if (!map::contains_key(rates, &provider)) {
            map::add(rates, provider, Rate { 
                lend_rate: 0, 
                last_update: timestamp::now_seconds() 
            });
        };
        
        // Now borrow from the rates map and return it
        map::borrow_mut(rates, &provider)
    }


// === GETS === //

    #[view]
    public fun get_vaults_by_token(token: String): Map<String, Map<String,Rate>> acquires RateList{
        let x = borrow_global_mut<RateList>(@dev);
        if (!table::contains(&x.rates,  token)) {
            table::add(&mut x.rates,  token, map::new<String, Map<String, Rate>>());
        };
        return *table::borrow_mut(&mut x.rates,  token)
    }

    #[view]
    public fun get_vault_rate(token: String, chain: String, provider: String): Rate acquires RateList{
        return *find_rate(borrow_global_mut<RateList>(@dev), token, chain, provider)
    }

    #[view]
    public fun get_vault_raw(token: String, chain: String, provider: String): (u64,u64) acquires RateList{
        let rate = find_rate(borrow_global_mut<RateList>(@dev), token, chain, provider);
        return (rate.lend_rate,rate.last_update)
    }

    public fun get_vault_lend_rate(rate: Rate): u64{
        return rate.lend_rate
    }

    public fun get_vault_last_updated(rate: Rate): u64{
        return rate.last_update
    }
}
