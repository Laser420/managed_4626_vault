// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >= 0.8.0;
pragma abicoder v2;

import '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';
import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
//import '@uniswap/v3-periphery/contracts/interfaces/IQuoterV2.sol';
//import "https://github.com/Uniswap/v3-periphery/blob/main/contracts/interfaces/IQuoterV2.sol";

contract uniswap_weth_stable {
    // For the scope of these swap examples,
    // we will detail the design considerations when using
    // `exactInput`, `exactInputSingle`, `exactOutput`, and  `exactOutputSingle`.
    address operator;
    address newOperator;

    constructor()
    {
         operator = msg.sender;
    }

    //The address of the swap router
    address public constant swapAddy = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    ISwapRouter public immutable swapRouter = ISwapRouter(swapAddy);
    //The address of the quoter router
    address public constant quoterAddy = 0x61fFE014bA17989E743c5F6cB21bF9697530B21e;
    IQuoterV2 quoteRouterV2 = IQuoterV2(quoterAddy);

    //Not using WETH9 (Goerli) this time around...
    address WETH9 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    //The address of WETH on Goerli..
    address WETH = 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6;

    //An address of USDC 
    //https://goerli.etherscan.io/token/0xD87Ba7A50B2E7E660f678A895E4B72E7CB4CCd9C
    address USDC = 0xD87Ba7A50B2E7E660f678A895E4B72E7CB4CCd9C;

    //
    address DAI = 0x0000000000000000000000000000000000000000;

    address USDT = 0x0000000000000000000000000000000000000000;

    address customAddress = 0x0000000000000000000000000000000000000000;

    //A pool fee of 0.3%....have to set this to whatever a pool's fee is
    uint24 poolFee = 3000;

    /* Customization options */
    function changeFee(uint24 newFee) public onlyOperator ()
    {
        poolFee = newFee;
    }
    function changeCustomAddress(address newCustom) public onlyOperator ()
    {
        customAddress = newCustom;
    }

    //This should get any quote for a single pool trade...
    //Returns the amount of the tokenOUT that would be received...and the gasFee associated
    function _getQuote(uint256 amountIn, address IN, address OUT) internal returns (uint256 amountOut, uint256 gasEstimate)
    {
           IQuoterV2.QuoteExactInputSingleParams memory params =
                IQuoterV2.QuoteExactInputSingleParams
                ({
                    tokenIn: IN,
                    tokenOut: OUT,
                    amountIn: amountIn,
                    fee: poolFee,
                    sqrtPriceLimitX96: 0
                });
            //uint160[] memory sqrtPriceX96AfterList;
            //uint32[] memory initializedTicksCrossedList;
        //Only worry about the amountOut and the gasEstimate..
        (amountOut, , , gasEstimate) = quoteRouterV2.quoteExactInputSingle(params);
    }

    

    
/*THIS CONTRACT NEEDS TO BE APPROVED BY THE CALLER OF THIS FUNCTION */
    /// @notice swapExactInputSingle swaps a fixed amount of DAI for a maximum possible amount of WETH9
    /// using the DAI/WETH9 0.3% pool by calling `exactInputSingle` in the swap router.
    /// @dev The calling address must approve this contract to spend at least `amountIn` worth of its DAI for this function to succeed.
    /// @param amountIn The exact amount of DAI that will be swapped for WETH9.
    /// @return amountOut The amount of WETH9 received.
    function swapExactInputSingle(uint256 amountIn, address IN, address OUT) external returns (uint256 amountOut) {
       
        // Transfer the specified amount of DAI to this contract.
        //TransferHelper.safeTransferFrom(DAI, msg.sender, address(this), amountIn);

        // Approve the router to spend DAI.
        TransferHelper.safeApprove(DAI, address(swapRouter), amountIn);

        // Naively set amountOutMinimum to 0. In production, use an oracle or other data source to choose a safer value for amountOutMinimum.
        // We also set the sqrtPriceLimitx96 to be 0 to ensure we swap our exact input amount.
        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: IN,
                tokenOut: OUT,
                fee: poolFee,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
        // The call to `exactInputSingle` executes the swap.
        amountOut = swapRouter.exactInputSingle(params);
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
}



/// @title QuoterV2 Interface
/// @notice Supports quoting the calculated amounts from exact input or exact output swaps.
/// @notice For each pool also tells you the number of initialized ticks crossed and the sqrt price of the pool after the swap.
/// @dev These functions are not marked view because they rely on calling non-view functions and reverting
/// to compute the result. They are also not gas efficient and should not be called on-chain.
interface IQuoterV2 {
    /// @notice Returns the amount out received for a given exact input swap without executing the swap
    /// @param path The path of the swap, i.e. each token pair and the pool fee
    /// @param amountIn The amount of the first token to swap
    /// @return amountOut The amount of the last token that would be received
    /// @return sqrtPriceX96AfterList List of the sqrt price after the swap for each pool in the path
    /// @return initializedTicksCrossedList List of the initialized ticks that the swap crossed for each pool in the path
    /// @return gasEstimate The estimate of the gas that the swap consumes
    function quoteExactInput(bytes memory path, uint256 amountIn)
        external
        returns (
            uint256 amountOut,
            uint160[] memory sqrtPriceX96AfterList,
            uint32[] memory initializedTicksCrossedList,
            uint256 gasEstimate
        );

    struct QuoteExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint24 fee;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Returns the amount out received for a given exact input but for a swap of a single pool
    /// @param params The params for the quote, encoded as `QuoteExactInputSingleParams`
    /// tokenIn The token being swapped in
    /// tokenOut The token being swapped out
    /// fee The fee of the token pool to consider for the pair
    /// amountIn The desired input amount
    /// sqrtPriceLimitX96 The price limit of the pool that cannot be exceeded by the swap
    /// @return amountOut The amount of `tokenOut` that would be received
    /// @return sqrtPriceX96After The sqrt price of the pool after the swap
    /// @return initializedTicksCrossed The number of initialized ticks that the swap crossed
    /// @return gasEstimate The estimate of the gas that the swap consumes
    function quoteExactInputSingle(QuoteExactInputSingleParams memory params)
        external
        returns (
            uint256 amountOut,
            uint160 sqrtPriceX96After,
            uint32 initializedTicksCrossed,
            uint256 gasEstimate
        );

    /// @notice Returns the amount in required for a given exact output swap without executing the swap
    /// @param path The path of the swap, i.e. each token pair and the pool fee. Path must be provided in reverse order
    /// @param amountOut The amount of the last token to receive
    /// @return amountIn The amount of first token required to be paid
    /// @return sqrtPriceX96AfterList List of the sqrt price after the swap for each pool in the path
    /// @return initializedTicksCrossedList List of the initialized ticks that the swap crossed for each pool in the path
    /// @return gasEstimate The estimate of the gas that the swap consumes
    function quoteExactOutput(bytes memory path, uint256 amountOut)
        external
        returns (
            uint256 amountIn,
            uint160[] memory sqrtPriceX96AfterList,
            uint32[] memory initializedTicksCrossedList,
            uint256 gasEstimate
        );

    struct QuoteExactOutputSingleParams {
        address tokenIn;
        address tokenOut;
        uint256 amount;
        uint24 fee;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Returns the amount in required to receive the given exact output amount but for a swap of a single pool
    /// @param params The params for the quote, encoded as `QuoteExactOutputSingleParams`
    /// tokenIn The token being swapped in
    /// tokenOut The token being swapped out
    /// fee The fee of the token pool to consider for the pair
    /// amountOut The desired output amount
    /// sqrtPriceLimitX96 The price limit of the pool that cannot be exceeded by the swap
    /// @return amountIn The amount required as the input for the swap in order to receive `amountOut`
    /// @return sqrtPriceX96After The sqrt price of the pool after the swap
    /// @return initializedTicksCrossed The number of initialized ticks that the swap crossed
    /// @return gasEstimate The estimate of the gas that the swap consumes
    function quoteExactOutputSingle(QuoteExactOutputSingleParams memory params)
        external
        returns (
            uint256 amountIn,
            uint160 sqrtPriceX96After,
            uint32 initializedTicksCrossed,
            uint256 gasEstimate
        );
}
