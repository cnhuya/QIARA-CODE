// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IVariables {
   function getActiveVariable(string calldata header, string calldata name) external view returns (bytes memory);
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


    event TokenListed(address indexed token, string provider);
    event Deposit(address indexed user, address indexed token, uint256 amount, string provider);
    event DirectWithdraw(address indexed user, address indexed token, uint256 amount, string provider);

    constructor(
        address _events,
        address _variablesRegistry, 
        address _delegator, 
        string memory _providerName
    ) Ownable(_delegator) {
        events = IEvents(_events);
        variablesRegistry = IVariables(_variablesRegistry);
        providerName = _providerName;
    }

    function resolveAsset(string memory assetName) public view returns (address) {
        string memory tokenKey = string(abi.encodePacked(assetName, "_", providerName));
        bytes memory tokenBytes = variablesRegistry.getActiveVariable("QiaraMonadAssets", tokenKey);
        
        require(tokenBytes.length >= 20, "Vault: Asset not found in registry");
        
        address assetAddress;
        assembly {
            assetAddress := mload(add(tokenBytes, 20))
        }
        return assetAddress;
    }

    function listNewToken(string calldata assetName) external {
        address tokenAddr = resolveAsset(assetName);
        isSupportedToken[tokenAddr] = true;
        emit TokenListed(tokenAddr, providerName);
    }

    /**
     * @dev This function can be called by the user, consensus then processes this, 
     *and if everything goes right, it then calls directWdirectWithdraw
     */

    // The sub_owner is intentionally bytes type, because if it is address, only EVM addresses are allowed,
    // which would result in this modular interface to not work on Aptos/Sui wallets or other different standarts.
    
    function m_withdraw(bytes calldata user, string calldata shared, string calldata assetName, uint256 amount) external { 
        // If you have the 'onlyOwner' modifier here, ensure the CALLER is the Delegator address
        
        address token = resolveAsset(assetName);
        require(isSupportedToken[token], "Vault: Token not supported");

        // FIX 1: Change array size from 6 to 5
        IEvents.Data[] memory eventData = new IEvents.Data[](6);
        
        eventData[0] = IEvents.Data("user", "bytes", abi.encode(user));
        eventData[1] = IEvents.Data("shared", "address", abi.encode(shared));
        eventData[2] = IEvents.Data("amount", "uint256", abi.encode(amount));
        eventData[3] = IEvents.Data("chain", "string", abi.encode("base"));
        eventData[4] = IEvents.Data("provider", "string", abi.encode(providerName));
        
        // FIX 2: Correct type label to "string" because assetName is a string
        eventData[5] = IEvents.Data("token", "string", abi.encode(assetName));
        
        // Slot [5] is removed, so no more null-pointer revert.
        
        events.emitVaultEvent("Modular Withdraw", eventData);
    }

    /**
     * @dev This function is called directly by the Delegator contract 
     * after it has verified the ZK Proof and Signatures.
     */
    function directWithdraw(address user, string calldata assetName, uint256 amount, uint256 nullifier) external onlyOwner { // ONLY the Delegator contract can call this
        address token = resolveAsset(assetName);
        require(isSupportedToken[token], "Vault: Token not supported");
        
        // IMMEDIATELY transfer the tokens to the user
        IERC20(token).safeTransfer(user, amount);

        // Log to the global events contract
        IEvents.Data[] memory eventData = new IEvents.Data[](6);
        eventData[0] = IEvents.Data("user", "address", abi.encode(user));
        eventData[1] = IEvents.Data("amount", "uint256", abi.encode(amount));
        eventData[2] = IEvents.Data("token", "string", abi.encode(assetName));
        eventData[3] = IEvents.Data("provider", "string", abi.encode(providerName));
        eventData[4] = IEvents.Data("nullifier", "uint256", abi.encode(nullifier));
        eventData[5] = IEvents.Data("timestamp", "uint256", abi.encode(block.timestamp));
        
        events.emitVaultEvent("Direct Withdraw", eventData);
        emit DirectWithdraw(user, token, amount, providerName);
    }

    function deposit(string calldata assetName, uint256 amount) external {
        address token = resolveAsset(assetName);
        require(isSupportedToken[token], "Vault: Token not supported");
        require(amount > 0, "Vault: Deposit must be > 0");

        // Transfers tokens from user to this vault
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        IEvents.Data[] memory eventData = new IEvents.Data[](5);
        eventData[0] = IEvents.Data("user", "address", abi.encode(msg.sender));
        eventData[1] = IEvents.Data("amount", "uint256", abi.encode(amount));
        eventData[2] = IEvents.Data("token", "string", abi.encode(assetName));
        eventData[3] = IEvents.Data("provider", "string", abi.encode(providerName));
        eventData[4] = IEvents.Data("timestamp", "uint256", abi.encode(block.timestamp));

        events.emitVaultEvent("Deposit", eventData);
        emit Deposit(msg.sender, token, amount, providerName);
    }
}