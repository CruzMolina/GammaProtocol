// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.10;

/**
 * @notice Minimal Uniswap V2 Pair contract interface for Price Emitter contract interface use
 */
interface IUniswapV2Pair {
    /**
     * @notice Returns the address of the pair token with the lower sort order.
     */
    function token0() external view returns (address);

    /**
     * @notice Returns the address of the pair token with the higher sort order.
     */
    function token1() external view returns (address);

    /**
     * @notice Returns the price of token0 denominated in token1.
     */
    function price0CumulativeLast() external view returns (uint256);

    /**
     * @notice Returns the price of token1 denominated in token0.
     */
    function price1CumulativeLast() external view returns (uint256);

    /**
     * @notice Returns the reserves of token0 and token1 used to price trades and distribute liquidity.
     * Also returns the block.timestamp (mod 2**32) of the last block during which an interaction occured for the pair.
     */
    function getReserves()
        external
        view
        returns (
            uint112 _reserve0,
            uint112 _reserve1,
            uint32 _blockTimestampLast
        );
}
