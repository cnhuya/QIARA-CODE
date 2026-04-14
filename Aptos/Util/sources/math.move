module dev::QiaraMathV2 {

    #[view]
    public fun pow10_u256(n: u8): u256 {
        let p = 1;
        let i = 0;
        while (i < n) {
            p = p * 10;
            i = i + 1;
        };
        p
    }

    #[view]
    public fun exp(x: u256, decimals: u8): u256 {
        let scale = pow10_u256(decimals);
        let  result = scale; // term 0 = 1.0
        let  term = scale;   // running term
        let  i = 1;

        while (i < 40) { // increase terms for better accuracy
            term = (term * x) / (scale * i);
            result = result + term;
            i = i + 1;
        };

        result
    }

// supra move tool view --function-id 0xad4689eb401dbd7cff34d47ce1f2c236375ae7481cdaca884a0c2cdb35b339b0::QiaraMathV9::compute_profit_fee --args u256:100 u256:7500 u8:3
#[view]
public fun compute_profit_fee(leverage: u256, base_scale: u256, decimals: u8): (u256, u256, u256) {
    let scale = pow10_u256(decimals);

    // ratio = leverage / base_scale
    let ratio = (leverage * scale) / (base_scale*100); // scaled input for exp()

    // exp_result = exp(ratio, decimals)
    let exp_result = exp(ratio, decimals);

    // profit = exp_result - scale  (because exp(0)=scale)
    let profit = exp_result - scale;

    return (ratio, exp_result, profit)
}




// supra move tool view --function-id 0xad4689eb401dbd7cff34d47ce1f2c236375ae7481cdaca884a0c2cdb35b339b0::QiaraMathV6::compute_exp_scale --args u256:1000 u256:220 u256:500 u256:3000 u8:6
// Computes the EXP_SCALE dynamically based on leverage.
// Excel equivalent:
//   = 1 + base_scale - (base_scale ^ (leverage / (10 + (leverage * 2))))
//
// Inputs:
//   - leverage: leverage value scaled by 1e4 (e.g. 1.43 -> 14300)
//   - base_scale: typically 50, scaled by 100 (so 50 -> 5000)
//   - decimals: precision used internally for fixed-point math (e.g. 8)
// Output:
//   exp_scale (u256) scaled by 100 (same scale as base_scale)
#[view]
public fun compute_exp_scale(
    leverage: u256,
    base_rate: u256,
    base_scale: u256,
    utilization: u256,
    decimals: u8
): (u256,u256,u256,u256,u256,u256,u256,u256,u256,u256) {
    let scale = pow10_u256(decimals);
    let scaled_scale = base_scale * scale;
    let exp_scale = scaled_scale - ((scaled_scale * leverage) / 10_000_000);
    let scaled_base_rate = base_rate * scale;

    let y = if (exp_scale > (utilization * scale * 100)) {
        1
    } else {
        ((utilization * scale * scale)/1000) / exp_scale
    };

    return (
        scaled_base_rate + ((scaled_base_rate * (leverage / 100)) / 100),
        ((scaled_base_rate * leverage) / 1000),
        (((utilization * (scale * scale)/1000)) / exp_scale),
        scaled_base_rate + ((scaled_base_rate * (leverage / 100)) / 100)+(((scaled_base_rate * leverage) / 1000)*((exp((((utilization * (scale * scale)/10))) / exp_scale, decimals)*scale)/(exp_scale / 2)))/10000,
        (exp_scale / 2),

        //  fixed exponential input (scaled correctly for your exp function)
        exp((((utilization * (scale * scale)/1000))) / exp_scale, decimals),
        ((exp((((utilization * (scale * scale)/1000))) / exp_scale, decimals)*scale)/(exp_scale / 2)),
        exp_scale,
        y,
        scale
    )
}







/*#[view]
public fun compute_exp_scale(leverage: u256, base_rate: u256, base_scale: u256, utilization: u256, decimals: u8): (u256,u256,u256,u256,u256,u256, u256,u256) {
    let scale = pow10_u256(decimals);
    let scaled_scale = base_scale * scale;
    let exp_scale = scaled_scale-((scaled_scale*(leverage))/10_000_000);
    let scaled_base_rate = base_rate*scale;
//    return(base_rate + (base_rate*(leverage/100)) + (base_rate*leverage)*((exp((utilization/exp_scale),decimals)-1)/(utilization/2)), exp_scale)

    let y =  if ( exp_scale > (utilization*scale*100)) { 1 }  else {(((utilization*scale*100)/exp_scale)-1)};

    return(scaled_base_rate + ((scaled_base_rate*(leverage/100))/100),((scaled_base_rate*leverage)/100),exp(y, decimals),(exp_scale/2), (exp(y, decimals)*(exp_scale/2)), exp_scale, scale, y)
}



*/

//supra move tool view --function-id 0xf286f429deaf08050a5ec8fc8a031b8b36e3d4e9d2486ef374e50ef487dd5bbd::QiaraMathV11::compute_rate --args u256:5000 u256:12500 u256:2000 bool:true u8:3
//OLD?

//supra move tool view --function-id 0xad4689eb401dbd7cff34d47ce1f2c236375ae7481cdaca884a0c2cdb35b339b0::QiaraMathV9::compute_rate --args u256:5000 u256:12500 u256:2000 bool:true u8:3
    /// Excel formula:
    ///   rate + rate * ((exp(utilization/exp_scale) - 1) / (exp_scale/2))
    /// Inputs:
    ///   - rate: % scaled by 100 (e.g. 51.47% = 5147)
    ///   - utilization: % scaled by 100
    ///   - exp_scale: scaled by 100
    ///   - decimals: output precision
    /// 
    /// 
    /// 
#[view]
public fun compute_rate(utilization: u256, base_rate: u256, exp_scale: u256, is_lending: bool,decimals: u8): (u256,u256, u256) {
    let scale = pow10_u256(decimals);

    if(is_lending){
        exp_scale=exp_scale-100;
    };
    
    // ratio = leverage / base_scale
    let ratio = (utilization * scale) / (exp_scale); // scaled input for exp()

    // exp_result = exp(ratio, decimals)
    let exp_result = exp(ratio, decimals);

    // profit = exp_result - scale  (because exp(0)=scale)
    let profit = exp_result - scale;

    return ((base_rate*exp_result)/100, exp_result,ratio)
}
/*
    #[view]
    public fun compute_rate(rate: u256,utilization: u256,exp_scale: u256,is_lending: bool,decimals: u8): u256 {
        let scale = pow10_u256(decimals);
        let exp_decimals: u8 = 8; // fixed internal precision for exp()
        let exp_scale_factor = pow10_u256(exp_decimals);

        // x = utilization / exp_scale, but we must preserve precision for exp()
        // So compute: x_scaled = (utilization * exp_scale_factor) / exp_scale
        let x_scaled = (utilization * exp_scale_factor) / exp_scale;

        // Compute e^x in fixed point with exp_decimals precision
        let exp_x = exp(x_scaled, exp_decimals);

        // (exp(x) - 1) / (exp_scale/2)
        let numerator = exp_x - exp_scale_factor; // subtract 1.0
        let denominator = exp_scale / 2;

        // factor is scaled by exp_decimals
        let factor = (numerator * 100) / denominator;

        // rate + rate * factor/scale
        let rate_increase = (rate * factor) / exp_scale_factor;
        let final_rate = rate + rate_increase;


        let increase = 100;
        if(is_lending == true){
            increase = 125
        };

        // Adjust to requested output decimals
        (((final_rate * scale) * increase) / 100 )/ 100
    }*/
}
