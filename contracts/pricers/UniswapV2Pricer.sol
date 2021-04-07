// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.10;
pragma experimental ABIEncoderV2;

import {IPriceEmitter} from "../interfaces/IPriceEmitter.sol";
import {IUniswapV2Pair} from "../interfaces/IUniswapV2Pair.sol";
import {OracleInterface} from "../interfaces/OracleInterface.sol";
import {OpynPricerInterface} from "../interfaces/OpynPricerInterface.sol";
import {SafeMath} from "../packages/oz/SafeMath.sol";

/**
 * @notice Pricer contract for a Uniswap V2 pairing as reported by a no-maintenance Uniswap V2 Oracle.
 */
contract UniswapV2Pricer is OpynPricerInterface {
    using SafeMath for uint256;

    /**
     * @notice The PriceEmitter contract interface.
     */
    IPriceEmitter public priceEmitter;

    /**
     * @notice Minimal UniswapV2Pair contract interface.
     */
    IUniswapV2Pair public uniswapV2Pair;

    /**
     * @notice The Opyn Oracle contract interface.
     */
    OracleInterface public oracle;

    /**
     * @notice Stores a given asset token address pricer will fetch a price for.
     */
    address public asset;

    /**
     * @notice Stores a given bot address that will be allowed to call setExpiryPriceInOracle.
     */
    address public bot;

    /**
     * @notice Stores a given denomination token address this pricer will use to return a price.
     */
    address public denominationToken;

    /**
     * @param _bot privileged address that can call setExpiryPriceInOracle
     * @param _asset asset that this pricer will get a price for
     * @param _priceEmitter PriceEmitter contract for the asset
     * @param _oracle Opyn Oracle address
     * @param _uniswapV2Pair Uniswap asset pair this pricer will retrieve a price for
     * @param _denominationToken address of denomination token
     */
    constructor(
        address _bot,
        address _asset,
        address _priceEmitter,
        address _oracle,
        address _uniswapV2Pair,
        address _denominationToken
    ) public {
        require(_bot != address(0), "UniswapV2Pricer: Cannot set 0 address as bot");
        require(_oracle != address(0), "UniswapV2Pricer: Cannot set 0 address as oracle");
        require(_priceEmitter != address(0), "UniswapV2Pricer: Cannot set 0 address as priceEmitter");

        bot = _bot;
        oracle = OracleInterface(_oracle);
        priceEmitter = IPriceEmitter(_priceEmitter);
        asset = _asset;
        uniswapV2Pair = IUniswapV2Pair(_uniswapV2Pair);
        denominationToken = _denominationToken;
    }

    /**
     * @notice modifier to check if sender address is equal to bot address
     */
    modifier onlyBot() {
        require(msg.sender == bot, "UniswapV2Pricer: unauthorized sender");

        _;
    }

    /**
     * @notice get the current last cumulative TWAP price for the pairing
     * @dev overides the getPrice function in OpynPricerInterface
     * @return currentLastPrice price of the asset in the denominationToken, scaled by 1e8
     */
    function getPrice() external override view returns (uint256) {
        bool denominationTokenIs0;

        if (uniswapV2Pair.token0() == denominationToken) {
            denominationTokenIs0 = true;
        } else if (uniswapV2Pair.token1() == denominationToken) {
            denominationTokenIs0 = false;
        } else {
            revert("denominationToken invalid");
        }

        uint256 currentLastPrice = priceEmitter.getCurrentPriceCumulativeLast(uniswapV2Pair, denominationTokenIs0);

        require(currentLastPrice > 0, "UniswapV2Pricer: price is lower than 0");

        return currentLastPrice;
    }

    /**
     * @notice set the expiry price in the oracle, can only be called by Bot address
     * @param _expiryTimestamp expiry to set a price for
     * @param _proofData to set a price for
     */
    function setExpiryPriceInOracle(uint256 _expiryTimestamp, IPriceEmitter.ProofData memory _proofData)
        external
        onlyBot
    {
        require(
            _expiryTimestamp <= block.timestamp,
            "UniswapV2Pricer: current block timestamp less than expiryTimestamp"
        );

        (uint256 price, ) = priceEmitter.emitPrice(uniswapV2Pair, denominationToken, 0, 255, _proofData);

        oracle.setExpiryPrice(asset, _expiryTimestamp, price);
    }
}
