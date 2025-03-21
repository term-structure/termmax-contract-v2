export interface MarketConfig {
    treasurer: string;
    maturity: string;
    lendTakerFeeRatio: string;
    lendMakerFeeRatio: string;
    borrowTakerFeeRatio: string;
    borrowMakerFeeRatio: string;
    issueFtFeeRatio: string;
    mintGtFeeRef: string;
    redeemFeeRatio: string;
}

export interface LoanConfig {
    liquidationLtv: string;
    maxLtv: string;
    liquidatable: boolean
}

export interface TokenConfig {
    tokenAddr: string;
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