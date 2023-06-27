// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.14;

import "prb-math/PRBMath.sol";

import "./FixedPoint128.sol";
import "./LiquidityMath.sol";
import "forge-std/console.sol";

library Position {
    struct Info {
        uint128 liquidity;
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
        uint128 tokensOwed0;
        uint128 tokensOwed1;
    }

    function get(
        mapping(bytes32 => Info) storage self,
        address owner,
        int24 lowerTick,
        int24 upperTick
    ) internal view returns (Position.Info storage position) {
        position = self[
            keccak256(abi.encodePacked(owner, lowerTick, upperTick))
        ];
    }

    function update(
        Info storage self,
        int128 liquidityDelta,
        uint256 feeGrowthInside0X128,
        uint256 feeGrowthInside1X128
    ) internal {
        // 更新的时候会结算当前已经获得的fee（两个token）
        // 如果是首次添加，self.liquidity = 0
        // 如果后续添加，feeGrowthInside0X128 - self.feeGrowthInside0LastX128 减去了首次添加之前的fee
        uint128 tokensOwed0 = uint128(
            PRBMath.mulDiv(
                feeGrowthInside0X128 - self.feeGrowthInside0LastX128,
                self.liquidity,
                FixedPoint128.Q128
            )
        );
        uint128 tokensOwed1 = uint128(
            PRBMath.mulDiv(
                feeGrowthInside1X128 - self.feeGrowthInside1LastX128,
                self.liquidity,
                FixedPoint128.Q128
            )
        );
        console.log("self.liquidity", self.liquidity);
        console.log("tokensOwed1", tokensOwed1);
        console.log("feeGrowthInside1X128", feeGrowthInside1X128);
        // 添加/删除流动性
        self.liquidity = LiquidityMath.addLiquidity(
            self.liquidity,
            liquidityDelta
        );
        // 记录本次最新的fee
        self.feeGrowthInside0LastX128 = feeGrowthInside0X128;
        self.feeGrowthInside1LastX128 = feeGrowthInside1X128;
        // 更新fee数量
        if (tokensOwed0 > 0 || tokensOwed1 > 0) {
            self.tokensOwed0 += tokensOwed0;
            self.tokensOwed1 += tokensOwed1;
        }
    }
}
