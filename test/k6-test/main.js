import { loadingTest } from './loading_test.js';
import { functionalTest } from './functional_test.js';
import { EnvConfig, WorkloadConfig } from './config.js';

const config = EnvConfig[__ENV.ENV] || EnvConfig['dev'];
const stages = WorkloadConfig[__ENV.WORKLOAD] || WorkloadConfig['smoke'];

export function setup() {
  return { config };
}

export function teardown() {
  console.log('Teardown phase completed.');
}

export const options = {
  thresholds: {
    checks: ['rate>0.95'], // the rate of successful checks should be higher than 95%
    http_req_failed: [{ threshold: 'rate<0.01' }], // http errors should be less than 1%
    http_req_duration: ['p(95)<1000'], // 95% of requests should be below 150ms
  },
  scenarios: {
    functional_test: {
      executor: 'per-vu-iterations',
      exec: 'functionalTest',
      vus: 1,
      iterations: 1,
      maxDuration: '1m',
    },
    loading_test_user: {
      executor: 'ramping-vus',
      exec: 'loadingTest',
      stages: stages,
    },
    // loading_test_api: {
    //   executor: 'ramping-vus',
    //   exec: 'functionalTest',
    //   stages: stages,
    // },
  },
};

export { loadingTest, functionalTest };
