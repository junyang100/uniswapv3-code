// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import {Test, stdError} from "forge-std/Test.sol";
import "./ERC20Mintable.sol";
import "./TestUtils.sol";

import "../src/lib/LiquidityMath.sol";
import "../src/UniswapV3Factory.sol";
import "../src/UniswapV3Manager.sol";

contract MineTest is Test, TestUtils {
    ERC20Mintable weth;
    ERC20Mintable usdc;
    ERC20Mintable uni;
    UniswapV3Factory factory;
    UniswapV3Pool pool;
    UniswapV3Manager manager;

    bool transferInMintCallback = true;
    bool transferInSwapCallback = true;
    bytes extra;

    function setUp() public {
        usdc = new ERC20Mintable("USDC", "USDC", 18);
        weth = new ERC20Mintable("Ether", "ETH", 18);
        uni = new ERC20Mintable("Uniswap Coin", "UNI", 18);
        factory = new UniswapV3Factory();
        manager = new UniswapV3Manager(address(factory));

        extra = encodeExtra(address(weth), address(usdc), address(this));
    }

    function atestFee() public {
        (
            IUniswapV3Manager.MintParams[] memory mints,
            uint256 poolBalance0,
            uint256 poolBalance1
        ) = setupPool(
                PoolParams({
                    wethBalance: 10 ether,
                    usdcBalance: 150000 ether,
                    currentPrice: 5000,
                    mints: mintParams(
                        mintParams(4545, 5500, 1 ether, 5000 ether)
                    ),
                    transferInMintCallback: true,
                    transferInSwapCallback: true,
                    mintLiquidity: true
                })
            );

        uint256 swapAmount = 42 ether; // 42 USDC
        usdc.mint(address(this), swapAmount);
        usdc.approve(address(manager), swapAmount);

        (uint256 userBalance0Before, uint256 userBalance1Before) = (
            weth.balanceOf(address(this)),
            usdc.balanceOf(address(this))
        );

        uint256 amountOut = manager.swapSingle(
            IUniswapV3Manager.SwapSingleParams({
                tokenIn: address(usdc),
                tokenOut: address(weth),
                fee: 3000,
                amountIn: swapAmount,
                sqrtPriceLimitX96: sqrtP(5004)
            })
        );
        uint256 expectedAmountOut = 0.008371593947078467 ether;
        assertEq(amountOut, expectedAmountOut, "invalid ETH out");

        assertMany(
            ExpectedMany({
                pool: pool,
                tokens: [weth, usdc],
                liquidity: liquidity(mints[0], 5000),
                sqrtPriceX96: 5604422590555458105735383351329, // 5003.830413717752
                tick: 85183,
                fees: [
                    uint256(0),
                    27727650748765949686643356806934465 // 0.000081484242041869
                ],
                userBalances: [
                    userBalance0Before + amountOut,
                    userBalance1Before - swapAmount
                ],
                poolBalances: [
                    poolBalance0 - amountOut,
                    poolBalance1 + swapAmount
                ],
                position: ExpectedPositionShort({
                    ticks: [mints[0].lowerTick, mints[0].upperTick],
                    liquidity: liquidity(mints[0], 5000),
                    feeGrowth: [uint256(0), 0],
                    tokensOwed: [uint128(0), 0]
                }),
                ticks: mintParamsToTicks(mints[0], 5000),
                observation: ExpectedObservationShort({
                    index: 0,
                    timestamp: 1,
                    tickCumulative: 0,
                    initialized: true
                })
            })
        );
        console.log("-------------------------------");
        uint256 poolBalance0Tmp;
        uint256 poolBalance1Tmp;
        usdc.approve(address(manager), 5000 ether);
        (poolBalance0Tmp, poolBalance1Tmp) = manager.mint(
            mintParams(4545, 5600, 1 ether, 5000 ether)
        );

        console.log("-------------------------------");
        usdc.approve(address(manager), 5000 ether);
        (poolBalance0Tmp, poolBalance1Tmp) = manager.mint(
            mintParams(4545, 5600, 1 ether, 5000 ether)
        );
    }

    function testSwap() public {
        setupPool(
            PoolParams({
                wethBalance: 10 ether,
                usdcBalance: 150000 ether,
                currentPrice: 5000,
                mints: mintParams(
                    mintParams(4545, 5500, 1 ether, 5000 ether)
                    // mintParams(5500, 6600, 1 ether, 5000 ether)
                ),
                transferInMintCallback: true,
                transferInSwapCallback: true,
                mintLiquidity: true
            })
        );
        console.log("-------------swap------------------");

        uint256 swapAmount = 50 ether; // 42 USDC
        usdc.mint(address(this), swapAmount);
        usdc.approve(address(manager), swapAmount);

        uint256 amountOut = manager.swapSingle(
            IUniswapV3Manager.SwapSingleParams({
                tokenIn: address(usdc),
                tokenOut: address(weth),
                fee: 3000,
                amountIn: swapAmount,
                sqrtPriceLimitX96: 0
            })
        );
        console.log("amountOut:", amountOut);
    }

    ////////////////////////////////////////////////////////////////////////////
    //
    // INTERNAL
    //
    ////////////////////////////////////////////////////////////////////////////
    struct PoolParams {
        uint256 wethBalance;
        uint256 usdcBalance;
        uint256 currentPrice;
        IUniswapV3Manager.MintParams[] mints;
        bool transferInMintCallback;
        bool transferInSwapCallback;
        bool mintLiquidity;
    }

    struct PoolParamsFull {
        ERC20Mintable token0;
        ERC20Mintable token1;
        uint256 token0Balance;
        uint256 token1Balance;
        uint256 currentPrice;
        IUniswapV3Manager.MintParams[] mints;
        bool transferInMintCallback;
        bool transferInSwapCallback;
        bool mintLiquidity;
    }

    function mintParams(
        ERC20Mintable token0,
        ERC20Mintable token1,
        uint256 lowerPrice,
        uint256 upperPrice,
        uint256 amount0,
        uint256 amount1
    ) internal pure returns (IUniswapV3Manager.MintParams memory params) {
        params = mintParams(
            address(token0),
            address(token1),
            lowerPrice,
            upperPrice,
            amount0,
            amount1
        );
    }

    function mintParams(
        uint256 lowerPrice,
        uint256 upperPrice,
        uint256 amount0,
        uint256 amount1
    ) internal view returns (IUniswapV3Manager.MintParams memory params) {
        params = mintParams(
            weth,
            usdc,
            lowerPrice,
            upperPrice,
            amount0,
            amount1
        );
    }

    function mintParams(
        IUniswapV3Manager.MintParams memory mint
    ) internal pure returns (IUniswapV3Manager.MintParams[] memory mints) {
        mints = new IUniswapV3Manager.MintParams[](1);
        mints[0] = mint;
    }

    function mintParams(
        IUniswapV3Manager.MintParams memory mint1,
        IUniswapV3Manager.MintParams memory mint2
    ) internal pure returns (IUniswapV3Manager.MintParams[] memory mints) {
        mints = new IUniswapV3Manager.MintParams[](2);
        mints[0] = mint1;
        mints[1] = mint2;
    }

    function mintParams(
        IUniswapV3Manager.MintParams memory mint1,
        IUniswapV3Manager.MintParams memory mint2,
        IUniswapV3Manager.MintParams memory mint3
    ) internal pure returns (IUniswapV3Manager.MintParams[] memory mints) {
        mints = new IUniswapV3Manager.MintParams[](3);
        mints[0] = mint1;
        mints[1] = mint2;
        mints[2] = mint3;
    }

    function mintParamsToTicks(
        IUniswapV3Manager.MintParams memory mint,
        uint256 currentPrice
    ) internal pure returns (ExpectedTickShort[2] memory ticks) {
        uint128 liq = liquidity(mint, currentPrice);

        ticks[0] = ExpectedTickShort({
            tick: mint.lowerTick,
            initialized: true,
            liquidityGross: liq,
            liquidityNet: int128(liq)
        });
        ticks[1] = ExpectedTickShort({
            tick: mint.upperTick,
            initialized: true,
            liquidityGross: liq,
            liquidityNet: -int128(liq)
        });
    }

    function liquidity(
        IUniswapV3Manager.MintParams memory params,
        uint256 currentPrice
    ) internal pure returns (uint128 liquidity_) {
        liquidity_ = LiquidityMath.getLiquidityForAmounts(
            sqrtP(currentPrice),
            sqrtP60FromTick(params.lowerTick),
            sqrtP60FromTick(params.upperTick),
            params.amount0Desired,
            params.amount1Desired
        );
    }

    function setupPool(
        PoolParamsFull memory params
    )
        internal
        returns (
            UniswapV3Pool pool_,
            IUniswapV3Manager.MintParams[] memory mints_,
            uint256 poolBalance0,
            uint256 poolBalance1
        )
    {
        params.token0.mint(address(this), params.token0Balance);
        params.token1.mint(address(this), params.token1Balance);

        pool_ = deployPool(
            factory,
            address(params.token0),
            address(params.token1),
            3000,
            params.currentPrice
        );

        if (params.mintLiquidity) {
            params.token0.approve(address(manager), params.token0Balance);
            params.token1.approve(address(manager), params.token1Balance);

            uint256 poolBalance0Tmp;
            uint256 poolBalance1Tmp;
            for (uint256 i = 0; i < params.mints.length; i++) {
                (poolBalance0Tmp, poolBalance1Tmp) = manager.mint(
                    params.mints[i]
                );
                poolBalance0 += poolBalance0Tmp;
                poolBalance1 += poolBalance1Tmp;
            }
        }

        transferInMintCallback = params.transferInMintCallback;
        transferInSwapCallback = params.transferInSwapCallback;
        mints_ = params.mints;
    }

    function setupPool(
        PoolParams memory params
    )
        internal
        returns (
            IUniswapV3Manager.MintParams[] memory mints_,
            uint256 poolBalance0,
            uint256 poolBalance1
        )
    {
        (pool, mints_, poolBalance0, poolBalance1) = setupPool(
            PoolParamsFull({
                token0: weth,
                token1: usdc,
                token0Balance: params.wethBalance,
                token1Balance: params.usdcBalance,
                currentPrice: params.currentPrice,
                mints: params.mints,
                transferInMintCallback: params.transferInMintCallback,
                transferInSwapCallback: params.transferInSwapCallback,
                mintLiquidity: params.mintLiquidity
            })
        );
    }
}
