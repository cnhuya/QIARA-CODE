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
    uint256 public min;
    uint256 public max;
    uint256 private nonce; // Incrementing counter to prevent same-block duplicates [1]

    // === ACCRUAL STORAGE === //
    // user => token => balance (including auto-compounded interest) [1]
    mapping(address => mapping(address => uint256)) public userBalances;
    // user => token => last interaction timestamp [1]
    mapping(address => mapping(address => uint256)) public lastInteracted;

    mapping(address => bool) public isSupportedToken;

    event TokenListed(address indexed token, string provider);
    event Deposit(address indexed user, address indexed token, uint256 amount, string provider);
    event DirectWithdraw(address indexed user, address indexed token, uint256 amount, string provider);

    constructor(
        address _events,
        address _variablesRegistry, 
        address _delegator, 
        string memory _providerName,
        uint256 _min,
        uint256 _max
    ) Ownable(_delegator) {
        events = IEvents(_events);
        min = _min;
        max = _max;
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
     * and if everything goes right, it then calls directWithdraw
     */
    function m_withdraw(bytes calldata user, string calldata shared, string calldata assetName, uint256 amount) external { 
        address token = resolveAsset(assetName);
        require(isSupportedToken[token], "Vault: Token not supported");

        IEvents.Data[] memory eventData = new IEvents.Data[](6);
        
        eventData[0] = IEvents.Data("user", "bytes", abi.encode(user));
        eventData[1] = IEvents.Data("shared", "address", abi.encode(shared));
        eventData[2] = IEvents.Data("amount", "uint256", abi.encode(amount));
        eventData[3] = IEvents.Data("chain", "string", abi.encode("base"));
        eventData[4] = IEvents.Data("provider", "string", abi.encode(providerName));
        eventData[5] = IEvents.Data("token", "string", abi.encode(assetName));
        
        events.emitVaultEvent("Modular Withdraw", eventData);
    }

    /**
     * @dev This function is called directly by the Delegator contract 
     * after it has verified the ZK Proof and Signatures.
     */
    function directWithdraw(address user, string calldata assetName, uint256 amount, uint256 nullifier) external onlyOwner { 
        address token = resolveAsset(assetName);
        require(isSupportedToken[token], "Vault: Token not supported");
        
        uint256 rate = _getPseudoRandomRange();
        uint256 rewards = 0;
        uint256 previousBalance = userBalances[user][token];
        uint256 lastTime = lastInteracted[user][token];

        // 1. Accrue pending interest on withdrawal [1]
        if (previousBalance > 0 && lastTime > 0 && block.timestamp > lastTime) {
            uint256 elapsed = block.timestamp - lastTime;
            // Interest = (Balance * APR * elapsed seconds) / (10^8 percentage scale * seconds per year) [3]
            rewards = (previousBalance * rate * elapsed) / (100_000_000 * 31_536_000);
        }

        uint256 totalAvailable = previousBalance + rewards;
        require(totalAvailable >= amount, "Vault: Insufficient balance");

        // 2. Reduce balance and update checkpoints [1]
        userBalances[user][token] = totalAvailable - amount;
        lastInteracted[user][token] = block.timestamp;

        // 3. Transfer the underlying tokens to the user
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

        uint256 rate = _getPseudoRandomRange();
        uint256 rewards = 0;
        uint256 previousBalance = userBalances[msg.sender][token];
        uint256 lastTime = lastInteracted[msg.sender][token];

        // 1. Calculate accrued interest/yield on existing balance since last interaction [1]
        if (previousBalance > 0 && lastTime > 0 && block.timestamp > lastTime) {
            uint256 elapsed = block.timestamp - lastTime;
            // Interest = (Balance * APR * elapsed seconds) / (10^8 percentage scale * seconds per year) [3]
            rewards = (previousBalance * rate * elapsed) / (100_000_000 * 31_536_000);
        }

        // 2. Transfer tokens from user to this vault
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // 3. Update user balance ledger and checkpoint timestamp (auto-compounds rewards) [1]
        userBalances[msg.sender][token] = previousBalance + amount + rewards;
        lastInteracted[msg.sender][token] = block.timestamp;

        // 4. Emit event tracking the deposit, rate, and newly accrued rewards [1]
        IEvents.Data[] memory eventData = new IEvents.Data[](7);
        eventData[0] = IEvents.Data("user", "address", abi.encode(msg.sender));
        eventData[1] = IEvents.Data("amount", "uint256", abi.encode(amount));
        eventData[2] = IEvents.Data("token", "string", abi.encode(assetName));
        eventData[3] = IEvents.Data("provider", "string", abi.encode(providerName));
        eventData[4] = IEvents.Data("timestamp", "uint256", abi.encode(block.timestamp));
        eventData[5] = IEvents.Data("rate", "uint256", abi.encode(rate));
        eventData[6] = IEvents.Data("rewards", "uint256", abi.encode(rewards)); // Records accrued interest [3]

        events.emitVaultEvent("Deposit", eventData);
        emit Deposit(msg.sender, token, amount, providerName);
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