```mermaid
sequenceDiagram
    title TermMaxToken - burn()
    actor User
    participant TMT as TermMaxToken
    participant ERC20 as ERC20Upgradeable
    participant UnderlyingToken as IERC20 (underlying)
    participant AavePool as IAaveV3Minimal (aavePool)

    User->>TMT: burn(to, amount)
    activate TMT

    TMT->>ERC20: _burn(User, amount)
    activate ERC20
    ERC20-->>TMT: (updates TMT balances)
    deactivate ERC20

    TMT->>TMT: _withdrawWithBuffer(underlying, to, amount)
    activate TMT #LightBlue
    Note right of TMT: Inherited from StakingBuffer
    TMT->>TMT: _bufferConfig(underlying)
    TMT-->>TMT: bufferConfig

    TMT->>TMT: (determines withdraw amount from pool vs buffer)
    Note right of TMT: amountFromPool, amountFromBuffer

    alt amountFromBuffer > 0
        TMT->>UnderlyingToken: safeTransfer(to, amountFromBuffer)
        activate UnderlyingToken
        UnderlyingToken-->>TMT: // Return signal from safeTransfer
        deactivate UnderlyingToken
    end

    alt amountFromPool > 0
        TMT->>TMT: _withdrawFromPool(underlying, to, amountFromPool)
        activate TMT #CornflowerBlue
        Note right of TMT: Overridden method
        TMT->>AavePool: withdraw(underlying, amountFromPool, to)
        activate AavePool
        AavePool-->>TMT: receivedAmount
        deactivate AavePool
        TMT->>TMT: require(receivedAmount == amountFromPool, "AaveWithdrawFailed")
        deactivate TMT #CornflowerBlue
    end
    deactivate TMT #LightBlue

    TMT-->>User: (success)
    deactivate TMT
```