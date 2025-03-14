const EnvConfig = {
  dev: {
    BASE_URL: 'https://termmax-backend-v2-test.onrender.com',
    CHAIN_IDS: [11155111, 421614],
  },
  staging: {
    BASE_URL: 'https://termmax-api.staging.ts.finance',
    CHAIN_IDS: [11155111, 421614],
  },
  testnet: {
    BASE_URL: 'https://termmax-api.testnet.ts.finance',
    CHAIN_IDS: [11155111, 421614],
  },
  mainnet: {
    BASE_URL: 'https://termmax-api.ts.finance',
    CHAIN_IDS: [1, 42161],
  },
};

const WorkloadConfig = {
  average: [
    { duration: '1m', target: 100 },
    { duration: '4m', target: 100 },
    { duration: '1m', target: 0 },
  ],
  stress: [
    { duration: '1m', target: 700 },
    { duration: '4m', target: 700 },
    { duration: '1m', target: 0 },
  ],
  smoke: [{ duration: '1m', target: 1 }],
};

export { EnvConfig, WorkloadConfig };
