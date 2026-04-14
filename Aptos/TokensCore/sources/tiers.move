module dev::QiaraTokensTiersV3{
    use std::signer;
    use std::string::{Self as String, String, utf8};
    use std::vector;
    use std::type_info::{Self, TypeInfo};
    use dev::QiaraStorageV1::{Self as storage};


// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_TIER_NOT_FOUND: u64 = 2;

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

/// === STRUCTS ===
    
    struct Tier has store, key, drop {
        tierID: u8,
        tierName: String,
        efficiency: u16,
        multiplier: u16,
    }


/// === INIT ===
    fun init_module(admin: &signer){

    }

/// === HELPER FUNCTIONS ===
  
    fun build_tiers(): vector<Tier>{
        
        let tier0 = Tier {
            tierID: 255,
            tierName: convert_tier_to_string(255),
            efficiency: storage::expect_u16(storage::viewConstant(utf8(b"QiaraTiers"), utf8(b"T0_EFF"))),
            multiplier: storage::expect_u16(storage::viewConstant(utf8(b"QiaraTiers"), utf8(b"T0_X"))),
        };

        let tier00 = Tier {
            tierID: 254,
            tierName: convert_tier_to_string(254),
            efficiency: storage::expect_u16(storage::viewConstant(utf8(b"QiaraTiers"), utf8(b"T00_EFF"))),
            multiplier: storage::expect_u16(storage::viewConstant(utf8(b"QiaraTiers"), utf8(b"T00_X"))),
        };

        let tier1 = Tier {
            tierID: 1,
            tierName: convert_tier_to_string(1),
            efficiency: storage::expect_u16(storage::viewConstant(utf8(b"QiaraTiers"), utf8(b"T1_EFF"))),
            multiplier: storage::expect_u16(storage::viewConstant(utf8(b"QiaraTiers"), utf8(b"T1_X"))),
        };

        let tier2 = Tier {
            tierID: 2,
            tierName: convert_tier_to_string(2),
            efficiency: storage::expect_u16(storage::viewConstant(utf8(b"QiaraTiers"), utf8(b"T2_EFF"))),
            multiplier: storage::expect_u16(storage::viewConstant(utf8(b"QiaraTiers"), utf8(b"T2_X"))),
        };

        let tier3 = Tier {
            tierID: 3,
            tierName: convert_tier_to_string(3),
            efficiency: storage::expect_u16(storage::viewConstant(utf8(b"QiaraTiers"), utf8(b"T3_EFF"))),
            multiplier: storage::expect_u16(storage::viewConstant(utf8(b"QiaraTiers"), utf8(b"T3_X"))),
        };

        let tier4 = Tier {
            tierID: 4,
            tierName: convert_tier_to_string(4),
            efficiency: storage::expect_u16(storage::viewConstant(utf8(b"QiaraTiers"), utf8(b"T4_EFF"))),
            multiplier: storage::expect_u16(storage::viewConstant(utf8(b"QiaraTiers"), utf8(b"T4_X"))),
        };
        
        let tier5 = Tier {
            tierID: 5,
            tierName: convert_tier_to_string(5),
            efficiency: storage::expect_u16(storage::viewConstant(utf8(b"QiaraTiers"), utf8(b"T5_EFF"))),
            multiplier: storage::expect_u16(storage::viewConstant(utf8(b"QiaraTiers"), utf8(b"T5_X"))),
        };

        let tier6 = Tier {
            tierID: 6,
            tierName: convert_tier_to_string(6),
            efficiency: storage::expect_u16(storage::viewConstant(utf8(b"QiaraTiers"), utf8(b"T6_EFF"))),
            multiplier: storage::expect_u16(storage::viewConstant(utf8(b"QiaraTiers"), utf8(b"T6_X"))),
        };

        let tier7 = Tier {
            tierID: 7,
            tierName: convert_tier_to_string(7),
            efficiency: storage::expect_u16(storage::viewConstant(utf8(b"QiaraTiers"), utf8(b"T7_EFF"))),
            multiplier: storage::expect_u16(storage::viewConstant(utf8(b"QiaraTiers"), utf8(b"T7_X"))),
        };

        return vector[tier0, tier00, tier1, tier2, tier3, tier4, tier5, tier6, tier7]
    }  
  
    fun view_tier(id: u8): Tier{
        let tiers = build_tiers();
        let len = vector::length(&tiers);

        while (len > 0){
            let tier = vector::pop_back(&mut tiers);
            if (tier.tierID == id){
                return tier;
            };
        };

        abort(ERROR_TIER_NOT_FOUND)
    }  

/// === VIEW FUNCTIONS ===
    #[view]
    public fun all_tiers():vector<Tier>{
        build_tiers()
    }

    #[view]
    public fun get_tier(id:u8):Tier{
        view_tier(id)
    }

  // === GET TIER DATA  === //
        #[view]
        public fun tier_efficiency(id: u8): u64{
            let tier = get_tier(id);
            (tier.efficiency as u64)
        }

        #[view]
        public fun tier_multiplier(id: u8): u64{
            let tier = get_tier(id);
            (tier.multiplier as u64)
        }

        #[view]
        public fun lend_ratio(id: u8): u64 {
            let tier = get_tier(id);
            (tier.efficiency as u64)
        }

        #[view]
        public fun minimal_w_fee(id: u8): u64 {
            let tier = get_tier(id);
            ((tier.multiplier as u64) * storage::expect_u64(storage::viewConstant(utf8(b"QiaraMarket"), utf8(b"W_FEE"))))
        }

        #[view]
        public fun w_limit(id: u8): u64 {
            let tier = get_tier(id);
            ((tier.multiplier  as u64)* storage::expect_u64(storage::viewConstant(utf8(b"QiaraMarket"), utf8(b"W_CAP"))))
        }

        #[view]
        public fun rate_scale(id: u8, isLending: bool): u64 {
            let x = 200;
            if(isLending) { x = 0 };
            ((storage::expect_u64(storage::viewConstant(utf8(b"QiaraMarket"), utf8(b"MARKET_PERCENTAGE_SCALE"))) - ((id as u64)*100)) - x)
        }

        #[view]
        public fun deposit_limit(id: u8): u128 {
            let tier = get_tier(id);
            ((tier.efficiency as u64) * storage::expect_u64(storage::viewConstant(utf8(b"QiaraMarket"), utf8(b"DEPOSIT_LIMIT"))) as u128)
        }

        #[view]
        public fun borrow_limit(id: u8): u128 {
            let tier = get_tier(id);
            ((tier.efficiency as u64) * storage::expect_u64(storage::viewConstant(utf8(b"QiaraMarket"), utf8(b"BORROW_LIMIT"))) as u128)
        }


        #[view]
        public fun profit_fee(id: u8): u64 {
            let tier = get_tier(id);
            ((tier.efficiency as u64) * storage::expect_u64(storage::viewConstant(utf8(b"QiaraPerps"), utf8(b"PROFIT_FEE"))))
        }

        #[view]
        public fun leverage_cut(id: u8): u64 {
            let tier = get_tier(id);
            ((tier.efficiency as u64) * storage::expect_u64(storage::viewConstant(utf8(b"QiaraPerps"), utf8(b"LEVERAGE_CUT"))))
        }

        #[view]
        public fun max_position(id: u8): u128{
            let tier = get_tier(id);
            ((tier.efficiency as u64) * storage::expect_u64(storage::viewConstant(utf8(b"QiaraPerps"), utf8(b"MAX_POSITION"))) as u128)
        }

        #[view]
        public fun perps_rate_scale(id: u8): u64 {
            storage::expect_u64(storage::viewConstant(utf8(b"QiaraPerps"), utf8(b"PERPS_PERCENTAGE_SCALE"))) - ((id as u64)*1000)
        }



        #[view]
        public fun perps_max_leverage(id: u8): u64 {
            // formula: (max_leverage * tier_multiplier (descending/flipped, starting from below)) / max_leverage_slashing
            // i.e (1_000_000 * 5_000) / 2_000_000 -> 2_500 (25x) || id = 1

            if(id == 255 || id == 254){
                return 0
            };

            let max_tier_id = 7;
            let effective_multiplier = tier_multiplier(max_tier_id-id+1); // +1 is here so that if id is 7, then it returns multiplier for tier 1 which is intended

            // in the future change the max leverage to 1_000_000 (1) and add MAX_LEVERAGE_SLASHING to 2_000_000 (2)
            storage::expect_u64(storage::viewConstant(utf8(b"QiaraPerps"), utf8(b"MAX_LEVERAGE"))) * effective_multiplier / 25_000_000 / 2 
        }

        #[view]
        public fun oracle_native_weight(id: u8): u256 {
            // formula: (native_oracle_weight * tier_multiplier) / native_oracle_weight_slashing + native_oracle_weight
            // i.e (1_000_000 * 300) / 10_000_000 + 1_000_000 -> 1_300_000 (1,3x) || id = 2

            let tier_multiplier = tier_multiplier(id);
            let native_oracle_weight = storage::expect_u64(storage::viewConstant(utf8(b"QiaraOracle"), utf8(b"NATIVE_ORACLE_WEIGHT")));
            let native_oracle_weight_slashing = storage::expect_u64(storage::viewConstant(utf8(b"QiaraOracle"), utf8(b"NATIVE_ORACLE_WEIGHT_SLASHING")));
            let stable_multiplier = 1;
            if(id == 255 || id == 254){
                stable_multiplier = 100
            };

            return ((native_oracle_weight*10000 * tier_multiplier / native_oracle_weight_slashing + native_oracle_weight)*stable_multiplier as u256)

        }


    //93010000000
        #[view]
        public fun market_daily_withdraw_limit(id: u8): u64 {
            // formula: (withdraw_limit * tier_efficiency)/1000 + withdraw_limit
            // i.e (10_000_000 * 9300)/10000 + 10_000_000 -> 19_300_000 (19,3%) || id = 1
            let tier_efficiency = tier_efficiency(id);
            let withdraw_limit = storage::expect_u64(storage::viewConstant(utf8(b"QiaraMarket"), utf8(b"WITHDRAW_LIMIT")));

            return(withdraw_limit * tier_efficiency)/10000 + withdraw_limit
        }
        #[view]
        public fun market_borrow_interest_multiplier(id: u8): u64 {
            // formula: (borrow_interest_multiplier * tier_multiplier)/borrow_interest_multiplier_slashing + borrow_interest_multiplier
            // i.e (100_000 * 9300)/10_000_000 + 100_000 -> 19_300_000 (19,3%) || id = 1

            let tier_multiplier = tier_multiplier(id);
            let borrow_interest_multiplier = storage::expect_u64(storage::viewConstant(utf8(b"QiaraMarket"), utf8(b"BORROW_INTEREST_MULTIPLIER")));
            let borrow_interest_multiplier_slashing = storage::expect_u64(storage::viewConstant(utf8(b"QiaraMarket"), utf8(b"BORROW_INTEREST_MULTIPLIER_SLASHING")));


            return(10000 * borrow_interest_multiplier * tier_multiplier)/borrow_interest_multiplier_slashing + borrow_interest_multiplier
        }

        #[view]
        public fun market_base_lending_apr(id: u8): u64 {
            // formula: (storage_variables_scale * base_rate * tier_multiplier)/market_base_rate_slashing + base_rate 
            // i.e (1_000_000 * 500_000 * 200)/100/5_000_000 + 500_000 -> 600_000 (0,7%) || id = 1

            let tier_multiplier = tier_multiplier(id);
            let market_base_rate = storage::expect_u64(storage::viewConstant(utf8(b"QiaraMarket"), utf8(b"MIN_LEND_APR_FACTOR")));
            
            //let market_base_rate_slashing = storage::expect_u64(storage::viewConstant(utf8(b"QiaraMarket"), utf8(b"WITHDRAW_LIMIT")));
            let market_base_rate_slashing = 5_000_000;

            return(1_000_000 * market_base_rate * tier_multiplier)/100/market_base_rate_slashing + market_base_rate
        }

        #[view]
        public fun price_impact_penalty(id: u8): u64 {

            let base = 100;

            // 100 * (9000 * 10) + 100_000_000 -> 100 * 90000 + 100_000_000 -> 109_000_000
            return base*(tier_efficiency(id)*10)+(base*10_000)   
        }

        #[view]
        public fun bridge_fee(id: u8): u128{
            let tier = get_tier(id);
            let base_fee = storage::expect_u64(storage::viewConstant(utf8(b"QiaraBridge"), utf8(b"FEE")));
            let multiplier = (tier.multiplier as u64);
            ((base_fee + ((base_fee * multiplier)/100) / 2) as u128) // the /100 is here because of multiplier scailing
        }

        #[view]
        public fun flat_usd_fee(id: u8): u128{
            let tier = get_tier(id);
            let base_fee = storage::expect_u64(storage::viewConstant(utf8(b"QiaraTokens"), utf8(b"FLAT_USD_FEE")));
            let multiplier = (tier.multiplier as u64);
            (((base_fee * multiplier)/100) as u128) // the /100 is here because of multiplier scailing
        }

        #[view]
        public fun transfer_fee(id: u8): u128{
            let tier = get_tier(id);
            let base_fee = storage::expect_u64(storage::viewConstant(utf8(b"QiaraTokens"), utf8(b"TRANSFER_FEE")));
            let multiplier = (tier.multiplier as u64);
            ((base_fee + ((base_fee * multiplier)/100) / 10) as u128) // the /100 is here because of multiplier scailing
        }


// === CONVERT === //
    public fun convert_tier_to_string(tier: u8): String{
        if(tier == 255 ){
            return utf8(b"Stable")
        } else if(tier == 254 ){
            return utf8(b"Alt-Stable")
        } else if(tier == 1 ){
            return utf8(b"Bluechip")
        } else if(tier == 2 ){
            return utf8(b"Adopted")
        } else if(tier == 3 ){
            return utf8(b"Volatile")
        } else if(tier == 4){
            return utf8(b"Experimental")
        } else if(tier == 5){
            return utf8(b"Fragile")
        } else if(tier == 6){
            return utf8(b"Risky")
        } else if(tier == 7){
            return utf8(b"Unknown")
        } else{
            return utf8(b"Null")
        }
    }
}
