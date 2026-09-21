module dev::Groth16VerifierV73 {
    use std::vector;
    use std::option;
    use aptos_std::crypto_algebra::{Self as ca, Element};
    use aptos_std::bn254_algebra::{G1, G2, Gt, FormatG1Compr, FormatG2Compr, Fr, FormatFrLsb};

    const ERROR_DESERIALIZE: u64 = 100;

    public fun verify(
        vk_bytes: &vector<u8>,
        proof_bytes: &vector<u8>,
        pub_inputs: &vector<vector<u8>>
    ): bool {
        // 1. Unpack Proof (128B -> A: 32B, B: 64B, C: 32B)
        let proof_a = ca::deserialize<G1, FormatG1Compr>(&slice(proof_bytes, 0, 32));
        let proof_b = ca::deserialize<G2, FormatG2Compr>(&slice(proof_bytes, 32, 96));
        let proof_c = ca::deserialize<G1, FormatG1Compr>(&slice(proof_bytes, 96, 128));

        // 2. Unpack VK (392B)
        let vk_alpha = ca::deserialize<G1, FormatG1Compr>(&slice(vk_bytes, 0, 32));
        let vk_beta  = ca::deserialize<G2, FormatG2Compr>(&slice(vk_bytes, 32, 96));
        let vk_gamma = ca::deserialize<G2, FormatG2Compr>(&slice(vk_bytes, 96, 160));
        let vk_delta = ca::deserialize<G2, FormatG2Compr>(&slice(vk_bytes, 160, 224));

        assert!(
            option::is_some(&proof_a) && option::is_some(&proof_b) && option::is_some(&proof_c) &&
            option::is_some(&vk_alpha) && option::is_some(&vk_beta) && 
            option::is_some(&vk_gamma) && option::is_some(&vk_delta), 
            ERROR_DESERIALIZE
        );

        let p_a = option::extract(&mut proof_a);
        let p_b = option::extract(&mut proof_b);
        let p_c = option::extract(&mut proof_c);
        let v_a = option::extract(&mut vk_alpha);
        let v_b = option::extract(&mut vk_beta);
        let v_g = option::extract(&mut vk_gamma);
        let v_d = option::extract(&mut vk_delta);

        // 3. Unpack gamma_abc and build MSM: IC[0] + sum(IC[i+1] * pub_inputs[i])
        let ic_points = vector::empty<Element<G1>>();
        let offset = 232;
        while (offset < 392) {
            let pt = ca::deserialize<G1, FormatG1Compr>(&slice(vk_bytes, offset, offset + 32));
            assert!(option::is_some(&pt), ERROR_DESERIALIZE);
            vector::push_back(&mut ic_points, option::extract(&mut pt));
            offset = offset + 32;
        };

        let scalars = vector[ca::from_u64<Fr>(1)];
        let i = 0;
        let num_inputs = vector::length(pub_inputs);
        while (i < num_inputs) {
            let s = ca::deserialize<Fr, FormatFrLsb>(vector::borrow(pub_inputs, i));
            assert!(option::is_some(&s), ERROR_DESERIALIZE);
            vector::push_back(&mut scalars, option::extract(&mut s));
            i = i + 1;
        };

        let vk_x = ca::multi_scalar_mul(&ic_points, &scalars);

        // 4. Pairings: e(A, B) == e(alpha, beta) * e(vk_x, gamma) * e(C, delta)
        let left = ca::pairing<G1, G2, Gt>(&p_a, &p_b);

        let right = ca::zero<Gt>();
        right = ca::add(&right, &ca::pairing<G1, G2, Gt>(&v_a, &v_b));
        right = ca::add(&right, &ca::pairing<G1, G2, Gt>(&vk_x, &v_g));
        right = ca::add(&right, &ca::pairing<G1, G2, Gt>(&p_c, &v_d));

        ca::eq(&left, &right)
    }

    fun slice(bytes: &vector<u8>, from: u64, to: u64): vector<u8> {
        let out = vector::empty();
        let i = from;
        while (i < to) {
            vector::push_back(&mut out, *vector::borrow(bytes, i));
            i = i + 1;
        };
        out
    }
}