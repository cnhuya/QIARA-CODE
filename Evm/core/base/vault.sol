// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IVariables {
   function getVariable(string calldata header, string calldata name) external view returns (bytes memory);
}
interface IEvents {
    struct Data { string name; string typeName; bytes value; }
    function emitVaultEvent(string calldata action, Data[] calldata data) external;
}


contract QiaraMultiAssetVault is Ownable {
    using SafeERC20 for IERC20;

    IVariables public immutable variablesRegistry;
    IEvents public immutable events;
    string public providerName; 

    mapping(address => bool) public isSupportedToken;
    mapping(address => mapping(address => uint256)) public claimableBalances;

    event TokenListed(address indexed token, string provider);
    event Deposit(address indexed user, address indexed token, uint256 amount, string provider);

    constructor(
        address _events,
        address _variablesRegistry, 
        address delegator, 
        string memory _providerName
    ) Ownable(delegator) {
        events = IEvents(_events);
        variablesRegistry = IVariables(_variablesRegistry);
        providerName = _providerName;
    }

    /**
     * @dev Internal helper to resolve "USDC" -> 0xA0b... using registry
     */
    function resolveAsset(string memory assetName) public view returns (address) {
        string memory tokenKey = string(abi.encodePacked(assetName, "_", providerName));
        bytes memory tokenBytes = variablesRegistry.getVariable("QiaraMonadAssets", tokenKey);
        require(tokenBytes.length > 0, "Vault: Asset not found in registry");
        return abi.decode(tokenBytes, (address));
    }

    function listNewToken(string calldata assetName) external {
        address tokenAddr = resolveAsset(assetName);
        isSupportedToken[tokenAddr] = true;
        emit TokenListed(tokenAddr, providerName);
    }


    function grantWithdrawalPermission(address user, string calldata assetName, uint256 amount, uint256 nullifier) external onlyOwner {
        address token = resolveAsset(assetName);
        require(isSupportedToken[token], "Vault: Token not supported");
        
        claimableBalances[user][token] += amount;

        IEvents.Data[] memory eventData = new IEvents.Data[](6);
        eventData[0] = IEvents.Data("user", "address", abi.encode(msg.sender));
        eventData[1] = IEvents.Data("amount", "uint256", abi.encode(amount));
        eventData[2] = IEvents.Data("token", "string", abi.encode(assetName));
        eventData[3] = IEvents.Data("provider", "string", abi.encode(providerName));
        eventData[4] = IEvents.Data("nullifier", "uint256", abi.encode(nullifier));
        eventData[5] = IEvents.Data("timestamp", "u256", abi.encode(block.timestamp));
        // SEND the event to the global logger address
        events.emitVaultEvent("Grant Withdraw Permission", eventData);
    }

    function deposit(string calldata assetName, uint256 amount) external {
        address token = resolveAsset(assetName);
        require(isSupportedToken[token], "Vault: Token not supported");
        require(amount > 0, "Vault: Deposit must be > 0");

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        claimableBalances[msg.sender][token] += amount;

        IEvents.Data[] memory eventData = new IEvents.Data[](5);
        eventData[0] = IEvents.Data("user", "address", abi.encode(msg.sender));
        eventData[1] = IEvents.Data("amount", "uint256", abi.encode(amount));
        eventData[2] = IEvents.Data("token", "string", abi.encode(assetName));
        eventData[3] = IEvents.Data("provider", "string", abi.encode(providerName));
        eventData[4] = IEvents.Data("timestamp", "u256", abi.encode(block.timestamp));

        // SEND the event to the global logger address
        events.emitVaultEvent("Deposit", eventData);
    }

    function withdraw(string calldata assetName, uint256 amount, address receiver) external {
        address token = resolveAsset(assetName);
        require(isSupportedToken[token], "Vault: Token not supported");
        require(amount <= claimableBalances[msg.sender][token], "Vault: Insufficient balance");
        
        claimableBalances[msg.sender][token] -= amount;
        IERC20(token).safeTransfer(receiver, amount);
        
        IEvents.Data[] memory eventData = new IEvents.Data[](5);
        eventData[0] = IEvents.Data("user", "address", abi.encode(msg.sender));
        eventData[1] = IEvents.Data("amount", "uint256", abi.encode(amount));
        eventData[2] = IEvents.Data("token", "string", abi.encode(assetName));
        eventData[3] = IEvents.Data("provider", "string", abi.encode(providerName));
        eventData[4] = IEvents.Data("timestamp", "u256", abi.encode(block.timestamp));
        // SEND the event to the global logger address
        events.emitVaultEvent("Withdraw", eventData);
    }
}