# A Managed 4626 Vault

### A vault where users can deposit any ERC20 asset to be managed by a singular authority known as the operator. The operator can be a DAO, multi-sig, singular individual, or other entity.

### The operator decides when to allow users to deposit and withdraw from the vault. When these interactions are disabled, the vault's assets are deployed in a yield strategy chosen by the operator.

#### An Optimism deployment is live: Interactions are currently unlocked as the strategy is not active. Aka. in theory you could invest if you were...Optimistic.

### System Deployment and Testing Steps
1. Deploy vault contract (flattened version).
2. Deploy strategy contract.
Note: both of these deployments are done through remix simply because I can (and not because I haven't properly learned Foundry yet)
3. Change the strategy.
	For the genesis strategy (fancy words) this is done using the operator function on the vault, afterwards strategy to strategy upgrades are possible.
4. Ensure calls meant for only the operator...can only be called by the Operator.
5. Ensure calls meant for only the vault...can only be called by the Vault.
6. Ensure calls located on the vault for the strategy, can only be called by the strategy.	
7. Ensure calls located on the vault for the NEW strategy, can only be called by the NEW strategy [USED BY THE STRATEGY UPGRADE SYSTEM].
8. Test setting of new operators.
	Set new operator for Vault.
	Set new operator for Strategy.
	Swap back (because whomever I've forced into helping me with this probably won't want to do everything else afterwards)
9. Deposit/Mint assets to the vault.
11. Lock interactions to the vault and TEST
	That the vault does not allow deposit/minting new assets.
	That the vault does not allow redeem/withdrawing assets (because those assets are not currently there...)
10. Test the strategy - Enter, Farm, Exit
	Test entering the strategy and wrapping up the vault's assets into whatever Defi Legos are making money.
	Manually acquire the same asset that the strategy wants and send it to the strategy to simulate the accrual of yield.
	Test exiting the strategy and unwrapping from these Defi Legos.
    10B. Test strategy to strategy upgrades and direct asset sending....
    	Test strategy to strategy upgrades.
    	Direct asset Sending:
		Don't worry too much for now if it doesn't work. The strategy can always be changed back and assets returned to the vault. 
		(This backup only fails if the DEX(s) we used in the strategy somehow fail)
####Note: Definitely check again that the yield into shares is properly calculated...a significant amount of testing showed it was fine earlier
####: This can be done by manually updating the underlying BEFORE unlocking interactions
11. Unlock interactions to the vault (Should automatically updates the underlying values anyway)
12. Make ANOTHER strategy contract.
