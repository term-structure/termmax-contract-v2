```mermaid
sequenceDiagram
    title TermMaxToken - withdrawIncomeAssets()
    actor Owner
    participant TMT as TermMaxToken
    participant aTkn as IERC20 (aToken)
    participant uTkn as IERC20 (underlying)
    participant AavePool as IAaveV3Minimal (aavePool)

    Owner->>TMT: withdrawIncomeAssets(asset, to, amount)
    activate TMT

    TMT->>aTkn: balanceOf(address(this))
    activate aTkn
    aTkn-->>TMT: aTokenBalance
    deactivate aTkn

    TMT->>uTkn: balanceOf(address(this))
    activate uTkn
    uTkn-->>TMT: underlyingBalance
    deactivate uTkn

    TMT->>TMT: (calculates availableAmount)
    TMT->>TMT: require(availableAmount >= amount)
    TMT->>TMT: withdawedIncomeAssets += amount

    alt asset == address(underlying)
        TMT->>TMT: _withdrawWithBuffer(address(underlying), to, amount)
        activate TMT #LightBlue
        Note right of TMT: Internal StakingBuffer logic
        TMT->>TMT: _bufferConfig(address(underlying))
        TMT-->>TMT: currentBufferConfig

        TMT->>TMT: (determines amountFromPool, amountFromBuffer)

        alt amountFromBuffer > 0
            TMT->>uTkn: safeTransfer(to, amountFromBuffer)
            activate uTkn
            uTkn-->>TMT: // Return signal from safeTransfer
            deactivate uTkn
        end

        alt amountFromPool > 0
            TMT->>TMT: _withdrawFromPool(address(underlying), to, amountFromPool)
            activate TMT #CornflowerBlue
            Note right of TMT: Overridden method
            TMT->>AavePool: withdraw(address(underlying), amountFromPool, to)
            activate AavePool
            AavePool-->>TMT: receivedAmount
            deactivate AavePool
            TMT->>TMT: require(receivedAmount == amountFromPool)
            deactivate TMT #CornflowerBlue
        end
        deactivate TMT #LightBlue
    else asset == address(aToken)
        TMT->>aTkn: safeTransfer(to, amount)
        activate aTkn
        aTkn-->>TMT: // Return signal from safeTransfer
        deactivate aTkn
    else
        TMT->>TMT: revert InvalidToken()
    end

    TMT->>TMT: emit WithdrawIncome(to, amount)
    TMT-->>Owner: (success)
    deactivate TMT
```