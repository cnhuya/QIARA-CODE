use anchor_lang::prelude::*;

#[derive(AnchorSerialize, AnchorDeserialize, Clone, Debug)]
pub struct UnpackedTx {
    pub chain_id: u64,
    pub amount: u64,
    pub nonce: u64,
    pub storage_id: u64,
}

pub fn extract_chunk(inputs: &[u8], index: usize) -> Result<[u8; 32]> {
    let start = index * 32;
    if inputs.len() < start + 32 {
        return err!(crate::QiaraError::InvalidInputLength);
    }
    let mut chunk = [0u8; 32];
    chunk.copy_from_slice(&inputs[start..start + 32]);
    Ok(chunk)
}

pub fn extract_variable_strings(inputs: &[u8]) -> Result<(String, String, Vec<u8>)> {
    if inputs.len() < 224 {
        return err!(crate::QiaraError::InvalidInputLength);
    }
    let chunk_2 = extract_chunk(inputs, 2)?;
    let mut header_bytes = chunk_2[2..].to_vec();
    header_bytes.retain(|&x| x != 0);
    let variable_header = String::from_utf8(header_bytes).unwrap_or_default();

    let chunk_3 = extract_chunk(inputs, 3)?;
    let chunk_4 = extract_chunk(inputs, 4)?;
    let mut name_bytes = [chunk_3, chunk_4].concat();
    name_bytes.retain(|&x| x != 0);
    let variable_name = String::from_utf8(name_bytes).unwrap_or_default();

    let chunk_5 = extract_chunk(inputs, 5)?;
    let chunk_6 = extract_chunk(inputs, 6)?;
    let mut variable_data = Vec::new();
    variable_data.extend_from_slice(&chunk_6[16..32]);
    variable_data.extend_from_slice(&chunk_5[16..32]);

    Ok((variable_header, variable_name, variable_data))
}

pub fn extract_validator_pubkey(inputs: &[u8]) -> Result<Vec<u8>> {
    if inputs.len() < 224 {
        return err!(crate::QiaraError::InvalidInputLength);
    }
    let x_low = extract_chunk(inputs, 3)?;
    let x_high = extract_chunk(inputs, 4)?;
    let y_low = extract_chunk(inputs, 5)?;
    let y_high = extract_chunk(inputs, 6)?;

    let mut pubkey = vec![0x04];
    pubkey.extend_from_slice(&x_high[16..32]);
    pubkey.extend_from_slice(&x_low[16..32]);
    pubkey.extend_from_slice(&y_high[16..32]);
    pubkey.extend_from_slice(&y_low[16..32]);

    Ok(pubkey)
}

pub fn extract_validator_is_removal(inputs: &[u8]) -> Result<bool> {
    let chunk_2 = extract_chunk(inputs, 2)?;
    Ok((chunk_2[2] & 1) == 1)
}

pub fn extract_all_tx_data(inputs: &[u8]) -> Result<UnpackedTx> {
    if inputs.len() < 192 {
        return err!(crate::QiaraError::InvalidInputLength);
    }
    let chunk_5 = extract_chunk(inputs, 5)?;

    Ok(UnpackedTx {
        amount: u64::from_le_bytes(chunk_5[0..8].try_into().unwrap()),
        chain_id: u32::from_le_bytes(chunk_5[8..12].try_into().unwrap()) as u64,
        nonce: u32::from_le_bytes(chunk_5[12..16].try_into().unwrap()) as u64,
        storage_id: u64::from_le_bytes(chunk_5[16..24].try_into().unwrap()),
    })
}

pub fn extract_user_address(inputs: &[u8]) -> Result<Pubkey> {
    if inputs.len() < 128 {
        return err!(crate::QiaraError::InvalidInputLength);
    }
    let low = extract_chunk(inputs, 2)?;
    let high = extract_chunk(inputs, 3)?;
    
    let mut addr_bytes = [0u8; 32];
    addr_bytes[0..16].copy_from_slice(&high[16..32]);
    addr_bytes[16..32].copy_from_slice(&low[16..32]);
    Ok(Pubkey::new_from_array(addr_bytes))
}

pub fn extract_provider(inputs: &[u8]) -> Result<String> {
    if inputs.len() < 160 {
        return err!(crate::QiaraError::InvalidInputLength);
    }
    let chunk_4 = extract_chunk(inputs, 4)?;
    let mut provider_bytes = chunk_4.to_vec();
    provider_bytes.retain(|&x| x != 0);
    Ok(String::from_utf8(provider_bytes).unwrap_or_default())
}