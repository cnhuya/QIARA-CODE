use anchor_lang::prelude::*;

#[error_code]
pub enum QiaraError {
    #[msg("Genesis timestamp is in the future.")]
    GenesisInFuture,
    #[msg("Epoch duration must be greater than zero.")]
    DurationIsZero,
    #[msg("Registry variable map has been locked.")]
    RegistryLocked,
    #[msg("Invalid payload encoding format.")]
    InvalidPayloadEncoding,
    #[msg("Trailing data detected in signed payload.")]
    TrailingDataInPayload,
    #[msg("Invalid signature size or format.")]
    InvalidSignatureLength,
    #[msg("Derivation recovered invalid SECP256K1 signature.")]
    InvalidSignature,
    #[msg("Signer is not an active validator.")]
    NotValidator,
    #[msg("Wrong chain ID.")]
    WrongChainId,
    #[msg("Insufficient validator signatures for quorum threshold.")]
    InsufficientSignatures,
    #[msg("Duplicate validator signature detected.")]
    DuplicateSigner,
    #[msg("Dev access has been permanently revoked.")]
    DevAccessRevoked,
    #[msg("Unauthorized developer admin.")]
    UnauthorizedAdmin,
    #[msg("Action hash does not match computed payload.")]
    InvalidActionHash,
}

#[error_code]
pub enum TokenError {
    #[msg("Amount must be greater than zero.")]
    ZeroAmount,
    #[msg("Fee exceeds total transfer amount.")]
    FeeExceedsAmount,
    #[msg("Signer is not authorized to edit whitelist.")]
    UnauthorizedWhitelistAdmin,
    #[msg("Signer is not authorized admin.")]
    UnauthorizedAdmin,
    #[msg("Packed chain ID does not match expected chain ID.")]
    WrongChain,
    #[msg("Nullifier does not match computed payload hash.")]
    InvalidNullifier,
    #[msg("Nullifier has already been consumed.")]
    NullifierAlreadyUsed,
    #[msg("Recipient does not match payload address.")]
    UnauthorizedRecipient,
    #[msg("Missing fee recipient token account.")]
    MissingFeeRecipientAta,
    #[msg("Invalid fee recipient account owner.")]
    InvalidFeeRecipient,
}