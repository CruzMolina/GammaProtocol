# `IUniswapV2Oracle`

Minimal Uniswap V2 Oracle contract interface for Price Emitter contract interface use.

## Functions:

- `getCurrentPriceCumulativeLast(contract IUniswapV2Pair uniswapV2Pair, bool denominationTokenIs0) (external)`

### Function `getCurrentPriceCumulativeLast(contract IUniswapV2Pair uniswapV2Pair, bool denominationTokenIs0) → uint256 priceCumulativeLast external`

Returns current/latest cumulative TWAP price for a given Uniswap V2 pairing.

#### Return Values:

- priceCumulativeLast latest cumulative price
