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


/// @notice Minimal ERC4626 tokenized Vault implementation.
/// @author Solmate (https://github.com/transmissions11/solmate/blob/main/src/mixins/ERC4626.sol)
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
    address strategy; //The current vault strategy
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

    //Make sure only the operator can use a given function
    modifier onlyOperator() {
        require(msg.sender == operator, "You aren't the operator.");
        _;
    }

    //Make sure only the vault's strategy contract can call this function
     modifier onlyStrategy() {
        require(msg.sender == strategy, "You aren't the current vault strategy");
        _;
    }

    //Make sure user interactions are currently allowed. 
    modifier interactControlled() {
        require(canInteract == true, "Interactions with this vault are currently locked");
        _;
    }

    //Just a public function to see the current vault's representation of its underlying while in limbo
    function checkUnderlying() public view returns (uint256) {
        return underlying_in_strategy;
    }

    //Just a way to see the current vault strategy
    function checkStrategy() public view returns (address) {
        return strategy;
    }

    /* 
        NOTE:
        NEED TO UPDATE UNDERLYING EVERYTIME A WITHDRAWAL AND DEPOSIT IS MADE
    This should now be implemented.
    */

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    //Enter the strategy by depositing x amount of assets to receive a given amount of vault share
    //This interaction is controlled by the vault operator
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

    //Enter the strategy by deciding to mint x amount of vault shares from your assets
    //This interaction is controlled by the vault operator
    function mint(uint256 shares, address receiver) public interactControlled returns (uint256 assets) {
        assets = previewMint(shares); // No need to check for rounding error, previewMint rounds up.

        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);
    
        _updateUnderlying(); //Update the underlying value in the system

        emit Deposit(msg.sender, receiver, assets, shares);

        afterDeposit(assets, shares);
    }

    //Withdraw assets based on a number of shares
    //This interaction is controlled by the vault operator
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

    //Redeem x amount of assets from your shares
    //This interaction is controlled by the vault operator
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
                            ACCOUNTING AND ADMIN LOGIC
    //////////////////////////////////////////////////////////////*/


    /*////////////////  Admin Logic: /////////////////////*/
            //While the vault is in limbo....(the actual wETH is within some external strategy)...the user's share values are determined by 'underlying_in_strategy'
            //When the vault is pulled out of limbo and the vault is holding its assets call 'updateUnderyling'
            //The share values are updated to include the yield generated while in limbo.

    //Non-standard - change the vault's operator
    function changeOperator(address op) public onlyOperator()
    {
     operator = op;
    }

    //Non-standard - update the vault representation of it's current assets
    //The vault holds a value representing its assets while these assets have been transferred away
    //Upon re-transferring these assets.....update this value to do accurate share depositing and withdrawing
    //DO NOT ALLOW FOR VAULT INTERACTIONS BEFORE PROPERLY UPDATING THE UNDERLYING VALUE
    function updateUnderlying() public onlyOperator()
    {
     _updateUnderlying();
    }

    //Non-standard - update the vault's representation of it's current assets
    //Internal call so that way other functions can update the underlying
    function _updateUnderlying() internal 
    {
     underlying_in_strategy = asset.balanceOf(address(this)); 
    }

    //Non-standard - change whether or not the user can interact with the vault
    //If B is true...the user can interact with the vault and deposit and redeem
    function updateInteractions(bool b) public onlyOperator()
    {
     canInteract = b; 
    }

    //Non-standard - change the address of the vault strategy.
    //DO NOT CHANGE STRATEGY UNTIL THE OLD STRATEGY HAS BEEN PROPERLY LIQUIDATED
    function changeStrategy(address newStrat) public onlyOperator()
    {
      strategy = newStrat;
    }


    //Non-standard - called by the strategy to transfer all funds to the strategy. 
    function transferFundsToStrategy() public onlyStrategy()
    {
        _updateUnderlying(); //make sure we have the right underlying value.
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

    
    //To be honest Im concerned that some fuck wucky security issue could occur by allowing interactions in the same call.

// NOTE: The vault strategy contract MUST call an approval for all its assets before calling this function
    //Nonstandard - called by the strategy to transfer all funds to this vault and update underlying, then it allows user interactions
     function transferFundsBackFromStrategyInteraction(uint256 strategyBal) public onlyStrategy()
    {
        asset.safeTransferFrom(msg.sender, address(this), strategyBal); //transfer from the strategy (msg.sender) to this contract, all of the strategy's assets
        _updateUnderlying(); //Update the underlying value in this contract.
        canInteract = true;
    }



    /*////////////////  Accounting Logic: /////////////////////*/

    //Might remove this....Unsure if it is neccessary for vault movement interactions

    //ERC2626 standard for totalAssets() - returns the total amount of vault shares
    function totalAssets() public view returns (uint256)
    {
        uint256 supply = totalSupply; 
        return supply;
    }


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
        //Make sure the minter mints the right amount of shares for the total underyling amount of assets
        
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
