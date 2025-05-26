#!/usr/bin/env node

import { ethers } from 'ethers';
import * as fs from 'fs';
import { abiTermMaxOrder } from '../abi_typescript/abiTermMaxOrder';

// Type definitions for the script
interface TokenInfo {
  address: string;
  name: string;
  symbol: string;
  decimals: number;
  error?: string;
}

interface MarketConfig {
  treasurer: string;
  maturity: string;
  maturityDate: string;
}

interface MarketTokens {
  ft: TokenInfo;
  xt: TokenInfo;
  gt: {
    address: string;
  };
  collateral: TokenInfo;
  debtToken: TokenInfo;
}

interface MarketInfo {
  address: string;
  config: MarketConfig | null;
  tokens: MarketTokens;
  error?: string;
}

interface OrderConfig {
  maxXtReserve: string;
  gtId: string;
  swapTrigger: string;
}

interface OrderInfo {
  address: string;
  marketAddress: string;
  marketInfo: MarketInfo;
  makerAddress: string;
  ftReserve: string;
  xtReserve: string;
  orderConfig: OrderConfig | null;
  error?: string;
}

interface BaseEvent {
  blockNumber: number;
  transactionHash: string;
  logIndex: number;
  eventType: string;
  operationType: 'Swap' | 'Deposit' | 'Withdraw' | 'UpdateCurve' | 'Create' | string;
  timestamp: number | null;
  date?: string;
  sortKey?: string;
  daysToMaturity?: number;
}

interface SwapEvent extends BaseEvent {
  tokenIn: string;
  tokenOut: string;
  caller: string;
  recipient: string;
  tokenInAmount: ethers.BigNumber;
  tokenOutAmount: ethers.BigNumber;
  feeAmount: ethers.BigNumber;
  tokenInSymbol?: string;
  tokenOutSymbol?: string;
  tokenInAmountFormatted?: string;
  tokenOutAmountFormatted?: string;
  feeAmountFormatted?: string;
  direction?: 'LEND' | 'BORROW' | 'OTHER';
  abstractTokenInSymbol?: string;
  abstractTokenOutSymbol?: string;
  abstractTokenInAmountFormatted?: string;
  abstractTokenOutAmountFormatted?: string;
  avgMatchedInterestRate?: number;
}

interface UpdateOrderEvent extends BaseEvent {
  ftChangeAmt: ethers.BigNumber;
  xtChangeAmt: ethers.BigNumber;
  gtId: ethers.BigNumber;
  maxXtReserve: ethers.BigNumber;
  swapTrigger: string;
  ftChangeAmtFormatted?: string;
  xtChangeAmtFormatted?: string;
  maxXtReserveFormatted?: string;
}

interface WithdrawAssetsEvent extends BaseEvent {
  token: string;
  owner: string;
  recipient: string;
  amount: ethers.BigNumber;
  tokenSymbol?: string;
  amountFormatted?: string;
}

interface OrderInitializedEvent extends BaseEvent {
  market: string;
  maker: string;
  maxXtReserve: ethers.BigNumber;
  swapTrigger: string;
  maxXtReserveFormatted?: string;
}

type EventType = SwapEvent | UpdateOrderEvent | WithdrawAssetsEvent | OrderInitializedEvent;

interface EventsCollection {
  swaps: SwapEvent[];
  deposits: UpdateOrderEvent[];
  withdrawals: (UpdateOrderEvent | WithdrawAssetsEvent)[];
  updateCurves: UpdateOrderEvent[];
  creations: OrderInitializedEvent[];
  all: EventType[];
}

interface DisplayOptions {
  limit?: number;
  detailed?: boolean;
}

/**
 * Helper function to construct proper tuple type strings
 * This is a critical function for correctly generating event signatures with complex tuple types
 * @param input - ABI input parameter
 * @returns Properly formatted type string
 */
function constructTupleType(input: any): string {
  // Handle tuple type
  if (input.type === 'tuple') {
    // Process all components of the tuple
    const componentsType = input.components.map((comp: any) => {
      if (comp.type === 'tuple' || comp.type.endsWith('[]')) {
        return constructTupleType(comp);
      }
      return comp.type;
    }).join(',');
    return `tuple(${componentsType})`;
  }
  // Handle array of tuples
  else if (input.type.endsWith('[]')) {
    const baseType = input.type.substring(0, input.type.length - 2);
    if (baseType === 'tuple') {
      const componentsType = input.components.map((comp: any) => {
        if (comp.type === 'tuple' || comp.type.endsWith('[]')) {
          return constructTupleType(comp);
        }
        return comp.type;
      }).join(',');
      return `tuple(${componentsType})[]`;
    }
    return input.type;
  }
  // Return simple type as is
  return input.type;
}

// Extract event signatures from ABI with additional debugging
function extractEventSignatures(abi: readonly any[]) {
  const eventSignatures: Record<string, string> = {};

  // Filter to get just the events from the ABI
  const events = abi.filter(item => item.type === 'event');

  // Generate signature and hash for each event
  events.forEach(event => {
    try {
      const paramTypes = event.inputs.map((input: any) => {
        // For tuples, we need special handling to match the Solidity signature format
        if (input.type === 'tuple' || input.type.endsWith('[]')) {
          return constructTupleType(input);
        }
        return input.type;
      }).join(',');

      const signature = `${event.name}(${paramTypes})`;
      const hash = ethers.utils.id(signature);
      eventSignatures[event.name] = hash;
    } catch (error) {
      console.error(`Error processing event ${event.name}: ${error instanceof Error ? error.message : String(error)}`);
    }
  });

  return eventSignatures;
}

// Extract event signatures from ABI
const eventTopics = extractEventSignatures(abiTermMaxOrder);

// Using the imported abiTermMaxOrder instead of defining a separate orderABI

// ABI for reading TermMaxMarket contract data
const marketABI = [
  "function tokens() external view returns (address, address, address, address, address)",
  "function config() external view returns (tuple(address treasurer, uint64 maturity, tuple(uint64 borrowTakerFeeRatio, uint64 borrowMakerFeeRatio, uint64 lendTakerFeeRatio, uint64 lendMakerFeeRatio, uint64 mintGtFeeRatio, uint64 mintGtFeeRef) feeConfig))"
];

// ABI for basic ERC20 token information
const erc20ABI = [
  "function name() external view returns (string)",
  "function symbol() external view returns (string)",
  "function decimals() external view returns (uint8)"
];

/**
 * Fetch token information
 * @param tokenAddress - Address of the token
 * @param provider - Ethers provider
 * @returns Basic information about the token
 */
async function getTokenInfo(tokenAddress: string, provider: ethers.providers.Provider): Promise<TokenInfo> {
  try {
    const tokenContract = new ethers.Contract(tokenAddress, erc20ABI, provider);

    const [name, symbol, decimals] = await Promise.all([
      tokenContract.name().catch(() => 'Unknown'),
      tokenContract.symbol().catch(() => 'Unknown'),
      tokenContract.decimals().catch(() => 18)
    ]);

    return {
      address: tokenAddress,
      name,
      symbol,
      decimals
    };
  } catch (error) {
    return {
      address: tokenAddress,
      name: 'Unknown',
      symbol: 'Unknown',
      decimals: 18,
      error: error instanceof Error ? error.message : String(error)
    };
  }
}

/**
 * Fetch market details from the contract
 * @param marketAddress - Address of the TermMaxMarket contract
 * @param provider - Ethers provider
 * @returns Detailed information about the market
 */
async function getMarketInfo(marketAddress: string, provider: ethers.providers.Provider): Promise<MarketInfo> {
  console.log(`Fetching market information for: ${marketAddress}`);

  const marketContract = new ethers.Contract(marketAddress, marketABI, provider);

  try {
    // Get token addresses from the market
    const [ft, xt, gt, collateral, debtToken] = await marketContract.tokens();
    console.log(`Found tokens: FT=${ft}, XT=${xt}, GT=${gt}, collateral=${collateral}, debtToken=${debtToken}`);

    // Get market configuration
    let marketConfig: MarketConfig | null = null;
    try {
      const config = await marketContract.config();
      marketConfig = {
        treasurer: config.treasurer,
        maturity: config.maturity.toString(),
        maturityDate: new Date(config.maturity.toNumber() * 1000).toISOString()
      };
      console.log(`Market maturity: ${marketConfig.maturityDate}`);
      console.log(`Market treasurer: ${marketConfig.treasurer}`);
    } catch (error) {
      console.log("Could not fetch market configuration details");
    }

    // Get token details
    const [ftInfo, xtInfo, collateralInfo, debtTokenInfo] = await Promise.all([
      getTokenInfo(ft, provider),
      getTokenInfo(xt, provider),
      getTokenInfo(collateral, provider),
      getTokenInfo(debtToken, provider)
    ]);

    console.log(`FT Token: ${ftInfo.symbol} (${ftInfo.name})`);
    console.log(`XT Token: ${xtInfo.symbol} (${xtInfo.name})`);
    console.log(`Collateral: ${collateralInfo.symbol} (${collateralInfo.name})`);
    console.log(`Debt Token: ${debtTokenInfo.symbol} (${debtTokenInfo.name})`);

    return {
      address: marketAddress,
      config: marketConfig,
      tokens: {
        ft: ftInfo,
        xt: xtInfo,
        gt: {
          address: gt
        },
        collateral: collateralInfo,
        debtToken: debtTokenInfo
      }
    };
  } catch (error) {
    console.error("Error fetching market information:", error instanceof Error ? error.message : String(error));
    return {
      address: marketAddress,
      config: null,
      tokens: {} as MarketTokens,
      error: error instanceof Error ? error.message : String(error)
    };
  }
}

/**
 * Fetch order details from the contract
 * @param orderAddress - Address of the TermMaxOrder contract
 * @param provider - Ethers provider
 * @returns Basic information about the order
 */
async function getOrderInfo(orderAddress: string, provider: ethers.providers.Provider): Promise<OrderInfo> {
  console.log(`Fetching order information for: ${orderAddress}`);

  const orderContract = new ethers.Contract(orderAddress, abiTermMaxOrder, provider);

  try {
    // Get market address
    const marketAddress = await orderContract.market();
    console.log(`Market address: ${marketAddress}`);

    // Get market information
    const marketInfo = await getMarketInfo(marketAddress, provider);

    // Get maker (owner) address
    const makerAddress = await orderContract.maker();
    console.log(`Maker address: ${makerAddress}`);

    // Get token reserves
    const [ftReserve, xtReserve] = await orderContract.tokenReserves();

    // Format reserves based on token decimals
    const ftDecimals = marketInfo.tokens?.ft?.decimals || 18;
    const xtDecimals = marketInfo.tokens?.xt?.decimals || 18;

    console.log(`Current FT reserve: ${ethers.utils.formatUnits(ftReserve, ftDecimals)} ${marketInfo.tokens?.ft?.symbol || 'FT'}`);
    console.log(`Current XT reserve: ${ethers.utils.formatUnits(xtReserve, xtDecimals)} ${marketInfo.tokens?.xt?.symbol || 'XT'}`);

    // Try to get order configuration (may fail if structure is different)
    let orderConfig: OrderConfig | null = null;
    try {
      const config = await orderContract.orderConfig();
      orderConfig = {
        maxXtReserve: config.maxXtReserve.toString(),
        gtId: config.gtId.toString(),
        swapTrigger: config.swapTrigger
      };
      console.log(`Max XT reserve: ${ethers.utils.formatUnits(config.maxXtReserve, xtDecimals)} ${marketInfo.tokens?.xt?.symbol || 'XT'}`);
    } catch (error) {
      console.log("Could not fetch order configuration details");
    }

    return {
      address: orderAddress,
      marketAddress,
      marketInfo,
      makerAddress,
      ftReserve: ftReserve.toString(),
      xtReserve: xtReserve.toString(),
      orderConfig
    };
  } catch (error) {
    console.error("Error fetching order information:", error instanceof Error ? error.message : String(error));
    return {
      address: orderAddress,
      marketAddress: '',
      marketInfo: {} as MarketInfo,
      makerAddress: '',
      ftReserve: '0',
      xtReserve: '0',
      orderConfig: null,
      error: error instanceof Error ? error.message : String(error)
    };
  }
}

/**
 * Collect and categorize events from the specified order contract
 * @param orderAddress - Address of the TermMaxOrder contract
 * @param provider - Ethers provider
 * @param startBlock - Starting block for event scanning
 * @param endBlock - Ending block for event scanning
 * @returns Categorized events
 */
async function collectOrderEvents(
  orderAddress: string,
  provider: ethers.providers.Provider,
  startBlock: number,
  endBlock?: number
): Promise<EventsCollection> {
  // Create contract interface for parsing events
  const iface = new ethers.utils.Interface(abiTermMaxOrder);

  // Events collection
  const events: EventsCollection = {
    swaps: [],
    deposits: [],
    withdrawals: [],
    updateCurves: [],
    creations: [],
    all: []
  };

  console.log(`Collecting events for order: ${orderAddress}`);
  console.log(`Scanning blocks ${startBlock} to ${endBlock || 'latest'}...`);

  // Get current block if endBlock not specified
  if (!endBlock) {
    endBlock = await provider.getBlockNumber();
    console.log(`Using current block ${endBlock} as end block`);
  }

  // Create contract instance for better event filtering
  const orderContract = new ethers.Contract(orderAddress, abiTermMaxOrder, provider);

  try {
    // Collect all relevant events using queryFilter which handles complex event types better
    console.log(`Querying events from block ${startBlock} to ${endBlock}...`);

    // Define batch size to avoid too large requests
    const BATCH_SIZE = 10000;

    // Arrays to hold all events
    let swapExactEvents: ethers.Event[] = [];
    let swapToExactEvents: ethers.Event[] = [];
    let updateOrderEvents: ethers.Event[] = [];
    let withdrawEvents: ethers.Event[] = [];
    let initEvents: ethers.Event[] = [];

    // Process in batches
    for (let fromBlock = startBlock; fromBlock <= endBlock; fromBlock += BATCH_SIZE) {
      const toBlock = Math.min(fromBlock + BATCH_SIZE - 1, endBlock);

      console.log(`Querying events from block ${fromBlock} to ${toBlock}...`);

      // Collect events in this batch
      const [
        batchSwapExactEvents,
        batchSwapToExactEvents,
        batchUpdateOrderEvents,
        batchWithdrawEvents,
        batchInitEvents
      ] = await Promise.all([
        orderContract.queryFilter(orderContract.filters.SwapExactTokenToToken(), fromBlock, toBlock),
        orderContract.queryFilter(orderContract.filters.SwapTokenToExactToken(), fromBlock, toBlock),
        orderContract.queryFilter(orderContract.filters.UpdateOrder(), fromBlock, toBlock),
        orderContract.queryFilter(orderContract.filters.WithdrawAssets(), fromBlock, toBlock),
        orderContract.queryFilter(orderContract.filters.OrderInitialized(), fromBlock, toBlock)
      ]);

      console.log(`Found in blocks ${fromBlock}-${toBlock}: ` +
        `SwapExact=${batchSwapExactEvents.length}, ` +
        `SwapToExact=${batchSwapToExactEvents.length}, ` +
        `UpdateOrder=${batchUpdateOrderEvents.length}, ` +
        `Withdraw=${batchWithdrawEvents.length}, ` +
        `Init=${batchInitEvents.length}`);

      // Append batch results to the main arrays
      swapExactEvents = swapExactEvents.concat(batchSwapExactEvents);
      swapToExactEvents = swapToExactEvents.concat(batchSwapToExactEvents);
      updateOrderEvents = updateOrderEvents.concat(batchUpdateOrderEvents);
      withdrawEvents = withdrawEvents.concat(batchWithdrawEvents);
      initEvents = initEvents.concat(batchInitEvents);
    }

    // Log the total events found after batching
    console.log(`Total events found: ` +
      `SwapExact=${swapExactEvents.length}, ` +
      `SwapToExact=${swapToExactEvents.length}, ` +
      `UpdateOrder=${updateOrderEvents.length}, ` +
      `Withdraw=${withdrawEvents.length}, ` +
      `Init=${initEvents.length}`);

    // Process SwapExactTokenToToken events
    for (const event of swapExactEvents) {
      try {
        // Use type assertion to handle the arguments
        const args = event.args as any;
        if (!args) {
          console.error(`Missing arguments in SwapExactTokenToToken event`);
          continue;
        }

        const tokenIn = args.tokenIn;
        const tokenOut = args.tokenOut;
        const caller = args.caller || '';
        const recipient = args.recipient || '';
        const tokenAmtIn = args.tokenAmtIn;
        const netTokenOut = args.netTokenOut;
        const feeAmt = args.feeAmt;

        // Ensure we have the required values before proceeding
        if (!tokenIn || !tokenOut) {
          console.error(`Missing required parameters in SwapExactTokenToToken event`);
          continue;
        }

        const swapEvent: SwapEvent = {
          blockNumber: event.blockNumber,
          transactionHash: event.transactionHash,
          logIndex: event.logIndex,
          eventType: 'SwapExactTokenToToken',
          operationType: 'Swap',
          tokenIn,
          tokenOut,
          caller,
          recipient,
          tokenInAmount: tokenAmtIn ? ethers.BigNumber.from(tokenAmtIn) : ethers.BigNumber.from(0),
          tokenOutAmount: netTokenOut ? ethers.BigNumber.from(netTokenOut) : ethers.BigNumber.from(0),
          feeAmount: feeAmt ? ethers.BigNumber.from(feeAmt) : ethers.BigNumber.from(0),
          timestamp: null  // Will be populated later if needed
        };

        events.swaps.push(swapEvent);
        events.all.push({
          ...swapEvent,
          sortKey: `${event.blockNumber.toString().padStart(10, '0')}-${event.logIndex.toString().padStart(5, '0')}`
        });
      } catch (error) {
        console.error(`Error processing SwapExactTokenToToken event: ${error instanceof Error ? error.message : String(error)}`);
      }
    }

    // Process SwapTokenToExactToken events
    for (const event of swapToExactEvents) {
      try {
        // Use type assertion to handle the arguments
        const args = event.args as any;
        if (!args) {
          console.error(`Missing arguments in SwapTokenToExactToken event`);
          continue;
        }

        const tokenIn = args.tokenIn;
        const tokenOut = args.tokenOut;
        const caller = args.caller || '';
        const recipient = args.recipient || '';
        const tokenAmtOut = args.tokenAmtOut;
        const netTokenIn = args.netTokenIn;
        const feeAmt = args.feeAmt;

        // Ensure we have the required values before proceeding
        if (!tokenIn || !tokenOut) {
          console.error(`Missing required parameters in SwapTokenToExactToken event`);
          continue;
        }

        const swapEvent: SwapEvent = {
          blockNumber: event.blockNumber,
          transactionHash: event.transactionHash,
          logIndex: event.logIndex,
          eventType: 'SwapTokenToExactToken',
          operationType: 'Swap',
          tokenIn,
          tokenOut,
          caller,
          recipient,
          tokenInAmount: netTokenIn ? ethers.BigNumber.from(netTokenIn) : ethers.BigNumber.from(0),
          tokenOutAmount: tokenAmtOut ? ethers.BigNumber.from(tokenAmtOut) : ethers.BigNumber.from(0),
          feeAmount: feeAmt ? ethers.BigNumber.from(feeAmt) : ethers.BigNumber.from(0),
          timestamp: null  // Will be populated later if needed
        };

        events.swaps.push(swapEvent);
        events.all.push({
          ...swapEvent,
          sortKey: `${event.blockNumber.toString().padStart(10, '0')}-${event.logIndex.toString().padStart(5, '0')}`
        });
      } catch (error) {
        console.error(`Error processing SwapTokenToExactToken event: ${error instanceof Error ? error.message : String(error)}`);
      }
    }

    // Process UpdateOrder events
    for (const event of updateOrderEvents) {
      try {
        // Use type assertion to handle the arguments
        const args = event.args as any;
        if (!args) {
          console.error(`Missing arguments in UpdateOrder event`);
          continue;
        }

        const curveCuts = args.curveCuts;
        const ftChangeAmt = args.ftChangeAmt;
        const xtChangeAmt = args.xtChangeAmt;
        const gtId = args.gtId;
        const maxXtReserve = args.maxXtReserve;
        const swapTrigger = args.swapTrigger || '';

        // Ensure we have the required values before proceeding
        if (ftChangeAmt === undefined || xtChangeAmt === undefined) {
          console.error(`Missing required parameters in UpdateOrder event`);
          continue;
        }

        // Determine if this is a deposit, withdrawal, or just a curve update
        let operationType: 'Deposit' | 'Withdraw' | 'UpdateCurve' = 'UpdateCurve';
        if (ethers.BigNumber.from(ftChangeAmt).gt(0) || ethers.BigNumber.from(xtChangeAmt).gt(0)) {
          operationType = 'Deposit';
        } else if (ethers.BigNumber.from(ftChangeAmt).lt(0) || ethers.BigNumber.from(xtChangeAmt).lt(0)) {
          operationType = 'Withdraw';
        }

        const updateEvent: UpdateOrderEvent = {
          blockNumber: event.blockNumber,
          transactionHash: event.transactionHash,
          logIndex: event.logIndex,
          eventType: 'UpdateOrder',
          operationType,
          ftChangeAmt: ethers.BigNumber.from(ftChangeAmt),
          xtChangeAmt: ethers.BigNumber.from(xtChangeAmt),
          gtId: gtId ? ethers.BigNumber.from(gtId) : ethers.BigNumber.from(0),
          maxXtReserve: maxXtReserve ? ethers.BigNumber.from(maxXtReserve) : ethers.BigNumber.from(0),
          swapTrigger,
          timestamp: null,  // Will be populated later if needed
        };

        events.updateCurves.push(updateEvent);

        // Add to the appropriate category
        if (operationType === 'Deposit') {
          events.deposits.push(updateEvent);
        } else if (operationType === 'Withdraw') {
          events.withdrawals.push(updateEvent);
        }

        events.all.push({
          ...updateEvent,
          sortKey: `${event.blockNumber.toString().padStart(10, '0')}-${event.logIndex.toString().padStart(5, '0')}`
        });
      } catch (error) {
        console.error(`Error processing UpdateOrder event: ${error instanceof Error ? error.message : String(error)}`);
      }
    }

    // Process WithdrawAssets events
    for (const event of withdrawEvents) {
      try {
        // Use type assertion to handle the arguments
        const args = event.args as any;
        if (!args) {
          console.error(`Missing arguments in WithdrawAssets event`);
          continue;
        }

        const token = args.token;
        const owner = args.owner;
        const caller = args.caller;
        const recipient = args.recipient || '';
        const amount = args.amount;

        // Ensure we have the required values before proceeding
        if (!token || !amount) {
          console.error(`Missing required parameters in WithdrawAssets event`);
          continue;
        }

        const withdrawEvent: WithdrawAssetsEvent = {
          blockNumber: event.blockNumber,
          transactionHash: event.transactionHash,
          logIndex: event.logIndex,
          eventType: 'WithdrawAssets',
          operationType: 'Withdraw',
          token,
          owner: owner || caller || '',
          recipient,
          amount: ethers.BigNumber.from(amount),
          timestamp: null  // Will be populated later if needed
        };

        events.withdrawals.push(withdrawEvent);
        events.all.push({
          ...withdrawEvent,
          sortKey: `${event.blockNumber.toString().padStart(10, '0')}-${event.logIndex.toString().padStart(5, '0')}`
        });
      } catch (error) {
        console.error(`Error processing WithdrawAssets event: ${error instanceof Error ? error.message : String(error)}`);
      }
    }

    // Process OrderInitialized events
    for (const event of initEvents) {
      try {
        // Use type assertion to handle the arguments
        const args = event.args as any;
        if (!args) {
          console.error(`Missing arguments in OrderInitialized event`);
          continue;
        }

        const market = args.market;
        const maker = args.maker;
        const maxXtReserve = args.maxXtReserve;
        const swapTrigger = args.swapTrigger || '';
        const curveCuts = args.curveCuts;

        // Ensure we have the required values before proceeding
        if (!market || !maker) {
          console.error(`Missing required parameters in OrderInitialized event`);
          continue;
        }

        const initEvent: OrderInitializedEvent = {
          blockNumber: event.blockNumber,
          transactionHash: event.transactionHash,
          logIndex: event.logIndex,
          eventType: 'OrderInitialized',
          operationType: 'Create',  // New operation type for order creation
          market,
          maker,
          maxXtReserve: maxXtReserve ? ethers.BigNumber.from(maxXtReserve) : ethers.BigNumber.from(0),
          swapTrigger,
          timestamp: null  // Will be populated later if needed
        };

        events.creations.push(initEvent);
        events.all.push({
          ...initEvent,
          sortKey: `${event.blockNumber.toString().padStart(10, '0')}-${event.logIndex.toString().padStart(5, '0')}`
        });
      } catch (error) {
        console.error(`Error processing OrderInitialized event: ${error instanceof Error ? error.message : String(error)}`);
      }
    }
  } catch (error) {
    console.error(`Error collecting events: ${error instanceof Error ? error.message : String(error)}`);
  }

  console.log(`Collected events: ${events.all.length} total`);
  console.log(`- Swaps: ${events.swaps.length}`);
  console.log(`- Deposits: ${events.deposits.length}`);
  console.log(`- Withdrawals: ${events.withdrawals.length}`);
  console.log(`- Update Curves: ${events.updateCurves.length}`);
  console.log(`- Creations: ${events.creations.length}`);

  return events;
}

/**
 * Format BigNumber to human-readable string with proper decimals
 * @param amount - Amount to format
 * @param decimals - Number of decimals
 * @returns Formatted string
 */
function formatAmount(amount: ethers.BigNumber | string | undefined, decimals: number = 18): string {
  if (!amount || typeof amount === 'string') {
    return amount?.toString() || '0';
  }

  try {
    return ethers.utils.formatUnits(amount, decimals);
  } catch (error) {
    console.error(`Error formatting amount: ${error instanceof Error ? error.message : String(error)}`);
    return '0';
  }
}

/**
 * Enrich events with additional data like timestamps and token details
 * @param events - Object containing categorized events
 * @param orderInfo - Information about the order and tokens
 * @param provider - Ethers provider
 * @returns - Enriched events
 */
async function enrichEvents(
  events: EventsCollection,
  orderInfo: OrderInfo,
  provider: ethers.providers.Provider
): Promise<EventsCollection> {
  console.log(`Enriching ${events.all.length} events with additional data...`);

  // Group events by block number to minimize RPC calls
  const blockNumbers = [...new Set(events.all.map(event => event.blockNumber))];

  // Get block data in batches
  const blockData: Record<number, { timestamp: number }> = {};
  const BATCH_SIZE = 50;

  for (let i = 0; i < blockNumbers.length; i += BATCH_SIZE) {
    const batch = blockNumbers.slice(i, i + BATCH_SIZE);
    console.log(`Fetching timestamps for blocks ${i} to ${i + batch.length - 1} of ${blockNumbers.length}...`);

    const promises = batch.map(blockNum => provider.getBlock(blockNum));
    const blocks = await Promise.all(promises);

    blocks.forEach(block => {
      if (block) {
        blockData[block.number] = {
          timestamp: block.timestamp
        };
      }
    });
  }

  // Token info for better display
  const tokens = orderInfo?.marketInfo?.tokens || {};
  const tokenDecimals: Record<string, number> = {};
  const tokenSymbols: Record<string, string> = {};

  if (tokens.ft) {
    tokenDecimals[tokens.ft.address.toLowerCase()] = tokens.ft.decimals;
    tokenSymbols[tokens.ft.address.toLowerCase()] = tokens.ft.symbol;
  }

  if (tokens.xt) {
    tokenDecimals[tokens.xt.address.toLowerCase()] = tokens.xt.decimals;
    tokenSymbols[tokens.xt.address.toLowerCase()] = tokens.xt.symbol;
  }

  if (tokens.debtToken) {
    tokenDecimals[tokens.debtToken.address.toLowerCase()] = tokens.debtToken.decimals;
    tokenSymbols[tokens.debtToken.address.toLowerCase()] = tokens.debtToken.symbol;
  }

  if (tokens.collateral) {
    tokenDecimals[tokens.collateral.address.toLowerCase()] = tokens.collateral.decimals;
    tokenSymbols[tokens.collateral.address.toLowerCase()] = tokens.collateral.symbol;
  }

  const debtTokenDecimals = tokens.debtToken?.decimals || 18;
  const ftDecimals = tokens.ft?.decimals || 18;
  const xtDecimals = tokens.xt?.decimals || 18;

  // Enrich swap events
  events.swaps = events.swaps.map(event => {
    // Add timestamp
    if (blockData[event.blockNumber]) {
      event.timestamp = blockData[event.blockNumber].timestamp;
      event.date = new Date(event.timestamp * 1000).toISOString();
    }

    // Add token details
    const tokenInLower = event.tokenIn?.toLowerCase();
    const tokenOutLower = event.tokenOut?.toLowerCase();

    event.tokenInSymbol = tokenSymbols[tokenInLower] || 'Unknown';
    event.tokenOutSymbol = tokenSymbols[tokenOutLower] || 'Unknown';

    const tokenInDecimals = tokenDecimals[tokenInLower] || 18;
    const tokenOutDecimals = tokenDecimals[tokenOutLower] || 18;

    // Add formatted amounts with proper decimals
    event.tokenInAmountFormatted = formatAmount(event.tokenInAmount, tokenInDecimals);
    event.tokenOutAmountFormatted = formatAmount(event.tokenOutAmount, tokenOutDecimals);
    event.feeAmountFormatted = formatAmount(event.feeAmount, debtTokenDecimals);

    // Determine transaction direction (Lend/Borrow/Other)
    const ftTokenAddress = tokens.ft?.address?.toLowerCase();
    const xtTokenAddress = tokens.xt?.address?.toLowerCase();
    const debtTokenAddress = tokens.debtToken?.address?.toLowerCase();

    // Calculate days to maturity for interest rates
    if (event.timestamp && orderInfo.marketInfo.config?.maturity) {
      event.daysToMaturity = Math.floor((parseInt(orderInfo.marketInfo.config.maturity) - event.timestamp) / 86400);
    }

    if (tokenInLower === ftTokenAddress && tokenOutLower === debtTokenAddress) {
      event.direction = 'LEND';
      event.abstractTokenInSymbol = tokens.ft.symbol;
      event.abstractTokenOutSymbol = tokens.xt.symbol;

      event.abstractTokenInAmountFormatted = formatAmount(
        ethers.BigNumber.from(event.tokenInAmount).sub(event.tokenOutAmount),
        debtTokenDecimals
      );
      event.abstractTokenOutAmountFormatted = event.tokenOutAmountFormatted;

      if (event.daysToMaturity && event.daysToMaturity > 0) {
        const abstractIn = parseFloat(event.abstractTokenInAmountFormatted);
        const abstractOut = parseFloat(event.abstractTokenOutAmountFormatted);
        event.avgMatchedInterestRate = (abstractIn / abstractOut) * (365 / event.daysToMaturity);
      }
    } else if (tokenInLower === debtTokenAddress && tokenOutLower === xtTokenAddress) {
      event.direction = 'LEND';
      event.abstractTokenInSymbol = tokens.ft.symbol;
      event.abstractTokenOutSymbol = tokens.xt.symbol;

      event.abstractTokenInAmountFormatted = event.tokenInAmountFormatted;
      event.abstractTokenOutAmountFormatted = formatAmount(
        ethers.BigNumber.from(event.tokenOutAmount).sub(event.tokenInAmount),
        debtTokenDecimals
      );

      if (event.daysToMaturity && event.daysToMaturity > 0) {
        const abstractIn = parseFloat(event.abstractTokenInAmountFormatted);
        const abstractOut = parseFloat(event.abstractTokenOutAmountFormatted);
        event.avgMatchedInterestRate = (abstractIn / abstractOut) * (365 / event.daysToMaturity);
      }
    } else if (tokenInLower === xtTokenAddress && tokenOutLower === debtTokenAddress) {
      event.direction = 'BORROW';
      event.abstractTokenInSymbol = tokens.xt.symbol;
      event.abstractTokenOutSymbol = tokens.ft.symbol;

      event.abstractTokenInAmountFormatted = formatAmount(
        ethers.BigNumber.from(event.tokenInAmount).sub(event.tokenOutAmount),
        debtTokenDecimals
      );
      event.abstractTokenOutAmountFormatted = event.tokenOutAmountFormatted;

      if (event.daysToMaturity && event.daysToMaturity > 0) {
        const abstractIn = parseFloat(event.abstractTokenInAmountFormatted);
        const abstractOut = parseFloat(event.abstractTokenOutAmountFormatted);
        event.avgMatchedInterestRate = (abstractOut / abstractIn) * (365 / event.daysToMaturity);
      }
    } else if (tokenInLower === debtTokenAddress && tokenOutLower === ftTokenAddress) {
      event.direction = 'BORROW';
      event.abstractTokenInSymbol = tokens.xt.symbol;
      event.abstractTokenOutSymbol = tokens.ft.symbol;

      event.abstractTokenInAmountFormatted = event.tokenInAmountFormatted;
      event.abstractTokenOutAmountFormatted = formatAmount(
        ethers.BigNumber.from(event.tokenOutAmount).sub(event.tokenInAmount),
        debtTokenDecimals
      );

      if (event.daysToMaturity && event.daysToMaturity > 0) {
        const abstractIn = parseFloat(event.abstractTokenInAmountFormatted);
        const abstractOut = parseFloat(event.abstractTokenOutAmountFormatted);
        event.avgMatchedInterestRate = (abstractOut / abstractIn) * (365 / event.daysToMaturity);
      }
    } else {
      event.direction = 'OTHER';
    }

    return event;
  });

  // Enrich deposit, withdrawal and update events
  const updateEnrichment = (event: UpdateOrderEvent | WithdrawAssetsEvent): UpdateOrderEvent | WithdrawAssetsEvent => {
    // Add timestamp
    if (blockData[event.blockNumber]) {
      event.timestamp = blockData[event.blockNumber].timestamp;
      event.date = new Date(event.timestamp * 1000).toISOString();
    }

    // For UpdateOrder events, add formatted amounts
    if (event.eventType === 'UpdateOrder' && 'ftChangeAmt' in event) {
      event.ftChangeAmtFormatted = formatAmount(event.ftChangeAmt, ftDecimals);
      event.xtChangeAmtFormatted = formatAmount(event.xtChangeAmt, xtDecimals);
      event.maxXtReserveFormatted = formatAmount(event.maxXtReserve, xtDecimals);
    }

    // For WithdrawAssets events, add token details
    if (event.eventType === 'WithdrawAssets' && 'token' in event) {
      const tokenLower = event.token?.toLowerCase();
      event.tokenSymbol = tokenSymbols[tokenLower] || 'Unknown';
      const tokenDecimal = tokenDecimals[tokenLower] || 18;
      event.amountFormatted = formatAmount(event.amount, tokenDecimal);
    }

    return event;
  };

  events.deposits = events.deposits.map(updateEnrichment) as UpdateOrderEvent[];
  events.withdrawals = events.withdrawals.map(updateEnrichment) as (UpdateOrderEvent | WithdrawAssetsEvent)[];
  events.updateCurves = events.updateCurves.map(updateEnrichment) as UpdateOrderEvent[];

  // Enrich creation events
  events.creations = events.creations.map(event => {
    // Add timestamp
    if (blockData[event.blockNumber]) {
      event.timestamp = blockData[event.blockNumber].timestamp;
      event.date = new Date(event.timestamp * 1000).toISOString();
    }

    // Format maxXtReserve with proper decimals
    event.maxXtReserveFormatted = formatAmount(event.maxXtReserve, xtDecimals);

    return event;
  });

  // Enrich all events and sort them
  events.all = events.all.map(event => {
    if (event.eventType === 'SwapExactTokenToToken' || event.eventType === 'SwapTokenToExactToken') {
      const matchingSwap = events.swaps.find(
        swap => swap.transactionHash === event.transactionHash && swap.logIndex === event.logIndex
      );
      return matchingSwap || event;
    } else if (event.eventType === 'UpdateOrder') {
      const matchingUpdate = [...events.deposits, ...events.withdrawals, ...events.updateCurves].find(
        update => update.transactionHash === event.transactionHash && update.logIndex === event.logIndex
      ) as UpdateOrderEvent;
      return matchingUpdate || event;
    } else if (event.eventType === 'WithdrawAssets') {
      const matchingWithdraw = events.withdrawals.find(
        withdraw => withdraw.transactionHash === event.transactionHash && withdraw.logIndex === event.logIndex
      ) as WithdrawAssetsEvent;
      return matchingWithdraw || event;
    } else if (event.eventType === 'OrderInitialized') {
      const matchingInit = events.creations.find(
        creation => creation.transactionHash === event.transactionHash && creation.logIndex === event.logIndex
      ) as OrderInitializedEvent;
      return matchingInit || event;
    }
    return event;
  });

  // Sort all events by block number (descending) and log index (ascending)
  events.all.sort((a, b) => {
    if (a.blockNumber !== b.blockNumber) {
      return b.blockNumber - a.blockNumber; // Newer blocks first
    }
    return a.logIndex - b.logIndex; // Earlier logs first within the same block
  });

  return events;
}

/**
 * Print event history in a readable format
 * @param events - Object with categorized events
 * @param options - Display options
 */
function printEventHistory(events: EventsCollection, options: DisplayOptions = {}): void {
  const { limit = 20, detailed = false } = options;

  if (events.all.length === 0) {
    console.log("No events found");
    return;
  }

  const displayEvents = events.all.slice(0, limit);

  console.log(`\n--- Order History (showing ${displayEvents.length} of ${events.all.length} events) ---`);
  console.log("Date       | Block   | Type       | Operation | Details");
  console.log("-----------+---------+------------+-----------+------------------------------------");

  for (const event of displayEvents) {
    let dateStr = event.date ? event.date.substring(0, 10) : 'Unknown';
    let typeStr = (event.eventType || 'Unknown').padEnd(12);
    let operationStr = (event.operationType || 'Unknown').padEnd(11);
    let detailsStr = '';

    switch (event.operationType) {
      case 'Swap': {
        const swapEvent = event as SwapEvent;
        const direction = swapEvent.direction || '';
        detailsStr = `${direction}: ${swapEvent.abstractTokenInAmountFormatted} ${swapEvent.abstractTokenInSymbol} → ${swapEvent.abstractTokenOutAmountFormatted} ${swapEvent.abstractTokenOutSymbol}`;
        break;
      }
      case 'Deposit': {
        const depositEvent = event as UpdateOrderEvent;
        let depositDetails: string[] = [];
        if (depositEvent.ftChangeAmt && depositEvent.ftChangeAmt.gt(0)) {
          depositDetails.push(`${depositEvent.ftChangeAmtFormatted} FT`);
        }
        if (depositEvent.xtChangeAmt && depositEvent.xtChangeAmt.gt(0)) {
          depositDetails.push(`${depositEvent.xtChangeAmtFormatted} XT`);
        }
        detailsStr = `Add: ${depositDetails.join(' and ')}`;
        break;
      }
      case 'Withdraw': {
        if (event.eventType === 'WithdrawAssets') {
          const withdrawEvent = event as WithdrawAssetsEvent;
          detailsStr = `Remove: ${withdrawEvent.amountFormatted} ${withdrawEvent.tokenSymbol}`;
        } else {
          const withdrawEvent = event as UpdateOrderEvent;
          let withdrawDetails: string[] = [];
          if (withdrawEvent.ftChangeAmt && withdrawEvent.ftChangeAmt.lt(0)) {
            withdrawDetails.push(`${withdrawEvent.ftChangeAmtFormatted?.replace('-', '')} FT`);
          }
          if (withdrawEvent.xtChangeAmt && withdrawEvent.xtChangeAmt.lt(0)) {
            withdrawDetails.push(`${withdrawEvent.xtChangeAmtFormatted?.replace('-', '')} XT`);
          }
          detailsStr = `Remove: ${withdrawDetails.join(' and ')}`;
        }
        break;
      }
      case 'UpdateCurve': {
        const updateEvent = event as UpdateOrderEvent;
        detailsStr = `Max XT Reserve: ${updateEvent.maxXtReserveFormatted}`;
        break;
      }
      case 'Create': {
        const createEvent = event as OrderInitializedEvent;
        detailsStr = `Order Created, Max XT Reserve: ${createEvent.maxXtReserveFormatted}, Maker: ${createEvent.maker.substring(0, 10)}...`;
        break;
      }
      default:
        detailsStr = event.eventType;
    }

    console.log(
      `${dateStr} | ${event.blockNumber} | ${typeStr} | ${operationStr} | ${detailsStr}`
    );
  }

  // Show detailed view if requested
  if (detailed && displayEvents.length > 0) {
    console.log("\n--- Detailed Event View ---");

    for (let i = 0; i < Math.min(5, displayEvents.length); i++) {
      const event = displayEvents[i];
      console.log(`\nEvent #${i + 1}:`);
      console.log(`Hash: ${event.transactionHash}`);
      console.log(`Block: ${event.blockNumber} | Log Index: ${event.logIndex}`);
      console.log(`Type: ${event.eventType}`);
      console.log(`Operation: ${event.operationType}`);
      console.log(`Date: ${event.date || 'Unknown'}`);

      switch (event.operationType) {
        case 'Swap': {
          const swapEvent = event as SwapEvent;
          console.log(`Direction: ${swapEvent.direction}`);
          console.log(`Token In: ${swapEvent.tokenInAmountFormatted} ${swapEvent.tokenInSymbol} (${swapEvent.tokenIn})`);
          console.log(`Token Out: ${swapEvent.tokenOutAmountFormatted} ${swapEvent.tokenOutSymbol} (${swapEvent.tokenOut})`);
          console.log(`Fee: ${swapEvent.feeAmountFormatted}`);
          console.log(`Caller: ${swapEvent.caller}`);
          console.log(`Recipient: ${swapEvent.recipient}`);
          break;
        }
        case 'Deposit':
        case 'Withdraw':
        case 'UpdateCurve': {
          if (event.eventType === 'UpdateOrder') {
            const updateEvent = event as UpdateOrderEvent;
            console.log(`FT Change: ${updateEvent.ftChangeAmtFormatted}`);
            console.log(`XT Change: ${updateEvent.xtChangeAmtFormatted}`);
            console.log(`Max XT Reserve: ${updateEvent.maxXtReserveFormatted}`);
            console.log(`GT ID: ${updateEvent.gtId.toString()}`);
            console.log(`Swap Trigger: ${updateEvent.swapTrigger}`);
          } else if (event.eventType === 'WithdrawAssets') {
            const withdrawEvent = event as WithdrawAssetsEvent;
            console.log(`Token: ${withdrawEvent.tokenSymbol} (${withdrawEvent.token})`);
            console.log(`Amount: ${withdrawEvent.amountFormatted}`);
            console.log(`Owner: ${withdrawEvent.owner}`);
            console.log(`Recipient: ${withdrawEvent.recipient}`);
          }
          break;
        }
        case 'Create': {
          const createEvent = event as OrderInitializedEvent;
          console.log(`Market: ${createEvent.market}`);
          console.log(`Maker: ${createEvent.maker}`);
          console.log(`Max XT Reserve: ${createEvent.maxXtReserveFormatted}`);
          console.log(`Swap Trigger: ${createEvent.swapTrigger}`);
          break;
        }
      }
    }
  }

  if (events.all.length > limit) {
    console.log(`\n... and ${events.all.length - limit} more events`);
  }
}

/**
 * Generate a CSV file with order history
 * @param events - Object with categorized events
 * @param filename - Output filename for the CSV
 */
function generateCsvFile(events: EventsCollection, filename: string): void {
  // Define CSV header
  const header = 'Date,Block,Operation,Direction,Amount,InterestRate\n';

  // Initialize CSV content with header
  let csvContent = header;

  // Sort events by block number (ascending) to show chronological order in the CSV
  const sortedEvents = [...events.all].sort((a, b) => a.blockNumber - b.blockNumber);

  for (const event of sortedEvents) {
    // Only include events with a date (those we've enriched with timestamps)
    if (event.date) {
      let date = event.date.substring(0, 10);
      let blockNumber = event.blockNumber;
      let operation = event.operationType || 'Unknown';
      let direction = (event as SwapEvent).direction || 'N/A';
      let amount: string | number = 0;
      let interestRate = (event as SwapEvent).avgMatchedInterestRate || '';

      // Determine amount based on direction
      if (direction === 'LEND') {
        const swapEvent = event as SwapEvent;
        amount = swapEvent.abstractTokenOutAmountFormatted || '0';
      } else if (direction === 'BORROW') {
        const swapEvent = event as SwapEvent;
        amount = swapEvent.abstractTokenInAmountFormatted || '0';
      } else if (operation === 'Deposit' && (event as UpdateOrderEvent).ftChangeAmtFormatted) {
        const depositEvent = event as UpdateOrderEvent;
        direction = 'DEPOSIT';
        amount = depositEvent.ftChangeAmtFormatted?.replace('-', '') || '0';
      } else if (operation === 'Withdraw' && (event as UpdateOrderEvent).ftChangeAmtFormatted) {
        const withdrawEvent = event as UpdateOrderEvent;
        direction = 'WITHDRAW';
        amount = withdrawEvent.ftChangeAmtFormatted?.replace('-', '') || '0';
      } else if (operation === 'Create') {
        const createEvent = event as OrderInitializedEvent;
        direction = 'CREATE';
        amount = createEvent.maxXtReserveFormatted || '0';
      }

      // Skip rows that don't have meaningful amounts
      if (amount) {
        // Escape any commas in the values
        csvContent += `${date},${blockNumber},${operation},${direction},${amount},${interestRate}\n`;
      }
    }
  }

  // Write to file
  fs.writeFileSync(filename, csvContent);
  console.log(`\nCSV order history exported to ${filename}`);
}

/**
 * Helper function to convert BigNumber values to strings for JSON serialization
 * @param event - Event object to process
 * @returns Processed event with BigNumber values converted to strings
 */
function processEventForJson(event: EventType): Record<string, any> {
  const result: Record<string, any> = { ...event };

  // Convert known BigNumber fields to strings
  const bigNumberFields = [
    'tokenInAmount', 'tokenOutAmount', 'feeAmount', 'amount',
    'ftChangeAmt', 'xtChangeAmt', 'maxXtReserve', 'gtId'
  ];

  for (const field of bigNumberFields) {
    if (result[field] && typeof result[field] !== 'string' && result[field].toString) {
      result[field] = result[field].toString();
    }
  }

  // Delete sort key as it's not needed in JSON output
  delete result.sortKey;

  return result;
}

/**
 * Process token objects for JSON serialization
 * @param tokens - Token objects to process
 * @returns Processed tokens
 */
function processMappedTokens(tokens?: MarketTokens): Record<string, any> {
  if (!tokens) return {};

  const result: Record<string, any> = {};
  for (const key in tokens) {
    if (Object.prototype.hasOwnProperty.call(tokens, key)) {
      result[key] = { ...(tokens as any)[key] };
    }
  }

  return result;
}

interface CommandOptions {
  startBlock?: number;
  endBlock?: number;
  includeTimestamps?: boolean;
  showDetails?: boolean;
  limit?: number;
  outputFile?: string;
  csvFile?: string;
}

async function main(): Promise<void> {
  // Get command line arguments
  const args = process.argv.slice(2);

  if (args.length < 2) {
    console.error("Usage: node order-history-tracker.js <order-address> <rpc-url> [options]");
    console.error("Options:");
    console.error("  --start-block <number>    Starting block number (default: 0)");
    console.error("  --end-block <number>      Ending block number (default: current)");
    console.error("  --include-timestamps      Include timestamps in output");
    console.error("  --show-details            Show detailed information for events");
    console.error("  --limit <number>          Maximum number of events to display (default: 20)");
    console.error("  --output-file <filename>  Save results to JSON file (default: order-history.json)");
    console.error("  --csv-file <filename>     Export order history to CSV file");
    process.exit(1);
  }

  const orderAddress = args[0];
  const rpcUrl = args[1];

  // Parse options from remaining arguments
  const options: CommandOptions = {};
  for (let i = 2; i < args.length; i++) {
    if (args[i] === '--start-block' && i + 1 < args.length) {
      options.startBlock = parseInt(args[i + 1]);
      i++; // Skip the next argument
    } else if (args[i] === '--end-block' && i + 1 < args.length) {
      options.endBlock = parseInt(args[i + 1]);
      i++; // Skip the next argument
    } else if (args[i] === '--include-timestamps') {
      options.includeTimestamps = true;
    } else if (args[i] === '--show-details') {
      options.showDetails = true;
    } else if (args[i] === '--limit' && i + 1 < args.length) {
      options.limit = parseInt(args[i + 1]);
      i++; // Skip the next argument
    } else if (args[i] === '--output-file' && i + 1 < args.length) {
      options.outputFile = args[i + 1];
      i++; // Skip the next argument
    } else if (args[i] === '--output-file') {
      options.outputFile = 'order-history.json'; // Default filename if none provided
    } else if (args[i] === '--csv-file' && i + 1 < args.length) {
      options.csvFile = args[i + 1];
      i++; // Skip the next argument
    } else if (args[i] === '--csv-file') {
      options.csvFile = 'order-history.csv'; // Default filename if none provided
    }
  }

  try {
    // Get an ethers provider
    const provider = new ethers.providers.JsonRpcProvider(rpcUrl);

    // Step 0: Get order information
    const orderInfo = await getOrderInfo(orderAddress, provider);

    // Step 1: Collect events
    let events = await collectOrderEvents(
      orderAddress,
      provider,
      options.startBlock || 0,
      options.endBlock
    );

    // Step 2: Optionally enrich events with additional data
    if (options.includeTimestamps || true) { // Always enrich for better display
      events = await enrichEvents(events, orderInfo, provider);
    }

    // Step 3: Print event history
    printEventHistory(events, {
      limit: options.limit || 20,
      detailed: options.showDetails || false
    });

    // Step 4: Save to JSON file if outputFile option is specified
    if (options.outputFile) {
      // Convert BigNumber to string for JSON serialization
      const jsonEvents = {
        swaps: events.swaps.map(processEventForJson),
        deposits: events.deposits.map(processEventForJson),
        withdrawals: events.withdrawals.map(processEventForJson),
        updateCurves: events.updateCurves.map(processEventForJson),
        creations: events.creations.map(processEventForJson),
        all: events.all.map(processEventForJson),
        orderInfo: {
          ...orderInfo,
          ftReserve: orderInfo.ftReserve,
          xtReserve: orderInfo.xtReserve,
          marketInfo: {
            ...orderInfo.marketInfo,
            tokens: processMappedTokens(orderInfo.marketInfo?.tokens)
          }
        }
      };

      fs.writeFileSync(options.outputFile, JSON.stringify(jsonEvents, null, 2));
      console.log(`\nResults saved to ${options.outputFile}`);
    }

    // Step 5: Generate CSV file if requested
    if (options.csvFile) {
      generateCsvFile(events, options.csvFile);
    }

    // Print summary stats
    console.log("\n--- Order Summary ---");
    console.log(`Total Events: ${events.all.length}`);
    console.log(`- Swaps: ${events.swaps.length}`);
    console.log(`- Deposits: ${events.deposits.length}`);
    console.log(`- Withdrawals: ${events.withdrawals.length}`);
    console.log(`- Curve Updates: ${events.updateCurves.length}`);
    console.log(`- Creations: ${events.creations.length}`);

    const marketInfo = orderInfo.marketInfo;
    const tokens = marketInfo?.tokens || {};

    if (marketInfo && tokens) {
      const ftDecimals = tokens.ft?.decimals || 18;
      const xtDecimals = tokens.xt?.decimals || 18;

      console.log("\n--- Current Reserves ---");
      console.log(`FT Reserve: ${formatAmount(ethers.BigNumber.from(orderInfo.ftReserve), ftDecimals)} ${tokens.ft?.symbol || 'FT'}`);
      console.log(`XT Reserve: ${formatAmount(ethers.BigNumber.from(orderInfo.xtReserve), xtDecimals)} ${tokens.xt?.symbol || 'XT'}`);

      if (marketInfo.config) {
        console.log(`\nMarket Maturity: ${marketInfo.config.maturityDate}`);
      }
    }

  } catch (error) {
    console.error("Error tracking order history:", error instanceof Error ? error.message : String(error));
    process.exit(1);
  }
}

// Export functions for potential use in other scripts
export {
  getTokenInfo,
  getMarketInfo,
  getOrderInfo,
  collectOrderEvents,
  enrichEvents,
  formatAmount,
  printEventHistory
};

// Run if this script is executed directly
if (require.main === module) {
  main();
} 