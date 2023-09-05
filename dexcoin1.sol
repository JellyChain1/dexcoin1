// SPDX-License-Identifier: GNU
    pragma solidity ^0.8.0;

    contract DEXCoin1 {
    string public name = "DEX Coin 1";
    string public symbol = "DEX1";
    uint8 public decimals = 6;
    uint256 public totalSupply = 100000000 * (10 ** 6);

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => uint256) private _lastClaimedTime;
    mapping(address => bool) private _royaltiesPaused;
    mapping(address => bool) private blacklistedAddresses;
    mapping(address => uint256) private _lastClaimedTokenId;
    mapping(address => uint256) public monthlySales;
    mapping(address => uint256) public lastPurchaseTimestamp;
    mapping(address => uint256) private _lastTokenAcquisitionTime;

    address public owner;

    uint256 public claimInterval = 30 days; // Claim interval for users
    uint256 public claimAmount = 50 * (10 ** 6); // 50 DEX Coin per claim
    uint256 public mintRate = 1670000 * 1 days;// 1.67 token per day
    uint256 public inflationCap = 2000000 * (10 ** 6); // 2% inflation cap
    uint256 private tokenIdCounter;
    uint256 private lastRoyaltyMintTime;
    uint256 private totalMintedTokens;
    uint256 private lastInflationCheckTime;
    uint256 private inflationCheckInterval = 8 hours; // Or as needed
    uint256 public dexCoinPrice; // Price of DEX Coin in terms of USDC

    bool private automaticMintingStarted;
    bool public isMintingPaused;
    bool public contractDisabled;
    
    event RoyaltiesPaused(address indexed account);
    event RoyaltiesResumed(address indexed account);
    event AddressBlocked(address indexed user);
    event AddressUnblocked(address indexed user);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event DexCoinPriceUpdated(uint256 newPrice);
    event TokensAcquired(address indexed account, uint256 acquisitionTime);
    event USDCPurchased(address indexed buyer, uint256 dexCoinsSold, uint256 usdcReceived, uint256 fee);

    constructor() {
        owner = msg.sender;
        balanceOf[msg.sender] = totalSupply;
        lastRoyaltyMintTime = block.timestamp;
        lastInflationCheckTime = block.timestamp;
        automaticMintingStarted = true; // Automatically start minting royalties
    }

    function _transfer(
    address sender,
    address recipient,
    uint256 amount
) internal notBlacklisted {
    require(sender != address(0), "Invalid sender address");
    require(recipient != address(0), "Invalid recipient address");
    require(amount > 0, "Transfer amount must be greater than zero");
    require(balanceOf[sender] >= amount, "Insufficient balance");

    balanceOf[sender] -= amount;
    balanceOf[recipient] += amount;

    emit Transfer(sender, recipient, amount); // Emit the Transfer event
}

    function transfer(address recipient, uint256 amount) public onlyTokenHolder notBlacklisted {
    _transfer(msg.sender, recipient, amount);
}


    function _mint(address account, uint256 amount) internal mintingNotPaused notBlacklisted {
        require(account != address(0), "Invalid account address");
        require(amount > 0, "Mint amount must be greater than zero");

        balanceOf[account] += amount;
        totalSupply += amount;

        emit Transfer(address(0), account, amount); // Emit Transfer event for minting
    }

    // Function to pause royalties for a specific address
    function pauseRoyalties(address account) external onlyOwner {
        _royaltiesPaused[account] = true;
        emit RoyaltiesPaused(account);
    }

    // Function to resume royalties for a specific address
    function resumeRoyalties(address account) external onlyOwner {
        _royaltiesPaused[account] = false;
        emit RoyaltiesResumed(account);
    }

    function _mintRoyalty(address account) internal mintingNotPaused notBlacklisted royaltiesNotPaused(account) {
    require(account != address(0), "Invalid account address");
    require(balanceOf[account] >= 50 * (10 ** 6), "Insufficient DEX Coins to mint"); // Require at least 50 DEX Coins

    tokenIdCounter++;
    balanceOf[account]++;
    totalMintedTokens++;

}

    function pauseMinting() external onlyOwner {
        isMintingPaused = true;
    }

    function resumeMinting() external onlyOwner {
        isMintingPaused = false;
    }

    function controlInflationIfNeeded() external onlyOwner {
    require(block.timestamp >= lastInflationCheckTime + inflationCheckInterval, "It's not time to check inflation yet");
    lastInflationCheckTime = block.timestamp;

    if (totalMintedTokens > inflationCap) {
        uint256 excessTokens = totalMintedTokens - inflationCap;
        uint256 tokensToBurn = excessTokens;

        // Burn excess tokens to reduce inflation
        _burn(owner, tokensToBurn);
        totalMintedTokens -= tokensToBurn;
    }
}

    function approveDEX(address dexAddress, uint256 amount) external onlyOwner {
        require(dexAddress != address(0), "Invalid dex address");
        allowance[owner][dexAddress] = amount;
    }

    function allocateToDEX(address dexAddress, uint256 amount) external onlyOwner {
        require(dexAddress != address(0), "Invalid dex address");
        require(balanceOf[address(this)] >= amount, "Insufficient pool balance");

        _transfer(address(this), dexAddress, amount);
    }

    function getMonthlySales() external view onlyTokenHolder notBlacklisted returns (uint256) {
    return monthlySales[msg.sender];
}

    function getAccumulatedRoyalty() external view notBlacklisted onlyTokenHolder returns (uint256) {
        return tokenIdCounter - _lastClaimedTokenId[msg.sender];
    }

    function getPoolBalance() external view notBlacklisted returns (uint256) {
        return balanceOf[address(this)];
    }

    function claim() external onlyTokenHolder mintingNotPaused notBlacklisted {
    require(balanceOf[msg.sender] >= 50 * (10 ** 6), "You must hold at least 50 DEX Coins to claim");
    require(balanceOf[msg.sender] > 0, "You must hold tokens to claim");

    if (_lastClaimedTime[msg.sender] == 0 || block.timestamp >= _lastClaimedTime[msg.sender] + claimInterval) {
        // If user hasn't claimed before or the waiting period has passed, proceed
        _lastClaimedTime[msg.sender] = block.timestamp; // Update last claim time
        _mint(msg.sender, claimAmount); // Mint claimAmount tokens to the sender
    } else {
        revert("It's not time to claim yet"); // Regular claim waiting period has not passed
    }
}

    function setDexCoinPrice(uint256 _price) external onlyOwner {
    dexCoinPrice = _price;
    emit DexCoinPriceUpdated(_price);
}

    function buyDexCoinsWithUSDC(uint256 dexCoinsToBuy) external notBlacklisted {
    // Calculate the amount of USDC to be paid based on dexCoinPrice
    uint256 usdcAmountToPay = dexCoinsToBuy * dexCoinPrice;

    // Check if the user has enough USDC balance
    require(balanceOf[msg.sender] >= usdcAmountToPay, "Insufficient USDC balance");

    // Transfer USDC from user to the contract
    _transfer(msg.sender, address(this), usdcAmountToPay);

    // Calculate the equivalent amount of DEX Coins to mint if the contract doesn't have enough DEX Coins
    uint256 requiredDexCoins = usdcAmountToPay / dexCoinPrice;

    // Calculate the amount to mint
    uint256 amountToMint = requiredDexCoins > balanceOf[address(this)] ? requiredDexCoins - balanceOf[address(this)] : 0;

    // Mint the required DEX Coins if needed
    if (amountToMint > 0) {
        _mint(address(this), amountToMint);
    }

    // Transfer the purchased DEX Coins to the user
    _transfer(address(this), msg.sender, dexCoinsToBuy);
}

    function buyUSDCWithDEXCoins(uint256 dexCoinsToSell) external onlyTokenHolder notBlacklisted {
    require(dexCoinPrice > 0, "DEX Coin price not set");
    require(dexCoinsToSell > 0, "Amount of DEX Coins to sell must be greater than zero");

    // Calculate the amount of USDC to receive based on dexCoinPrice
    uint256 usdcAmountToReceive = dexCoinsToSell * dexCoinPrice;

    // Calculate the 2% fee amount
    uint256 usdcFee = (usdcAmountToReceive * 2) / 100; // 2% fee

    // Calculate the net USDC amount after deducting the fee
    uint256 netUsdcAmount = usdcAmountToReceive - usdcFee;

    // Check if the contract has enough USDC balance (including the fee)
    require(balanceOf[address(this)] >= usdcAmountToReceive, "Sold Out");

    // Check if the user has enough DEX Coin balance
    require(balanceOf[msg.sender] >= dexCoinsToSell, "Insufficient DEX Coin balance");

    // Check if the user has at least 6000 DEX coins to make the purchase
    require(balanceOf[msg.sender] >= 6000 * (10 ** 6), "Minimum 6000 DEX coins required");

    // Get the timestamp of the last purchase for the user
    uint256 lastPurchaseTime = lastPurchaseTimestamp[msg.sender];

    // Check if 30 days have passed since the last purchase
    require(block.timestamp >= lastPurchaseTime + 30 days, "It's Not Time Yet");

    // Check if the user's monthly sales limit has been reached
    require(monthlySales[msg.sender] + netUsdcAmount <= 6000 * dexCoinPrice, "Sales Limit Reached");

    // Deduct the DEX Coins from the user and transfer to the contract
    _transfer(msg.sender, address(this), dexCoinsToSell);

    // Transfer USDC (with fee deduction) from the contract to the user
    _transfer(address(this), msg.sender, netUsdcAmount);

    // Transfer the fee amount to the contract owner
    _transfer(address(this), owner, usdcFee);

    // Update the monthly sales counter and the last purchase timestamp
    monthlySales[msg.sender] += netUsdcAmount;
    lastPurchaseTimestamp[msg.sender] = block.timestamp;

    // Emit an event indicating the successful purchase
    emit USDCPurchased(msg.sender, dexCoinsToSell, netUsdcAmount, usdcFee);
}

    function getTokenAcquisitionTime(address user) external view onlyOwner returns (uint256) {
    require(user != address(0), "Invalid user address");
    return _lastTokenAcquisitionTime[user];
}

    function blockAddress(address user) external onlyOwner {
        require(user != address(0), "Invalid user address");
        require(!blacklistedAddresses[user], "Address is already blacklisted");

        blacklistedAddresses[user] = true;
        emit AddressBlocked(user);
    }

    function unblockAddress(address user) external onlyOwner {
        require(user != address(0), "Invalid user address");
        require(blacklistedAddresses[user], "Address is not blacklisted");

        blacklistedAddresses[user] = false;
        emit AddressUnblocked(user);
    }

   function mintFreshDexCoins(uint256 amountToMint) external mintingNotPaused onlyOwner {
    // Ensure the minting amount is positive
    require(amountToMint > 0, "Mint amount must be greater than zero");

    // Mint the specified amount of DEX Coins and add to the owner's balance
    _mint(owner, amountToMint);
}

    function mintFreshDEXCoinsToAccount(address account, uint256 amountToMint) external onlyOwner mintingNotPaused {
    require(account != address(0), "Invalid account address");
    require(amountToMint > 0, "Mint amount must be greater than zero");

    // Mint the specified amount of DEX Coins and add to the account's balance
    _mint(account, amountToMint);
}

    function burn(uint256 amount) external onlyOwner {
    require(amount > 0, "Amount to burn must be greater than zero");
    require(balanceOf[msg.sender] >= amount, "Insufficient balance");

    balanceOf[msg.sender] -= amount;
    totalSupply -= amount;
}

    function burnFrom(address account, uint256 amount) external onlyOwner {
    require(amount > 0, "Amount to burn must be greater than zero");
    require(balanceOf[account] >= amount, "Insufficient balance");
    require(allowance[account][msg.sender] >= amount, "Allowance exceeded");

    balanceOf[account] -= amount;
    totalSupply -= amount;
    allowance[account][msg.sender] -= amount;
}

function _burn(address account, uint256 amount) internal {
    require(account != address(0), "Invalid account address");
    require(balanceOf[account] >= amount, "Insufficient balance");

    balanceOf[account] -= amount;
    totalSupply -= amount;

    emit Transfer(account, address(0), amount); // Emit event for token burn
}

    modifier royaltiesNotPaused(address account) {
    require(!_royaltiesPaused[account], "Royalties are paused for this address");
    _;
}

    modifier mintingNotPaused() {
    require(!isMintingPaused, "Minting is paused");
    _;
}

    modifier onlyTokenHolder() {
        require(balanceOf[msg.sender] > 0, "Only token holder allowed");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only contract owner allowed");
        _;
    }

    modifier notBlacklisted() {
        require(!blacklistedAddresses[msg.sender], "You are blacklisted and cannot perform this action");
        _;
    }

    modifier notDisabled() {
        require(!contractDisabled, "Contract is disabled");
        _;
    }

    //One Time Only Function
    function emergencyKill() external onlyOwner {
        // Send all USDC held by the contract to the sender
        uint256 usdcBalance = balanceOf[address(this)];
        require(usdcBalance > 0, "No USDC balance to withdraw");
        
        _transfer(address(this), msg.sender, usdcBalance);

        // Disable the contract
        contractDisabled = true;
    }
}