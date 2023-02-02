# A Managed 4626 Vault

### This is a vault where users can deposit WETH (or any given ERC20 asset) to be managed by a singular authority known as the operator. Though as far as I can tell, a multi-sig or DAO vote could easily be configured to execute all of the operator's tasks.

### The operator decides when to allow users to deposit and withdraw from the vault. When these interactions are disabled, the vault's assets are elsewhere, in a vault strategy contract farming yield. The operator also creates the vault strategy contracts which are meant to function as zap contracts and leverage DEFI legos to farm the greatest yield for the vault's users.
Testing Steps
1. Deploy Vault
	Constructer takes: 
				WETH Address,
				Name for our ERC20 vault token,
				Token for our ERC20 vault token,
  Verify Vault on Etherscan.

2. Deploy Strategy
	Set the hardcoded vault and WETH addresses in Constructer before deployment
   Verify Strategy on Etherscan.


3. Simulate a basic user interaction (entering into vault position)
	User first calls an approval() on the WETH contract to approve the vault for x amount of WETH
		(Yes we are using manual approval, approval can always be done on the website 

	User then calls deposit() (or mint if denominating in shares)
	Ensure that this call properly updates underlying. 


4. Configure the strategy by calling changeStrategy() with the deployed strategies's address


5. Lock interaction with the vault by calling updateInteractions() with a value of false.
	Attempt to call: deposit(), mint(), redeem(), withdraw() to confirm they are not possible. 


4. Simulate strategy interaction
	Strategies would normally be automated with multiple layers.
	These calls are the core logic for but would be used in larger functions meant to zap into a strategy.

	Ensure that conventional users cannot call strategy functions.
	
	Call getAssetsFromVaultTest() which calls the internal function of 'getAssetsFromVault'
	This sends a call to the Vault contract to then execute a function which sends the strategy all of the vault's assets.
Make sure this properly updates the 'underlying_in_strategy' value held by the vault

	Send the strategy a given amount of the asset just using basic blockchain transfer calls on metamask
	This is meant to simulate yield accrued in a vault strategy.
	
	Call returnAssetsToVaultTest() which calls the internal function of "returnAssetsToVault'
	This sends a call to the Vault contract to then execute a function which sends the vault all of the strategies assets.
Make sure this properly updates the 'underlying_in_strategy' value held by the vault


5. Unlock interaction with the vault by calling updateInteractions() with a value of true


6. Simulate users entering and withdrawing
	Repeat Step 3 with a new user
		Ensure that the vault shares are still proportional.

	Now, withdraw some of the original user's assets. 
		Ensure that withdrawal correctly updates underlying.
		Ensure that the vault shares are still proportional 

//CONCERN: users depositing and entering in the same block? This shouldn't be an issue?


Some security measures to check using a secondary address:
Ensure nobody but the vault operator can call:
	changeOperator()
	changeStrategy()
	updateUnderlying()
	transferFundsBackFromStrategy()
	transferFundsToStrategy()
	transferFundsBackFromStrategyInteraction() //?? this one is an unknown if I will use it
