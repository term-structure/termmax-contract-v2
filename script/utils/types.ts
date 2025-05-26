export interface MarketConfig {
    maturity: string;
    lendTakerFeeRatio: string;
    lendMakerFeeRatio: string;
    borrowTakerFeeRatio: string;
    borrowMakerFeeRatio: string;
    mintGtFeeRatio: string;
    mintGtFeeRef: string;
}

export interface LoanConfig {
    liquidationLtv: string;
    maxLtv: string;
    liquidatable: boolean
}

export interface TokenConfig {
    tokenAddr: string;
    priceFeedAddr: string;
    backupPriceFeedAddr: string;
    heartBeat: string;
    name: string;
    symbol: string;
    decimals: string;
    initialPrice: string;
}

export interface CollateralConfig extends TokenConfig {
    gtKeyIdentifier: string;
}

export interface MarketData {
    salt: number;
    collateralCapForGt: string;
    marketName?: string;
    marketSymbol?: string;
    marketConfig: MarketConfig;
    loanConfig: LoanConfig;
    underlyingConfig: TokenConfig;
    collateralConfig: CollateralConfig;
}

export interface DeployConfig {
    configNum: string;
    configs: {
        [key: string]: MarketData;
    };
} 