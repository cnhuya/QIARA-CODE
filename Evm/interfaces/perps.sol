// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IEvents {
    struct Data { string name; string typeName; bytes value; }
    function emitVaultEvent(string calldata action, Data[] calldata data) external;
}

contract PerpsInterface {

    IEvents public immutable events;

    constructor(address _events) {
        events = IEvents(_events);
    }

    // ==========================================
    // NEW MODULAR FUNCTIONS (PERPS & RESERVES)
    // ==========================================

    function p_accrue_interest(
        bytes memory user, 
        string memory shared, 
        string memory asset
    ) external {
        IEvents.Data[] memory eventData = new IEvents.Data[](4);

        _addAddress(eventData, 0, "sender", msg.sender);
        _addBytes(eventData, 1, "user", user);
        _addString(eventData, 2, "shared", shared);
        _addString(eventData, 3, "asset", asset);

        events.emitVaultEvent("Modular Interest Accrued", eventData);
    }

    function p_trade(
        bytes memory user, 
        string memory shared, 
        string memory asset, 
        uint256 size, 
        uint64 leverage, 
        bool isLong, 
        string memory reserve_chain, 
        string memory reserve_provider, 
        string memory reserve_token
    ) external {
        IEvents.Data[] memory eventData = new IEvents.Data[](10);

        _addAddress(eventData, 0, "sender", msg.sender);
        _addBytes(eventData, 1, "user", user);
        _addString(eventData, 2, "shared", shared);
        _addString(eventData, 3, "asset", asset);
        _addUint256(eventData, 4, "size", size);
        _addUint64(eventData, 5, "leverage", leverage);
        _addBool(eventData, 6, "isLong", isLong);
        _addString(eventData, 7, "reserve_chain", reserve_chain);
        _addString(eventData, 8, "reserve_provider", reserve_provider);
        _addString(eventData, 9, "reserve_token", reserve_token);

        events.emitVaultEvent("Modular Trade Executed", eventData);
    }

    function p_update_oracle_and_trade(
        bytes memory user, 
        string memory shared, 
        string memory asset, 
        uint256 size, 
        uint64 leverage, 
        bool isLong, 
        string memory reserve_chain, 
        string memory reserve_provider, 
        string memory reserve_token, 
        bytes[] memory price_update_data
    ) external {
        IEvents.Data[] memory eventData = new IEvents.Data[](11);

        _addAddress(eventData, 0, "sender", msg.sender);
        _addBytes(eventData, 1, "user", user);
        _addString(eventData, 2, "shared", shared);
        _addString(eventData, 3, "asset", asset);
        _addUint256(eventData, 4, "size", size);
        _addUint64(eventData, 5, "leverage", leverage);
        _addBool(eventData, 6, "isLong", isLong);
        _addString(eventData, 7, "reserve_chain", reserve_chain);
        _addString(eventData, 8, "reserve_provider", reserve_provider);
        _addString(eventData, 9, "reserve_token", reserve_token);
        _addBytesArray(eventData, 10, "price_update_data", price_update_data);

        events.emitVaultEvent("Modular Oracle Update and Trade", eventData);
    }

    function p_change_reserve(
        bytes memory user, 
        string memory shared, 
        string memory asset, 
        string memory new_reserve_chain, 
        string memory new_reserve_provider, 
        string memory new_reserve_token
    ) external {
        IEvents.Data[] memory eventData = new IEvents.Data[](7);

        _addAddress(eventData, 0, "sender", msg.sender);
        _addBytes(eventData, 1, "user", user);
        _addString(eventData, 2, "shared", shared);
        _addString(eventData, 3, "asset", asset);
        _addString(eventData, 4, "new_reserve_chain", new_reserve_chain);
        _addString(eventData, 5, "new_reserve_provider", new_reserve_provider);
        _addString(eventData, 6, "new_reserve_token", new_reserve_token);

        events.emitVaultEvent("Modular Reserve Changed", eventData);
    }

    // ==========================================
    // STACK-SAVING INTERNAL HELPERS
    // ==========================================

    function _addAddress(IEvents.Data[] memory eventData, uint256 index, string memory name, address value) internal pure {
        eventData[index] = IEvents.Data(name, "address", abi.encode(value));
    }

    function _addBytes(IEvents.Data[] memory eventData, uint256 index, string memory name, bytes memory value) internal pure {
        eventData[index] = IEvents.Data(name, "bytes", abi.encode(value));
    }

    function _addString(IEvents.Data[] memory eventData, uint256 index, string memory name, string memory value) internal pure {
        eventData[index] = IEvents.Data(name, "string", abi.encode(value));
    }

    function _addUint256(IEvents.Data[] memory eventData, uint256 index, string memory name, uint256 value) internal pure {
        eventData[index] = IEvents.Data(name, "uint256", abi.encode(value));
    }

    function _addUint64(IEvents.Data[] memory eventData, uint256 index, string memory name, uint64 value) internal pure {
        eventData[index] = IEvents.Data(name, "uint64", abi.encode(value));
    }

    function _addBool(IEvents.Data[] memory eventData, uint256 index, string memory name, bool value) internal pure {
        eventData[index] = IEvents.Data(name, "bool", abi.encode(value));
    }

    function _addBytesArray(IEvents.Data[] memory eventData, uint256 index, string memory name, bytes[] memory value) internal pure {
        eventData[index] = IEvents.Data(name, "bytes[]", abi.encode(value));
    }
}