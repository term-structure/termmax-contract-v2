```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                                                                                     │
│                               TermMaxToken Contract                                 │
│                                                                                     │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                     │
│ Roles:                                                                              │
│ ┌────────────────────────┐    ┌────────────┐    ┌──────────────┐                    │
│ │ Owner/Proxy Admin      │    │   Users    │    │ Aave Protocol│                    │
│ └───────────┬────────────┘    └──────┬─────┘    └───────┬──────┘                    │
│             │                        │                  │                           │
│             │                        │                  │                           │
└─────────────┼────────────────────────┼──────────────────┼───────────────────────────┘
              │                        │                  │
              │                        │                  │
┌─────────────┼────────────────────────┼──────────────────┼───────────────────────────┐
│             │                        │                  │                           │
│ ┌───────────▼────────────────────────▼──────────────────▼─────────────────────┐     │
│ │                              Functions                                      │     │
│ └───────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                     │
│ ┌──────────────────────────────┐ ┌─────────────────────────────┐                    │
│ │     Initialization           │ │      User Operations        │                    │
│ ├──────────────────────────────┤ ├─────────────────────────────┤                    │
│ │ constructor                  │ │ mint                        │                    │
│ │ initialize                   │ │ burn                        │                    │
│ └──────────────────────────────┘ │ burnToAToken                │                    │
│                                  │ totalIncomeAssets           │                    │
│ ┌──────────────────────────────┐ └─────────────────────────────┘                    │
│ │     Owner Functions          │                                                    │
│ │  (including Proxy Admin)     │ ┌─────────────────────────────┐                    │
│ ├──────────────────────────────┤ │  Overridden Functions       │                    │
│ │ withdrawIncomeAssets         │ ├─────────────────────────────┤                    │
│ │ updateBufferConfigAndAdd     │ │ decimals                    │                    │
│ │ Reserves                     │ │ _bufferConfig               │                    │
│ │ _authorizeUpgrade            │ │ _depositToPool              │                    │
│ └──────────────────────────────┘ │ _withdrawFromPool           │                    │
│                                  └─────────────────────────────┘                    │
│ ┌──────────────────────────────┐                                                    │
│ │     Internal Functions       │                                                    │
│ ├──────────────────────────────┤                                                    │
│ │ _updateBufferConfig          │                                                    │
│ └──────────────────────────────┘                                                    │
│                                                                                     │
└─────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────┐
│                           Function Flow Diagram                                     │
└─────────────────────────────────────────────────────────────────────────────────────┘

   User                          TermMaxToken                           Aave
    │                                │                                   │
    │ ─────────► mint() ───────────► │                                   │
    │                                │ ─────► _depositWithBuffer() ────► │
    │                                │                                   │
    │ ─────────► burn() ───────────► │                                   │
    │                                │ ─────► _withdrawWithBuffer() ───► │
    │                                │                                   │
    │ ─────────► burnToAToken() ───► │                                   │
    │                                │                                   │
    │ ─────────► totalIncomeAssets()►│                                   │
    │                                │                                   │

   Owner                         TermMaxToken                           Aave
   (Proxy Admin)                     │                                   │
    │                                │                                   │
    │ ─► withdrawIncomeAssets() ───► │                                   │
    │                                │ ─────► _withdrawWithBuffer() ───► │
    │                                │                                   │
    │ ─► updateBufferConfigAndAdd ─► │                                   │
    │    Reserves()                  │                                   │
    │                                │                                   │
    │ ─► upgrade (via _authorize ──► │                                   │
    │    Upgrade)                    │                                   │
    │                                │                                   │
```

## Role Descriptions

### Owner/Proxy Admin
- Has privileged access to admin functions
- Can withdraw income generated from yield farming
- Can update buffer configuration settings
- Controls contract upgrades via the UUPS upgrade pattern
- Is the only role that can authorize implementation upgrades

### Users
- Can mint new TermMaxTokens by providing underlying assets
- Can burn their tokens to receive underlying assets or aTokens
- Can check total income assets generated

### Aave Protocol
- External protocol used for yield generation
- Receives/provides assets during deposit/withdraw operations
- Issues aTokens that accrue yield

## Function Categories

### Initialization Functions
- **constructor**: Sets up immutable variables like Aave pool address and referral code
- **initialize**: Sets up token name, symbol, decimals, and initial buffer configuration

### User Operations
- **mint**: Creates new TermMaxTokens and deposits underlying assets with buffering
- **burn**: Burns tokens and withdraws underlying assets to the specified address
- **burnToAToken**: Burns tokens and transfers aTokens directly to the user
- **totalIncomeAssets**: Calculates total yield generated by the protocol

### Admin Functions
- **withdrawIncomeAssets**: Allows owner to withdraw generated yield
- **updateBufferConfigAndAddReserves**: Updates buffer settings and adds additional reserves
- **_authorizeUpgrade**: Authorizes contract implementation upgrades (only owner)

### Internal Buffer Management
- **_updateBufferConfig**: Updates buffer configuration parameters
- **_bufferConfig**: Returns current buffer configuration
- **_depositToPool**: Handles depositing assets to Aave
- **_withdrawFromPool**: Handles withdrawing assets from Aave

### Other Overridden Functions
- **decimals**: Returns token decimals matching the underlying asset

The TermMaxToken contract is designed as an upgradeable ERC20 token that wraps an underlying asset, automatically deposits it in Aave for yield generation, and manages liquidity buffers to optimize gas costs and availability.