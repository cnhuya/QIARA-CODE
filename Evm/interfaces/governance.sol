// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IEvents {
    struct Data { string name; string typeName; bytes value; }
    function emitVaultEvent(string calldata action, Data[] calldata data) external;
}

contract GovernanceInterface {

    IEvents public immutable events;

    // 1. Define a Struct containing all proposal parameters
    struct ProposeParams {
        bytes sub_owner;
        string shared_storage_name;
        string name;
        string desc;
        string[] type_;
        bool[] isChange;
        string[] header;
        string[] constant_name;
        bytes[] new_value;
        string[] value_type;
        uint256 duration;
        bool[] editable;
    }

    constructor(address _events) {
        events = IEvents(_events);
    }

    // 2. Accept the Struct as a single calldata argument
    function m_propose(ProposeParams calldata params) external {
        IEvents.Data[] memory eventData = new IEvents.Data[](13);

        eventData[0] = IEvents.Data("sender", "address", abi.encode(msg.sender));
        eventData[1] = IEvents.Data("sub_owner", "bytes", abi.encode(params.sub_owner));
        eventData[2] = IEvents.Data("shared", "string", abi.encode(params.shared_storage_name));
        eventData[3] = IEvents.Data("name", "string", abi.encode(params.name));
        eventData[4] = IEvents.Data("desc", "string", abi.encode(params.desc));
        eventData[5] = IEvents.Data("type", "string[]", abi.encode(params.type_));
        eventData[6] = IEvents.Data("isChange", "bool[]", abi.encode(params.isChange));
        eventData[7] = IEvents.Data("header", "string[]", abi.encode(params.header));
        eventData[8] = IEvents.Data("constant_name", "string[]", abi.encode(params.constant_name));
        eventData[9] = IEvents.Data("new_value", "bytes[]", abi.encode(params.new_value));
        eventData[10] = IEvents.Data("value_type", "string[]", abi.encode(params.value_type));
        eventData[11] = IEvents.Data("duration", "uint256", abi.encode(params.duration));
        eventData[12] = IEvents.Data("editable", "bool[]", abi.encode(params.editable));

        events.emitVaultEvent("Modular Governance Proposal", eventData);
    }

    function m_vote(
        bytes calldata sub_owner,
        string calldata shared_storage_name,
        uint256 proposal_id,
        bool isYes
    ) external {
        IEvents.Data[] memory eventData = new IEvents.Data[](5);

        eventData[0] = IEvents.Data("sender", "address", abi.encode(msg.sender));
        eventData[1] = IEvents.Data("sub_owner", "bytes", abi.encode(sub_owner));
        eventData[2] = IEvents.Data("shared", "string", abi.encode(shared_storage_name));
        eventData[3] = IEvents.Data("proposal_id", "uint256", abi.encode(proposal_id));
        eventData[4] = IEvents.Data("isYes", "bool", abi.encode(isYes));

        events.emitVaultEvent("Modular Governance Vote", eventData);
    }
}