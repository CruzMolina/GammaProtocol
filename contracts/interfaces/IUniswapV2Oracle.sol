// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.10;

import {IUniswapV2Pair} from "./IUniswapV2Pair.sol";

/**
 * @notice Minimal Uniswap V2 Oracle contract interface for Price Emitter contract interface use.
 */
interface IUniswapV2Oracle {
    /**
     * @notice Structure storing Uniswap Oracle's merkle proof data.
     */
    struct ProofData {
        bytes block;
        bytes accountProofNodesRlp;
        bytes reserveAndTimestampProofNodesRlp;
        bytes priceAccumulatorProofNodesRlp;
    }

    /**
     * @notice Returns current/latest cumulative TWAP price for a given Uniswap V2 pairing.
     * @return priceCumulativeLast latest cumulative price
     */
    function getCurrentPriceCumulativeLast(IUniswapV2Pair uniswapV2Pair, bool denominationTokenIs0)
        external
        view
        returns (uint256 priceCumulativeLast);
}
