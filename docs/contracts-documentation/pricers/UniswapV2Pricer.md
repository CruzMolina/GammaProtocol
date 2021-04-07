# `UniswapV2Pricer`

Pricer contract for a Uniswap V2 pairing as reported by a no-maintenance Uniswap V2 Oracle.

## Modifiers:

- `onlyBot()`

## Functions:

- `constructor(address _bot, address _asset, address _priceEmitter, address _oracle, address _uniswapV2Pair, address _denominationToken) (public)`

- `getPrice() (external)`

- `setExpiryPriceInOracle(uint256 _expiryTimestamp, struct IUniswapV2Oracle.ProofData _proofData) (external)`

### Modifier `onlyBot()`

modifier to check if sender address is equal to bot address

### Function `constructor(address _bot, address _asset, address _priceEmitter, address _oracle, address _uniswapV2Pair, address _denominationToken) public`

#### Parameters:

- `_bot`: privileged address that can call setExpiryPriceInOracle

- `_asset`: asset that this pricer will get a price for

- `_priceEmitter`: PriceEmitter contract for the asset

- `_oracle`: Opyn Oracle address

- `_uniswapV2Pair`: Uniswap asset pair this pricer will retrieve a price for

- `_denominationToken`: address of denomination token

### Function `getPrice() → uint256 external`

get the current last cumulative TWAP price for the pairing

overides the getPrice function in OpynPricerInterface

#### Return Values:

- currentLastPrice price of the asset in the denominationToken, scaled by 1e8

### Function `setExpiryPriceInOracle(uint256 _expiryTimestamp, struct IUniswapV2Oracle.ProofData _proofData) external`

set the expiry price in the oracle, can only be called by Bot address

#### Parameters:

- `_expiryTimestamp`: expiry to set a price for

- `_proofData`: to set a price for
