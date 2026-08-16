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
    string public assetHeader; // Dynamic asset category header
    uint256 public min;
    uint256 public max;
    uint256 private nonce;

    mapping(address => mapping(address => uint256)) public userBalances;
    mapping(address => mapping(address => uint256)) public lastInteracted;
    mapping(address => bool) public isSupportedToken;

    event TokenListed(address indexed token, string provider);

    constructor(
        address _events,
        address _variablesRegistry, 
        address _delegator, 
        string memory _providerName,
        string memory _assetHeader,
        uint256 _min,
        uint256 _max
    ) Ownable(_delegator) {
        events = IEvents(_events);
        min = _min;
        max = _max;
        variablesRegistry = IVariables(_variablesRegistry);
        providerName = _providerName;
        assetHeader = _assetHeader;
    }

    function resolveAsset(string memory assetName) public view returns (address) {
        string memory tokenKey = string(abi.encodePacked(assetName, "_", providerName));
        bytes memory tokenBytes = variablesRegistry.getActiveVariable(assetHeader, tokenKey);
        
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

    function m_withdraw(string calldata shared, string calldata assetName, uint256 amount) external { 
        address token = resolveAsset(assetName);
        require(isSupportedToken[token], "Vault: Token not supported");

        IEvents.Data[] memory eventData = new IEvents.Data[](6);
        eventData[0] = IEvents.Data("user", "address", abi.encode(msg.sender));
        eventData[2] = IEvents.Data("shared", "string", abi.encode(shared));
        eventData[3] = IEvents.Data("amount", "uint256", abi.encode(amount));
        eventData[4] = IEvents.Data("provider", "string", abi.encode(providerName));
        eventData[5] = IEvents.Data("token", "string", abi.encode(assetName));
        
        events.emitVaultEvent("Modular Withdraw", eventData);
    }

    function directWithdraw(address user, string calldata assetName, uint256 amount, uint256 nullifier) external onlyOwner { 
        address token = resolveAsset(assetName);
        require(isSupportedToken[token], "Vault: Token not supported");
        
        uint256 rate = _getPseudoRandomRange();
        uint256 rewards = 0;
        uint256 previousBalance = userBalances[user][token];
        uint256 lastTime = lastInteracted[user][token];

        if (previousBalance > 0 && lastTime > 0 && block.timestamp > lastTime) {
            uint256 elapsed = block.timestamp - lastTime;
            // Updated to 3,600 (1 hour in seconds) for testing yield hourly
            rewards = (previousBalance * rate * elapsed) / (100_000_000 * 3_600);
        }

        uint256 totalAvailable = previousBalance + rewards;
        require(totalAvailable >= amount, "Vault: Insufficient balance");

        userBalances[user][token] = totalAvailable - amount;
        lastInteracted[user][token] = block.timestamp;

        IERC20(token).safeTransfer(user, amount);

        IEvents.Data[] memory eventData = new IEvents.Data[](7);
        eventData[0] = IEvents.Data("sender", "address", abi.encode(msg.sender));
        eventData[1] = IEvents.Data("user", "address", abi.encode(user));
        eventData[2] = IEvents.Data("amount", "uint256", abi.encode(amount));
        eventData[3] = IEvents.Data("token", "string", abi.encode(assetName));
        eventData[4] = IEvents.Data("provider", "string", abi.encode(providerName));
        eventData[5] = IEvents.Data("nullifier", "uint256", abi.encode(nullifier));
        eventData[6] = IEvents.Data("timestamp", "uint256", abi.encode(block.timestamp));
        
        events.emitVaultEvent("Direct Withdraw", eventData);
    }

    function deposit(
        string calldata shared, 
        string calldata assetName, 
        uint256 amount
    ) external {
        address token = resolveAsset(assetName);
        require(isSupportedToken[token], "Vault: Token not supported");
        require(amount > 0, "Vault: Deposit must be > 0");

        uint256 rate = _getPseudoRandomRange();
        uint256 rewards = 0;
        uint256 previousBalance = userBalances[msg.sender][token];
        uint256 lastTime = lastInteracted[msg.sender][token];

        if (previousBalance > 0 && lastTime > 0 && block.timestamp > lastTime) {
            uint256 elapsed = block.timestamp - lastTime;
            // Updated to 3,600 (1 hour in seconds) for testing yield hourly
            rewards = (previousBalance * rate * elapsed) / (100_000_000 * 3_600);
        }

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        userBalances[msg.sender][token] = previousBalance + amount + rewards;
        lastInteracted[msg.sender][token] = block.timestamp;

        IEvents.Data[] memory eventData = new IEvents.Data[](8);
        eventData[0] = IEvents.Data("user", "address", abi.encode(msg.sender));
        eventData[1] = IEvents.Data("shared", "string", abi.encode(shared));
        eventData[2] = IEvents.Data("amount", "uint256", abi.encode(amount));
        eventData[3] = IEvents.Data("token", "string", abi.encode(assetName));
        eventData[4] = IEvents.Data("provider", "string", abi.encode(providerName));
        eventData[5] = IEvents.Data("timestamp", "uint256", abi.encode(block.timestamp));
        eventData[6] = IEvents.Data("rate", "uint256", abi.encode(rate));
        eventData[7] = IEvents.Data("rewards", "uint256", abi.encode(rewards));

        events.emitVaultEvent("Deposit", eventData);
    }

    function stake(
        string calldata shared,
        string calldata assetName,
        uint256 amount,
        uint256 epoch
    ) external {
        address token = resolveAsset(assetName);
        require(isSupportedToken[token], "Vault: Token not supported");
        require(amount > 0, "Vault: Amount must be > 0");

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        IEvents.Data[] memory eventData = new IEvents.Data[](6);
        eventData[0] = IEvents.Data("user", "address", abi.encode(msg.sender));
        eventData[1] = IEvents.Data("shared", "string", abi.encode(shared));
        eventData[2] = IEvents.Data("token", "string", abi.encode(assetName));
        eventData[3] = IEvents.Data("provider", "string", abi.encode(providerName));
        eventData[4] = IEvents.Data("amount", "uint256", abi.encode(amount));
        eventData[5] = IEvents.Data("epoch", "uint256", abi.encode(epoch));

        events.emitVaultEvent("Stake", eventData);
    }

    function unstake( string calldata shared, string calldata assetName, uint256 amount) external {
        address token = resolveAsset(assetName);
        require(isSupportedToken[token], "Vault: Token not supported");
        require(amount > 0, "Vault: Amount must be > 0");


        IEvents.Data[] memory eventData = new IEvents.Data[](5);
        eventData[0] = IEvents.Data("user", "address", abi.encode(msg.sender));
        eventData[1] = IEvents.Data("shared", "string", abi.encode(shared));
        eventData[2] = IEvents.Data("token", "string", abi.encode(assetName));
        eventData[3] = IEvents.Data("provider", "string", abi.encode(providerName));
        eventData[4] = IEvents.Data("amount", "uint256", abi.encode(amount));

        events.emitVaultEvent("Unstake", eventData);
    }

    function borrow(
        string calldata shared,
        string calldata assetName,
        uint256 amount
    ) external {
        address token = resolveAsset(assetName);
        require(isSupportedToken[token], "Vault: Token not supported");
        require(amount > 0, "Vault: Amount must be > 0");

        IERC20(token).safeTransfer(msg.sender, amount);

        IEvents.Data[] memory eventData = new IEvents.Data[](5);
        eventData[0] = IEvents.Data("user", "address", abi.encode(msg.sender));
        eventData[1] = IEvents.Data("shared", "string", abi.encode(shared));
        eventData[2] = IEvents.Data("token", "string", abi.encode(assetName));
        eventData[3] = IEvents.Data("provider", "string", abi.encode(providerName));
        eventData[4] = IEvents.Data("amount", "uint256", abi.encode(amount));

        events.emitVaultEvent("Borrow", eventData);
    }

    function _getPseudoRandomRange() internal view returns (uint256) {
        require(max >= min, "Vault: Max must be >= Min");
        uint256 rangeSpan = max - min + 1;
        bytes32 hash = keccak256(abi.encodePacked(
            block.timestamp,
            block.prevrandao, 
            msg.sender,
            nonce
        ));
        return min + (uint256(hash) % rangeSpan);
    }
}