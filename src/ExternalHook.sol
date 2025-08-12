// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager, SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

contract ExternalHook is BaseHook {
    using PoolIdLibrary for PoolKey;

    uint256 public constant BPS_DENOMINATOR = 1000000;

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: true,
            afterSwapReturnDelta: true,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // -----------------------------------------------
    // NOTE: see IHooks.sol for function documentation
    // -----------------------------------------------

    function _beforeSwap(address, PoolKey calldata key, SwapParams calldata, bytes calldata)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        
        //@audit-issue => Incorrectly returning the LP_FEE to be overriden. Pool won't do the override and default fee for dynamicFee will be used, which is 0
        // return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, uint24(1000));

        //@audit-ok => Correctly overriding the LP_FEE. Pool will override LP_FEE and will charged `overrideFee` as fee during the swap!
        uint256 overrideFee = 0 | uint256(LPFeeLibrary.OVERRIDE_FEE_FLAG);
        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, uint24(overrideFee));
    }

    function _afterSwap(
        address, 
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal override returns (bytes4, int128) {
        PoolId poolId = key.toId();
        return _collectSwapFee(key, params, delta, hookData, poolId);
    }



    function _collectSwapFee(
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData,
        PoolId poolId
    ) internal virtual returns (bytes4, int128) {

        // Follow FeeTakingHook pattern exactly: fee on unspecified token (output)
        bool specifiedTokenIs0 = (params.amountSpecified < 0 == params.zeroForOne);
        (Currency feeCurrency, int128 swapAmount) =
            (specifiedTokenIs0) ? (key.currency1, delta.amount1()) : (key.currency0, delta.amount0());

        // if fee is on output, get the absolute output amount
        if (swapAmount < 0) swapAmount = -swapAmount;

        // Load fee rate from transient storage
        uint256 feeBps = 300;

        // Calculate fee amount directly to reduce stack depth
        uint256 feeAmount = (uint256(uint128(swapAmount)) * feeBps) / BPS_DENOMINATOR;

        poolManager.take(feeCurrency, address(this), feeAmount);

        return (BaseHook.afterSwap.selector, int128(int256(feeAmount)));
    }
}
