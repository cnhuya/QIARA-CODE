// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

interface IBalanceVerifier {
    function verifyProof(uint[8] calldata proof, uint[6] calldata input) external view;
}


contract QiaraZKDelegator is Ownable {
    IBalanceVerifier public immutable balance_verifier;

    
    // Mapping to prevent replay attacks
    mapping(uint256 => bool) public usedNullifiers;

    constructor(address _balance_verifier) Ownable(msg.sender) {
        balance_verifier = IBalanceVerifier(_balance_verifier);
    }

    function processZkWithdraw(uint[8] calldata proof, uint[6] calldata input) external {
        // 2. Call directly. It will revert here if proof is bad.
        balance_verifier.verifyProof(proof, input);

        // 3. Logic only continues if proof was valid.
        require(!usedNullifiers[input[4]], "Nullifier already used");
        usedNullifiers[input[4]] = true;
    }

}