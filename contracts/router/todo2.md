- FT
  - buyFt
    - swapExactTokenForFt
    - swapExactFtForXt ??
  - sellFt
    - swapExactFtForToken


    
- XT
  - buyXt
    - swapExactTokenForXt
    - swapExactFtForXt ??
  - sellXt
    - swapExactXtForToken
    - swapExactXtForFt ??

- 
  

buyXt
sellXt

provideLiquidity
withdrawLp

redeemFxAndXtToUnderlying
lever
mintGNft
redeem

---

- caller/receiver

- _addLiquidity 不應該每一次都 emit Event (Ex. Buy FT)

- uint256 netOut -> int256 netOut
- uint256/uint128/int256 計算
uint256 / uint128 / int256



- collateral/underlying/MaxToken scale (Ex. _redeemFtAndXtToUnderlying, Xt->Underlying decimals?)

- _mintGt , gtId = gt.mint(receiver, debt, collateralData); 在前面

- GT setAuthentication(operator, )