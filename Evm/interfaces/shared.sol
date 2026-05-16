// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


interface IEvents {
    struct Data { string name; string typeName; bytes value; }
    function emitVaultEvent(string calldata action, Data[] calldata data) external;
}

contract ModularShared  {

    IEvents public immutable events;

    constructor(address _events)  {
        events = IEvents(_events);
    }


    function m_create_shared_storage(string calldata name) external { 

        IEvents.Data[] memory eventData = new IEvents.Data[](2);
        
        eventData[0] = IEvents.Data("user", "address", abi.encode(msg.sender));
        eventData[1] = IEvents.Data("name", "string", abi.encode(name));
        
        events.emitVaultEvent("Modular Storage Creation", eventData);
    }

    function p_allow_sub_owner(string calldata name, address sub_owner) external { 

        IEvents.Data[] memory eventData = new IEvents.Data[](3);
        
        eventData[0] = IEvents.Data("user", "address", abi.encode(msg.sender));
        eventData[2] = IEvents.Data("sub_owner", "address", abi.encode(sub_owner));
        eventData[3] = IEvents.Data("name", "string", abi.encode(name));
        
        events.emitVaultEvent("Modular Storage Sub Owner Added", eventData);
    }

    function p_remove_sub_owner(string calldata name, address sub_owner) external { 

        IEvents.Data[] memory eventData = new IEvents.Data[](3);
        
        eventData[0] = IEvents.Data("user", "address", abi.encode(msg.sender));
        eventData[2] = IEvents.Data("sub_owner", "address", abi.encode(sub_owner));
        eventData[3] = IEvents.Data("name", "string", abi.encode(name));
        
        events.emitVaultEvent("Modular Storage Sub Owner Removed", eventData);
    }
}