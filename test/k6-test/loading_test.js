import http from 'k6/http';
import { check, group, sleep } from 'k6';
import { randomItem, randomIntBetween } from 'https://jslib.k6.io/k6-utils/1.6.0/index.js';

// VU code
export async function loadingTest(data) {
  const config = data.config;
  group('TermMax - Load Orders', () => {
    const chainId = randomItem(config.CHAIN_IDS);
    const { marketAddresses, orderAddresses } = getConfigs(config, chainId);
    getOrders(config, chainId, orderAddresses);
    getPrices(config, chainId, marketAddresses);
  });

  sleep(randomIntBetween(1, 5));
}

// --- Helper Functions ---
function getConfigs(config, chainId) {
  const res = http.get(`${config.BASE_URL}/market/config/list?chainId=${chainId}&minLowCapacityValue=10000`);
  check(res, { 'get configs success': (r) => r.status === 200 });
  const marketConfigs = JSON.parse(res.body);
  const marketAddresses = marketConfigs.data.markets.map((market) => market.contracts.marketAddr);
  const orderAddresses = marketConfigs.data.orderConfigs.map((order) => order.contracts.orderAddr);
  return { marketAddresses, orderAddresses };
}
function getPrices(config, chainId, marketAddresses) {
  for (let i = 0; i < marketAddresses.length; i++) {
    getPriceByMarket(config, chainId, marketAddresses[i]);
  }
}
function getPriceByMarket(config, chainId, marketAddress) {
  const res = http.get(
    `${config.BASE_URL}/market/info/prices?chainId=${chainId}&marketAddress=${marketAddress}&includeInactive=false`,
  );
  if (res.status != 200) {
    console.log(res.body);
  }
  check(res, { 'get price success': (r) => r.status === 200 });
}
function getOrders(config, chainId, orderAddresses) {
  for (let i = 0; i < orderAddresses.length; i++) {
    getOrderInfo(config, chainId, orderAddresses[i]);
  }
}
function getOrderInfo(config, chainId, orderAddress) {
  const res = http.get(`${config.BASE_URL}/market/info/order?chainId=${chainId}&orderAddress=${orderAddress}`);
  check(res, { 'get order info success': (r) => r.status === 200 });
}
