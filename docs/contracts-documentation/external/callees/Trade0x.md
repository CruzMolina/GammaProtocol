# `Trade0x`

callee contract to trade on 0x.

## Functions:

- `constructor(address _exchange, address _assetProxy, address _weth, address _staking, address _controller) (public)`

- `callFunction(address payable _sender, bytes _data) (external)`

- `_directlyTrade(address payable _sender, bytes _data) (internal)`

- `getTxHash(struct ZeroXExchangeInterface.Transaction transaction) (external)`

- `decodeERC20Asset(bytes b) (internal)`

## Events:

- `Trade(address taker, address maker, address takerAsset, address makerAsset, uint256 takerAmount, uint256 makerAmount)`

### Function `constructor(address _exchange, address _assetProxy, address _weth, address _staking, address _controller) public`

### Function `callFunction(address payable _sender, bytes _data) external`

fill 0x order

it is dangerous to do an unlimited approval to this contract

#### Parameters:

- `_sender`: the original sender who wants to trade on 0x

- `_data`: abi-encoded order, fillamount, signature and _sender. fee payer is the address we pull weth from.

### Function `_directlyTrade(address payable _sender, bytes _data) internal`

### Function `getTxHash(struct ZeroXExchangeInterface.Transaction transaction) → bytes32 result external`

### Function `decodeERC20Asset(bytes b) → address result internal`

decode 0x AssetData into contract address

This is the merge of the following 2 function from 0x

https://github.com/0xProject/0x-monorepo/blob/0571244e9e84b9ad778bccb99b837dd6f9baaf6e/contracts/dev-utils/contracts/src/LibAssetData.sol#L69

https://github.com/0xProject/0x-monorepo/blob/0571244e9e84b9ad778bccb99b837dd6f9baaf6e/contracts/utils/contracts/src/LibBytes.sol#L296

### Event `Trade(address taker, address maker, address takerAsset, address makerAsset, uint256 takerAmount, uint256 makerAmount)`
