// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IEvents {
    struct Data { string name; string typeName; bytes value; }
    function emitVaultEvent(string calldata action, Data[] calldata data) external;
}

contract SharedInterface  {

    IEvents public immutable events;

    constructor(address _events)  {
        events = IEvents(_events);
    }

    function m_create_shared_storage(string calldata name, string calldata ref_code, string calldata used_ref_code,  string calldata selected_validator, uint64 xp_tax, uint64 fee_tax ) external { 
        IEvents.Data[] memory eventData = new IEvents.Data[](7);
        
        eventData[0] = IEvents.Data("sender", "address", abi.encode(msg.sender));
        eventData[1] = IEvents.Data("name", "string", abi.encode(name));
        eventData[2] = IEvents.Data("ref_code", "string", abi.encode(ref_code));
        eventData[3] = IEvents.Data("ref_code", "string", abi.encode(used_ref_code));
        eventData[4] = IEvents.Data("selected_validator", "string", abi.encode(selected_validator));
        eventData[5] = IEvents.Data("xp_tax", "uint64", abi.encode(xp_tax));
        eventData[6] = IEvents.Data("fee_tax", "uint64", abi.encode(fee_tax));
        
        events.emitVaultEvent("Modular Storage Creation", eventData);
    }

    // The sub_owner is intentionally bytes type, because if it is address, only EVM addresses are allowed,
    // which would result in this modular interface to not work on Aptos/Sui wallets or other different standards.
    function p_allow_sub_owner(string calldata name, bytes calldata sub_owner) external { 
        IEvents.Data[] memory eventData = new IEvents.Data[](3);
        
        eventData[0] = IEvents.Data("sender", "address", abi.encode(msg.sender));
        eventData[1] = IEvents.Data("sub_owner", "bytes", abi.encode(sub_owner));
        eventData[2] = IEvents.Data("name", "string", abi.encode(name));
        
        events.emitVaultEvent("Modular Storage Sub Owner Added", eventData);
    }

    // The sub_owner is intentionally bytes type, because if it is address, only EVM addresses are allowed,
    // which would result in this modular interface to not work on Aptos/Sui wallets or other different standards.
    function p_remove_sub_owner(string calldata name, bytes calldata sub_owner) external { 
        IEvents.Data[] memory eventData = new IEvents.Data[](3);
        
        eventData[0] = IEvents.Data("sender", "address", abi.encode(msg.sender));
        eventData[1] = IEvents.Data("sub_owner", "bytes", abi.encode(sub_owner));
        eventData[2] = IEvents.Data("name", "string", abi.encode(name));
        
        events.emitVaultEvent("Modular Storage Sub Owner Removed", eventData);
    }

    // Updates the designated referral code for a specific shared storage
    function p_change_used_ref_code(string calldata name, bytes calldata sub_owner, string calldata new_used_ref_code) external {
        IEvents.Data[] memory eventData = new IEvents.Data[](4);
        
        eventData[0] = IEvents.Data("sender", "address", abi.encode(msg.sender));
        eventData[1] = IEvents.Data("sub_owner", "bytes", abi.encode(sub_owner));
        eventData[2] = IEvents.Data("name", "string", abi.encode(name));
        eventData[3] = IEvents.Data("new_used_ref_code", "string", abi.encode(new_used_ref_code));
        
        events.emitVaultEvent("Modular Storage Used Ref Code Updated", eventData);
    }
}