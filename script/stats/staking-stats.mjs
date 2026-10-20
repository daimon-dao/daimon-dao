// Staking statistics of DMN, rebuilt from the chain and checked against the
// contract's own totals. Read-only, public RPC endpoints only, no key, no
// dependency (Node 22+ built-in fetch). See script/stats/README.md and
// docs/STAKING_STATS.md.
//
//   node script/stats/staking-stats.mjs                         # events, at head - 20
//   node script/stats/staking-stats.mjs --source state          # lock structs, at head - 20
//   node script/stats/staking-stats.mjs --block 128734500 --source state
//
// Two ways to rebuild the active locks, same aggregates, same checks:
//   events  every Staked and Withdrawn event of the staking contract from the
//           deploy block to the target block (history RPC, 5000-block pages),
//           replayed in chain order: a lock is active if it was staked and not
//           withdrawn by the target block;
//   state   locks(i) for every i below nextLockId(), read at the target block
//           (state RPC, batched eth_call): a lock is active if its `withdrawn`
//           flag is false.
// Either way the script then reads totalStakedAmount(), totalVotingPower() and
// nextLockId() at the target block and FAILS if the rebuilt totals differ by a
// single wei. It prints, per lock period, the number of locks, the DMN, the
// share of staked DMN and the share of voting power; periods with fewer than 3
// locks are merged into one "small buckets" line.
//
// Aggregates only: the holder address (topics[1] of the events, the first word
// of the lock struct) is never decoded, stored or printed. Lock ids are used
// only to pair Staked with Withdrawn and to enumerate the structs.

const STAKING = "0xBb596e7308D6C5AED55cEC597D372840Cbe575b1"; // DaimonStaking, BSC mainnet
const DEPLOY_BLOCK = 124626901; // docs/MAINNET_LAUNCH_RECORD.md
const PAGE = 5000; // bloXroute: "exceed maximum block range: 5000"
const BATCH = 50; // eth_call per JSON-RPC batch (state source)
const HEAD_LAG = 20; // default target = head - 20, past any short reorg
const MIN_LOCKS_PER_LINE = 3; // periods with fewer locks go to "small buckets"

// Signatures (cast sig / cast keccak, src/DaimonStaking.sol):
//   totalStakedAmount()  0x567e98f9
//   totalVotingPower()   0x671b3793
//   nextLockId()         0x6518a0b3
//   locks(uint256)       0xf4dadc61 -> (address owner, uint256 amount, uint256 start, uint256 unlockTime,
//                                        uint256 multiplierX1000, uint256 votingPowerGranted, bool withdrawn)
//   Staked(address indexed user, uint256 indexed lockId, uint256 amount, uint256 duration, uint256 votingPowerGranted)
//   Withdrawn(address indexed user, uint256 indexed lockId, uint256 amount)
const SEL = { totalStakedAmount: "0x567e98f9", totalVotingPower: "0x671b3793", nextLockId: "0x6518a0b3", locks: "0xf4dadc61" };
const TOPIC_STAKED = "0x9cfd25589d1eb8ad71e342a86a8524e83522e3936c0803048c08f6d9ad974f40";
const TOPIC_WITHDRAWN = "0x92ccf450a286a957af52509bc1c9939d1a6a481783e142e41e2499f0bb66ebc6";

// ---------------------------------------------------------------- arguments
const args = process.argv.slice(2);
const opt = (name, dflt) => {
  const i = args.indexOf(name);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : dflt;
};
if (args.includes("--help") || args.includes("-h")) {
  console.log(`usage: node script/stats/staking-stats.mjs [--source events|state] [--block N] [--history-rpc URL] [--state-rpc URL]

  --source events    replay Staked/Withdrawn from the deploy block (default)
  --source state     read locks(i) for every lock id at the target block
  --block N          target block (default: head - ${HEAD_LAG}); the state RPC must serve
                     state at that block (publicnode: the last few minutes only; for an
                     older block pass --state-rpc with an endpoint that serves it)
  --history-rpc URL  eth_getLogs endpoint, ${PAGE}-block pages (default: bloXroute)
  --state-rpc URL    eth_call / eth_getBlockByNumber endpoint (default: publicnode)`);
  process.exit(0);
}
const SOURCE = opt("--source", process.env.STAKING_STATS_SOURCE ?? "events");
if (!["events", "state"].includes(SOURCE)) throw new Error(`--source must be "events" or "state", not "${SOURCE}"`);
const HISTORY_RPC = opt("--history-rpc", process.env.STAKING_STATS_HISTORY_RPC ?? "https://bsc.rpc.blxrbdn.com");
const STATE_RPC = opt("--state-rpc", process.env.STAKING_STATS_STATE_RPC ?? "https://bsc-rpc.publicnode.com");
const BLOCK_ARG = opt("--block", process.env.STAKING_STATS_BLOCK ?? null);

// ---------------------------------------------------------------- JSON-RPC
let rpcId = 0;
async function post(url, payload, attempts = 5) {
  let lastErr;
  for (let i = 0; i < attempts; i++) {
    try {
      const res = await fetch(url, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(payload),
        signal: AbortSignal.timeout(60_000),
      });
      if (!res.ok) throw new Error(`HTTP ${res.status} ${res.statusText}`);
      return await res.json();
    } catch (e) {
      lastErr = e;
      await new Promise((r) => setTimeout(r, 1000 * (i + 1)));
    }
  }
  throw new Error(`${url}: ${lastErr.message} (after ${attempts} attempts)`);
}
const unwrap = (body, what) => {
  if (body.error) throw new Error(`${what}: ${body.error.message ?? JSON.stringify(body.error)}`);
  return body.result;
};
const rpc = async (url, method, params) => unwrap(await post(url, { jsonrpc: "2.0", id: ++rpcId, method, params }), `${url} ${method}`);
async function rpcBatch(url, calls) {
  const payload = calls.map(([method, params]) => ({ jsonrpc: "2.0", id: ++rpcId, method, params }));
  const body = await post(url, payload);
  if (!Array.isArray(body) || body.length !== payload.length) throw new Error(`${url}: malformed batch response`);
  const byId = new Map(body.map((r) => [r.id, r]));
  return payload.map((p) => unwrap(byId.get(p.id) ?? { error: { message: "missing response" } }, `${url} ${p.method}`));
}
const hex = (n) => "0x" + n.toString(16);
const big = (h) => BigInt(h);
const word = (data, i) => BigInt("0x" + data.slice(2 + 64 * i, 2 + 64 * (i + 1)));
const uint = (n) => "0x" + n.toString(16).padStart(64, "0");
const callAt = async (selector, block) => big(await rpc(STATE_RPC, "eth_call", [{ to: STAKING, data: selector }, hex(block)]));

// ---------------------------------------------------------------- target block
const head = Number(big(await rpc(STATE_RPC, "eth_blockNumber", [])));
const target = BLOCK_ARG === null ? head - HEAD_LAG : Number(BLOCK_ARG);
if (!Number.isInteger(target) || target < DEPLOY_BLOCK || target > head) {
  throw new Error(`target block ${target} is not between the deploy block ${DEPLOY_BLOCK} and the head ${head}`);
}
const blockInfo = await rpc(STATE_RPC, "eth_getBlockByNumber", [hex(target), false]);
if (!blockInfo) throw new Error(`block ${target} not found on ${STATE_RPC}`);
const timestamp = Number(big(blockInfo.timestamp));
const utc = new Date(timestamp * 1000).toISOString().replace("T", " ").replace(".000Z", " UTC");
console.error(`head ${head}, target block ${target} (${utc}), source: ${SOURCE}`);

// ---------------------------------------------------------------- contract totals at the target block
const [onchainStaked, onchainVp, onchainNext] = await Promise.all([
  callAt(SEL.totalStakedAmount, target), callAt(SEL.totalVotingPower, target), callAt(SEL.nextLockId, target),
]);
const lockCount = Number(onchainNext);

// ---------------------------------------------------------------- rebuild the active locks
const locks = new Map(); // lockId -> { amount, duration (s), vp }
let created = 0, withdrawn = 0;

if (SOURCE === "events") {
  let pages = 0;
  for (let from = DEPLOY_BLOCK; from <= target; from += PAGE) {
    const to = Math.min(from + PAGE - 1, target);
    const logs = await rpc(HISTORY_RPC, "eth_getLogs", [
      { address: STAKING, fromBlock: hex(from), toBlock: hex(to), topics: [[TOPIC_STAKED, TOPIC_WITHDRAWN]] },
    ]);
    pages++;
    // Chain order: by block, then by log index.
    logs.sort((a, b) => Number(big(a.blockNumber) - big(b.blockNumber)) || Number(big(a.logIndex) - big(b.logIndex)));
    for (const log of logs) {
      if (log.removed) throw new Error(`removed log at block ${Number(big(log.blockNumber))}: reorg, retry`);
      const lockId = big(log.topics[2]).toString(); // topics[1] (the holder) is deliberately not read
      if (log.topics[0] === TOPIC_STAKED) {
        if (locks.has(lockId)) throw new Error(`lock ${lockId} staked twice`);
        locks.set(lockId, { amount: word(log.data, 0), duration: Number(word(log.data, 1)), vp: word(log.data, 2) });
        created++;
      } else {
        const l = locks.get(lockId);
        if (!l) throw new Error(`lock ${lockId} withdrawn but never staked (or withdrawn twice)`);
        if (l.amount !== word(log.data, 0)) throw new Error(`lock ${lockId}: withdrawn amount differs from the staked amount`);
        locks.delete(lockId);
        withdrawn++;
      }
    }
    if (pages % 50 === 0) process.stderr.write(`  ${to - DEPLOY_BLOCK + 1} blocks scanned, ${created} Staked, ${withdrawn} Withdrawn\r`);
  }
  console.error(`${pages} pages, ${created} Staked, ${withdrawn} Withdrawn, ${locks.size} active locks`);
} else {
  for (let i = 0; i < lockCount; i += BATCH) {
    const ids = Array.from({ length: Math.min(BATCH, lockCount - i) }, (_, k) => i + k);
    const results = await rpcBatch(STATE_RPC, ids.map((id) => ["eth_call", [{ to: STAKING, data: SEL.locks + uint(BigInt(id)).slice(2) }, hex(target)]]));
    results.forEach((data, k) => {
      if (typeof data !== "string" || data.length !== 2 + 64 * 7) throw new Error(`locks(${ids[k]}): unexpected return data`);
      // word 0 is the owner: deliberately not read.
      const amount = word(data, 1), start = word(data, 2), unlockTime = word(data, 3), vp = word(data, 5), isWithdrawn = word(data, 6) !== 0n;
      created++;
      if (isWithdrawn) { withdrawn++; return; }
      locks.set(String(ids[k]), { amount, duration: Number(unlockTime - start), vp });
    });
  }
  console.error(`${lockCount} lock structs read, ${withdrawn} withdrawn, ${locks.size} active locks`);
}

// ---------------------------------------------------------------- check against the contract
let sumAmount = 0n, sumVp = 0n;
for (const l of locks.values()) { sumAmount += l.amount; sumVp += l.vp; }
const mismatches = [];
if (sumAmount !== onchainStaked) mismatches.push(`totalStakedAmount: rebuilt ${sumAmount} wei, contract ${onchainStaked} wei`);
if (sumVp !== onchainVp) mismatches.push(`totalVotingPower: rebuilt ${sumVp}, contract ${onchainVp}`);
if (created !== lockCount) mismatches.push(`nextLockId: ${created} locks seen, contract ${lockCount}`);
if (mismatches.length) {
  console.error(`MISMATCH at block ${target}:\n  ${mismatches.join("\n  ")}`);
  process.exit(1);
}
console.error(`checked: totalStakedAmount, totalVotingPower and nextLockId at block ${target} match the rebuilt locks`);

// ---------------------------------------------------------------- aggregate per lock period
const byPeriod = new Map(); // duration (s) -> { n, amount, vp }
for (const l of locks.values()) {
  const p = byPeriod.get(l.duration) ?? { n: 0, amount: 0n, vp: 0n };
  p.n++; p.amount += l.amount; p.vp += l.vp;
  byPeriod.set(l.duration, p);
}
const periodLabel = (s) => (s % 86400 === 0 ? `${s / 86400} days` : `${s} s`);
const rows = [], small = { periods: 0, n: 0, amount: 0n, vp: 0n };
for (const [duration, p] of [...byPeriod].sort((a, b) => a[0] - b[0])) {
  if (p.n < MIN_LOCKS_PER_LINE) { small.periods++; small.n += p.n; small.amount += p.amount; small.vp += p.vp; }
  else rows.push({ label: periodLabel(duration), ...p });
}
if (small.periods) rows.push({ ...small, label: `small buckets (${small.periods} period${small.periods > 1 ? "s" : ""} with fewer than ${MIN_LOCKS_PER_LINE} locks)` });

// ---------------------------------------------------------------- output
const WEI = 10n ** 18n;
const fmtDmn = (w) => {
  const int = (w / WEI).toLocaleString("en-US"), cents = ((w % WEI) / 10n ** 16n).toString().padStart(2, "0");
  return `${int}.${cents}`;
};
const pct = (part, whole) => (whole === 0n ? "0.00" : (Number((part * 10000n) / whole) / 100).toFixed(2));

console.log(`Block ${target.toLocaleString("en-US")}, timestamp ${timestamp} = ${utc} (source: ${SOURCE})`);
console.log();
console.log("| Lock period | Locks | DMN staked | % of staked DMN | Voting power | % of voting power |");
console.log("|---|---:|---:|---:|---:|---:|");
for (const r of rows) {
  console.log(`| ${r.label} | ${r.n} | ${fmtDmn(r.amount)} | ${pct(r.amount, sumAmount)} % | ${fmtDmn(r.vp)} | ${pct(r.vp, sumVp)} % |`);
}
console.log(`| **Total** | **${locks.size}** | **${fmtDmn(sumAmount)}** | **100.00 %** | **${fmtDmn(sumVp)}** | **100.00 %** |`);
console.log();
console.log(`totalStakedAmount ${onchainStaked} wei = ${fmtDmn(onchainStaked)} DMN`);
console.log(`totalVotingPower  ${onchainVp} = ${fmtDmn(onchainVp)} (same 18-decimal unit as DMN)`);
console.log(`locks ever created ${created}, withdrawn ${withdrawn}, active ${locks.size}`);
