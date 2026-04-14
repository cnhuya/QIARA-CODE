module dev::QiaraTokensValidatorsV3{
    use std::signer;
    use std::vector;
    use std::string::{Self as string, String, utf8};
    use std::table::{Self, Table};
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    use std::timestamp;
    use std::bcs;

    use dev::QiaraTokensCoreV3::{Self as TokensCore, Access as TokensCoreAccess};
    use dev::QiaraTokensOmnichainV3::{Self as TokensOmnichain};

    use dev::QiaraSharedV1::{Self as Shared};
    // === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 0;
    const ERROR_INVALID_VALIDATOR: u64 = 1;
    const ERROR_TOKEN_NOT_YET_REWARDED: u64 = 2;
    const ERROR_VALIDATORS_AND_WEIGHT_LENGHT_DOESNT_MATCH: u64 = 3;
    const ERROR_TOKEN_NOT_INITIALIZED_FOR_THIS_CHAIN: u64 = 4;
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
    struct Permissions has key {
        tokens_core_access: TokensCoreAccess,
    }

    struct ValidatorRewards has key {
        balances: Table<address, Table<String, Map<String, u128>>>,
        last_reward: Table<address, u128>
    }

    struct RewardIndex has key{
        index: u128
    }

    // ----------------------------------------------------------------
    // Module init
    // ----------------------------------------------------------------
    fun init_module(admin: &signer) {
        if (!exists<Permissions>(@dev)) {
            move_to(admin, Permissions { tokens_core_access: TokensCore::give_access(admin)});
        };
        if (!exists<ValidatorRewards>(@dev)) {
            move_to(admin, ValidatorRewards { balances: table::new<address,Table<String, Map<String, u128>>>(), last_reward: table::new<address,u128>() });
        };
        if (!exists<RewardIndex>(@dev)) {
            move_to(admin, RewardIndex { index: 0 });
        };
    }

    fun accrue_index() acquires RewardIndex{
        let index_ref = borrow_global_mut<RewardIndex>(@dev);
        index_ref.index = index_ref.index +1; 
    }


    fun ensure_validator_index(ref: &mut ValidatorRewards, validator: address) acquires RewardIndex{
        if (!table::contains(&ref.last_reward, validator)) {
            table::add(&mut ref.last_reward, validator, return_current_index());
        };

        table::upsert(&mut ref.last_reward, validator, return_current_index());
    }

    fun ensure_validator_rewards_store(ref: &mut ValidatorRewards, validator: address, token: String, chain: String, amount: u128){
        if (!table::contains(&ref.balances, validator)) {
            table::add(&mut ref.balances, validator, table::new<String, Map<String, u128>>());
        };
            
        let validator_balances = table::borrow_mut(&mut ref.balances, validator);

        // Ensure token entry exists
        if (!table::contains(validator_balances, token)) {
            table::add(validator_balances, token, map::new<String, u128>());
        };
            
        let token_balances = table::borrow_mut(validator_balances, token);
            
        // Ensure chain entry exists and return mutable reference
        if (!map::contains_key(token_balances, &chain)) {
            map::add(token_balances, chain, amount);
            return
        };

        let x = map::borrow_mut(token_balances, &chain);
        map::upsert(token_balances, chain, *x+amount);
    }

    fun sum_total_weight(weights: vector<u64>): u256{
        let len = vector::length(&weights);
        let sum_weight: u256 = 0;
        while(len>0){
            let weight = *vector::borrow(&weights, len-1);
            sum_weight = sum_weight + (weight as u256);
            len=len-1;
        };
        return sum_weight
    }

 
    public entry fun claim_rewards(signer: &signer, shared: String) acquires Permissions, ValidatorRewards{
        Shared::assert_is_sub_owner(shared, bcs::to_bytes(&signer::address_of(signer)));
        
        let registry_map = TokensOmnichain::return_registry();

        let tokens = map::keys(&registry_map);
        let len = vector::length(&tokens);
        while(len>0){
            let token = vector::borrow(&tokens, len-1);
            let reward_map = return_validator_rewards(signer::address_of(signer),*token);
            let (chains, rewards) = map::to_vec_pair(reward_map);
            let len_chains = vector::length(&chains);
            while(len_chains>0){
                let chain = vector::borrow(&chains, len_chains-1);
                let reward = *vector::borrow(&rewards, len_chains-1);
                if(reward > 1_000_000*1_000_000){
                    return;
                };
                // The 100_000_000 is here because rewards are upscaled by 100_000_000, due to the fact that the fees might be extremely low,
                // when user invokes permissioneless function with really small amount of tokens. (i.e 1 -> 0.000001).
                TokensCore::mint_to(signer::address_of(signer),shared, *token, *chain, ((reward/100_000_000)as u64), TokensCore::give_permission(&borrow_global<Permissions>(@dev).tokens_core_access));
                len_chains = len_chains-1;
            };
            len=len-1;
        };
    }

    public fun ensure_and_accrue_validator_rewards(validators: vector<address>, weights: vector<u64>, token: String, chain: String, reward_amount: u256, perm: Permission) acquires ValidatorRewards, RewardIndex {
        let ref = borrow_global_mut<ValidatorRewards>(@dev);
        assert!(vector::length(&validators) == vector::length(&weights), ERROR_VALIDATORS_AND_WEIGHT_LENGHT_DOESNT_MATCH);


        let sum_weight = sum_total_weight(weights);
        let reward_index = reward_amount/sum_weight;

        accrue_index();

        let len = vector::length(&validators);
        while(len>0){
            len=len-1;

            let validator = vector::borrow(&validators, len-1);
            let weight = *vector::borrow(&weights, len-1);
            let validator_legitimate_reward = (reward_index as u128)*(weight as u128);

            ensure_validator_index(ref, *validator);
            ensure_validator_rewards_store(ref, *validator, token, chain, validator_legitimate_reward);
        }
    }

        // --------------------------
        // PUBLIC FUNCTIONS
        // --------------------------
        #[view]
        public fun return_validator_rewards(validator: address, token: String): Map<String, u128> acquires ValidatorRewards {
            let rewards = borrow_global<ValidatorRewards>(@dev);

            // Ensure validator entry exists
            if (!table::contains(&rewards.balances, validator)) {
                abort ERROR_INVALID_VALIDATOR
            };

            let validator_balances = table::borrow(&rewards.balances, validator);
            // Ensure token entry exists
            if (!table::contains(validator_balances, token)) {
                abort ERROR_TOKEN_NOT_YET_REWARDED
            };
            
            *table::borrow(validator_balances, token)
        }

        #[view]
        public fun return_validator_rewards_path(validator: address, token: String, chain: String): u128 acquires ValidatorRewards {
            let rewards = borrow_global<ValidatorRewards>(@dev);

            // Ensure validator entry exists
            if (!table::contains(&rewards.balances, validator)) {
                abort ERROR_INVALID_VALIDATOR
            };

            let validator_balances = table::borrow(&rewards.balances, validator);
            // Ensure token entry exists
            if (!table::contains(validator_balances, token)) {
                abort ERROR_TOKEN_NOT_YET_REWARDED
            };
            
            let table = table::borrow(validator_balances, token);

            if(!map::contains_key(table, &chain)) {
                abort ERROR_TOKEN_NOT_INITIALIZED_FOR_THIS_CHAIN
            };

            return *map::borrow(table, &chain)

        }

        #[view]
        public fun return_validator_last_reward(validator: address): u128 acquires ValidatorRewards {
            let rewards = borrow_global<ValidatorRewards>(@dev);

            // Ensure validator entry exists
            if (!table::contains(&rewards.last_reward, validator)) {
                abort ERROR_INVALID_VALIDATOR
            };

            *table::borrow(&rewards.last_reward, validator)
        }

       #[view]
        public fun return_current_index(): u128 acquires RewardIndex{
            let index = borrow_global_mut<RewardIndex>(@dev);
            index.index
        }

    }