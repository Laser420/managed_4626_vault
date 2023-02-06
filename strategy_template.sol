// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

contract strategy_template {

    address vaultAddress; //
    IERC4626 vaultInterface;

    address assetAddress; //WETH address
    ERC20_WETH assetInterface; //WETH interface

    address ankrAddress; //ankrETH address
    ERC20_WETH ankrInterface; //ankrETH interface - just using the ERC20 interface already available

    address poolAddress;
    CurvePool poolInterface;

    address operator; //The vault's operator
    address newOperator; //A variable used for safer transitioning between vault operators


    constructor() {

        operator = msg.sender;

        /* ////////// Vault Specific Instantiations ////////// */
        vaultAddress = 0xd598930e2474fFa73f1E1f29746ddEA7D5976dC4; //set this to be the vault address
        vaultInterface = IERC4626(vaultAddress); //this initializes an interface with the vault
        

        assetAddress = 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6;//set this to be the vault's asset address
        assetInterface = ERC20_WETH(assetAddress); //this initializes an interface with the asset 
        //In this specific instance...the asset is WETH...the interface is Transmissions11's ERC20 interface with two WETH functions added
        //I am sorry for butchering your boy lord Solmate.
        //Key concern...will my modified solmate ERC20 interface work?

        ankrAddress = 0x0000000000000000000000000000000000000000; //set this to be the ankrETH asset address
        ankrInterface = ERC20_WETH(ankrAddress); //ERC20 interface for ankrETH
        

        poolAddress = 0x0000000000000000000000000000000000000000; //set this to be the curve pool's address
        poolInterface = CurvePool(poolAddress); //this initializes an interface to the curve Pool
         /* ////////// Vault Specific Instantiations ////////// */
    }

    /*////// Operator functions and modifiers ///// */

    modifier onlyOperator() {
        require(msg.sender == operator, "You aren't the operator.");
        _;
    }

    //Make sure only the address set in the newOperator variable can use a given function
    modifier onlyNewOperator() {
        require(msg.sender == newOperator, "You aren't the new operator.");
        _;
    }

    function setNewOperator(address op) public onlyOperator()
    {
     newOperator = op;
    }

    //Non-standard - called by the newOperator address to officialy take over control as the new vault operator
    function changeToNewOperator() public onlyNewOperator(){
        operator = newOperator;
    }

    /*////// Operator functions ///// */


    /* ////////// Vault Interactions - Internal functions ////////// */

    //Send all of the vault's assets to this strategy
    // This should be it. The function is meant to be a one stop shop.
    // Inshallah this will work.
    function getAssetsFromVault() internal {
        vaultInterface.transferFundsToStrategy();
    }

    //Send all of the assets that the strategy has back to the vault
    //This should only be called after the strategy has unwrapped itself from whatever DEFI legos it was in
    function returnAssetsToVault() internal {
        uint256 totalAssets = assetInterface.balanceOf(address(this)); //Get the amount of asset that this strategy contract has
        assetInterface.approve(vaultAddress, totalAssets); //Approve the vault to interact with this amount
        vaultInterface.transferFundsBackFromStrategy(totalAssets); //Call the vault function that withdraws this amount from this strategy contract
    }

     /* ////////// END Vault Interactions - Internal functions ////////// */


    /*/////////// Vault Executions  //////////////*/

//Does a function that isn't payable.....does it allow for calling payable functions within it?
//Essentially....do I need to allocate gas somewhere in here for this exchange function to work?
//I cannot remember that being neccessary since it is a interface call to a payable function...not an address to address transfer call

//Enter the strategy
    function executeStrategyEnter () public onlyOperator {

        getAssetsFromVault(); //Get assets from the vault - WETH from vault

        uint256 balance = assetInterface.balanceOf(address(this)); //Get the strategy's new balance of WETh

        assetInterface.withdraw(balance); //Unwrap assets - WETH into ETH - 
        //The asset from the vault is WETH...so we call withdraw on the asset Interface to get raw ETH

        uint256 expected = (poolInterface.get_dy(0, 1, address(this).balance ) / 10000) * 9750; 
        //Get this contract's new balance of raw WETH, and calculate an expected value for the curve swap with 250 bps allowance

        poolInterface.exchange {value: address(this).balance} (0,1, address(this).balance, expected);
        //Call the curve pool exchange function with a msg.value of the strategy's ETH balance
        //Swapping pool coin 0 (ETH) with pool coin 1 (ankrETH), the amount is the same as the msg.value, and expected is seen above
    }

//Exit the strategy
    function executeStrategyExit () public onlyOperator {
        uint256 expected = ( poolInterface.get_dy( 1, 0, ankrInterface.balanceOf(address(this))  ) / 10000 ) * 9750; 
        //Get this contract's balance of ankrETH, and calculate an expected value for the curve swap with 250 bps allowance

        ankrInterface.approve(poolAddress, ankrInterface.balanceOf(address(this)));
        //Call an approval for the pool to use this ankrETH ERC20

        poolInterface.exchange {value: 0} ( 1 , 0 , ankrInterface.balanceOf(address(this)), expected);
        //Call the curve pool exchange function with a msg.value of 0 to exchange all of this contract's 
        //Swapping pool coin 1 (ankrETH) with pool coin 0 (ETH), the total ankrETH balance of this contract

        assetInterface.deposit {value: address(this).balance};
        //Deposit all of this recently acquired ETH into the WETH contract.

        returnAssetsToVault(); //Return all of these assets to the vault.
    }

    //This function sends this vault's ankrETH to whatever address is the vault's current strategy
    //FOR THE LOVE OF GOD....ENSURE THAT THIS OTHER STRATEGY IS CAPABLE OF HANDLING AnkrETH
    //Call this after changing strategies....
    //if the new strategy cannot handle ankrETH then first call executeStrategyExit
    function sendAnkrETHToNewStrategy() public onlyOperator {
        address strat = vaultInterface.checkStrategy();
        ankrInterface.transfer(strat, ankrInterface.balanceOf(address(this)));
    }
 
    //Begin changing strategies by setting a new strategy address
    function beginStrategyChange(address newStrat) public onlyOperator {
        vaultInterface.beginStrategyChangeStrat(newStrat);
    }

    //Confirm this is the new strategy to switch to
    function confirmNewStrategy() public onlyOperator {
        vaultInterface.completeStrategyChange();
    }

    /*/////////// END Vault Executions  //////////////*/

    //After this works...implement functional ownership of strategies...
    //Also ensure proper ownership of the vault

    /* PLANNING FOR TRANSFERRING ASSETS DIRECTLY STRATEGY TO STRATEGY:
    Vault has another address variable: newStrategy
        Ability to see this address through a checker function on the vault
    Vault then has a function: newStrategyChange
        This sets a new newStrategy address

    This strategy has a function that can be called by only the newStrategy address
        Using a modifier checking if the caller matches the newStrategy set on the vault
    This function sends the newStrategy all of the strategy's assets
    */

}

interface CurvePool {
    //Get the coins in the pool
    function coins (uint256 arg) external view returns(address);

    //"Get the amount of coin j one would receive for swapping _dx of coin i."
    function get_dy (int128 i, int128 j, uint256 dx) external view returns (uint256);

    //Get the amount of dx you would need to swap in order to obtain dy of the other coin
    function get_dx (int128 i, int128 j, uint256 dy) external view returns (uint256);
    
    /*Perform an exchange between two coins.
        i: Index value for the coin to send
        j: Index value of the coin to receive
        _dx: Amount of i being exchanged
        _min_dy: Minimum amount of j to receive
    Returns the actual amount of coin j received. 
      To get _min_dy ....take the value of get_dy and do the slippage math
    */// This function is external BUT PAYABLE ONLY FOR THIS SPECIFIC TYPE OF CURVE POOL
    function exchange (int128 i, int128 j, uint256 _dx ,uint256 _min_dy) payable external;

}

pragma solidity >=0.8.0;

/// @notice Modern and gas efficient ERC20 + EIP-2612 implementation.
/// @author Solmate (https://github.com/transmissions11/solmate/blob/main/src/tokens/ERC20.sol)
/// @author Modified from Uniswap (https://github.com/Uniswap/uniswap-v2-core/blob/master/contracts/UniswapV2ERC20.sol)
/// @dev Do not manually set balances without updating totalSupply, as the sum of all user balances must not exceed it.
abstract contract ERC20_WETH {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Transfer(address indexed from, address indexed to, uint256 amount);

    event Approval(address indexed owner, address indexed spender, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                            METADATA STORAGE
    //////////////////////////////////////////////////////////////*/

    string public name;

    string public symbol;

    uint8 public immutable decimals;

    /*//////////////////////////////////////////////////////////////
                              ERC20 STORAGE
    //////////////////////////////////////////////////////////////*/

    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;

    mapping(address => mapping(address => uint256)) public allowance;

    /*//////////////////////////////////////////////////////////////
                            EIP-2612 STORAGE
    //////////////////////////////////////////////////////////////*/

    uint256 internal immutable INITIAL_CHAIN_ID;

    bytes32 internal immutable INITIAL_DOMAIN_SEPARATOR;

    mapping(address => uint256) public nonces;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;

        INITIAL_CHAIN_ID = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = computeDomainSeparator();
    }

    /*//////////////////////////////////////////////////////////////
                               ERC20 LOGIC
    //////////////////////////////////////////////////////////////*/

    function approve(address spender, uint256 amount) public virtual returns (bool) {
        allowance[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);

        return true;
    }

    function transfer(address to, uint256 amount) public virtual returns (bool) {
        balanceOf[msg.sender] -= amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(msg.sender, to, amount);

        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual returns (bool) {
        uint256 allowed = allowance[from][msg.sender]; // Saves gas for limited approvals.

        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;

        balanceOf[from] -= amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(from, to, amount);

        return true;
    }

    /*//////////////////////////////////////////////////////////////
                             EIP-2612 LOGIC
    //////////////////////////////////////////////////////////////*/

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual {
        require(deadline >= block.timestamp, "PERMIT_DEADLINE_EXPIRED");

        // Unchecked because the only math done is incrementing
        // the owner's nonce which cannot realistically overflow.
        unchecked {
            address recoveredAddress = ecrecover(
                keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        DOMAIN_SEPARATOR(),
                        keccak256(
                            abi.encode(
                                keccak256(
                                    "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                                ),
                                owner,
                                spender,
                                value,
                                nonces[owner]++,
                                deadline
                            )
                        )
                    )
                ),
                v,
                r,
                s
            );

            require(recoveredAddress != address(0) && recoveredAddress == owner, "INVALID_SIGNER");

            allowance[recoveredAddress][spender] = value;
        }

        emit Approval(owner, spender, value);
    }

    function DOMAIN_SEPARATOR() public view virtual returns (bytes32) {
        return block.chainid == INITIAL_CHAIN_ID ? INITIAL_DOMAIN_SEPARATOR : computeDomainSeparator();
    }

    function computeDomainSeparator() internal view virtual returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                    keccak256(bytes(name)),
                    keccak256("1"),
                    block.chainid,
                    address(this)
                )
            );
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL MINT/BURN LOGIC
    //////////////////////////////////////////////////////////////*/

    function _mint(address to, uint256 amount) internal virtual {
        totalSupply += amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal virtual {
        balanceOf[from] -= amount;

        // Cannot underflow because a user's balance
        // will never be larger than the total supply.
        unchecked {
            totalSupply -= amount;
        }

        emit Transfer(from, address(0), amount);
    }


    //I am so sorry Transmissions11 but I need this interface specifically for WETH...forgive me father
    
    //WETH Deposit function
    function deposit () external payable virtual;

    //WETH Withdraw function
    function withdraw (uint256 amt) external virtual; 

}


pragma solidity >=0.8.0;

/// @title ERC4626 interface
/// See: https://eips.ethereum.org/EIPS/eip-4626
abstract contract IERC4626 is ERC20_WETH {
    /*////////////////////////////////////////////////////////
                      Events
    ////////////////////////////////////////////////////////*/

    /// @notice `sender` has exchanged `assets` for `shares`,
    /// and transferred those `shares` to `receiver`.
    event Deposit(address indexed sender, address indexed receiver, uint256 assets, uint256 shares);

    /// @notice `sender` has exchanged `shares` for `assets`,
    /// and transferred those `assets` to `receiver`.
    event Withdraw(address indexed sender, address indexed receiver, uint256 assets, uint256 shares);

    /*////////////////////////////////////////////////////////
                      Vault properties
    ////////////////////////////////////////////////////////*/

    /// @notice The address of the underlying ERC20 token used for
    /// the Vault for accounting, depositing, and withdrawing.
    function asset() external view virtual returns (address asset);

    /// @notice Total amount of the underlying asset that
    /// is "managed" by Vault.
    function totalAssets() external view virtual returns (uint256 totalAssets);

    //Begin the strategy change...called here if this is the old contract
    function beginStrategyChangeStrat(address newStrat) external virtual;

    //Complete the strategy change...called here if this is the new contract
    function completeStrategyChange() external virtual;

    /*////////////////////////////////////////////////////////
                     Admin/Deposit/Withdrawal Logic
    ////////////////////////////////////////////////////////*/

    //CHANGE STRATEGY FUNCTIONS NEEDED HERE

    //Non-standard - called by the strategy to transfer all funds to the strategy. 
    //This call has a modifier on it to make sure only the strategy contract can call it
        //This could be external?
        //Virtual?
    function transferFundsToStrategy() public virtual ;

    //Nonstandard - called by the strategy to transfer all funds to this vault and update underlying
     //This call has a modifier on it to make sure only the strategy contract can call it
    function transferFundsBackFromStrategy(uint256 strategyBal) public virtual;

    /// @notice Mints `shares` Vault shares to `receiver` by
    /// depositing exactly `assets` of underlying tokens.
    function deposit(uint256 assets, address receiver) external virtual returns (uint256 shares);

    /// @notice Mints exactly `shares` Vault shares to `receiver`
    /// by depositing `assets` of underlying tokens.
    function mint(uint256 shares, address receiver) external virtual returns (uint256 assets);

    /// @notice Redeems `shares` from `owner` and sends `assets`
    /// of underlying tokens to `receiver`.
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) external virtual returns (uint256 shares);

    /// @notice Redeems `shares` from `owner` and sends `assets`
    /// of underlying tokens to `receiver`.
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external virtual returns (uint256 assets);

    /*////////////////////////////////////////////////////////
                      Vault Accounting Logic
    ////////////////////////////////////////////////////////*/

    //Just a public function to see the current vault's representation of its underlying while in limbo
    function checkUnderlying() public view virtual returns (uint256);

    //Just a way to see the current vault strategy
    function checkStrategy() public view virtual returns (address);


    /// @notice The amount of shares that the vault would
    /// exchange for the amount of assets provided, in an
    /// ideal scenario where all the conditions are met.
    function convertToShares(uint256 assets) external view virtual returns (uint256 shares);

    /// @notice The amount of assets that the vault would
    /// exchange for the amount of shares provided, in an
    /// ideal scenario where all the conditions are met.
    function convertToAssets(uint256 shares) external view virtual returns (uint256 assets);

    /// @notice Total number of underlying assets that can
    /// be deposited by `owner` into the Vault, where `owner`
    /// corresponds to the input parameter `receiver` of a
    /// `deposit` call.
    function maxDeposit(address owner) external view virtual returns (uint256 maxAssets);

    /// @notice Allows an on-chain or off-chain user to simulate
    /// the effects of their deposit at the current block, given
    /// current on-chain conditions.
    function previewDeposit(uint256 assets) external view virtual returns (uint256 shares);

    /// @notice Total number of underlying shares that can be minted
    /// for `owner`, where `owner` corresponds to the input
    /// parameter `receiver` of a `mint` call.
    function maxMint(address owner) external view virtual returns (uint256 maxShares);

    /// @notice Allows an on-chain or off-chain user to simulate
    /// the effects of their mint at the current block, given
    /// current on-chain conditions.
    function previewMint(uint256 shares) external view virtual returns (uint256 assets);

    /// @notice Total number of underlying assets that can be
    /// withdrawn from the Vault by `owner`, where `owner`
    /// corresponds to the input parameter of a `withdraw` call.
    function maxWithdraw(address owner) external view virtual returns (uint256 maxAssets);

    /// @notice Allows an on-chain or off-chain user to simulate
    /// the effects of their withdrawal at the current block,
    /// given current on-chain conditions.
    function previewWithdraw(uint256 assets) external view virtual returns (uint256 shares);

    /// @notice Total number of underlying shares that can be
    /// redeemed from the Vault by `owner`, where `owner` corresponds
    /// to the input parameter of a `redeem` call.
    function maxRedeem(address owner) external view virtual returns (uint256 maxShares);

    /// @notice Allows an on-chain or off-chain user to simulate
    /// the effects of their redeemption at the current block,
    /// given current on-chain conditions.
    function previewRedeem(uint256 shares) external view virtual returns (uint256 assets);
}
