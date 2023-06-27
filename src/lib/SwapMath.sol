// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.14;

import "./Math.sol";

library SwapMath {
    function computeSwapStep(
        uint160 sqrtPriceCurrentX96,
        uint160 sqrtPriceTargetX96,
        uint128 liquidity,
        uint256 amountRemaining,
        uint24 fee
    )
        internal
        pure
        returns (
            uint160 sqrtPriceNextX96,
            uint256 amountIn,
            uint256 amountOut,
            uint256 feeAmount
        )
    {
        // 判断方向
        bool zeroForOne = sqrtPriceCurrentX96 >= sqrtPriceTargetX96;
        // 先扣除手续费
        uint256 amountRemainingLessFee = PRBMath.mulDiv(
            amountRemaining,
            1e6 - fee,
            1e6
        );
        // 利用价格变化、流动性公式，计算当前能提供的最大输入数量
        amountIn = zeroForOne
            ? Math.calcAmount0Delta(
                sqrtPriceCurrentX96,
                sqrtPriceTargetX96, // 获取的nextTick
                liquidity, // 当前价格区间的流动性
                true
            )
            : Math.calcAmount1Delta(
                sqrtPriceCurrentX96,
                sqrtPriceTargetX96,
                liquidity,
                true
            );
        // amountIn是当前区间能提供swap的最大输入数量
        // 超过了amountIn，则此区间全部兑换，目标价即是sqrtPriceTargetX96
        if (amountRemainingLessFee >= amountIn)
            sqrtPriceNextX96 = sqrtPriceTargetX96;
            // 可以在此区间全部兑换、则获取目标价格
        else
            sqrtPriceNextX96 = Math.getNextSqrtPriceFromInput(
                sqrtPriceCurrentX96,
                liquidity,
                amountRemainingLessFee,
                zeroForOne
            );
        // max true 到达了上限target price
        bool max = sqrtPriceNextX96 == sqrtPriceTargetX96;

        if (zeroForOne) {
            // 如果未达到上限，重新计算amountIn
            amountIn = max
                ? amountIn
                : Math.calcAmount0Delta(
                    sqrtPriceCurrentX96,
                    sqrtPriceNextX96,
                    liquidity,
                    true
                );
            amountOut = Math.calcAmount1Delta(
                sqrtPriceCurrentX96,
                sqrtPriceNextX96,
                liquidity,
                false
            );
        } else {
            amountIn = max
                ? amountIn
                : Math.calcAmount1Delta(
                    sqrtPriceCurrentX96,
                    sqrtPriceNextX96,
                    liquidity,
                    true
                );
            amountOut = Math.calcAmount0Delta(
                sqrtPriceCurrentX96,
                sqrtPriceNextX96,
                liquidity,
                false
            );
        }

        if (!max) {
            // 未达到上限、 即全部可以兑换，总兑换数量amountRemaining， 减去实际兑换数量amountIn，返回即是手续费
            feeAmount = amountRemaining - amountIn;
        } else {
            // 达到了上限，按比例计算出fee，eg  a : b = 3 : 7 -> a = 3 * b / 7 (为什么需要重新计算，是精度问题？？)
            feeAmount = Math.mulDivRoundingUp(amountIn, fee, 1e6 - fee);
        }
    }
}
