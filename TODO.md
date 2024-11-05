# TermMax Router Interface

## Leverage Market
- [x] buyFt (swapExactTokenForFt)
- [x] sellFt (swapExactFtForToken)
- [x] buyXt (swapExactTokenForXt)
- [x] sellXt (swapExactXtForToken)
- [x] withdrawLiquidityToToken
- [x] withdrawLiquidityToFtXt
- [x] redeem
- [ ] LeverageByToken()
- [ ] LeverageByXt()

---
## Lending Market
- [ ] borrowTokenFromCash
- [ ] borrowTokenFromColl
- [x] lendFromCash (swapExactTokenForFt)
- [x] redeem

---
## GT (Loan)
- [x] RepayByFt
- [x] RepayByTokenThroughFt

- [ ] emit Events

---

## Necessary
### LeverageByToken()
> Cash -> XT -> Flashloan -> GT

### LeverageByXt()
> XT -> Flashloan -> GT

### WithdrawLiquidityToToken()
> Withdraw LP -> get FT/XT -> redeemFtAndXt(等比例) -> sell FT/XT (if 有剩要賣掉) -> get Cash

### Borrow
> Borrow: Collateral -> Sell FT -> GT

### RepayByFT()
### RepayByTokenThroughFt()
> RepayByCashAndFT: cash buy ft -> RepayFromFT -> cash

### Basic methods..
> Buy-Sell/Lend/Lp/GT...

---

# Optional
### Execute(...)
> Integrate Multiple operations


# Redeem()
- Redeem All Ft/Xt/LpFt/LpXt