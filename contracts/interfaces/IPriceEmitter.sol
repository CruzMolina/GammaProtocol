// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.10;
pragma experimental ABIEncoderV2;

import {IUniswapV2Oracle} from "./IUniswapV2Oracle.sol";
import {IUniswapV2Pair} from "./IUniswapV2Pair.sol";

/**
 * @notice Keydonix Uniswap V2 Oracle Price Emitter contract interface.
 */
interface IPriceEmitter is IUniswapV2Oracle {
    /**
     * @notice Emitted when emitPrice successfully executed.
     */
    event Price(uint256 price);

    /**
     * @notice Calls getPrice on the Uniswap Oracle.
     * @return price and block number
     *
     * Emits a {Price} event.
     */
    function emitPrice(
        IUniswapV2Pair exchange,
        address denominationToken,
        uint8 minBlocksBack,
        uint8 maxBlocksBack,
        IUniswapV2Oracle.ProofData memory proofData
    ) external returns (uint256 price, uint256 blockNumber);
}
