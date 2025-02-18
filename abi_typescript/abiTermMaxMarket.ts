// This file is auto-generated. Do not edit manually.

export const abiTermMaxMarket = [
  {
    type: 'constructor',
    inputs: [
      {
        name: 'MINTABLE_ERC20_IMPLEMENT_',
        type: 'address',
        internalType: 'address',
      },
      {
        name: 'TERMMAX_ORDER_IMPLEMENT_',
        type: 'address',
        internalType: 'address',
      },
    ],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'acceptOwnership',
    inputs: [],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'burn',
    inputs: [
      {
        name: 'recipient',
        type: 'address',
        internalType: 'address',
      },
      {
        name: 'debtTokenAmt',
        type: 'uint256',
        internalType: 'uint256',
      },
    ],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'config',
    inputs: [],
    outputs: [
      {
        name: '',
        type: 'tuple',
        internalType: 'struct MarketConfig',
        components: [
          {
            name: 'treasurer',
            type: 'address',
            internalType: 'address',
          },
          {
            name: 'maturity',
            type: 'uint64',
            internalType: 'uint64',
          },
          {
            name: 'feeConfig',
            type: 'tuple',
            internalType: 'struct FeeConfig',
            components: [
              {
                name: 'lendTakerFeeRatio',
                type: 'uint32',
                internalType: 'uint32',
              },
              {
                name: 'lendMakerFeeRatio',
                type: 'uint32',
                internalType: 'uint32',
              },
              {
                name: 'borrowTakerFeeRatio',
                type: 'uint32',
                internalType: 'uint32',
              },
              {
                name: 'borrowMakerFeeRatio',
                type: 'uint32',
                internalType: 'uint32',
              },
              {
                name: 'issueFtFeeRatio',
                type: 'uint32',
                internalType: 'uint32',
              },
              {
                name: 'issueFtFeeRef',
                type: 'uint32',
                internalType: 'uint32',
              },
              {
                name: 'redeemFeeRatio',
                type: 'uint32',
                internalType: 'uint32',
              },
            ],
          },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'createOrder',
    inputs: [
      {
        name: 'maker',
        type: 'address',
        internalType: 'address',
      },
      {
        name: 'maxXtReserve',
        type: 'uint256',
        internalType: 'uint256',
      },
      {
        name: 'swapTrigger',
        type: 'address',
        internalType: 'contract ISwapCallback',
      },
      {
        name: 'curveCuts',
        type: 'tuple',
        internalType: 'struct CurveCuts',
        components: [
          {
            name: 'lendCurveCuts',
            type: 'tuple[]',
            internalType: 'struct CurveCut[]',
            components: [
              {
                name: 'xtReserve',
                type: 'uint256',
                internalType: 'uint256',
              },
              {
                name: 'liqSquare',
                type: 'uint256',
                internalType: 'uint256',
              },
              {
                name: 'offset',
                type: 'int256',
                internalType: 'int256',
              },
            ],
          },
          {
            name: 'borrowCurveCuts',
            type: 'tuple[]',
            internalType: 'struct CurveCut[]',
            components: [
              {
                name: 'xtReserve',
                type: 'uint256',
                internalType: 'uint256',
              },
              {
                name: 'liqSquare',
                type: 'uint256',
                internalType: 'uint256',
              },
              {
                name: 'offset',
                type: 'int256',
                internalType: 'int256',
              },
            ],
          },
        ],
      },
    ],
    outputs: [
      {
        name: 'order',
        type: 'address',
        internalType: 'contract ITermMaxOrder',
      },
    ],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'initialize',
    inputs: [
      {
        name: 'params',
        type: 'tuple',
        internalType: 'struct MarketInitialParams',
        components: [
          {
            name: 'collateral',
            type: 'address',
            internalType: 'address',
          },
          {
            name: 'debtToken',
            type: 'address',
            internalType: 'contract IERC20Metadata',
          },
          {
            name: 'admin',
            type: 'address',
            internalType: 'address',
          },
          {
            name: 'gtImplementation',
            type: 'address',
            internalType: 'address',
          },
          {
            name: 'marketConfig',
            type: 'tuple',
            internalType: 'struct MarketConfig',
            components: [
              {
                name: 'treasurer',
                type: 'address',
                internalType: 'address',
              },
              {
                name: 'maturity',
                type: 'uint64',
                internalType: 'uint64',
              },
              {
                name: 'feeConfig',
                type: 'tuple',
                internalType: 'struct FeeConfig',
                components: [
                  {
                    name: 'lendTakerFeeRatio',
                    type: 'uint32',
                    internalType: 'uint32',
                  },
                  {
                    name: 'lendMakerFeeRatio',
                    type: 'uint32',
                    internalType: 'uint32',
                  },
                  {
                    name: 'borrowTakerFeeRatio',
                    type: 'uint32',
                    internalType: 'uint32',
                  },
                  {
                    name: 'borrowMakerFeeRatio',
                    type: 'uint32',
                    internalType: 'uint32',
                  },
                  {
                    name: 'issueFtFeeRatio',
                    type: 'uint32',
                    internalType: 'uint32',
                  },
                  {
                    name: 'issueFtFeeRef',
                    type: 'uint32',
                    internalType: 'uint32',
                  },
                  {
                    name: 'redeemFeeRatio',
                    type: 'uint32',
                    internalType: 'uint32',
                  },
                ],
              },
            ],
          },
          {
            name: 'loanConfig',
            type: 'tuple',
            internalType: 'struct LoanConfig',
            components: [
              {
                name: 'oracle',
                type: 'address',
                internalType: 'contract IOracle',
              },
              {
                name: 'liquidationLtv',
                type: 'uint32',
                internalType: 'uint32',
              },
              {
                name: 'maxLtv',
                type: 'uint32',
                internalType: 'uint32',
              },
              {
                name: 'liquidatable',
                type: 'bool',
                internalType: 'bool',
              },
            ],
          },
          {
            name: 'gtInitalParams',
            type: 'bytes',
            internalType: 'bytes',
          },
          {
            name: 'tokenName',
            type: 'string',
            internalType: 'string',
          },
          {
            name: 'tokenSymbol',
            type: 'string',
            internalType: 'string',
          },
        ],
      },
    ],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'issueFt',
    inputs: [
      {
        name: 'recipient',
        type: 'address',
        internalType: 'address',
      },
      {
        name: 'debt',
        type: 'uint128',
        internalType: 'uint128',
      },
      {
        name: 'collateralData',
        type: 'bytes',
        internalType: 'bytes',
      },
    ],
    outputs: [
      {
        name: 'gtId',
        type: 'uint256',
        internalType: 'uint256',
      },
      {
        name: 'ftOutAmt',
        type: 'uint128',
        internalType: 'uint128',
      },
    ],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'issueFtByExistedGt',
    inputs: [
      {
        name: 'recipient',
        type: 'address',
        internalType: 'address',
      },
      {
        name: 'debt',
        type: 'uint128',
        internalType: 'uint128',
      },
      {
        name: 'gtId',
        type: 'uint256',
        internalType: 'uint256',
      },
    ],
    outputs: [
      {
        name: 'ftOutAmt',
        type: 'uint128',
        internalType: 'uint128',
      },
    ],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'issueFtFeeRatio',
    inputs: [],
    outputs: [
      {
        name: '',
        type: 'uint256',
        internalType: 'uint256',
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'leverageByXt',
    inputs: [
      {
        name: 'recipient',
        type: 'address',
        internalType: 'address',
      },
      {
        name: 'xtAmt',
        type: 'uint128',
        internalType: 'uint128',
      },
      {
        name: 'callbackData',
        type: 'bytes',
        internalType: 'bytes',
      },
    ],
    outputs: [
      {
        name: 'gtId',
        type: 'uint256',
        internalType: 'uint256',
      },
    ],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'mint',
    inputs: [
      {
        name: 'recipient',
        type: 'address',
        internalType: 'address',
      },
      {
        name: 'debtTokenAmt',
        type: 'uint256',
        internalType: 'uint256',
      },
    ],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'owner',
    inputs: [],
    outputs: [
      {
        name: '',
        type: 'address',
        internalType: 'address',
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'pendingOwner',
    inputs: [],
    outputs: [
      {
        name: '',
        type: 'address',
        internalType: 'address',
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'redeem',
    inputs: [
      {
        name: 'ftAmount',
        type: 'uint256',
        internalType: 'uint256',
      },
      {
        name: 'recipient',
        type: 'address',
        internalType: 'address',
      },
    ],
    outputs: [
      {
        name: '',
        type: 'uint256',
        internalType: 'uint256',
      },
    ],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'renounceOwnership',
    inputs: [],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'tokens',
    inputs: [],
    outputs: [
      {
        name: '',
        type: 'address',
        internalType: 'contract IMintableERC20',
      },
      {
        name: '',
        type: 'address',
        internalType: 'contract IMintableERC20',
      },
      {
        name: '',
        type: 'address',
        internalType: 'contract IGearingToken',
      },
      {
        name: '',
        type: 'address',
        internalType: 'address',
      },
      {
        name: '',
        type: 'address',
        internalType: 'contract IERC20',
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'transferOwnership',
    inputs: [
      {
        name: 'newOwner',
        type: 'address',
        internalType: 'address',
      },
    ],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'updateGtConfig',
    inputs: [
      {
        name: 'configData',
        type: 'bytes',
        internalType: 'bytes',
      },
    ],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'updateMarketConfig',
    inputs: [
      {
        name: 'newConfig',
        type: 'tuple',
        internalType: 'struct MarketConfig',
        components: [
          {
            name: 'treasurer',
            type: 'address',
            internalType: 'address',
          },
          {
            name: 'maturity',
            type: 'uint64',
            internalType: 'uint64',
          },
          {
            name: 'feeConfig',
            type: 'tuple',
            internalType: 'struct FeeConfig',
            components: [
              {
                name: 'lendTakerFeeRatio',
                type: 'uint32',
                internalType: 'uint32',
              },
              {
                name: 'lendMakerFeeRatio',
                type: 'uint32',
                internalType: 'uint32',
              },
              {
                name: 'borrowTakerFeeRatio',
                type: 'uint32',
                internalType: 'uint32',
              },
              {
                name: 'borrowMakerFeeRatio',
                type: 'uint32',
                internalType: 'uint32',
              },
              {
                name: 'issueFtFeeRatio',
                type: 'uint32',
                internalType: 'uint32',
              },
              {
                name: 'issueFtFeeRef',
                type: 'uint32',
                internalType: 'uint32',
              },
              {
                name: 'redeemFeeRatio',
                type: 'uint32',
                internalType: 'uint32',
              },
            ],
          },
        ],
      },
    ],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'updateOrderFeeRate',
    inputs: [
      {
        name: 'order',
        type: 'address',
        internalType: 'contract ITermMaxOrder',
      },
      {
        name: 'newFeeConfig',
        type: 'tuple',
        internalType: 'struct FeeConfig',
        components: [
          {
            name: 'lendTakerFeeRatio',
            type: 'uint32',
            internalType: 'uint32',
          },
          {
            name: 'lendMakerFeeRatio',
            type: 'uint32',
            internalType: 'uint32',
          },
          {
            name: 'borrowTakerFeeRatio',
            type: 'uint32',
            internalType: 'uint32',
          },
          {
            name: 'borrowMakerFeeRatio',
            type: 'uint32',
            internalType: 'uint32',
          },
          {
            name: 'issueFtFeeRatio',
            type: 'uint32',
            internalType: 'uint32',
          },
          {
            name: 'issueFtFeeRef',
            type: 'uint32',
            internalType: 'uint32',
          },
          {
            name: 'redeemFeeRatio',
            type: 'uint32',
            internalType: 'uint32',
          },
        ],
      },
    ],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'event',
    name: 'Burn',
    inputs: [
      {
        name: 'caller',
        type: 'address',
        indexed: true,
        internalType: 'address',
      },
      {
        name: 'receiver',
        type: 'address',
        indexed: true,
        internalType: 'address',
      },
      {
        name: 'amount',
        type: 'uint256',
        indexed: false,
        internalType: 'uint256',
      },
    ],
    anonymous: false,
  },
  {
    type: 'event',
    name: 'CreateOrder',
    inputs: [
      {
        name: 'maker',
        type: 'address',
        indexed: true,
        internalType: 'address',
      },
      {
        name: 'order',
        type: 'address',
        indexed: true,
        internalType: 'contract ITermMaxOrder',
      },
    ],
    anonymous: false,
  },
  {
    type: 'event',
    name: 'Initialized',
    inputs: [
      {
        name: 'version',
        type: 'uint64',
        indexed: false,
        internalType: 'uint64',
      },
    ],
    anonymous: false,
  },
  {
    type: 'event',
    name: 'IssueFt',
    inputs: [
      {
        name: 'caller',
        type: 'address',
        indexed: true,
        internalType: 'address',
      },
      {
        name: 'recipient',
        type: 'address',
        indexed: true,
        internalType: 'address',
      },
      {
        name: 'gtId',
        type: 'uint256',
        indexed: true,
        internalType: 'uint256',
      },
      {
        name: 'debtAmt',
        type: 'uint128',
        indexed: false,
        internalType: 'uint128',
      },
      {
        name: 'ftAmt',
        type: 'uint128',
        indexed: false,
        internalType: 'uint128',
      },
      {
        name: 'issueFee',
        type: 'uint128',
        indexed: false,
        internalType: 'uint128',
      },
      {
        name: 'collateralData',
        type: 'bytes',
        indexed: false,
        internalType: 'bytes',
      },
    ],
    anonymous: false,
  },
  {
    type: 'event',
    name: 'IssueFtByExistedGt',
    inputs: [
      {
        name: 'caller',
        type: 'address',
        indexed: true,
        internalType: 'address',
      },
      {
        name: 'recipient',
        type: 'address',
        indexed: true,
        internalType: 'address',
      },
      {
        name: 'gtId',
        type: 'uint256',
        indexed: true,
        internalType: 'uint256',
      },
      {
        name: 'debtAmt',
        type: 'uint128',
        indexed: false,
        internalType: 'uint128',
      },
      {
        name: 'ftAmt',
        type: 'uint128',
        indexed: false,
        internalType: 'uint128',
      },
      {
        name: 'issueFee',
        type: 'uint128',
        indexed: false,
        internalType: 'uint128',
      },
    ],
    anonymous: false,
  },
  {
    type: 'event',
    name: 'MarketInitialized',
    inputs: [
      {
        name: 'collateral',
        type: 'address',
        indexed: true,
        internalType: 'address',
      },
      {
        name: 'underlying',
        type: 'address',
        indexed: true,
        internalType: 'contract IERC20',
      },
      {
        name: 'maturity',
        type: 'uint64',
        indexed: false,
        internalType: 'uint64',
      },
      {
        name: 'ft',
        type: 'address',
        indexed: false,
        internalType: 'contract IMintableERC20',
      },
      {
        name: 'xt',
        type: 'address',
        indexed: false,
        internalType: 'contract IMintableERC20',
      },
      {
        name: 'gt',
        type: 'address',
        indexed: false,
        internalType: 'contract IGearingToken',
      },
    ],
    anonymous: false,
  },
  {
    type: 'event',
    name: 'Mint',
    inputs: [
      {
        name: 'caller',
        type: 'address',
        indexed: true,
        internalType: 'address',
      },
      {
        name: 'receiver',
        type: 'address',
        indexed: true,
        internalType: 'address',
      },
      {
        name: 'amount',
        type: 'uint256',
        indexed: false,
        internalType: 'uint256',
      },
    ],
    anonymous: false,
  },
  {
    type: 'event',
    name: 'MintGt',
    inputs: [
      {
        name: 'loanReceiver',
        type: 'address',
        indexed: true,
        internalType: 'address',
      },
      {
        name: 'gtReceiver',
        type: 'address',
        indexed: true,
        internalType: 'address',
      },
      {
        name: 'gtId',
        type: 'uint256',
        indexed: true,
        internalType: 'uint256',
      },
      {
        name: 'debtAmt',
        type: 'uint128',
        indexed: false,
        internalType: 'uint128',
      },
      {
        name: 'collateralData',
        type: 'bytes',
        indexed: false,
        internalType: 'bytes',
      },
    ],
    anonymous: false,
  },
  {
    type: 'event',
    name: 'OwnershipTransferStarted',
    inputs: [
      {
        name: 'previousOwner',
        type: 'address',
        indexed: true,
        internalType: 'address',
      },
      {
        name: 'newOwner',
        type: 'address',
        indexed: true,
        internalType: 'address',
      },
    ],
    anonymous: false,
  },
  {
    type: 'event',
    name: 'OwnershipTransferred',
    inputs: [
      {
        name: 'previousOwner',
        type: 'address',
        indexed: true,
        internalType: 'address',
      },
      {
        name: 'newOwner',
        type: 'address',
        indexed: true,
        internalType: 'address',
      },
    ],
    anonymous: false,
  },
  {
    type: 'event',
    name: 'Redeem',
    inputs: [
      {
        name: 'caller',
        type: 'address',
        indexed: true,
        internalType: 'address',
      },
      {
        name: 'recipient',
        type: 'address',
        indexed: true,
        internalType: 'address',
      },
      {
        name: 'proportion',
        type: 'uint128',
        indexed: false,
        internalType: 'uint128',
      },
      {
        name: 'underlyingAmt',
        type: 'uint128',
        indexed: false,
        internalType: 'uint128',
      },
      {
        name: 'feeAmt',
        type: 'uint128',
        indexed: false,
        internalType: 'uint128',
      },
      {
        name: 'deliveryData',
        type: 'bytes',
        indexed: false,
        internalType: 'bytes',
      },
    ],
    anonymous: false,
  },
  {
    type: 'event',
    name: 'UpdateMarketConfig',
    inputs: [
      {
        name: 'config',
        type: 'tuple',
        indexed: false,
        internalType: 'struct MarketConfig',
        components: [
          {
            name: 'treasurer',
            type: 'address',
            internalType: 'address',
          },
          {
            name: 'maturity',
            type: 'uint64',
            internalType: 'uint64',
          },
          {
            name: 'feeConfig',
            type: 'tuple',
            internalType: 'struct FeeConfig',
            components: [
              {
                name: 'lendTakerFeeRatio',
                type: 'uint32',
                internalType: 'uint32',
              },
              {
                name: 'lendMakerFeeRatio',
                type: 'uint32',
                internalType: 'uint32',
              },
              {
                name: 'borrowTakerFeeRatio',
                type: 'uint32',
                internalType: 'uint32',
              },
              {
                name: 'borrowMakerFeeRatio',
                type: 'uint32',
                internalType: 'uint32',
              },
              {
                name: 'issueFtFeeRatio',
                type: 'uint32',
                internalType: 'uint32',
              },
              {
                name: 'issueFtFeeRef',
                type: 'uint32',
                internalType: 'uint32',
              },
              {
                name: 'redeemFeeRatio',
                type: 'uint32',
                internalType: 'uint32',
              },
            ],
          },
        ],
      },
    ],
    anonymous: false,
  },
  {
    type: 'error',
    name: 'CanNotRedeemBeforeFinalLiquidationDeadline',
    inputs: [
      {
        name: 'liquidationDeadline',
        type: 'uint256',
        internalType: 'uint256',
      },
    ],
  },
  {
    type: 'error',
    name: 'CanNotTransferUintMax',
    inputs: [],
  },
  {
    type: 'error',
    name: 'CollateralCanNotEqualUnderlyinng',
    inputs: [],
  },
  {
    type: 'error',
    name: 'FailedDeployment',
    inputs: [],
  },
  {
    type: 'error',
    name: 'FeeTooHigh',
    inputs: [],
  },
  {
    type: 'error',
    name: 'InsufficientBalance',
    inputs: [
      {
        name: 'balance',
        type: 'uint256',
        internalType: 'uint256',
      },
      {
        name: 'needed',
        type: 'uint256',
        internalType: 'uint256',
      },
    ],
  },
  {
    type: 'error',
    name: 'InvalidInitialization',
    inputs: [],
  },
  {
    type: 'error',
    name: 'InvalidMaturity',
    inputs: [],
  },
  {
    type: 'error',
    name: 'NotInitializing',
    inputs: [],
  },
  {
    type: 'error',
    name: 'OwnableInvalidOwner',
    inputs: [
      {
        name: 'owner',
        type: 'address',
        internalType: 'address',
      },
    ],
  },
  {
    type: 'error',
    name: 'OwnableUnauthorizedAccount',
    inputs: [
      {
        name: 'account',
        type: 'address',
        internalType: 'address',
      },
    ],
  },
  {
    type: 'error',
    name: 'ReentrancyGuardReentrantCall',
    inputs: [],
  },
  {
    type: 'error',
    name: 'SafeCastOverflowedUintDowncast',
    inputs: [
      {
        name: 'bits',
        type: 'uint8',
        internalType: 'uint8',
      },
      {
        name: 'value',
        type: 'uint256',
        internalType: 'uint256',
      },
    ],
  },
  {
    type: 'error',
    name: 'SafeERC20FailedOperation',
    inputs: [
      {
        name: 'token',
        type: 'address',
        internalType: 'address',
      },
    ],
  },
  {
    type: 'error',
    name: 'TermIsNotOpen',
    inputs: [],
  },
] as const;
