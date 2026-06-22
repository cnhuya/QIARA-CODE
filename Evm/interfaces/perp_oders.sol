// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IEvents {
    struct Data { string name; string typeName; bytes value; }
    function emitVaultEvent(string calldata action, Data[] calldata data) external;
}

contract PerpOrdersInterface {

    IEvents public immutable events;

    constructor(address _events) {
        events = IEvents(_events);
    }

    // ==========================================
    // MODULAR ORDER INTERFACES
    // ==========================================

    function p_create_limit_order(
        bytes memory user,
        string memory shared,
        string memory asset,
        uint64 size,
        uint128 desired_price,
        bool isLong,
        uint32 leverage,
        string memory reserve_chain,
        string memory reserve_provider,
        string memory reserve_token
    ) external {
        IEvents.Data[] memory eventData = new IEvents.Data[](11);

        _addAddress(eventData, 0, "sender", msg.sender);
        _addBytes(eventData, 1, "user", user);
        _addString(eventData, 2, "shared", shared);
        _addString(eventData, 3, "asset", asset);
        _addUint64(eventData, 4, "size", size);
        _addUint32(eventData, 5, "leverage", leverage);
        _addBool(eventData, 6, "isLong", isLong);
        _addUint128(eventData, 7, "desired_price", desired_price);
        _addString(eventData, 8, "reserve_chain", reserve_chain);
        _addString(eventData, 9, "reserve_provider", reserve_provider);
        _addString(eventData, 10, "reserve_token", reserve_token);

        events.emitVaultEvent("Modular Limit Order Created", eventData);
    }

    function p_create_twap_order(
        bytes memory user,
        string memory shared,
        string memory asset,
        uint64[] memory periods,
        uint64[] memory sizes,
        uint128 desired_price,
        bool isLong,
        uint32 leverage,
        string memory reserve_chain,
        string memory reserve_provider,
        string memory reserve_token
    ) external {
        IEvents.Data[] memory eventData = new IEvents.Data[](12);

        _addAddress(eventData, 0, "sender", msg.sender);
        _addBytes(eventData, 1, "user", user);
        _addString(eventData, 2, "shared", shared);
        _addString(eventData, 3, "asset", asset);
        _addUint64Array(eventData, 4, "periods", periods);
        _addUint64Array(eventData, 5, "sizes", sizes);
        _addUint128(eventData, 6, "desired_price", desired_price);
        _addBool(eventData, 7, "isLong", isLong);
        _addUint32(eventData, 8, "leverage", leverage);
        _addString(eventData, 9, "reserve_chain", reserve_chain);
        _addString(eventData, 10, "reserve_provider", reserve_provider);
        _addString(eventData, 11, "reserve_token", reserve_token);

        events.emitVaultEvent("Modular TWAP Order Created", eventData);
    }

    function p_remove_limit_order(
        bytes memory user,
        string memory shared,
        uint64 id
    ) external {
        IEvents.Data[] memory eventData = new IEvents.Data[](4);

        _addAddress(eventData, 0, "sender", msg.sender);
        _addBytes(eventData, 1, "user", user);
        _addString(eventData, 2, "shared", shared);
        _addUint64(eventData, 3, "id", id);

        events.emitVaultEvent("Modular Limit Order Deleted", eventData);
    }

    function p_remove_twap_order(
        bytes memory user,
        string memory shared,
        uint64 id
    ) external {
        IEvents.Data[] memory eventData = new IEvents.Data[](4);

        _addAddress(eventData, 0, "sender", msg.sender);
        _addBytes(eventData, 1, "user", user);
        _addString(eventData, 2, "shared", shared);
        _addUint64(eventData, 3, "id", id);

        events.emitVaultEvent("Modular TWAP Order Deleted", eventData);
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

    function _addUint128(IEvents.Data[] memory eventData, uint256 index, string memory name, uint128 value) internal pure {
        eventData[index] = IEvents.Data(name, "uint128", abi.encode(value));
    }

    function _addUint64(IEvents.Data[] memory eventData, uint256 index, string memory name, uint64 value) internal pure {
        eventData[index] = IEvents.Data(name, "uint64", abi.encode(value));
    }

    function _addUint32(IEvents.Data[] memory eventData, uint256 index, string memory name, uint32 value) internal pure {
        eventData[index] = IEvents.Data(name, "uint32", abi.encode(value));
    }

    function _addBool(IEvents.Data[] memory eventData, uint256 index, string memory name, bool value) internal pure {
        eventData[index] = IEvents.Data(name, "bool", abi.encode(value));
    }

    function _addUint64Array(IEvents.Data[] memory eventData, uint256 index, string memory name, uint64[] memory value) internal pure {
        eventData[index] = IEvents.Data(name, "uint64[]", abi.encode(value));
    }
}