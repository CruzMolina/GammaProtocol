/**
 * SPDX-License-Identifier: UNLICENSED
 */
pragma solidity 0.6.10;
pragma experimental ABIEncoderV2;

import {SafeMath} from "./packages/oz/SafeMath.sol";
import {Ownable} from "./packages/oz/Ownable.sol";
import {OtokenInterface} from "./interfaces/OtokenInterface.sol";
import {OracleInterface} from "./interfaces/OracleInterface.sol";
import {ERC20Interface} from "./interfaces/ERC20Interface.sol";
import {FixedPointInt256 as FPI} from "./libs/FixedPointInt256.sol";
import {MarginVault} from "./libs/MarginVault.sol";

/**
 * @title MarginCalculator
 * @author Opyn
 * @notice Calculator module that checks if a given vault is valid, calculates margin requirements, and settlement proceeds
 */
contract MarginCalculator is Ownable {
    using SafeMath for uint256;
    using FPI for FPI.FixedPointInt;

    /// @dev struct to store all needed vault details
    struct VaultDetails {
        address shortUnderlyingAsset;
        address shortStrikeAsset;
        address shortCollateralAsset;
        address longUnderlyingAsset;
        address longStrikeAsset;
        address longCollateralAsset;
        uint256 shortStrikePrice;
        uint256 shortExpiryTimestamp;
        uint256 shortCollateralDecimals;
        uint256 longStrikePrice;
        uint256 longExpiryTimestamp;
        uint256 longCollateralDecimals;
        uint256 collateralDecimals;
        uint256 vaultType;
        bool isShortPut;
        bool isLongPut;
        bool hasLong;
        bool hasShort;
        bool hasCollateral;
    }

    /// @dev oracle module
    OracleInterface public oracle;

    /// @dev decimals used by strike price and oracle price
    uint256 internal constant BASE = 8;

    /// @dev oracle deviation value (1e27)
    uint256 internal oracleDeviation;

    /// @dev FixedPoint 0
    FPI.FixedPointInt internal ZERO = FPI.fromScaledUint(0, BASE);

    /// @dev mapping to store dust amount per option collateral asset (1e27)
    mapping(address => uint256) internal dust;

    /// @dev mapping to store array of time to expiry per product
    mapping(bytes32 => uint256[]) internal productTimeToExpiry;

    /// @dev mapping to store option upper bound value at specific time to expiry per product (1e27)
    mapping(bytes32 => mapping(uint256 => uint256)) internal timeToExpiryValue;

    /// @dev mapping to store shock value for spot price per product
    mapping(bytes32 => uint256) internal spotShock;

    /// @notice emits an event when collateral dust is updated
    event CollateralDustUpdated(address indexed collateral, uint256 dust);
    /// @notice emits an event when new time to expiry is added for a specific product
    event ProductTimeToExpiryAdded(bytes32 indexed productHash, uint256 timeToExpiry);
    /// @notice emits an event when new upper bound value is added for a specific time to expiry timestamp
    event TimeToExpiryValueAdded(bytes32 indexed productHash, uint256 timeToExpiry, uint256 value);
    /// @notice emits an event when spot shock value is updated for a specific product
    event SpotShockUpdated(bytes32 indexed product, uint256 spotShock);

    constructor(address _oracle) public {
        require(_oracle != address(0), "MarginCalculator: invalid oracle address");

        oracle = OracleInterface(_oracle);
    }

    /**
     * @notice set dust amount for collateral asset (1e27)
     * @dev can only be called by owner
     * @param _collateral collateral asset address
     * @param _dust dust amount
     */
    function setCollateralDust(address _collateral, uint256 _dust) external onlyOwner {
        dust[_collateral] = _dust;
    }

    /**
     * @notice set new time to expiry for specific product
     * @dev can only be called by owner
     * @param _underlying otoken underlying asset
     * @param _strike otoken strike asset
     * @param _collateral otoken collateral asset
     * @param _isPut otoken type
     * @param _timeToExpiry option time to expiry timestamp
     */
    function setProductTimeToExpiry(
        address _underlying,
        address _strike,
        address _collateral,
        bool _isPut,
        uint256 _timeToExpiry
    ) external onlyOwner {
        bytes32 productHash = keccak256(abi.encode(_underlying, _strike, _collateral, _isPut));
        uint256[] storage expiryArray = productTimeToExpiry[productHash];

        require(
            (expiryArray.length == 0) || (_timeToExpiry > expiryArray[expiryArray.length - 1]),
            "MarginCalculator: expiry array is not in order"
        );
        require(
            timeToExpiryValue[productHash][_timeToExpiry] != 0,
            "MarginCalculator: no expiry upper bound value found"
        );

        expiryArray.push(_timeToExpiry);
    }

    /**
     * @notice set option upper bound value for specific time to expiry (1e27)
     * @dev can only be called by owner
     * @param _underlying otoken underlying asset
     * @param _strike otoken strike asset
     * @param _collateral otoken collateral asset
     * @param _isPut otoken type
     * @param _timeToExpiry option time to expiry timestamp
     * @param _value upper bound value
     */
    function setTimeToExpiryValue(
        address _underlying,
        address _strike,
        address _collateral,
        bool _isPut,
        uint256 _timeToExpiry,
        uint256 _value
    ) external onlyOwner {
        require(_value > 0, "MarginCalculator: invalid option upper bound value");

        bytes32 productHash = keccak256(abi.encode(_underlying, _strike, _collateral, _isPut));

        timeToExpiryValue[productHash][_timeToExpiry] = _value;
    }

    /**
     * @notice set spot shock value (1e27)
     * @dev can only be called by owner
     * @param _underlying otoken underlying asset
     * @param _strike otoken strike asset
     * @param _collateral otoken collateral asset
     * @param _isPut otoken type
     * @param _shockValue spot shock value
     */
    function setSpotShock(
        address _underlying,
        address _strike,
        address _collateral,
        bool _isPut,
        uint256 _shockValue
    ) external onlyOwner {
        bytes32 productHash = keccak256(abi.encode(_underlying, _strike, _collateral, _isPut));

        spotShock[productHash] = _shockValue;
    }

    /**
     * @notice set oracle deviation (1e27)
     * @dev can only be called by owner
     * @param _deviation deviation value
     */
    function setOracleDeviation(uint256 _deviation) external onlyOwner {
        oracleDeviation = _deviation;
    }

    /**
     * @notice get dust amount for collateral asset
     * @param _collateral collateral asset address
     * @return dust amount (1e27)
     */
    function getCollateralDust(address _collateral) external view returns (uint256) {
        return dust[_collateral];
    }

    /**
     * @notice get time to expiry for specific product
     * @param _underlying otoken underlying asset
     * @param _strike otoken strike asset
     * @param _collateral otoken collateral asset
     * @param _isPut otoken type
     * @return array of times to expiry
     */
    function getProductTimeToExpiry(
        address _underlying,
        address _strike,
        address _collateral,
        bool _isPut
    ) external view returns (uint256[] memory) {
        bytes32 productHash = keccak256(abi.encode(_underlying, _strike, _collateral, _isPut));
        return productTimeToExpiry[productHash];
    }

    /**
     * @notice get option upper bound value for specific time to expiry
     * @param _underlying otoken underlying asset
     * @param _strike otoken strike asset
     * @param _collateral otoken collateral asset
     * @param _isPut otoken type
     * @param _timeToExpiry option time to expiry timestamp
     * @return option upper bound value (1e27)
     */
    function getTimeToExpiryValue(
        address _underlying,
        address _strike,
        address _collateral,
        bool _isPut,
        uint256 _timeToExpiry
    ) external view returns (uint256) {
        bytes32 productHash = keccak256(abi.encode(_underlying, _strike, _collateral, _isPut));

        return timeToExpiryValue[productHash][_timeToExpiry];
    }

    /**
     * @notice get spot shock value
     * @param _underlying otoken underlying asset
     * @param _strike otoken strike asset
     * @param _collateral otoken collateral asset
     * @param _isPut otoken type
     * @return _shockValue spot shock value (1e27)
     */
    function getSpotShock(
        address _underlying,
        address _strike,
        address _collateral,
        bool _isPut
    ) external view returns (uint256) {
        bytes32 productHash = keccak256(abi.encode(_underlying, _strike, _collateral, _isPut));

        return spotShock[productHash];
    }

    /**
     * @notice get oracle deviation
     * @return oracle deviation value (1e27)
     */
    function getOracleDeviation() external view returns (uint256) {
        return oracleDeviation;
    }

    /**
     * @notice return the cash value of an expired oToken, denominated in collateral
     * @param _otoken oToken address
     * @return how much collateral can be taken out by 1 otoken unit, scaled by 1e8,
     * or how much collateral can be taken out for 1 (1e8) oToken
     */
    function getExpiredPayoutRate(address _otoken) external view returns (uint256) {
        require(_otoken != address(0), "MarginCalculator: Invalid token address");

        OtokenInterface otoken = OtokenInterface(_otoken);

        (
            address collateral,
            address underlying,
            address strikeAsset,
            uint256 strikePrice,
            uint256 expiry,
            bool isPut
        ) = otoken.getOtokenDetails();

        require(now >= expiry, "MarginCalculator: Otoken not expired yet");

        FPI.FixedPointInt memory cashValueInStrike = _getExpiredCashValue(
            underlying,
            strikeAsset,
            expiry,
            strikePrice,
            isPut
        );

        FPI.FixedPointInt memory cashValueInCollateral = _convertAmountOnExpiryPrice(
            cashValueInStrike,
            strikeAsset,
            collateral,
            expiry
        );

        // the exchangeRate was scaled by 1e8, if 1e8 otoken can take out 1 USDC, the exchangeRate is currently 1e8
        // we want to return: how much USDC units can be taken out by 1 (1e8 units) oToken
        uint256 collateralDecimals = uint256(ERC20Interface(collateral).decimals());
        return cashValueInCollateral.toScaledUint(collateralDecimals, true);
    }

    /**
     * @notice returns the amount of collateral that can be removed from an actual or a theoretical vault
     * @dev return amount is denominated in the collateral asset for the oToken in the vault, or the collateral asset in the vault
     * @param _vault theoretical vault that needs to be checked
     * @param _vaultType vault type (0 for spread/max loss, 1 for naked margin)
     * @return excessCollateral the amount by which the margin is above or below the required amount
     * @return isExcess True if there is excess margin in the vault, False if there is a deficit of margin in the vault
     * if True, collateral can be taken out from the vault, if False, additional collateral needs to be added to vault
     */
    function getExcessCollateral(MarginVault.Vault memory _vault, uint256 _vaultType)
        public
        view
        returns (uint256, bool)
    {
        // get vault details
        VaultDetails memory vaultDetails = getVaultDetails(_vault, _vaultType);
        // include all the checks for to ensure the vault is valid
        _checkIsValidVault(_vault, vaultDetails);

        // if the vault contains no oTokens, return the amount of collateral
        if (!vaultDetails.hasShort && !vaultDetails.hasLong) {
            uint256 amount = vaultDetails.hasCollateral ? _vault.collateralAmounts[0] : 0;
            return (amount, true);
        }

        // get required margin, denominated in collateral
        (FPI.FixedPointInt memory collateralAmount, FPI.FixedPointInt memory collateralRequired) = _getMarginRequired(
            _vault,
            vaultDetails
        );
        FPI.FixedPointInt memory excessCollateral = collateralAmount.sub(collateralRequired);

        bool isExcess = excessCollateral.isGreaterThanOrEqual(ZERO);
        uint256 collateralDecimals = vaultDetails.hasLong
            ? vaultDetails.longCollateralDecimals
            : vaultDetails.shortCollateralDecimals;
        // if is excess, truncate the tailing digits in excessCollateralExternal calculation
        uint256 excessCollateralExternal = excessCollateral.toScaledUint(collateralDecimals, isExcess);
        return (excessCollateralExternal, isExcess);
    }

    /**
     * @notice return the cash value of an expired oToken, denominated in strike asset
     * @dev for a call, return Max (0, underlyingPriceInStrike - otoken.strikePrice)
     * @dev for a put, return Max(0, otoken.strikePrice - underlyingPriceInStrike)
     * @param _underlying otoken underlying asset
     * @param _strike otoken strike asset
     * @param _expiryTimestamp otoken expiry timestamp
     * @param _strikePrice otoken strike price
     * @param _strikePrice true if otoken is put otherwise false
     * @return cash value of an expired otoken, denominated in the strike asset
     */
    function _getExpiredCashValue(
        address _underlying,
        address _strike,
        uint256 _expiryTimestamp,
        uint256 _strikePrice,
        bool _isPut
    ) internal view returns (FPI.FixedPointInt memory) {
        // strike price is denominated in strike asset
        FPI.FixedPointInt memory strikePrice = FPI.fromScaledUint(_strikePrice, BASE);
        FPI.FixedPointInt memory one = FPI.fromScaledUint(1, 0);

        // calculate the value of the underlying asset in terms of the strike asset
        FPI.FixedPointInt memory underlyingPriceInStrike = _convertAmountOnExpiryPrice(
            one, // underlying price denominated in underlying
            _underlying,
            _strike,
            _expiryTimestamp
        );

        if (_isPut) {
            return strikePrice.isGreaterThan(underlyingPriceInStrike) ? strikePrice.sub(underlyingPriceInStrike) : ZERO;
        } else {
            return underlyingPriceInStrike.isGreaterThan(strikePrice) ? underlyingPriceInStrike.sub(strikePrice) : ZERO;
        }
    }

    /// @dev added this struct to avoid stack-too-deep error
    struct OtokenDetails {
        address otokenUnderlyingAsset;
        address otokenCollateralAsset;
        address otokenStrikeAsset;
        uint256 otokenExpiry;
        bool isPut;
    }

    /**
     * @notice calculate the amount of collateral needed for a vault
     * @dev vault passed in has already passed the checkIsValidVault function
     * @param _vault theoretical vault that needs to be checked
     * @return marginRequired the minimal amount of collateral needed in a vault, denominated in collateral
     */
    function _getMarginRequired(MarginVault.Vault memory _vault, VaultDetails memory _vaultDetails)
        internal
        view
        returns (FPI.FixedPointInt memory, FPI.FixedPointInt memory)
    {
        FPI.FixedPointInt memory shortAmount = _vaultDetails.hasShort
            ? FPI.fromScaledUint(_vault.shortAmounts[0], BASE)
            : ZERO;
        FPI.FixedPointInt memory longAmount = _vaultDetails.hasLong
            ? FPI.fromScaledUint(_vault.longAmounts[0], BASE)
            : ZERO;
        FPI.FixedPointInt memory collateralAmount = _vaultDetails.hasCollateral
            ? FPI.fromScaledUint(_vault.collateralAmounts[0], _vaultDetails.collateralDecimals)
            : ZERO;
        FPI.FixedPointInt memory shortStrike = _vaultDetails.hasShort
            ? FPI.fromScaledUint(_vaultDetails.shortStrikePrice, BASE)
            : ZERO;

        OtokenDetails memory otokenDetails = OtokenDetails(
            _vaultDetails.hasShort ? _vaultDetails.shortUnderlyingAsset : _vaultDetails.longUnderlyingAsset,
            _vaultDetails.hasShort ? _vaultDetails.shortCollateralAsset : _vaultDetails.longCollateralAsset,
            _vaultDetails.hasShort ? _vaultDetails.shortStrikeAsset : _vaultDetails.longStrikeAsset,
            _vaultDetails.hasShort ? _vaultDetails.shortExpiryTimestamp : _vaultDetails.longExpiryTimestamp,
            _vaultDetails.hasShort ? _vaultDetails.isShortPut : _vaultDetails.isLongPut
        );

        if (!(now >= otokenDetails.otokenExpiry)) {
            // check if vault is naked margin vault
            if (_vaultDetails.vaultType == 1) {
                require(!_vaultDetails.hasLong, "MarginCalculator: naked margin vault cannot have long otoken");

                // fetch dust amount for otoken collateral asset as FixedPointInt, assuming dust is already scaled to 1e27
                FPI.FixedPointInt memory dustAmount = FPI.fromScaledUint(dust[_vaultDetails.shortCollateralAsset], 27);

                // check that collateral deposited in naked margin vault is greater than dust amount for that particular collateral asset
                if (collateralAmount.isGreaterThan(ZERO)) {
                    require(
                        collateralAmount.isGreaterThan(dustAmount),
                        "MarginCalculator: naked margin vault should have collateral amount greater than dust amount"
                    );
                }

                // get underlying asset price for short option
                FPI.FixedPointInt memory shortUnderlyingPrice = FPI.fromScaledUint(
                    oracle.getPrice(_vaultDetails.shortUnderlyingAsset),
                    BASE
                );

                // encode product hash
                bytes32 productHash = keccak256(
                    abi.encode(
                        _vaultDetails.shortUnderlyingAsset,
                        _vaultDetails.shortStrikeAsset,
                        _vaultDetails.shortCollateralAsset,
                        _vaultDetails.isShortPut
                    )
                );

                // return amount of collateral in vault and needed collateral amount for margin
                return (
                    collateralAmount,
                    _getNakedMarginRequired(
                        productHash,
                        shortAmount,
                        shortStrike,
                        shortUnderlyingPrice,
                        otokenDetails.otokenExpiry,
                        otokenDetails.isPut
                    )
                );
            } else {
                FPI.FixedPointInt memory longStrike = _vaultDetails.hasLong
                    ? FPI.fromScaledUint(_vaultDetails.longStrikePrice, BASE)
                    : ZERO;

                if (otokenDetails.isPut) {
                    FPI.FixedPointInt memory strikeNeeded = _getPutSpreadMarginRequired(
                        shortAmount,
                        longAmount,
                        shortStrike,
                        longStrike
                    );
                    // convert amount to be denominated in collateral
                    return (
                        collateralAmount,
                        _convertAmountOnLivePrice(
                            strikeNeeded,
                            otokenDetails.otokenStrikeAsset,
                            otokenDetails.otokenCollateralAsset
                        )
                    );
                } else {
                    FPI.FixedPointInt memory underlyingNeeded = _getCallSpreadMarginRequired(
                        shortAmount,
                        longAmount,
                        shortStrike,
                        longStrike
                    );
                    // convert amount to be denominated in collateral
                    return (
                        collateralAmount,
                        _convertAmountOnLivePrice(
                            underlyingNeeded,
                            otokenDetails.otokenUnderlyingAsset,
                            otokenDetails.otokenCollateralAsset
                        )
                    );
                }
            }
        } else {
            FPI.FixedPointInt memory shortCashValue = _vaultDetails.hasShort
                ? _getExpiredCashValue(
                    _vaultDetails.shortUnderlyingAsset,
                    _vaultDetails.shortStrikeAsset,
                    _vaultDetails.shortExpiryTimestamp,
                    _vaultDetails.shortStrikePrice,
                    otokenDetails.isPut
                )
                : ZERO;
            FPI.FixedPointInt memory longCashValue = _vaultDetails.hasLong
                ? _getExpiredCashValue(
                    _vaultDetails.longUnderlyingAsset,
                    _vaultDetails.longStrikeAsset,
                    _vaultDetails.longExpiryTimestamp,
                    _vaultDetails.longStrikePrice,
                    otokenDetails.isPut
                )
                : ZERO;

            FPI.FixedPointInt memory valueInStrike = _getExpiredSpreadCashValue(
                shortAmount,
                longAmount,
                shortCashValue,
                longCashValue
            );

            // convert amount to be denominated in collateral
            return (
                collateralAmount,
                _convertAmountOnExpiryPrice(
                    valueInStrike,
                    otokenDetails.otokenStrikeAsset,
                    otokenDetails.otokenCollateralAsset,
                    otokenDetails.otokenExpiry
                )
            );
        }
    }

    /**
     * @notice get required collateral for naked margin position
     */
    function _getNakedMarginRequired(
        bytes32 _productHash,
        FPI.FixedPointInt memory _shortAmount,
        FPI.FixedPointInt memory _strikePrice,
        FPI.FixedPointInt memory _underlyingPrice,
        uint256 _shortExpiryTimestamp,
        bool _isPut
    ) internal view returns (FPI.FixedPointInt memory) {
        return ZERO;
    }

    /**
     * @notice find upper bound value for product by specific expiry timestamp
     * @dev should return the upper bound value that correspond to option time to expiry, of if not found should return the next greater one, revert if no value found
     * @param _productHash product hash
     * @param _expiryTimestamp expiry timestamp
     * @return option upper bound value
     */
    function _findUpperBoundValue(bytes32 _productHash, uint256 _expiryTimestamp)
        internal
        view
        returns (FPI.FixedPointInt memory)
    {
        uint256[] memory timesToExpiry = productTimeToExpiry[_productHash];

        require(timesToExpiry.length != 0, "MarginCalculator: product have no expiry values");

        uint256 optionTimeToExpiry = _expiryTimestamp.sub(now);

        require(
            timesToExpiry[timesToExpiry.length - 1] >= optionTimeToExpiry,
            "MarginCalculator: product have no upper bound value"
        );

        uint256 i;

        while ((i < timesToExpiry.length) && (timesToExpiry[i] < optionTimeToExpiry)) {
            i++;
        }

        return FPI.fromScaledUint(timeToExpiryValue[_productHash][timesToExpiry[i]], 27);
    }

    /**
     * @dev returns the strike asset amount of margin required for a put or put spread with the given short oTokens, long oTokens and amounts
     *
     * marginRequired = max( (short amount * short strike) - (long strike * min (short amount, long amount)) , 0 )
     *
     * @return margin requirement denominated in the strike asset
     */
    function _getPutSpreadMarginRequired(
        FPI.FixedPointInt memory _shortAmount,
        FPI.FixedPointInt memory _longAmount,
        FPI.FixedPointInt memory _shortStrike,
        FPI.FixedPointInt memory _longStrike
    ) internal view returns (FPI.FixedPointInt memory) {
        return FPI.max(_shortAmount.mul(_shortStrike).sub(_longStrike.mul(FPI.min(_shortAmount, _longAmount))), ZERO);
    }

    /**
     * @dev returns the underlying asset amount required for a call or call spread with the given short oTokens, long oTokens, and amounts
     *
     *                           (long strike - short strike) * short amount
     * marginRequired =  max( ------------------------------------------------- , max (short amount - long amount, 0) )
     *                                           long strike
     *
     * @dev if long strike = 0, return max( short amount - long amount, 0)
     * @return margin requirement denominated in the underlying asset
     */
    function _getCallSpreadMarginRequired(
        FPI.FixedPointInt memory _shortAmount,
        FPI.FixedPointInt memory _longAmount,
        FPI.FixedPointInt memory _shortStrike,
        FPI.FixedPointInt memory _longStrike
    ) internal view returns (FPI.FixedPointInt memory) {
        // max (short amount - long amount , 0)
        if (_longStrike.isEqual(ZERO)) {
            return FPI.max(_shortAmount.sub(_longAmount), ZERO);
        }

        /**
         *             (long strike - short strike) * short amount
         * calculate  ----------------------------------------------
         *                             long strike
         */
        FPI.FixedPointInt memory firstPart = _longStrike.sub(_shortStrike).mul(_shortAmount).div(_longStrike);

        /**
         * calculate max ( short amount - long amount , 0)
         */
        FPI.FixedPointInt memory secondPart = FPI.max(_shortAmount.sub(_longAmount), ZERO);

        return FPI.max(firstPart, secondPart);
    }

    /**
     * @dev ensure that:
     * a) at most 1 asset type used as collateral
     * b) at most 1 series of option used as the long option
     * c) at most 1 series of option used as the short option
     * d) asset array lengths match for long, short and collateral
     * e) long option and collateral asset is acceptable for margin with short asset
     * @param _vault the vault to check
     */
    function _checkIsValidVault(MarginVault.Vault memory _vault, VaultDetails memory _vaultDetails) internal view {
        // ensure all the arrays in the vault are valid
        require(_vault.shortOtokens.length <= 1, "MarginCalculator: Too many short otokens in the vault");
        require(_vault.longOtokens.length <= 1, "MarginCalculator: Too many long otokens in the vault");
        require(_vault.collateralAssets.length <= 1, "MarginCalculator: Too many collateral assets in the vault");

        require(
            _vault.shortOtokens.length == _vault.shortAmounts.length,
            "MarginCalculator: Short asset and amount mismatch"
        );
        require(
            _vault.longOtokens.length == _vault.longAmounts.length,
            "MarginCalculator: Long asset and amount mismatch"
        );
        require(
            _vault.collateralAssets.length == _vault.collateralAmounts.length,
            "MarginCalculator: Collateral asset and amount mismatch"
        );

        // ensure the long asset is valid for the short asset
        require(
            _isMarginableLong(_vault, _vaultDetails),
            "MarginCalculator: long asset not marginable for short asset"
        );

        // ensure that the collateral asset is valid for the short asset
        require(
            _isMarginableCollateral(_vault, _vaultDetails),
            "MarginCalculator: collateral asset not marginable for short asset"
        );
    }

    /**
     * @dev if there is a short option and a long option in the vault, ensure that the long option is able to be used as collateral for the short option
     * @param _vault the vault to check.
     */
    function _isMarginableLong(MarginVault.Vault memory _vault, VaultDetails memory _vaultDetails)
        internal
        view
        returns (bool)
    {
        // if vault is missing a long or a short, return True
        if (!_vaultDetails.hasLong || !_vaultDetails.hasShort) return true;

        return
            _vault.longOtokens[0] != _vault.shortOtokens[0] &&
            _vaultDetails.longUnderlyingAsset == _vaultDetails.shortUnderlyingAsset &&
            _vaultDetails.longStrikeAsset == _vaultDetails.shortStrikeAsset &&
            _vaultDetails.longCollateralAsset == _vaultDetails.shortCollateralAsset &&
            _vaultDetails.longExpiryTimestamp == _vaultDetails.shortExpiryTimestamp &&
            _vaultDetails.isLongPut == _vaultDetails.isShortPut;
    }

    /**
     * @dev if there is short option and collateral asset in the vault, ensure that the collateral asset is valid for the short option
     * @param _vault the vault to check.
     */
    function _isMarginableCollateral(MarginVault.Vault memory _vault, VaultDetails memory _vaultDetails)
        internal
        view
        returns (bool)
    {
        bool isMarginable = true;

        if (!_vaultDetails.hasCollateral) return isMarginable;

        if (_vaultDetails.hasShort) {
            isMarginable = _vaultDetails.shortCollateralAsset == _vault.collateralAssets[0];
        } else if (_vaultDetails.hasLong) {
            isMarginable = _vaultDetails.longCollateralAsset == _vault.collateralAssets[0];
        }

        return isMarginable;
    }

    /**
     * @notice convert an amount in asset A to equivalent amount of asset B, based on a live price
     * @dev function includes the amount and applies .mul() first to increase the accuracy
     * @param _amount amount in asset A
     * @param _assetA asset A
     * @param _assetB asset B
     * @return _amount in asset B
     */
    function _convertAmountOnLivePrice(
        FPI.FixedPointInt memory _amount,
        address _assetA,
        address _assetB
    ) internal view returns (FPI.FixedPointInt memory) {
        if (_assetA == _assetB) {
            return _amount;
        }
        uint256 priceA = oracle.getPrice(_assetA);
        uint256 priceB = oracle.getPrice(_assetB);
        // amount A * price A in USD = amount B * price B in USD
        // amount B = amount A * price A / price B
        return _amount.mul(FPI.fromScaledUint(priceA, BASE)).div(FPI.fromScaledUint(priceB, BASE));
    }

    /**
     * @notice convert an amount in asset A to equivalent amount of asset B, based on an expiry price
     * @dev function includes the amount and apply .mul() first to increase the accuracy
     * @param _amount amount in asset A
     * @param _assetA asset A
     * @param _assetB asset B
     * @return _amount in asset B
     */
    function _convertAmountOnExpiryPrice(
        FPI.FixedPointInt memory _amount,
        address _assetA,
        address _assetB,
        uint256 _expiry
    ) internal view returns (FPI.FixedPointInt memory) {
        if (_assetA == _assetB) {
            return _amount;
        }
        (uint256 priceA, bool priceAFinalized) = oracle.getExpiryPrice(_assetA, _expiry);
        (uint256 priceB, bool priceBFinalized) = oracle.getExpiryPrice(_assetB, _expiry);
        require(priceAFinalized && priceBFinalized, "MarginCalculator: price at expiry not finalized yet.");
        // amount A * price A in USD = amount B * price B in USD
        // amount B = amount A * price A / price B
        return _amount.mul(FPI.fromScaledUint(priceA, BASE)).div(FPI.fromScaledUint(priceB, BASE));
    }

    function getVaultDetails(MarginVault.Vault memory _vault, uint256 _vaultType)
        internal
        view
        returns (VaultDetails memory)
    {
        VaultDetails memory vaultDetails = VaultDetails(
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            false,
            false,
            false,
            false,
            false
        );

        vaultDetails.hasLong = _isNotEmpty(_vault.longOtokens);
        vaultDetails.hasShort = _isNotEmpty(_vault.shortOtokens);
        vaultDetails.hasCollateral = _isNotEmpty(_vault.collateralAssets);

        vaultDetails.vaultType = _vaultType;

        if (vaultDetails.hasLong) {
            OtokenInterface long = OtokenInterface(_vault.longOtokens[0]);
            (
                vaultDetails.longCollateralAsset,
                vaultDetails.longUnderlyingAsset,
                vaultDetails.longStrikeAsset,
                vaultDetails.longStrikePrice,
                vaultDetails.longExpiryTimestamp,
                vaultDetails.isLongPut
            ) = long.getOtokenDetails();
            vaultDetails.longCollateralDecimals = uint256(ERC20Interface(vaultDetails.longCollateralAsset).decimals());
        }

        if (vaultDetails.hasShort) {
            OtokenInterface short = OtokenInterface(_vault.shortOtokens[0]);
            (
                vaultDetails.shortCollateralAsset,
                vaultDetails.shortUnderlyingAsset,
                vaultDetails.shortStrikeAsset,
                vaultDetails.shortStrikePrice,
                vaultDetails.shortExpiryTimestamp,
                vaultDetails.isShortPut
            ) = short.getOtokenDetails();
            vaultDetails.shortCollateralDecimals = uint256(
                ERC20Interface(vaultDetails.shortCollateralAsset).decimals()
            );
        }

        if (vaultDetails.hasCollateral) {
            vaultDetails.collateralDecimals = uint256(ERC20Interface(_vault.collateralAssets[0]).decimals());
        }

        return vaultDetails;
    }

    /**
     * @dev calculate the cash value obligation for an expired vault, where a positive number is an obligation
     *
     * Formula: net = (short cash value * short amount) - ( long cash value * long Amount )
     *
     * @return cash value obligation denominated in the strike asset
     */
    function _getExpiredSpreadCashValue(
        FPI.FixedPointInt memory _shortAmount,
        FPI.FixedPointInt memory _longAmount,
        FPI.FixedPointInt memory _shortCashValue,
        FPI.FixedPointInt memory _longCashValue
    ) internal pure returns (FPI.FixedPointInt memory) {
        return _shortCashValue.mul(_shortAmount).sub(_longCashValue.mul(_longAmount));
    }

    /**
     * @dev check if asset array contain a token address
     * @return True if the array is not empty
     */
    function _isNotEmpty(address[] memory _assets) internal pure returns (bool) {
        return _assets.length > 0 && _assets[0] != address(0);
    }
}
