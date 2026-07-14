use anchor_lang::prelude::*;
use anchor_lang::solana_program::clock::Clock;

#[derive(AnchorSerialize, AnchorDeserialize, Clone, Debug)]
pub struct Data {
    pub name: String,
    pub type_name: String,
    pub value: Vec<u8>,
}

#[event]
pub struct VaultEvent {
    pub name: String,
    pub aux: Vec<Data>,
}

pub fn create_data_struct(name: String, type_name: String, value: Vec<u8>) -> Data {
    Data { name, type_name, value }
}

fn create_timestamp_data() -> Result<Data> {
    let clock = Clock::get()?;
    let ts_ms = (clock.unix_timestamp * 1000) as u64;
    
    Ok(Data {
        name: "timestamp".to_string(),
        type_name: "u64".to_string(),
        value: ts_ms.to_le_bytes().to_vec(),
    })
}

pub fn emit_event(name: String, mut data: Vec<Data>) -> Result<()> {
    let timestamp_data = create_timestamp_data()?;
    data.insert(0, timestamp_data);
    
    emit!(VaultEvent { name, aux: data });
    Ok(())
}