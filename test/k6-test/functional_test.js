import http from 'k6/http';
import { check, group, sleep } from 'k6';
import { randomItem, randomIntBetween } from 'https://jslib.k6.io/k6-utils/1.6.0/index.js';

// VU code
export async function functionalTest(data) {
  const config = data.config;
  group('TermMax - default', () => {
    root(config.BASE_URL);
    health(config.BASE_URL);
    // error(config.BASE_URL);
  });

  group('TermMax - market', () => {
    const chainId = randomItem(config.CHAIN_IDS);
    generalConfig(config.BASE_URL, chainId);
    marketData(config.BASE_URL, chainId);
    configList(config.BASE_URL, chainId);
    marketList(config.BASE_URL, chainId);
    marketItem(config.BASE_URL, chainId);
    assetList(config.BASE_URL, chainId);
    assetItem(config.BASE_URL, chainId);
    gtList(config.BASE_URL, chainId);
    gtItem(config.BASE_URL, chainId);
    orderList(config.BASE_URL, chainId);
    orderItem(config.BASE_URL, chainId);
    orderInfos(config.BASE_URL, chainId);
    orderInfo(config.BASE_URL, chainId);
    priceInfos(config.BASE_URL, chainId);
    priceInfo(config.BASE_URL, chainId);
  });

  // group('TermMax - contract', () => {
  //   const chainId = randomItem(config.CHAIN_IDS);
  //   const sampleData = {
  //     chainId: chainId,
  //     marketAddress: '0x...', // Sample market address
  //     orderAddress: '0x...', // Sample order address
  //     userAddress: '0x...', // Sample user address
  //   };

  //   flashRepayFromColl(config.BASE_URL, sampleData);
  //   leverageFromToken(config.BASE_URL, sampleData);
  //   leverageFromXt(config.BASE_URL, sampleData);
  //   borrowTokenFromCollateral(config.BASE_URL, sampleData);
  // });

  group('TermMax - dashboard', () => {
    const chainId = randomItem(config.CHAIN_IDS);
    const userAddress = '0x2a58a3d405c527491daae4c62561b949e7f87efe'; // Sample user address

    positionSummary(config.BASE_URL, chainId, userAddress);
    totalUsdValue(config.BASE_URL, chainId, userAddress);
  });

  group('TermMax - Maker', () => {
    const chainId = randomItem(config.CHAIN_IDS);
    defaultOrderParams(config.BASE_URL, chainId);
    createOrderHistory(config.BASE_URL, chainId);
    updateOrderHistory(config.BASE_URL, chainId);
    debugCreateHistory(config.BASE_URL);
  });

  group('TermMax - Taker', () => {
    const chainId = randomItem(config.CHAIN_IDS);
    buyFt(config.BASE_URL, chainId);
    buyXt(config.BASE_URL, chainId);
    sellFt(config.BASE_URL, chainId);
    sellXt(config.BASE_URL, chainId);
    aggregatorBuyFt(config.BASE_URL, chainId);
    aggregatorBuyXt(config.BASE_URL, chainId);
    aggregatorSellFt(config.BASE_URL, chainId);
    aggregatorSellXt(config.BASE_URL, chainId);
  });

  sleep(randomIntBetween(1, 5));
}

// Add new helper functions
// function flashRepayFromColl(BASE_URL, data) {
//   const payload = {
//     chainId: data.chainId,
//     marketAddress: data.marketAddress,
//     orderAddress: data.orderAddress,
//     // Add other required fields based on your API requirements
//   };

//   const res = http.post(`${BASE_URL}/contract/flashRepayFromColl`, JSON.stringify(payload), {
//     headers: { 'Content-Type': 'application/json' },
//   });
//   check(res, { 'flash repay from coll success': (r) => r.status === 200 });
// }

// function leverageFromToken(BASE_URL, data) {
//   const payload = {
//     chainId: data.chainId,
//     marketAddress: data.marketAddress,
//     // Add other required fields
//   };

//   const res = http.post(`${BASE_URL}/contract/leverageFromToken`, JSON.stringify(payload), {
//     headers: { 'Content-Type': 'application/json' },
//   });
//   check(res, { 'leverage from token success': (r) => r.status === 200 });
// }

// function leverageFromXt(BASE_URL, data) {
//   const payload = {
//     chainId: data.chainId,
//     marketAddress: data.marketAddress,
//     // Add other required fields
//   };

//   const res = http.post(`${BASE_URL}/contract/LeverageFromXt`, JSON.stringify(payload), {
//     headers: { 'Content-Type': 'application/json' },
//   });
//   check(res, { 'leverage from xt success': (r) => r.status === 200 });
// }

// function borrowTokenFromCollateral(BASE_URL, data) {
//   const payload = {
//     chainId: data.chainId,
//     marketAddress: data.marketAddress,
//     // Add other required fields
//   };

//   const res = http.post(`${BASE_URL}/contract/borrowTokenFromCollateral`, JSON.stringify(payload), {
//     headers: { 'Content-Type': 'application/json' },
//   });
//   check(res, { 'borrow token from collateral success': (r) => r.status === 200 });
// }

function positionSummary(BASE_URL, chainId, userAddress) {
  const res = http.get(`${BASE_URL}/dashboard/position/summary?chainId=${chainId}&userAddress=${userAddress}`);
  check(res, { 'get position summary success': (r) => r.status === 200 });
}

function totalUsdValue(BASE_URL, chainId, userAddress) {
  const res = http.get(`${BASE_URL}/dashboard/position/total-usd-value?chainId=${chainId}&userAddress=${userAddress}`);
  check(res, { 'get total usd value success': (r) => r.status === 200 });
}

// --- Helper Functions ---
function root(BASE_URL) {
  const res = http.get(`${BASE_URL}/`);
  check(res, { 'get root success': (r) => r.status === 200 });
}
function health(BASE_URL) {
  const res = http.get(`${BASE_URL}/health`);
  check(res, { 'get health success': (r) => r.status === 200 });
}
function error(BASE_URL) {
  const res = http.get(`${BASE_URL}/error`);
  check(res, { 'get error success': (r) => r.status === 403 });
}
function generalConfig(BASE_URL, chainId) {
  const res = http.get(`${BASE_URL}/market/config/general?chainId=${chainId}`);
  check(res, { 'get general config success': (r) => r.status === 200 });
}
function marketData(BASE_URL, chainId) {
  var res = http.get(`${BASE_URL}/market/data?chainId=${chainId}`);
  check(res, { 'get market data success': (r) => r.status === 200 });
  const minLowCapacityValue = randomIntBetween(10000, 1000000);
  res = http.get(`${BASE_URL}/market/data?chainId=${chainId}&minLowCapacityValue=${minLowCapacityValue}`);
  check(res, { 'get market data with minLowCapacityValue success': (r) => r.status === 200 });
}
function configList(BASE_URL, chainId) {
  var res = http.get(`${BASE_URL}/market/config/list?chainId=${chainId}`);
  check(res, { 'get config list success': (r) => r.status === 200 });
  const minLowCapacityValue = randomIntBetween(10000, 1000000);
  res = http.get(`${BASE_URL}/market/config/list?chainId=${chainId}&minLowCapacityValue=${minLowCapacityValue}`);
  check(res, { 'get config list with minLowCapacityValue success': (r) => r.status === 200 });
}
function assetList(BASE_URL, chainId) {
  var res = http.get(`${BASE_URL}/market/config/asset/list?chainId=${chainId}`);
  check(res, { 'get asset list success': (r) => r.status === 200 });
  return res.json().data.map((asset) => asset.contractAddress);
}
function assetItem(BASE_URL, chainId) {
  const assetAddresses = assetList(BASE_URL, chainId);
  for (let i = 0; i < assetAddresses.length; i++) {
    const res = http.get(`${BASE_URL}/market/config/asset/item?chainId=${chainId}&assetAddress=${assetAddresses[i]}`);
    check(res, { 'get asset item success': (r) => r.status === 200 });
  }
}
function gtList(BASE_URL, chainId) {
  var res = http.get(`${BASE_URL}/market/config/gt/list?chainId=${chainId}`);
  check(res, { 'get gt list success': (r) => r.status === 200 });
}
function gtItem(BASE_URL, chainId) {
  const marketAddresses = marketList(BASE_URL, chainId);
  for (let i = 0; i < marketAddresses.length; i++) {
    var res = http.get(`${BASE_URL}/market/config/gt/item?chainId=${chainId}&marketAddress=${marketAddresses[i]}`);
    check(res, { 'get gt item success': (r) => r.status === 200 });
  }
}
function marketList(BASE_URL, chainId) {
  var res = http.get(`${BASE_URL}/market/config/market/list?chainId=${chainId}`);
  check(res, { 'get market list success': (r) => r.status === 200 });
  return res.json().data.map((market) => market.contracts.marketAddr);
}
function marketItem(BASE_URL, chainId) {
  const marketAddresses = marketList(BASE_URL, chainId);
  for (let i = 0; i < marketAddresses.length; i++) {
    const res = http.get(
      `${BASE_URL}/market/config/market/item?chainId=${chainId}&marketAddress=${marketAddresses[i]}`,
    );
    check(res, { 'get market item success': (r) => r.status === 200 });
  }
}
function orderList(BASE_URL, chainId) {
  const res = http.get(`${BASE_URL}/market/config/order/list?chainId=${chainId}`);
  check(res, { 'get order list success': (r) => r.status === 200 });
  return res.json().data.map((order) => order.contracts.orderAddr);
}
function orderItem(BASE_URL, chainId) {
  const orderAddresses = orderList(BASE_URL, chainId);
  for (let i = 0; i < orderAddresses.length; i++) {
    const res = http.get(`${BASE_URL}/market/config/order/item?chainId=${chainId}&orderAddress=${orderAddresses[i]}`);
    check(res, { 'get order item success': (r) => r.status === 200 });
  }
}
function orderInfos(BASE_URL, chainId) {
  const res = http.get(`${BASE_URL}/market/info/orders?chainId=${chainId}`);
  check(res, { 'get order infos success': (r) => r.status === 200 });
}
function orderInfo(BASE_URL, chainId) {
  const orderAddresses = orderList(BASE_URL, chainId);
  for (let i = 0; i < orderAddresses.length; i++) {
    const res = http.get(`${BASE_URL}/market/info/order?chainId=${chainId}&orderAddress=${orderAddresses[i]}`);
    check(res, { 'get order info success': (r) => r.status === 200 });
  }
}
function priceInfos(BASE_URL, chainId) {
  const res = http.get(`${BASE_URL}/market/info/prices?chainId=${chainId}`);
  check(res, { 'get price infos success': (r) => r.status === 200 });
}
function priceInfo(BASE_URL, chainId) {
  const assetAddresses = assetList(BASE_URL, chainId);
  for (let i = 0; i < assetAddresses.length; i++) {
    const res = http.get(`${BASE_URL}/market/info/price?chainId=${chainId}&assetAddress=${assetAddresses[i]}`);
    check(res, { 'get price info success': (r) => r.status === 200 });
  }
}
function defaultOrderParams(BASE_URL, chainId) {
  const marketAddresses = marketList(BASE_URL, chainId);
  for (let i = 0; i < marketAddresses.length; i++) {
    const typ = randomItem(['hybrid', 'lend', 'borrow']);
    const res = http.get(
      `${BASE_URL}/maker/order/default-order-params?chainId=${chainId}&typ=${typ}&marketAddress=${marketAddresses[i]}`,
    );
    check(res, { 'get default order params success': (r) => r.status === 200 });
  }
}
function createOrderHistory(BASE_URL, chainId) {
  const marketAddresses = marketList(BASE_URL, chainId);
  for (let i = 0; i < marketAddresses.length; i++) {
    const res = http.get(
      `${BASE_URL}/maker/order/create-order-history?chainId=${chainId}&marketAddress=${marketAddresses[i]}`,
    );
    check(res, { 'get create order history success': (r) => r.status === 200 });
  }
}
function updateOrderHistory(BASE_URL, chainId) {
  const orderAddresses = orderList(BASE_URL, chainId);
  for (let i = 0; i < orderAddresses.length; i++) {
    const res = http.get(
      `${BASE_URL}/maker/order/update-order-history?chainId=${chainId}&orderAddress=${orderAddresses[i]}`,
    );
    check(res, { 'get update order history success': (r) => r.status === 200 });
  }
}
function debugCreateHistory(BASE_URL) {
  const res = http.get(`${BASE_URL}/maker/order/debug-create-history`);
  check(res, { 'get debug create history success': (r) => r.status === 200 });
}
function buyFt(BASE_URL, chainId) {
  const marketAddresses = marketList(BASE_URL, chainId);
  for (let i = 0; i < marketAddresses.length; i++) {
    const res = http.get(`${BASE_URL}/taker/order/buy-ft?chainId=${chainId}&marketAddress=${marketAddresses[i]}`);
    check(res, { 'get buy ft success': (r) => r.status === 200 });
  }
}
function buyXt(BASE_URL, chainId) {
  const marketAddresses = marketList(BASE_URL, chainId);
  for (let i = 0; i < marketAddresses.length; i++) {
    const res = http.get(`${BASE_URL}/taker/order/buy-xt?chainId=${chainId}&marketAddress=${marketAddresses[i]}`);
    check(res, { 'get buy xt success': (r) => r.status === 200 });
  }
}
function sellFt(BASE_URL, chainId) {
  const marketAddresses = marketList(BASE_URL, chainId);
  for (let i = 0; i < marketAddresses.length; i++) {
    const res = http.get(`${BASE_URL}/taker/order/sell-ft?chainId=${chainId}&marketAddress=${marketAddresses[i]}`);
    check(res, { 'get sell ft success': (r) => r.status === 200 });
  }
}
function sellXt(BASE_URL, chainId) {
  const marketAddresses = marketList(BASE_URL, chainId);
  for (let i = 0; i < marketAddresses.length; i++) {
    const res = http.get(`${BASE_URL}/taker/order/sell-xt?chainId=${chainId}&marketAddress=${marketAddresses[i]}`);
    check(res, { 'get sell xt success': (r) => r.status === 200 });
  }
}
function aggregatorBuyFt(BASE_URL, chainId) {
  const marketAddreses = marketList(BASE_URL, chainId);
  for (let i = 0; i < marketAddreses.length; i++) {
    const res = http.get(
      `${BASE_URL}/taker/order/aggregator/buy-ft?chainId=${chainId}&marketAddress=${marketAddreses[i]}`,
    );
    check(res, { 'get aggregator buy ft success': (r) => r.status === 200 });
  }
}
function aggregatorBuyXt(BASE_URL, chainId) {
  const marketAddreses = marketList(BASE_URL, chainId);
  for (let i = 0; i < marketAddreses.length; i++) {
    const res = http.get(
      `${BASE_URL}/taker/order/aggregator/buy-xt?chainId=${chainId}&marketAddress=${marketAddreses[i]}`,
    );
    check(res, { 'get aggregator buy xt success': (r) => r.status === 200 });
  }
}
function aggregatorSellFt(BASE_URL, chainId) {
  const marketAddreses = marketList(BASE_URL, chainId);
  for (let i = 0; i < marketAddreses.length; i++) {
    const res = http.get(
      `${BASE_URL}/taker/order/aggregator/sell-ft?chainId=${chainId}&marketAddress=${marketAddreses[i]}`,
    );
    check(res, { 'get aggregator sell ft success': (r) => r.status === 200 });
  }
}
function aggregatorSellXt(BASE_URL, chainId) {
  const marketAddreses = marketList(BASE_URL, chainId);
  for (let i = 0; i < marketAddreses.length; i++) {
    const res = http.get(
      `${BASE_URL}/taker/order/aggregator/sell-xt?chainId=${chainId}&marketAddress=${marketAddreses[i]}`,
    );
    check(res, { 'get aggregator sell xt success': (r) => r.status === 200 });
  }
}
