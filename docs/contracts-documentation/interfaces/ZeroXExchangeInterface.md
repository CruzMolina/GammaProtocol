# `ZeroXExchangeInterface`

ZeroX Exchange contract interface.

## Functions:

- `fillOrder(struct ZeroXExchangeInterface.Order order, uint256 takerAssetFillAmount, bytes signature) (external)`

- `batchFillOrders(struct ZeroXExchangeInterface.Order[] orders, uint256[] takerAssetFillAmounts, bytes[] signatures) (external)`

- `executeTransaction(struct ZeroXExchangeInterface.Transaction transaction, bytes signature) (external)`

- `preSign(bytes32 hash) (external)`

- `isValidTransactionSignature(struct ZeroXExchangeInterface.Transaction transaction, bytes signature) (external)`

- `isValidOrderSignature(struct ZeroXExchangeInterface.Order order, bytes signature) (external)`

### Function `fillOrder(struct ZeroXExchangeInterface.Order order, uint256 takerAssetFillAmount, bytes signature) → struct ZeroXExchangeInterface.FillResults fillResults external`

Fills the input order.

#### Parameters:

- `order`: Order struct containing order specifications.

- `takerAssetFillAmount`: Desired amount of takerAsset to sell.

- `signature`: Proof that order has been created by maker.

#### Return Values:

- fillResults Amounts filled and fees paid by maker and taker.

### Function `batchFillOrders(struct ZeroXExchangeInterface.Order[] orders, uint256[] takerAssetFillAmounts, bytes[] signatures) → struct ZeroXExchangeInterface.FillResults[] fillResults external`

Executes multiple calls of fillOrder.

#### Parameters:

- `orders`: Array of order specifications.

- `takerAssetFillAmounts`: Array of desired amounts of takerAsset to sell in orders.

- `signatures`: Proofs that orders have been created by makers.

#### Return Values:

- fillResults Array of amounts filled and fees paid by makers and taker.

### Function `executeTransaction(struct ZeroXExchangeInterface.Transaction transaction, bytes signature) → bytes external`

### Function `preSign(bytes32 hash) external`

### Function `isValidTransactionSignature(struct ZeroXExchangeInterface.Transaction transaction, bytes signature) → bool isValid external`

Verifies that a signature for a transaction is valid.

#### Parameters:

- `transaction`: The transaction.

- `signature`: Proof that the order has been signed by signer.

#### Return Values:

- isValid `true` if the signature is valid for the given transaction and signer.

### Function `isValidOrderSignature(struct ZeroXExchangeInterface.Order order, bytes signature) → bool isValid external`

Verifies that a signature for an order is valid.

#### Parameters:

- `order`: The order.

- `signature`: Proof that the order has been signed by signer.

#### Return Values:

- isValid `true` if the signature is valid for the given order and signer.
