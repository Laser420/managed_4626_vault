/*
NOTE: I DEPLOY THE FLATTENED VERSION OF THIS CONTRACT WHERE ALL OF THE IMPORTED CONTRACTS ARE ALL ON THE SAME FILE.
But for reviewing just the 4626 functionality, this contract works fine. 
I don't want to subject others to scanning through three of Transmissions11's contracts before getting to my chaos.
Here in this contract we just take those as gospel and pray they work.

*/

// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {ERC20} from "https://github.com/transmissions11/solmate/blob/main/src/tokens/ERC20.sol";
import {SafeTransferLib} from "https://github.com/transmissions11/solmate/blob/main/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "https://github.com/transmissions11/solmate/blob/main/src/utils/FixedPointMathLib.sol";

/// @notice Manually Operated 4626 Yield Vault
/// @author Laser420 with ERC4626 template sourced from transmissions11's Solmate library

   contract ERC4626 is ERC20 {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);

    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    /*//////////////////////////////////////////////////////////////
                               IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    ERC20 public immutable asset;
    uint256 underlying_in_strategy; //Keep track of the vault's balance of the underlying asset
    address operator; //The vault's operator
    address newOperator; //A variable used for safer transitioning between vault operators
    address strategy; //The current vault strategy
    address newStrategy; //An address used for safer transitioning between strategies. 
    bool canInteract; //Manage when the user can interact with the vault

    constructor(
        ERC20 _asset, // 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6
        string memory _name, 
        string memory _symbol
    ) 
    ERC20(_name, _symbol, _asset.decimals()) 
    {
        asset = _asset; //the erc20 acting as our receipt token
        operator = msg.sender; //set the operator
        //Set the strategy contract up.
        canInteract = true; //Set whether or not the vault may be interacted with
    }

    /*//////////////////////////////////////////////////////////////
                               Modifiers
    //////////////////////////////////////////////////////////////*/

        //Make sure only the operator can use a given function
    modifier onlyOperator() {
        require(msg.sender == operator, "You aren't the operator.");
        _;
    }
        //Make sure only the address set in the newOperator variable can use a given function
    modifier onlyNewOperator() {
        require(msg.sender == newOperator, "You aren't the new operator.");
        _;
    }
        //Make sure only the vault's strategy contract can call this function
     modifier onlyStrategy() {
        require(msg.sender == strategy, "You aren't the current vault strategy");
        _;
    }

       //Make sure only the vault's strategy contract can call this function
     modifier onlyNewStrategy() {
        require(msg.sender == newStrategy, "You aren't the new vault strategy");
        _;
    }

        //Make sure user interactions are currently allowed. 
    modifier interactControlled() {
        require(canInteract == true, "Interactions with this vault are currently locked");
        _;
    }

    /*//////////////////////////////////////////////////////////////
                           Checker Functions
    //////////////////////////////////////////////////////////////*/

    // see the current vault's underlying representation (even when vault is in limbo)
    function checkUnderlying() public view returns (uint256) {
        return underlying_in_strategy;
    }

    function checkStrategy() public view returns (address) { //See the current vault strategy
        return strategy;
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    //Enter the strategy by depositing x amount of assets to receive a given amount of vault shares - interactControlled
    function deposit(uint256 assets, address receiver) public interactControlled returns (uint256 shares) {
        // Check for rounding error since we round down in previewDeposit.
        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");
        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);
        
        _updateUnderlying(); //Update the underlying value in the system

        emit Deposit(msg.sender, receiver, assets, shares);

        afterDeposit(assets, shares);
    }

    //Enter the strategy by deciding to mint x amount of vault shares from your assets - interactControlled
    function mint(uint256 shares, address receiver) public interactControlled returns (uint256 assets) {
        assets = previewMint(shares); // No need to check for rounding error, previewMint rounds up.
        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);
    
        _updateUnderlying(); //Update the underlying value in the system

        emit Deposit(msg.sender, receiver, assets, shares);

        afterDeposit(assets, shares);
    }

    //Withdraw assets based on a number of shares - interactControlled
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public interactControlled virtual returns (uint256 shares) {
        shares = previewWithdraw(assets); // No need to check for rounding error, previewWithdraw rounds up.

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        beforeWithdraw(assets, shares);

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
        
        asset.safeTransfer(receiver, assets);

        _updateUnderlying(); //Update the underlying value in the system
    }

    //Redeem x amount of assets from your shares - interactControlled
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public interactControlled returns (uint256 assets) {
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        // Check for rounding error since we round down in previewRedeem.
        require((assets = previewRedeem(shares)) != 0, "ZERO_ASSETS");

        beforeWithdraw(assets, shares);

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        asset.safeTransfer(receiver, assets);

        _updateUnderlying(); //Update the underlying value in the system
    }

    /*//////////////////////////////////////////////////////////////
                            Operator Logic
    //////////////////////////////////////////////////////////////*/

    //Non-standard - set the newOperator address - called by the current vault operator
    function setNewOperator(address op) public onlyOperator()
    {
     newOperator = op;
    }

    //Non-standard - called by the newOperator address to officialy take over control as the new vault operator
    function changeToNewOperator() public onlyNewOperator(){
        operator = newOperator;
    }

    //Non-standard - update the vault representation of it's current assets
    //External call for manually updating this value. Just in case. 
    //The vault holds a value representing its assets while these assets have been transferred away
    //Upon re-transferring these assets.....update this value for accurate share depositing and withdrawing
    //DO NOT ALLOW FOR VAULT INTERACTIONS BEFORE PROPERLY UPDATING THE UNDERLYING VALUE
    function updateUnderlying() public onlyOperator()
    {
     _updateUnderlying();
    }

    //Non-standard - update the vault's representation of it's current assets - internally callable
    //DO NOT ALLOW FOR VAULT INTERACTIONS BEFORE PROPERLY UPDATING THE UNDERLYING VALUE
    function _updateUnderlying() internal 
    {
     underlying_in_strategy = asset.balanceOf(address(this)); 
    }

//Non-standard - when B is set true users can deposit and redeem
    function updateInteractions(bool b) public onlyOperator()
    {
     canInteract = b; 
    }

/* Changing strategies:
    'beginStrategyChangeStrat' is called from the old strategy contract to set the newStrategy address.
    'beginStrategyChangeOp' is called from the operator to set the newStrategy address.
        This is used for when the vault is not in an active strategy and wants to upgrade to a new strategy.
    'completeStrategyChange' is called from the newStrategy and changes the strategy address variable to that address.

    //if the assets are unwrapped to be the vault native token...transfer assets when beginning to change strategies
    //if the assets are wrapped as something else....transfer them to the new strategy after the vault is updated
*/
    function beginStrategyChangeStrat(address newStrat) public onlyStrategy()
    {
      newStrategy = newStrat;
    }

    function beginStrategyChangeOp(address newStrat) public onlyOperator()
    {
      newStrategy = newStrat;
    }

    function completeStrategyChange() public onlyNewStrategy()
    {
      strategy = msg.sender;
    }

    /*//////////////////////////////////////////////////////////////
                     STRATEGY ACCESSED FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    //Non-standard - called by the strategy to transfer all funds to the strategy. 
    function transferFundsToStrategy() public onlyStrategy()
    {
        _updateUnderlying(); //make sure we have the right underlying value before transferring back
        asset.safeTransfer(strategy, underlying_in_strategy); //transfer all of the underlying funds to the strategy
    }

 // NOTE: The vault strategy contract MUST call an approval for all its assets before calling this function
    //Nonstandard - called by the strategy to transfer all funds to this vault and update underlying
    function transferFundsBackFromStrategy(uint256 strategyBal) public onlyStrategy()
    {
        // uint256 balanceOfStrategy = asset.balanceOf(msg.sender); //Get the strategy's balance of the asset
            /* had the strategy balance in a hard-coded check here but decided to make it something to input just in case */
        //Need to call an approval for this value
        asset.safeTransferFrom(msg.sender, address(this), strategyBal); //transfer from the strategy (msg.sender) to this contract, all of the strategy's assets
        _updateUnderlying(); //Update the underlying value in this contract.
    }

    /*//////////////////////////////////////////////////////////////
                     ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    function totalAssets() public view returns (uint256) //returns the total amount of vault shares
    {
        uint256 supply = totalSupply; 
        return supply;
    }
    /* //////////////////////////////////////////
    totalAssets() function is currently unused.
    The below functions reference the vault's total assets using 'underlying_in_strategy' variable
    Function names are still 4626 compliant. 
    //////////////////////////////////////////*/
    function convertToShares(uint256 assets) public view returns (uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.
        return supply == 0 ? assets : assets.mulDivDown(supply, underlying_in_strategy);
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.
        return supply == 0 ? shares : shares.mulDivDown(underlying_in_strategy, supply);
    }

    function previewDeposit(uint256 assets) public view returns (uint256) {
        return convertToShares(assets);
    }

    function previewMint(uint256 shares) public view returns (uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.
        return supply == 0 ? shares : shares.mulDivUp(underlying_in_strategy, supply);
        //Make sure the minter mints the right amount of shares for the underyling amount of assets
    }

    function previewWithdraw(uint256 assets) public view returns (uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.
        return supply == 0 ? assets : assets.mulDivUp(supply, underlying_in_strategy);
        //Give the user their percentage of the total underyling amount of vault assets.
    }

    function previewRedeem(uint256 shares) public view  returns (uint256) {
        return convertToAssets(shares);
    }

    /*//////////////////////////////////////////////////////////////
                     DEPOSIT/WITHDRAWAL LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

    function maxDeposit(address) public pure returns (uint256) { //pure because no blockchain data read
        return type(uint256).max; 
    }

    function maxMint(address) public pure returns (uint256) { //pure because no blockchain data read
        return type(uint256).max;
    }

    function maxWithdraw(address owner) public view returns (uint256) {
        return convertToAssets(balanceOf[owner]);
    }

    function maxRedeem(address owner) public view returns (uint256) {
        return balanceOf[owner];
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function beforeWithdraw(uint256 assets, uint256 shares) internal virtual {}

    function afterDeposit(uint256 assets, uint256 shares) internal virtual {}
}
