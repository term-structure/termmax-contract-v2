```mermaid
sequenceDiagram
    title TermMaxToken - mint()
    actor User
    participant TMT as TermMaxToken
    participant ERC20 as ERC20Upgradeable
    participant UnderlyingToken as IERC20 (underlying)
    participant AavePool as IAaveV3Minimal (aavePool)

    User->>TMT: mint(to, amount)
    activate TMT

    TMT->>ERC20: _mint(to, amount)
    activate ERC20
    ERC20-->>TMT: (updates TMT balances)
    deactivate ERC20

    TMT->>UnderlyingToken: safeTransferFrom(User, TMT, amount)
    activate UnderlyingToken
    UnderlyingToken-->>TMT: (transfers underlying to TMT)
    deactivate UnderlyingToken

    TMT->>TMT: _depositWithBuffer(underlying, amount)
    activate TMT #LightBlue
    Note right of TMT: Inherited from StakingBuffer
    TMT->>TMT: _bufferConfig(underlying)
    TMT-->>TMT: bufferConfig
    
    TMT->>TMT: (determines deposit amount to pool vs buffer based on bufferConfig)
    Note right of TMT: amountToPool, amountToBuffer

    alt amountToBuffer > 0
        TMT->>TMT: (updates internal buffer balance for underlying)
    end

    alt amountToPool > 0
        TMT->>TMT: _depositToPool(underlying, amountToPool)
        activate TMT #CornflowerBlue
        Note right of TMT: Overridden method
        TMT->>AavePool: supply(underlying, amountToPool, TMT, referralCode)
        activate AavePool
        AavePool-->>TMT: (Aave supplies liquidity, mints aTokens to TMT)
        deactivate AavePool
        deactivate TMT #CornflowerBlue
    end
    deactivate TMT #LightBlue

    TMT-->>User: (success)
    deactivate TMT
```