// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";

import {EasyPosm} from "./utils/libraries/EasyPosm.sol";
import {Deployers} from "./utils/Deployers.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {ExternalHook} from "../src/ExternalHook.sol";

contract ExternalHookTest is Test, Deployers {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    Currency currency0;
    Currency currency1;

    PoolKey poolKey;

    ExternalHook hook;
    PoolId poolId;

    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;

    uint256 public constant BPS_DENOMINATOR = 1000000;

    function setUp() public {
        // Deploys all required artifacts.
        deployArtifacts();

        (currency0, currency1) = deployCurrencyPair();

        // Deploy the hook to an address with the correct flags
        address flags = address(
            uint160(
                Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
                    | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
            ) ^ (0x4444 << 144) // Namespace the hook to avoid collisions
        );
        bytes memory constructorArgs = abi.encode(poolManager); // Add all the necessary constructor arguments from the hook
        deployCodeTo("ExternalHook.sol:ExternalHook", constructorArgs, flags);
        hook = ExternalHook(flags);

        // Create the pool
        poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 0x800000, // DYNAMIC_FEE_FLAG
            tickSpacing: 60,
            hooks: IHooks(hook)
        });
        poolId = poolKey.toId();
        poolManager.initialize(poolKey, Constants.SQRT_PRICE_1_1);

        // Provide full-range liquidity to the pool
        tickLower = TickMath.minUsableTick(poolKey.tickSpacing);
        tickUpper = TickMath.maxUsableTick(poolKey.tickSpacing);

        uint128 liquidityAmount = 100e18;

        (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts.getAmountsForLiquidity(
            Constants.SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidityAmount
        );

        (tokenId,) = positionManager.mint(
            poolKey,
            tickLower,
            tickUpper,
            liquidityAmount,
            amount0Expected + 1,
            amount1Expected + 1,
            address(this),
            block.timestamp,
            Constants.ZERO_BYTES
        );
    }

    function testSwappingUsingHooks() public {
        (, , , uint24 lpFee) = poolManager.getSlot0(poolId);
        assertEq(lpFee, 0);

        assertEq(ERC20(Currency.unwrap(currency1)).balanceOf(address(hook)), 0);

        // positions were created in setup()
        (uint256 feeGrowthGlobal0Before, uint256 feeGrowthGlobal1Before) = poolManager.getFeeGrowthGlobals(poolId);

        // Perform a test swap //
        uint256 amountIn = 1e18;
        BalanceDelta swapDelta = swapRouter.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0, // Very bad, but we want to allow for unlimited price impact
            zeroForOne: true,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 1
        });

        (uint256 feeGrowthGlobal0After, uint256 feeGrowthGlobal1After) = poolManager.getFeeGrowthGlobals(poolId);
        // ------------------- //

        assertEq(int256(swapDelta.amount0()), -int256(amountIn));

        assertEq(feeGrowthGlobal0Before, feeGrowthGlobal0After);
        assertEq(feeGrowthGlobal1Before, feeGrowthGlobal1After);

        uint256 feeBps = 300;
        uint256 expectedTakenFee = (amountIn * feeBps) / BPS_DENOMINATOR;

        //@audit-info => fees taken on the afterSwap() and received on the Hook!
        uint256 hookBalance1After = ERC20(Currency.unwrap(currency1)).balanceOf(address(hook));

        assertApproxEqAbs(hookBalance1After, expectedTakenFee, 1e13);
    }
}
