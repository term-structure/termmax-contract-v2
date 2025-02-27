// This file is auto-generated. Do not edit manually.

export const abiTermMaxOrder = [
  {
    type: 'constructor',
    inputs: [],
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
    name: 'apr',
    inputs: [],
    outputs: [
      {
        name: 'lendApr_',
        type: 'uint256',
        internalType: 'uint256',
      },
      {
        name: 'borrowApr_',
        type: 'uint256',
        internalType: 'uint256',
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'initialize',
    inputs: [
      {
        name: 'maker_',
        type: 'address',
        internalType: 'address',
      },
      {
        name: 'tokens',
        type: 'address[3]',
        internalType: 'contract IERC20[3]',
      },
      {
        name: 'gt_',
        type: 'address',
        internalType: 'contract IGearingToken',
      },
      {
        name: 'maxXtReserve_',
        type: 'uint256',
        internalType: 'uint256',
      },
      {
        name: 'swapTrigger',
        type: 'address',
        internalType: 'contract ISwapCallback',
      },
      {
        name: 'curveCuts_',
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
    name: 'maker',
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
    name: 'market',
    inputs: [],
    outputs: [
      {
        name: '',
        type: 'address',
        internalType: 'contract ITermMaxMarket',
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'orderConfig',
    inputs: [],
    outputs: [
      {
        name: '',
        type: 'tuple',
        internalType: 'struct OrderConfig',
        components: [
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
          {
            name: 'gtId',
            type: 'uint256',
            internalType: 'uint256',
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
            ],
          },
        ],
      },
    ],
    stateMutability: 'view',
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
    name: 'renounceOwnership',
    inputs: [],
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
        name: 'tokenAmtIn',
        type: 'uint128',
        internalType: 'uint128',
      },
      {
        name: 'minTokenOut',
        type: 'uint128',
        internalType: 'uint128',
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
        name: 'tokenAmtOut',
        type: 'uint128',
        internalType: 'uint128',
      },
      {
        name: 'maxTokenIn',
        type: 'uint128',
        internalType: 'uint128',
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
    name: 'tokenReserves',
    inputs: [],
    outputs: [
      {
        name: '',
        type: 'uint256',
        internalType: 'uint256',
      },
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
    name: 'updateFeeConfig',
    inputs: [
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
        ],
      },
    ],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'updateOrder',
    inputs: [
      {
        name: 'newOrderConfig',
        type: 'tuple',
        internalType: 'struct OrderConfig',
        components: [
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
          {
            name: 'gtId',
            type: 'uint256',
            internalType: 'uint256',
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
            ],
          },
        ],
      },
      {
        name: 'ftChangeAmt',
        type: 'int256',
        internalType: 'int256',
      },
      {
        name: 'xtChangeAmt',
        type: 'int256',
        internalType: 'int256',
      },
    ],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'withdrawAssets',
    inputs: [
      {
        name: 'token',
        type: 'address',
        internalType: 'contract IERC20',
      },
      {
        name: 'recipient',
        type: 'address',
        internalType: 'address',
      },
      {
        name: 'amount',
        type: 'uint256',
        internalType: 'uint256',
      },
    ],
    outputs: [],
    stateMutability: 'nonpayable',
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
    name: 'MakerOwnershipTransferred',
    inputs: [
      {
        name: 'oldMaker',
        type: 'address',
        indexed: false,
        internalType: 'address',
      },
      {
        name: 'newMaker',
        type: 'address',
        indexed: false,
        internalType: 'address',
      },
    ],
    anonymous: false,
  },
  {
    type: 'event',
    name: 'OrderInitialized',
    inputs: [
      {
        name: 'market',
        type: 'address',
        indexed: true,
        internalType: 'contract ITermMaxMarket',
      },
      {
        name: 'maker',
        type: 'address',
        indexed: true,
        internalType: 'address',
      },
      {
        name: 'maxXtReserve',
        type: 'uint256',
        indexed: false,
        internalType: 'uint256',
      },
      {
        name: 'swapTrigger',
        type: 'address',
        indexed: false,
        internalType: 'contract ISwapCallback',
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
        name: 'tokenAmtIn',
        type: 'uint128',
        indexed: false,
        internalType: 'uint128',
      },
      {
        name: 'netTokenOut',
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
        name: 'tokenAmtOut',
        type: 'uint128',
        indexed: false,
        internalType: 'uint128',
      },
      {
        name: 'netTokenIn',
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
    name: 'UpdateFeeConfig',
    inputs: [
      {
        name: 'feeConfig',
        type: 'tuple',
        indexed: false,
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
        ],
      },
    ],
    anonymous: false,
  },
  {
    type: 'event',
    name: 'UpdateOrder',
    inputs: [
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
      {
        name: 'ftChangeAmt',
        type: 'int256',
        indexed: false,
        internalType: 'int256',
      },
      {
        name: 'xtChangeAmt',
        type: 'int256',
        indexed: false,
        internalType: 'int256',
      },
      {
        name: 'gtId',
        type: 'uint256',
        indexed: false,
        internalType: 'uint256',
      },
      {
        name: 'maxXtReserve',
        type: 'uint256',
        indexed: false,
        internalType: 'uint256',
      },
      {
        name: 'swapTrigger',
        type: 'address',
        indexed: false,
        internalType: 'contract ISwapCallback',
      },
    ],
    anonymous: false,
  },
  {
    type: 'event',
    name: 'WithdrawAssets',
    inputs: [
      {
        name: 'token',
        type: 'address',
        indexed: true,
        internalType: 'contract IERC20',
      },
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
        name: 'amount',
        type: 'uint256',
        indexed: false,
        internalType: 'uint256',
      },
    ],
    anonymous: false,
  },
  {
    type: 'error',
    name: 'BorrowIsNotAllowed',
    inputs: [],
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
    name: 'CantNotIssueFtWithoutGt',
    inputs: [],
  },
  {
    type: 'error',
    name: 'CantNotSwapToken',
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
    ],
  },
  {
    type: 'error',
    name: 'CantSwapSameToken',
    inputs: [],
  },
  {
    type: 'error',
    name: 'EnforcedPause',
    inputs: [],
  },
  {
    type: 'error',
    name: 'EvacuationIsActived',
    inputs: [],
  },
  {
    type: 'error',
    name: 'EvacuationIsNotActived',
    inputs: [],
  },
  {
    type: 'error',
    name: 'ExpectedPause',
    inputs: [],
  },
  {
    type: 'error',
    name: 'GtNotApproved',
    inputs: [
      {
        name: 'gtId',
        type: 'uint256',
        internalType: 'uint256',
      },
    ],
  },
  {
    type: 'error',
    name: 'InvalidCurveCuts',
    inputs: [],
  },
  {
    type: 'error',
    name: 'InvalidInitialization',
    inputs: [],
  },
  {
    type: 'error',
    name: 'LendIsNotAllowed',
    inputs: [],
  },
  {
    type: 'error',
    name: 'NotEnoughFtOrXtToWithdraw',
    inputs: [],
  },
  {
    type: 'error',
    name: 'NotInitializing',
    inputs: [],
  },
  {
    type: 'error',
    name: 'OnlyMarket',
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
    name: 'SafeCastOverflowedIntToUint',
    inputs: [
      {
        name: 'value',
        type: 'int256',
        internalType: 'int256',
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
    name: 'SafeCastOverflowedUintToInt',
    inputs: [
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
  {
    type: 'error',
    name: 'UnexpectedAmount',
    inputs: [
      {
        name: 'expectedAmt',
        type: 'uint256',
        internalType: 'uint256',
      },
      {
        name: 'actualAmt',
        type: 'uint256',
        internalType: 'uint256',
      },
    ],
  },
  {
    type: 'error',
    name: 'XtReserveTooHigh',
    inputs: [],
  },
] as const;
