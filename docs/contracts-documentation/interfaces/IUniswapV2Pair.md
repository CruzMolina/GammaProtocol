# `IUniswapV2Pair`

Minimal Uniswap V2 Pair contract interface for Price Emitter contract interface use

## Functions:

- `token0() (external)`

- `token1() (external)`

- `price0CumulativeLast() (external)`

- `price1CumulativeLast() (external)`

- `getReserves() (external)`

### Function `token0() → address external`

Returns the address of the pair token with the lower sort order.

### Function `token1() → address external`

Returns the address of the pair token with the higher sort order.

### Function `price0CumulativeLast() → uint256 external`

Returns the price of token0 denominated in token1.

### Function `price1CumulativeLast() → uint256 external`

Returns the price of token1 denominated in token0.

### Function `getReserves() → uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast external`

Returns the reserves of token0 and token1 used to price trades and distribute liquidity.

Also returns the block.timestamp (mod 2**32) of the last block during which an interaction occured for the pair.
