// This file is auto-generated. Do not edit manually.

export const abiTermMaxRouter = [
  {
    type: 'function',
    name: 'UPGRADE_INTERFACE_VERSION',
    inputs: [],
    outputs: [
      {
        name: '',
        type: 'string',
        internalType: 'string',
      },
    ],
    stateMutability: 'view',
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
    name: 'adapterWhitelist',
    inputs: [
      {
        name: '',
        type: 'address',
        internalType: 'address',
      },
    ],
    outputs: [
      {
        name: '',
        type: 'bool',
        internalType: 'bool',
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'assetsWithERC20Collateral',
    inputs: [
      {
        name: 'market',
        type: 'address',
        internalType: 'contract ITermMaxMarket',
      },
      {
        name: 'owner',
        type: 'address',
        internalType: 'address',
      },
    ],
    outputs: [
      {
        name: 'tokens',
        type: 'address[4]',
        internalType: 'contract IERC20[4]',
      },
      {
        name: 'balances',
        type: 'uint256[4]',
        internalType: 'uint256[4]',
      },
      {
        name: 'gtAddr',
        type: 'address',
        internalType: 'address',
      },
      {
        name: 'gtIds',
        type: 'uint256[]',
        internalType: 'uint256[]',
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'borrowTokenFromCollateral',
    inputs: [
      {
        name: 'recipient',
        type: 'address',
        internalType: 'address',
      },
      {
        name: 'market',
        type: 'address',
        internalType: 'contract ITermMaxMarket',
      },
      {
        name: 'collInAmt',
        type: 'uint256',
        internalType: 'uint256',
      },
      {
        name: 'borrowAmt',
        type: 'uint256',
        internalType: 'uint256',
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
    name: 'borrowTokenFromCollateral',
    inputs: [
      {
        name: 'recipient',
        type: 'address',
        internalType: 'address',
      },
      {
        name: 'market',
        type: 'address',
        internalType: 'contract ITermMaxMarket',
      },
      {
        name: 'collInAmt',
        type: 'uint256',
        internalType: 'uint256',
      },
      {
        name: 'orders',
        type: 'address[]',
        internalType: 'contract ITermMaxOrder[]',
      },
      {
        name: 'tokenAmtsWantBuy',
        type: 'uint128[]',
        internalType: 'uint128[]',
      },
      {
        name: 'maxDebtAmt',
        type: 'uint128',
        internalType: 'uint128',
      },
      {
        name: 'deadline',
        type: 'uint256',
        internalType: 'uint256',
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
    name: 'borrowTokenFromGt',
    inputs: [
      {
        name: 'recipient',
        type: 'address',
        internalType: 'address',
      },
      {
        name: 'market',
        type: 'address',
        internalType: 'contract ITermMaxMarket',
      },
      {
        name: 'gtId',
        type: 'uint256',
        internalType: 'uint256',
      },
      {
        name: 'borrowAmt',
        type: 'uint256',
        internalType: 'uint256',
      },
    ],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'createOrderAndDeposit',
    inputs: [
      {
        name: 'market',
        type: 'address',
        internalType: 'contract ITermMaxMarket',
      },
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
        name: 'debtTokenToDeposit',
        type: 'uint256',
        internalType: 'uint256',
      },
      {
        name: 'ftToDeposit',
        type: 'uint128',
        internalType: 'uint128',
      },
      {
        name: 'xtToDeposit',
        type: 'uint128',
        internalType: 'uint128',
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
    name: 'executeOperation',
    inputs: [
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
      {
        name: 'amount',
        type: 'uint256',
        internalType: 'uint256',
      },
      {
        name: 'data',
        type: 'bytes',
        internalType: 'bytes',
      },
    ],
    outputs: [
      {
        name: 'collateralData',
        type: 'bytes',
        internalType: 'bytes',
      },
    ],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'executeOperation',
    inputs: [
      {
        name: 'repayToken',
        type: 'address',
        internalType: 'contract IERC20',
      },
      {
        name: 'debtAmt',
        type: 'uint128',
        internalType: 'uint128',
      },
      {
        name: '',
        type: 'address',
        internalType: 'address',
      },
      {
        name: 'collateralData',
        type: 'bytes',
        internalType: 'bytes',
      },
      {
        name: 'callbackData',
        type: 'bytes',
        internalType: 'bytes',
      },
    ],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'flashRepayFromColl',
    inputs: [
      {
        name: 'recipient',
        type: 'address',
        internalType: 'address',
      },
      {
        name: 'market',
        type: 'address',
        internalType: 'contract ITermMaxMarket',
      },
      {
        name: 'gtId',
        type: 'uint256',
        internalType: 'uint256',
      },
      {
        name: 'orders',
        type: 'address[]',
        internalType: 'contract ITermMaxOrder[]',
      },
      {
        name: 'amtsToBuyFt',
        type: 'uint128[]',
        internalType: 'uint128[]',
      },
      {
        name: 'byDebtToken',
        type: 'bool',
        internalType: 'bool',
      },
      {
        name: 'units',
        type: 'tuple[]',
        internalType: 'struct SwapUnit[]',
        components: [
          {
            name: 'adapter',
            type: 'address',
            internalType: 'address',
          },
          {
            name: 'tokenIn',
            type: 'address',
            internalType: 'address',
          },
          {
            name: 'tokenOut',
            type: 'address',
            internalType: 'address',
          },
          {
            name: 'swapData',
            type: 'bytes',
            internalType: 'bytes',
          },
        ],
      },
      {
        name: 'deadline',
        type: 'uint256',
        internalType: 'uint256',
      },
    ],
    outputs: [
      {
        name: 'netTokenOut',
        type: 'uint256',
        internalType: 'uint256',
      },
    ],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'initialize',
    inputs: [
      {
        name: 'admin',
        type: 'address',
        internalType: 'address',
      },
    ],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'leverageFromToken',
    inputs: [
      {
        name: 'recipient',
        type: 'address',
        internalType: 'address',
      },
      {
        name: 'market',
        type: 'address',
        internalType: 'contract ITermMaxMarket',
      },
      {
        name: 'orders',
        type: 'address[]',
        internalType: 'contract ITermMaxOrder[]',
      },
      {
        name: 'amtsToBuyXt',
        type: 'uint128[]',
        internalType: 'uint128[]',
      },
      {
        name: 'minXtOut',
        type: 'uint128',
        internalType: 'uint128',
      },
      {
        name: 'tokenToSwap',
        type: 'uint128',
        internalType: 'uint128',
      },
      {
        name: 'maxLtv',
        type: 'uint128',
        internalType: 'uint128',
      },
      {
        name: 'units',
        type: 'tuple[]',
        internalType: 'struct SwapUnit[]',
        components: [
          {
            name: 'adapter',
            type: 'address',
            internalType: 'address',
          },
          {
            name: 'tokenIn',
            type: 'address',
            internalType: 'address',
          },
          {
            name: 'tokenOut',
            type: 'address',
            internalType: 'address',
          },
          {
            name: 'swapData',
            type: 'bytes',
            internalType: 'bytes',
          },
        ],
      },
      {
        name: 'deadline',
        type: 'uint256',
        internalType: 'uint256',
      },
    ],
    outputs: [
      {
        name: 'gtId',
        type: 'uint256',
        internalType: 'uint256',
      },
      {
        name: 'netXtOut',
        type: 'uint256',
        internalType: 'uint256',
      },
    ],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'leverageFromXt',
    inputs: [
      {
        name: 'recipient',
        type: 'address',
        internalType: 'address',
      },
      {
        name: 'market',
        type: 'address',
        internalType: 'contract ITermMaxMarket',
      },
      {
        name: 'xtInAmt',
        type: 'uint128',
        internalType: 'uint128',
      },
      {
        name: 'tokenInAmt',
        type: 'uint128',
        internalType: 'uint128',
      },
      {
        name: 'maxLtv',
        type: 'uint128',
        internalType: 'uint128',
      },
      {
        name: 'units',
        type: 'tuple[]',
        internalType: 'struct SwapUnit[]',
        components: [
          {
            name: 'adapter',
            type: 'address',
            internalType: 'address',
          },
          {
            name: 'tokenIn',
            type: 'address',
            internalType: 'address',
          },
          {
            name: 'tokenOut',
            type: 'address',
            internalType: 'address',
          },
          {
            name: 'swapData',
            type: 'bytes',
            internalType: 'bytes',
          },
        ],
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
    name: 'leverageFromXtAndCollateral',
    inputs: [
      {
        name: 'recipient',
        type: 'address',
        internalType: 'address',
      },
      {
        name: 'market',
        type: 'address',
        internalType: 'contract ITermMaxMarket',
      },
      {
        name: 'xtInAmt',
        type: 'uint128',
        internalType: 'uint128',
      },
      {
        name: 'collateralInAmt',
        type: 'uint128',
        internalType: 'uint128',
      },
      {
        name: 'maxLtv',
        type: 'uint128',
        internalType: 'uint128',
      },
      {
        name: 'units',
        type: 'tuple[]',
        internalType: 'struct SwapUnit[]',
        components: [
          {
            name: 'adapter',
            type: 'address',
            internalType: 'address',
          },
          {
            name: 'tokenIn',
            type: 'address',
            internalType: 'address',
          },
          {
            name: 'tokenOut',
            type: 'address',
            internalType: 'address',
          },
          {
            name: 'swapData',
            type: 'bytes',
            internalType: 'bytes',
          },
        ],
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
    name: 'onERC721Received',
    inputs: [
      {
        name: '',
        type: 'address',
        internalType: 'address',
      },
      {
        name: '',
        type: 'address',
        internalType: 'address',
      },
      {
        name: '',
        type: 'uint256',
        internalType: 'uint256',
      },
      {
        name: '',
        type: 'bytes',
        internalType: 'bytes',
      },
    ],
    outputs: [
      {
        name: '',
        type: 'bytes4',
        internalType: 'bytes4',
      },
    ],
    stateMutability: 'pure',
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
    name: 'pause',
    inputs: [],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'paused',
    inputs: [],
    outputs: [
      {
        name: '',
        type: 'bool',
        internalType: 'bool',
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
    name: 'proxiableUUID',
    inputs: [],
    outputs: [
      {
        name: '',
        type: 'bytes32',
        internalType: 'bytes32',
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'redeemAndSwap',
    inputs: [
      {
        name: 'recipient',
        type: 'address',
        internalType: 'address',
      },
      {
        name: 'market',
        type: 'address',
        internalType: 'contract ITermMaxMarket',
      },
      {
        name: 'ftAmount',
        type: 'uint256',
        internalType: 'uint256',
      },
      {
        name: 'units',
        type: 'tuple[]',
        internalType: 'struct SwapUnit[]',
        components: [
          {
            name: 'adapter',
            type: 'address',
            internalType: 'address',
          },
          {
            name: 'tokenIn',
            type: 'address',
            internalType: 'address',
          },
          {
            name: 'tokenOut',
            type: 'address',
            internalType: 'address',
          },
          {
            name: 'swapData',
            type: 'bytes',
            internalType: 'bytes',
          },
        ],
      },
      {
        name: 'minTokenOut',
        type: 'uint256',
        internalType: 'uint256',
      },
    ],
    outputs: [
      {
        name: 'netTokenOut',
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
    name: 'repayByTokenThroughFt',
    inputs: [
      {
        name: 'recipient',
        type: 'address',
        internalType: 'address',
      },
      {
        name: 'market',
        type: 'address',
        internalType: 'contract ITermMaxMarket',
      },
      {
        name: 'gtId',
        type: 'uint256',
        internalType: 'uint256',
      },
      {
        name: 'orders',
        type: 'address[]',
        internalType: 'contract ITermMaxOrder[]',
      },
      {
        name: 'ftAmtsWantBuy',
        type: 'uint128[]',
        internalType: 'uint128[]',
      },
      {
        name: 'maxTokenIn',
        type: 'uint128',
        internalType: 'uint128',
      },
      {
        name: 'deadline',
        type: 'uint256',
        internalType: 'uint256',
      },
    ],
    outputs: [
      {
        name: 'returnAmt',
        type: 'uint256',
        internalType: 'uint256',
      },
    ],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'sellTokens',
    inputs: [
      {
        name: 'recipient',
        type: 'address',
        internalType: 'address',
      },
      {
        name: 'market',
        type: 'address',
        internalType: 'contract ITermMaxMarket',
      },
      {
        name: 'ftInAmt',
        type: 'uint128',
        internalType: 'uint128',
      },
      {
        name: 'xtInAmt',
        type: 'uint128',
        internalType: 'uint128',
      },
      {
        name: 'orders',
        type: 'address[]',
        internalType: 'contract ITermMaxOrder[]',
      },
      {
        name: 'amtsToSellTokens',
        type: 'uint128[]',
        internalType: 'uint128[]',
      },
      {
        name: 'minTokenOut',
        type: 'uint128',
        internalType: 'uint128',
      },
      {
        name: 'deadline',
        type: 'uint256',
        internalType: 'uint256',
      },
    ],
    outputs: [
      {
        name: 'netTokenOut',
        type: 'uint256',
        internalType: 'uint256',
      },
    ],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'setAdapterWhitelist',
    inputs: [
      {
        name: 'adapter',
        type: 'address',
        internalType: 'address',
      },
      {
        name: 'isWhitelist',
        type: 'bool',
        internalType: 'bool',
      },
    ],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'swapExactTokenToToken',
    inputs: [
      {
        name: 'tokenIn',
        type: 'address',
        internalType: 'contract IERC20',
      },
      {
        name: 'tokenOut',
        type: 'address',
        internalType: 'contract IERC20',
      },
      {
        name: 'recipient',
        type: 'address',
        internalType: 'address',
      },
      {
        name: 'orders',
        type: 'address[]',
        internalType: 'contract ITermMaxOrder[]',
      },
      {
        name: 'tradingAmts',
        type: 'uint128[]',
        internalType: 'uint128[]',
      },
      {
        name: 'minTokenOut',
        type: 'uint128',
        internalType: 'uint128',
      },
      {
        name: 'deadline',
        type: 'uint256',
        internalType: 'uint256',
      },
    ],
    outputs: [
      {
        name: 'netTokenOut',
        type: 'uint256',
        internalType: 'uint256',
      },
    ],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'swapTokenToExactToken',
    inputs: [
      {
        name: 'tokenIn',
        type: 'address',
        internalType: 'contract IERC20',
      },
      {
        name: 'tokenOut',
        type: 'address',
        internalType: 'contract IERC20',
      },
      {
        name: 'recipient',
        type: 'address',
        internalType: 'address',
      },
      {
        name: 'orders',
        type: 'address[]',
        internalType: 'contract ITermMaxOrder[]',
      },
      {
        name: 'tradingAmts',
        type: 'uint128[]',
        internalType: 'uint128[]',
      },
      {
        name: 'maxTokenIn',
        type: 'uint128',
        internalType: 'uint128',
      },
      {
        name: 'deadline',
        type: 'uint256',
        internalType: 'uint256',
      },
    ],
    outputs: [
      {
        name: 'netTokenIn',
        type: 'uint256',
        internalType: 'uint256',
      },
    ],
    stateMutability: 'nonpayable',
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
    name: 'unpause',
    inputs: [],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'upgradeToAndCall',
    inputs: [
      {
        name: 'newImplementation',
        type: 'address',
        internalType: 'address',
      },
      {
        name: 'data',
        type: 'bytes',
        internalType: 'bytes',
      },
    ],
    outputs: [],
    stateMutability: 'payable',
  },
  {
    type: 'event',
    name: 'Borrow',
    inputs: [
      {
        name: 'market',
        type: 'address',
        indexed: true,
        internalType: 'contract ITermMaxMarket',
      },
      {
        name: 'gtId',
        type: 'uint256',
        indexed: true,
        internalType: 'uint256',
      },
      {
        name: 'caller',
        type: 'address',
        indexed: false,
        internalType: 'address',
      },
      {
        name: 'recipient',
        type: 'address',
        indexed: false,
        internalType: 'address',
      },
      {
        name: 'collInAmt',
        type: 'uint256',
        indexed: false,
        internalType: 'uint256',
      },
      {
        name: 'actualDebtAmt',
        type: 'uint128',
        indexed: false,
        internalType: 'uint128',
      },
      {
        name: 'borrowAmt',
        type: 'uint128',
        indexed: false,
        internalType: 'uint128',
      },
    ],
    anonymous: false,
  },
  {
    type: 'event',
    name: 'CreateOrderAndDeposit',
    inputs: [
      {
        name: 'market',
        type: 'address',
        indexed: true,
        internalType: 'contract ITermMaxMarket',
      },
      {
        name: 'order',
        type: 'address',
        indexed: true,
        internalType: 'contract ITermMaxOrder',
      },
      {
        name: 'maker',
        type: 'address',
        indexed: false,
        internalType: 'address',
      },
      {
        name: 'debtTokenToDeposit',
        type: 'uint256',
        indexed: false,
        internalType: 'uint256',
      },
      {
        name: 'ftToDeposit',
        type: 'uint128',
        indexed: false,
        internalType: 'uint128',
      },
      {
        name: 'xtToDeposit',
        type: 'uint128',
        indexed: false,
        internalType: 'uint128',
      },
      {
        name: 'curveCuts',
        type: 'tuple',
        indexed: false,
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
    name: 'IssueGt',
    inputs: [
      {
        name: 'market',
        type: 'address',
        indexed: true,
        internalType: 'contract ITermMaxMarket',
      },
      {
        name: 'gtId',
        type: 'uint256',
        indexed: true,
        internalType: 'uint256',
      },
      {
        name: 'caller',
        type: 'address',
        indexed: false,
        internalType: 'address',
      },
      {
        name: 'recipient',
        type: 'address',
        indexed: false,
        internalType: 'address',
      },
      {
        name: 'debtTokenAmtIn',
        type: 'uint128',
        indexed: false,
        internalType: 'uint128',
      },
      {
        name: 'xtAmtIn',
        type: 'uint128',
        indexed: false,
        internalType: 'uint128',
      },
      {
        name: 'ltv',
        type: 'uint128',
        indexed: false,
        internalType: 'uint128',
      },
      {
        name: 'collData',
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
    name: 'Paused',
    inputs: [
      {
        name: 'account',
        type: 'address',
        indexed: false,
        internalType: 'address',
      },
    ],
    anonymous: false,
  },
  {
    type: 'event',
    name: 'RedeemAndSwap',
    inputs: [
      {
        name: 'market',
        type: 'address',
        indexed: true,
        internalType: 'contract ITermMaxMarket',
      },
      {
        name: 'ftAmount',
        type: 'uint256',
        indexed: false,
        internalType: 'uint256',
      },
      {
        name: 'caller',
        type: 'address',
        indexed: false,
        internalType: 'address',
      },
      {
        name: 'recipient',
        type: 'address',
        indexed: false,
        internalType: 'address',
      },
      {
        name: 'actualTokenOut',
        type: 'uint256',
        indexed: false,
        internalType: 'uint256',
      },
    ],
    anonymous: false,
  },
  {
    type: 'event',
    name: 'RepayByTokenThroughFt',
    inputs: [
      {
        name: 'market',
        type: 'address',
        indexed: true,
        internalType: 'contract ITermMaxMarket',
      },
      {
        name: 'gtId',
        type: 'uint256',
        indexed: true,
        internalType: 'uint256',
      },
      {
        name: 'caller',
        type: 'address',
        indexed: false,
        internalType: 'address',
      },
      {
        name: 'recipient',
        type: 'address',
        indexed: false,
        internalType: 'address',
      },
      {
        name: 'repayAmt',
        type: 'uint256',
        indexed: false,
        internalType: 'uint256',
      },
      {
        name: 'returnAmt',
        type: 'uint256',
        indexed: false,
        internalType: 'uint256',
      },
    ],
    anonymous: false,
  },
  {
    type: 'event',
    name: 'SellTokens',
    inputs: [
      {
        name: 'market',
        type: 'address',
        indexed: true,
        internalType: 'contract ITermMaxMarket',
      },
      {
        name: 'caller',
        type: 'address',
        indexed: false,
        internalType: 'address',
      },
      {
        name: 'recipient',
        type: 'address',
        indexed: false,
        internalType: 'address',
      },
      {
        name: 'ftInAmt',
        type: 'uint128',
        indexed: false,
        internalType: 'uint128',
      },
      {
        name: 'xtInAmt',
        type: 'uint128',
        indexed: false,
        internalType: 'uint128',
      },
      {
        name: 'orders',
        type: 'address[]',
        indexed: false,
        internalType: 'contract ITermMaxOrder[]',
      },
      {
        name: 'amtsToSellTokens',
        type: 'uint128[]',
        indexed: false,
        internalType: 'uint128[]',
      },
      {
        name: 'actualTokenOut',
        type: 'uint256',
        indexed: false,
        internalType: 'uint256',
      },
    ],
    anonymous: false,
  },
  {
    type: 'event',
    name: 'SwapExactTokenToToken',
    inputs: [
      {
        name: 'tokenIn',
        type: 'address',
        indexed: true,
        internalType: 'contract IERC20',
      },
      {
        name: 'tokenOut',
        type: 'address',
        indexed: true,
        internalType: 'contract IERC20',
      },
      {
        name: 'caller',
        type: 'address',
        indexed: false,
        internalType: 'address',
      },
      {
        name: 'recipient',
        type: 'address',
        indexed: false,
        internalType: 'address',
      },
      {
        name: 'orders',
        type: 'address[]',
        indexed: false,
        internalType: 'contract ITermMaxOrder[]',
      },
      {
        name: 'tradingAmts',
        type: 'uint128[]',
        indexed: false,
        internalType: 'uint128[]',
      },
      {
        name: 'actualTokenOut',
        type: 'uint256',
        indexed: false,
        internalType: 'uint256',
      },
    ],
    anonymous: false,
  },
  {
    type: 'event',
    name: 'SwapTokenToExactToken',
    inputs: [
      {
        name: 'tokenIn',
        type: 'address',
        indexed: true,
        internalType: 'contract IERC20',
      },
      {
        name: 'tokenOut',
        type: 'address',
        indexed: true,
        internalType: 'contract IERC20',
      },
      {
        name: 'caller',
        type: 'address',
        indexed: false,
        internalType: 'address',
      },
      {
        name: 'recipient',
        type: 'address',
        indexed: false,
        internalType: 'address',
      },
      {
        name: 'orders',
        type: 'address[]',
        indexed: false,
        internalType: 'contract ITermMaxOrder[]',
      },
      {
        name: 'tradingAmts',
        type: 'uint128[]',
        indexed: false,
        internalType: 'uint128[]',
      },
      {
        name: 'actualTokenIn',
        type: 'uint256',
        indexed: false,
        internalType: 'uint256',
      },
    ],
    anonymous: false,
  },
  {
    type: 'event',
    name: 'Unpaused',
    inputs: [
      {
        name: 'account',
        type: 'address',
        indexed: false,
        internalType: 'address',
      },
    ],
    anonymous: false,
  },
  {
    type: 'event',
    name: 'UpdateMarketWhiteList',
    inputs: [
      {
        name: 'market',
        type: 'address',
        indexed: false,
        internalType: 'address',
      },
      {
        name: 'isWhitelist',
        type: 'bool',
        indexed: false,
        internalType: 'bool',
      },
    ],
    anonymous: false,
  },
  {
    type: 'event',
    name: 'UpdateSwapAdapterWhiteList',
    inputs: [
      {
        name: 'adapter',
        type: 'address',
        indexed: false,
        internalType: 'address',
      },
      {
        name: 'isWhitelist',
        type: 'bool',
        indexed: false,
        internalType: 'bool',
      },
    ],
    anonymous: false,
  },
  {
    type: 'event',
    name: 'Upgraded',
    inputs: [
      {
        name: 'implementation',
        type: 'address',
        indexed: true,
        internalType: 'address',
      },
    ],
    anonymous: false,
  },
  {
    type: 'error',
    name: 'AdapterNotWhitelisted',
    inputs: [
      {
        name: 'adapter',
        type: 'address',
        internalType: 'address',
      },
    ],
  },
  {
    type: 'error',
    name: 'AddressEmptyCode',
    inputs: [
      {
        name: 'target',
        type: 'address',
        internalType: 'address',
      },
    ],
  },
  {
    type: 'error',
    name: 'ApproveTokenFailWhenSwap',
    inputs: [
      {
        name: 'token',
        type: 'address',
        internalType: 'address',
      },
      {
        name: 'revertData',
        type: 'bytes',
        internalType: 'bytes',
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
    name: 'ERC1967InvalidImplementation',
    inputs: [
      {
        name: 'implementation',
        type: 'address',
        internalType: 'address',
      },
    ],
  },
  {
    type: 'error',
    name: 'ERC1967NonPayable',
    inputs: [],
  },
  {
    type: 'error',
    name: 'EnforcedPause',
    inputs: [],
  },
  {
    type: 'error',
    name: 'ExpectedPause',
    inputs: [],
  },
  {
    type: 'error',
    name: 'FailedCall',
    inputs: [],
  },
  {
    type: 'error',
    name: 'GtNotOwnedBySender',
    inputs: [],
  },
  {
    type: 'error',
    name: 'GtNotWhitelisted',
    inputs: [
      {
        name: 'gt',
        type: 'address',
        internalType: 'address',
      },
    ],
  },
  {
    type: 'error',
    name: 'InsufficientTokenIn',
    inputs: [
      {
        name: 'token',
        type: 'address',
        internalType: 'address',
      },
      {
        name: 'expectedTokenIn',
        type: 'uint256',
        internalType: 'uint256',
      },
      {
        name: 'actualTokenIn',
        type: 'uint256',
        internalType: 'uint256',
      },
    ],
  },
  {
    type: 'error',
    name: 'InsufficientTokenOut',
    inputs: [
      {
        name: 'token',
        type: 'address',
        internalType: 'address',
      },
      {
        name: 'expectedTokenOut',
        type: 'uint256',
        internalType: 'uint256',
      },
      {
        name: 'actualTokenOut',
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
    name: 'LtvBiggerThanExpected',
    inputs: [
      {
        name: 'expectedLtv',
        type: 'uint128',
        internalType: 'uint128',
      },
      {
        name: 'actualLtv',
        type: 'uint128',
        internalType: 'uint128',
      },
    ],
  },
  {
    type: 'error',
    name: 'MarketNotWhitelisted',
    inputs: [
      {
        name: 'market',
        type: 'address',
        internalType: 'address',
      },
    ],
  },
  {
    type: 'error',
    name: 'NotInitializing',
    inputs: [],
  },
  {
    type: 'error',
    name: 'OrdersAndAmtsLengthNotMatch',
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
    name: 'SwapFailed',
    inputs: [
      {
        name: 'adapter',
        type: 'address',
        internalType: 'address',
      },
      {
        name: 'revertData',
        type: 'bytes',
        internalType: 'bytes',
      },
    ],
  },
  {
    type: 'error',
    name: 'UUPSUnauthorizedCallContext',
    inputs: [],
  },
  {
    type: 'error',
    name: 'UUPSUnsupportedProxiableUUID',
    inputs: [
      {
        name: 'slot',
        type: 'bytes32',
        internalType: 'bytes32',
      },
    ],
  },
] as const;
