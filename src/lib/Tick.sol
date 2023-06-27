// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.14;

import "./LiquidityMath.sol";
import "./Math.sol";

import "forge-std/console.sol";

library Tick {
    struct Info {
        bool initialized;
        // total liquidity at tick
        // 这个是无符号的数，用于判断tickBitMap是否flip
        uint128 liquidityGross;
        // amount of liqudiity added or subtracted when tick is crossed
        // 这个是有符号的数，代表cross时需要增减的流动性数
        int128 liquidityNet;
        // fee growth on the other side of this tick (relative to the current tick)
        uint256 feeGrowthOutside0X128;
        uint256 feeGrowthOutside1X128;
    }

    function update(
        mapping(int24 => Tick.Info) storage self,
        int24 tick,
        int24 currentTick,
        int128 liquidityDelta,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128,
        bool upper
    ) internal returns (bool flipped) {
        Tick.Info storage tickInfo = self[tick];
        // 记录之前的该tick的流动性
        uint128 liquidityBefore = tickInfo.liquidityGross;
        // 记录add/remove之后的流动性
        uint128 liquidityAfter = LiquidityMath.addLiquidity(
            liquidityBefore,
            liquidityDelta
        );
        // true 为初始化或全部移除
        flipped = (liquidityAfter == 0) != (liquidityBefore == 0);
        // 初始化tick
        if (liquidityBefore == 0) {
            // by convention, assume that all previous fees were collected below
            // the tick
            // 假设之前的流动性都在tick之下、？？？？ 可以消除？？
            // 如果 tick在当前价格对应的tick之下、记录外部流动性（小于tick的所有流动性）
            if (tick <= currentTick) {
                tickInfo.feeGrowthOutside0X128 = feeGrowthGlobal0X128;
                tickInfo.feeGrowthOutside1X128 = feeGrowthGlobal1X128;
            }

            tickInfo.initialized = true;
        }
        // 更新tick新的流动性
        tickInfo.liquidityGross = liquidityAfter;
        // 上限 net减去变化、下限 net加上变化
        tickInfo.liquidityNet = upper
            ? int128(int256(tickInfo.liquidityNet) - liquidityDelta)
            : int128(int256(tickInfo.liquidityNet) + liquidityDelta);
    }

    function cross(
        mapping(int24 => Tick.Info) storage self,
        int24 tick,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128
    ) internal returns (int128 liquidityDelta) {
        console.log("-----cross------");
        Tick.Info storage info = self[tick];
        // 穿越上边界 即 当前价格大于了 这个tick，outside是小于该tick的fee
        // 穿越下边界 即 当前价格小于了 这个tick， outside是大于该tick的fee
        // cross的过程的相当于 反转了外侧fee的方向
        info.feeGrowthOutside0X128 =
            feeGrowthGlobal0X128 -
            info.feeGrowthOutside0X128;
        console.log("feeGrowthGlobal0X128:", feeGrowthGlobal0X128);
        console.log("feeGrowthOutside0X128:", info.feeGrowthOutside0X128);

        info.feeGrowthOutside1X128 =
            feeGrowthGlobal1X128 -
            info.feeGrowthOutside1X128;

        console.log("feeGrowthGlobal1X128:", feeGrowthGlobal1X128);
        console.log("feeGrowthOutside1X128:", info.feeGrowthOutside1X128);
        console.log("-----cross-end------");
        // 流动性变化数
        liquidityDelta = info.liquidityNet;
    }

    function getFeeGrowthInside(
        mapping(int24 => Tick.Info) storage self,
        int24 lowerTick_,
        int24 upperTick_,
        int24 currentTick,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128
    )
        internal
        view
        returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128)
    {
        Tick.Info storage lowerTick = self[lowerTick_];
        Tick.Info storage upperTick = self[upperTick_];

        uint256 feeGrowthBelow0X128;
        uint256 feeGrowthBelow1X128;
        if (currentTick >= lowerTick_) {
            feeGrowthBelow0X128 = lowerTick.feeGrowthOutside0X128;
            feeGrowthBelow1X128 = lowerTick.feeGrowthOutside1X128;
        } else {
            feeGrowthBelow0X128 =
                feeGrowthGlobal0X128 -
                lowerTick.feeGrowthOutside0X128;
            feeGrowthBelow1X128 =
                feeGrowthGlobal1X128 -
                lowerTick.feeGrowthOutside1X128;
        }

        uint256 feeGrowthAbove0X128;
        uint256 feeGrowthAbove1X128;
        if (currentTick < upperTick_) {
            feeGrowthAbove0X128 = upperTick.feeGrowthOutside0X128;
            feeGrowthAbove1X128 = upperTick.feeGrowthOutside1X128;
        } else {
            feeGrowthAbove0X128 =
                feeGrowthGlobal0X128 -
                upperTick.feeGrowthOutside0X128;
            feeGrowthAbove1X128 =
                feeGrowthGlobal1X128 -
                upperTick.feeGrowthOutside1X128;
        }

        feeGrowthInside0X128 =
            feeGrowthGlobal0X128 -
            feeGrowthBelow0X128 -
            feeGrowthAbove0X128;
        feeGrowthInside1X128 =
            feeGrowthGlobal1X128 -
            feeGrowthBelow1X128 -
            feeGrowthAbove1X128;
    }
}
