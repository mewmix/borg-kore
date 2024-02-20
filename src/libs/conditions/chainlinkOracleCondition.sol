// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "./BaseCondition.sol";

contract ChainLinkOracleCondition is BaseCondition {
    AggregatorV3Interface internal priceFeed;
    int256 private conditionPrice;
    enum Condition {GREATER, EQUAL, LESS}
    Condition private condition;

    constructor(address _oracleAddress, int256 _conditionPrice, Condition _condition) {
        priceFeed = AggregatorV3Interface(_oracleAddress);
        conditionPrice = _conditionPrice;
        condition = _condition;
    }

    function checkCondition() public override returns (bool) {
        (
            /* uint80 roundID */,
            int256 price,
            /* uint256 startedAt */,
            /* uint256 timeStamp */,
            /* uint80 answeredInRound */
        ) = priceFeed.latestRoundData();

        if (condition == Condition.GREATER) {
            return price > conditionPrice;
        } else if (condition == Condition.EQUAL) {
            return price == conditionPrice;
        } else if (condition == Condition.LESS) {
            return price < conditionPrice;
        }

        // Default to false in case of unexpected condition value
        return false;
    }
}