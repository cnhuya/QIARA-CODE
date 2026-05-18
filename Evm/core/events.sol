// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract QiaraEventsV1 {

    // --- Data Structures ---

    struct Data {
        string name; 
        string typeName;  
        bytes value;
    }

    event Vault(string name, Data[] aux);

    function createDataStruct(string memory _name, string memory _typeName, bytes memory _value) public pure returns (Data memory) {
        return Data({name: _name,typeName: _typeName,value: _value});
    }

   function emitVaultEvent(string memory _eventName, Data[] memory _userProvidedData) public {
        // 1. Create a new array that is 1 slot larger than the one provided
        Data[] memory extendedData = new Data[](_userProvidedData.length + 1);

        // 2. Insert Timestamp at Slot 0
        extendedData[0] = Data("timestamp", "uint256", abi.encode(block.timestamp));

        // 4. Copy the original user data into the remaining slots
        for (uint i = 0; i < _userProvidedData.length; i++) {
            extendedData[i + 1] = _userProvidedData[i];
        }

        // 5. Emit the final expanded array
        emit Vault(_eventName, extendedData);
    }

}