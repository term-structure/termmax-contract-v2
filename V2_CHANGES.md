# TermMax V2 Changes

## 1. Market Architecture Changes

### Removal of LP Token System

- V2 removes the LP token-based liquidity provision system from V1
- Simplifies market interaction by eliminating the need for LP token management

### New Order Contract System

- Trading functions moved from main market contract to dedicated order contracts
- Each order contract can define and manage its own trading curve
- Enables multiple trading strategies within the same market
- Provides greater flexibility in market making strategies

### Automated Market Maker Improvements

- Introduction of customizable trading curves per order
- Multiple curves can coexist in the same market
- Enhanced price discovery through curve competition
- More efficient market making with specialized curves

## 2. New Vault System

V2 introduces a new Vault system that enables automated yield generation and portfolio management. This is a significant architectural addition that was not present in V1.

### Core Vault Features

1. **ERC4626-Compliant Vault**

   - Implements the ERC4626 standard for tokenized vault strategies
   - Provides standardized deposit/withdraw mechanisms
   - Offers share-based accounting for user positions

2. **Role-Based Access Control**

   - Guardian: Emergency controls and parameter management
   - Curator: Market whitelisting and strategy oversight
   - Allocator: Position adjustments
   - Owner: Protocol governance and role management

3. **Order Management System**

   - Supply queue for managing deposit allocations
   - Withdraw queue for managing redemptions
   - Bad debt handling mechanism for risk management

4. **Dynamic Interest System**

   - Real-time APR adjustments based on vault profit changes
   - Automated annual interest outlook updates
   - Interest accrual tracking across different market positions
   - Optimized yield generation through dynamic rate adjustments
   - The interest rate will not be negative, and the safety of investors' funds will be guaranteed through mandatory inspections

5. **Performance Fee Structure**

   - Configurable performance fee rate
   - Earn more profit through performance incentives for curators
   - Timelock protection for fee parameter changes

6. **Market Integration**

   - Market whitelisting system for security
   - Dynamic capacity management
   - Maturity-based position management

### Technical Implementation of Vault

1. **BaseVault Contract**

   - Core accounting logic
   - Dynamic interest calculations and updates
   - Order tracking and management
   - Position management utilities

2. **TermMaxVault Contract**

   - ERC4626 implementation
   - Role-based access control
   - Parameter management with timelock
   - Market whitelist management

3. **Key Functions**
   - createOrder: Create new market positions
   - updateOrders: Modify existing positions
   - updateSupplyQueue: Optimize deposit allocations
   - updateWithdrawQueue: Manage redemption order
   - dealBadDebt: Handle underwater positions
   - accruedInterest: Calculate and update APR
   - swapCallback: Handle swap events and update APR

## Impact on Existing System

The V2 changes fundamentally improve the TermMax protocol by:

- Removing LP token complexity
- Enabling flexible market making through order contracts
- Supporting multiple trading curves
- Adding automated portfolio management through vaults
