# `IPriceEmitter`

Keydonix Uniswap V2 Oracle Price Emitter contract interface.

## Functions:

- `emitPrice(contract IUniswapV2Pair exchange, address denominationToken, uint8 minBlocksBack, uint8 maxBlocksBack, struct IUniswapV2Oracle.ProofData proofData) (external)`

## Events:

- `Price(uint256 price)`

### Function `emitPrice(contract IUniswapV2Pair exchange, address denominationToken, uint8 minBlocksBack, uint8 maxBlocksBack, struct IUniswapV2Oracle.ProofData proofData) → uint256 price, uint256 blockNumber external`

Calls getPrice on the Uniswap Oracle.

#### Return Values:

- price and block number

Emits a {Price} event.

### Event `Price(uint256 price)`

Emitted when emitPrice successfully executed.
