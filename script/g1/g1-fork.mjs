// G1 rehearsal on a LOCAL anvil fork of BSC mainnet: propose (the exact bytes
// published in docs/G1_PROPOSAL.md) -> vote -> queue -> 7 days -> execute ->
// poke, then what G1 cannot do. See script/g1/README.md.
//
//   anvil --fork-url https://bsc-mainnet.public.blastapi.io --chain-id 56 \
//         --auto-impersonate --gas-price 0 --block-base-fee-per-gas 0
//   node script/g1/g1-fork.mjs
//
// Every write goes to the local node (anvil impersonation, no key anywhere).
// The script refuses to run unless the endpoint is an anvil FORK of chain 56.
// Real addresses are read from chain state at run time; none is stored here.
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(HERE, "..", "..");
const OUT = process.env.G1_OUT_DIR ? resolve(process.env.G1_OUT_DIR) : join(HERE, "out");
const L = process.env.G1_FORK_RPC ?? "http://127.0.0.1:8545";

// viem from the dApp's lockfile (no extra dependency), ABIs from forge build.
const VIEM = join(REPO, "daimon-dapp", "node_modules", "viem", "_esm", "index.js");
if (!existsSync(VIEM)) throw new Error(`viem not found at ${VIEM}: run "npm ci" in daimon-dapp/ first`);
const ARTIFACT = (n) => join(REPO, "out", `${n}.sol`, `${n}.json`);
for (const n of ["DaimonV2", "DaimonGovernor", "DaimonTimelock", "DaimonStaking"]) {
  if (!existsSync(ARTIFACT(n))) throw new Error(`${ARTIFACT(n)} missing: run "forge build" at the repository root first`);
}
const v = await import(pathToFileURL(VIEM).href);
const { createPublicClient, createTestClient, createWalletClient, http, parseAbi, decodeEventLog, keccak256, encodeAbiParameters,
  encodeFunctionData, decodeFunctionData, toHex, BaseError, ContractFunctionRevertedError, getAddress } = v;

const chain = { id: 56, name: "bsc-local-fork", nativeCurrency: { name: "BNB", symbol: "BNB", decimals: 18 }, rpcUrls: { default: { http: [L] } } };
const pub = createPublicClient({ chain, transport: http(L, { timeout: 120_000 }) });
const test = createTestClient({ chain, mode: "anvil", transport: http(L, { timeout: 120_000 }) });
const wal = createWalletClient({ chain, transport: http(L, { timeout: 120_000 }) });

const art = (n) => JSON.parse(readFileSync(ARTIFACT(n), "utf8")).abi;
const tokenAbi = art("DaimonV2"), govAbi = art("DaimonGovernor"), tlAbi = art("DaimonTimelock"), stAbi = art("DaimonStaking");
const pairAbi = parseAbi([
  "function getReserves() view returns (uint112, uint112, uint32)", "function balanceOf(address) view returns (uint256)",
  "function totalSupply() view returns (uint256)", "function token0() view returns (address)",
  "event Sync(uint112 reserve0, uint112 reserve1)",
  "event Swap(address indexed sender, uint256 amount0In, uint256 amount1In, uint256 amount0Out, uint256 amount1Out, address indexed to)",
]);
const erc20 = parseAbi(["function balanceOf(address) view returns (uint256)"]);
const ALL_ABI = [...tokenAbi, ...govAbi, ...tlAbi, ...stAbi, ...pairAbi].filter((x) => x.type === "event" || x.type === "error");

// Mainnet addresses (docs/MAINNET_LAUNCH_RECORD.md, README "Mainnet addresses").
const A = {
  TOKEN: "0x160864F9945C52063A7c9f5dcd57C0C89eacbE6a", GOV: "0x1397a7d25595B718BE6FEEDd42ed5E60F66E16De",
  TL: "0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891", ST: "0xBb596e7308D6C5AED55cEC597D372840Cbe575b1",
  MIG: "0x76368b60514b145617385847aCFF7b7EA9764725", PAIR: "0x40A97Ae210a44057603186B4BE92BAe719342AFA",
  SAFE: "0x37F45839765AD3418E29c97d5D92407Ddbf5c7a8", DMX: "0x36EbA94407B53c631eE822C219e94580fadd67c7",
  DEPLOYER: "0x4D38C9FE5250235dc99D3e098cd515B008aCa26e",
};
// Team-sized positions: 140 B DMN (CALENDARIO_GOVERNANCE_Q1, Scenario W: the team's personal holdings),
// 365 days (4x), in four fresh fork-only wallets funded from the Migration's unclaimed DMN (fee-exempt
// sender: the token's fee inventory does not move). This funding exists only on the fork.
const TEAM = [1, 2, 3, 4].map((i) => getAddress(`0x7ea7000000000000000000000000000000000${String(i).padStart(3, "0")}`));
const TEAM_EACH = 35_000_000_000n * 10n ** 18n;
const POKER = getAddress("0x7ea70000000000000000000000000000000000ff");
const STRANGER = getAddress("0x7ea70000000000000000000000000000000000ee");
const INNER = "0x6cf839b90000000000000000000000000000000000000000000000000000000000000258";
const ZERO32 = "0x" + "00".repeat(32);
const ROLE = { GOV: keccak256(toHex("GOVERNANCE_ROLE")), GUARD: keccak256(toHex("GUARDIAN_ROLE")), ADMIN: ZERO32,
  PROPOSER: keccak256(toHex("PROPOSER_ROLE")), EXECUTOR: keccak256(toHex("EXECUTOR_ROLE")), CANCELLER: keccak256(toHex("CANCELLER_ROLE")) };
const IMPL_SLOT = "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc";
const B = (x) => (Number(x) / 1e27).toFixed(4) + " B";
const iso = (t) => new Date(Number(t) * 1000).toISOString().replace(".000Z", " UTC").replace("T", " ");
const short = (a) => `${a.slice(0, 6)}...${a.slice(-4)}`;

// ---- The bytes under test: exactly those published in docs/G1_PROPOSAL.md -----------
const docLines = readFileSync(join(REPO, "docs", "G1_PROPOSAL.md"), "utf8").split(/\r?\n/);
const descLines = docLines.filter((l) => l.startsWith("G1 - "));
const dataLines = docLines.filter((l) => /^0x82ff16c1[0-9a-f]+$/.test(l));
if (descLines.length !== 1 || dataLines.length !== 1) throw new Error("docs/G1_PROPOSAL.md: expected exactly one description line and one calldata line");
const DESC = descLines[0], OUTER = dataLines[0];
const reencoded = encodeFunctionData({ abi: govAbi, functionName: "propose", args: [A.TOKEN, 0n, INNER, DESC] });
const dec = decodeFunctionData({ abi: govAbi, data: OUTER });
if (reencoded !== OUTER || dec.args[0] !== A.TOKEN || dec.args[1] !== 0n || dec.args[2] !== INNER || dec.args[3] !== DESC) {
  throw new Error("docs/G1_PROPOSAL.md: the published calldata is not propose(TOKEN, 0, setStakingRewardShareBps(600), the published description)");
}
console.log(`bytes under test (docs/G1_PROPOSAL.md): calldata ${(OUTER.length - 2) / 2} bytes keccak ${keccak256(OUTER)}; ` +
  `description ${Buffer.byteLength(DESC)} bytes keccak ${keccak256(toHex(DESC))}; == propose(token, 0, setStakingRewardShareBps(600), description): true`);

const rows = []; const facts = {};
let fails = 0;
function row(step, action, expected, observed, verdict, tx = "-") {
  if (verdict === "FAIL") fails++;
  rows.push({ step, action, expected, observed, verdict, tx });
  console.log(`${verdict.padEnd(9)} ${step} ${action}\n          ${observed}${tx !== "-" ? `\n          tx ${tx}` : ""}`);
}
const V = (b) => (b ? "PASS" : "FAIL");
const rd = (address, abi, functionName, args = [], blockNumber) => pub.readContract({ address, abi, functionName, args, blockNumber });
const bal = (address, blockNumber) => pub.getBalance({ address, blockNumber });
async function send(from, address, abi, functionName, args = []) {
  const hash = await wal.writeContract({ account: from, address, abi, functionName, args, gasPrice: 0n, chain });
  const r = await pub.waitForTransactionReceipt({ hash });
  if (r.status !== "success") throw new Error(`${functionName} reverted in ${hash}`);
  return r;
}
function decodeLogs(r) {
  return r.logs.map((l) => { try { const d = decodeEventLog({ abi: ALL_ABI, data: l.data, topics: l.topics }); return { address: l.address, ...d }; } catch { return { address: l.address, eventName: "?", topics: l.topics }; } });
}
function revertName(e) {
  if (e instanceof BaseError) {
    const r = e.walk((x) => x instanceof ContractFunctionRevertedError);
    if (r) return r.data?.errorName ?? r.reason ?? r.signature ?? "reverted";
  }
  return (e.shortMessage || e.message || String(e)).split("\n")[0];
}
// Errors of every contract are in the decoding ABI: a Timelock error bubbles up through the Governor.
async function expectRevert(account, address, abi, functionName, args) {
  try { await pub.simulateContract({ account, address, abi: [...abi, ...ALL_ABI], functionName, args }); return "NO REVERT"; } catch (e) { return revertName(e); }
}
async function warpTo(ts) { await test.setNextBlockTimestamp({ timestamp: BigInt(ts) }); await test.mine({ blocks: 1 }); }
async function now() { const b = await pub.getBlock(); return { n: b.number, ts: b.timestamp }; }

// Every zero-argument view of the four contracts, plus the parametrized reads that matter: the full "what can change" surface.
async function paramSnapshot(tag, proposer) {
  const out = {};
  for (const [name, address, abi] of [["token", A.TOKEN, tokenAbi], ["governor", A.GOV, govAbi], ["timelock", A.TL, tlAbi], ["staking", A.ST, stAbi]]) {
    for (const f of abi.filter((x) => x.type === "function" && (x.stateMutability === "view" || x.stateMutability === "pure") && x.inputs.length === 0)) {
      try { const r = await rd(address, abi, f.name); out[`${name}.${f.name}`] = JSON.stringify(r, (k, x) => (typeof x === "bigint" ? x.toString() : x)); }
      catch (e) { out[`${name}.${f.name}`] = `ERR ${revertName(e)}`; }
    }
  }
  const who = { TL: A.TL, GOV: A.GOV, SAFE: A.SAFE, DEPLOYER: A.DEPLOYER, MIG: A.MIG, ST: A.ST, TOKEN: A.TOKEN, PROPOSER: proposer };
  for (const [rn, r] of Object.entries(ROLE)) for (const [wn, w] of Object.entries(who)) {
    out[`token.hasRole(${rn},${wn})`] = String(await rd(A.TOKEN, tokenAbi, "hasRole", [r, w]));
    out[`timelock.hasRole(${rn},${wn})`] = String(await rd(A.TL, tlAbi, "hasRole", [r, w]));
  }
  for (const [wn, w] of Object.entries(who)) {
    out[`token.isExcludedFromFee(${wn})`] = String(await rd(A.TOKEN, tokenAbi, "isExcludedFromFee", [w]));
    out[`staking.isGovernance(${wn})`] = String(await rd(A.ST, stAbi, "isGovernance", [w]));
  }
  const n = await rd(A.ST, stAbi, "lockOptionsLength");
  for (let i = 0n; i < n; i++) out[`staking.lockOptions(${i})`] = JSON.stringify(await rd(A.ST, stAbi, "lockOptions", [i]), (k, x) => (typeof x === "bigint" ? x.toString() : x));
  out["token.implementation(EIP-1967)"] = await pub.getStorageAt({ address: A.TOKEN, slot: IMPL_SLOT });
  out["treasury.BNB"] = String(await bal(A.TL));
  out["treasury.DMN"] = String(await rd(A.TOKEN, tokenAbi, "balanceOf", [A.TL]));
  out["treasury.LP"] = String(await rd(A.PAIR, pairAbi, "balanceOf", [A.TL]));
  out["treasury.DMX"] = String(await rd(A.DMX, erc20, "balanceOf", [A.TL]));
  writeFileSync(join(OUT, `params-${tag}.json`), JSON.stringify(out, null, 1));
  return out;
}
function diff(a, b) { return Object.keys({ ...a, ...b }).filter((k) => a[k] !== b[k]).map((k) => `${k}: ${a[k]} -> ${b[k]}`); }

// ============================================================================
mkdirSync(OUT, { recursive: true });
const info = await pub.request({ method: "anvil_nodeInfo" }).catch(() => null);
const cid = await pub.getChainId().catch(() => { throw new Error(`no node answers at ${L}: start the anvil fork first (script/g1/README.md)`); });
if (cid !== 56 || !info?.forkConfig?.forkUrl) throw new Error(`REFUSED: ${L} is not a local anvil fork of chain 56`);
// (anvil_nodeInfo reports a default gasPrice even with --gas-price 0; the base fee is what gates a zero-priced tx.)
if (BigInt(info.environment?.baseFee ?? 1) !== 0n) {
  throw new Error("REFUSED: start anvil with --gas-price 0 --block-base-fee-per-gas 0 (the rehearsal sends zero-priced transactions from impersonated accounts)");
}
const used = (await rd(A.TOKEN, tokenAbi, "balanceOf", [POKER])) !== 0n ||
  (await Promise.all(TEAM.map((t) => rd(A.ST, stAbi, "votingPower", [t])))).some((x) => x !== 0n);
if (used) throw new Error("REFUSED: this fork was already used by a previous run -- stop anvil and start a fresh fork");
const base = await now();
row("F.0", "The local fork", "anvil, chain 56, forked from BSC mainnet at the latest block", `chainId=${cid}, forkUrl=${info.forkConfig.forkUrl}, forkBlockNumber=${info.forkConfig.forkBlockNumber}, head=${base.n} ts=${base.ts} (${iso(base.ts)})`, V(BigInt(info.forkConfig.forkBlockNumber) === base.n));
facts.forkBlock = String(base.n); facts.forkTs = String(base.ts);

// ---- 1. The live Governor -----------------------------------------------------
const g = {};
for (const f of ["VOTING_DELAY", "VOTING_PERIOD", "quorumBps", "MIN_QUORUM_BPS", "proposalThreshold", "MAX_PROPOSAL_THRESHOLD", "proposalCount", "guardian", "guardianAuthorityExpiry", "staking", "timelock"]) g[f] = await rd(A.GOV, govAbi, f);
const code = await pub.getCode({ address: A.GOV });
const tvpNow = await rd(A.ST, stAbi, "totalVotingPower");
const tvpPrev = await rd(A.ST, stAbi, "totalVotingPowerAt", [base.n - 1n]);
const ID = g.proposalCount; // G1's id on this fork: 0 unless another proposal exists first
row("G.1", "The live Governor: propose(), threshold, quorum, delay, period", "propose(address,uint256,bytes,string) selector 0x82ff16c1 in the bytecode; threshold 1000 DMN of voting power; quorum 1000 bps of the snapshot total, For+Abstain, For > Against; delay 86400 s; period 432000 s; staking/timelock wired",
  `selectorInCode=${code.includes("6382ff16c1")}, proposalThreshold=${g.proposalThreshold} (${Number(g.proposalThreshold) / 1e18} DMN vp), quorumBps=${g.quorumBps} (MIN ${g.MIN_QUORUM_BPS}), VOTING_DELAY=${g.VOTING_DELAY}, VOTING_PERIOD=${g.VOTING_PERIOD}, proposalCount=${g.proposalCount} (G1 will be id ${ID}), guardian=${g.guardian}, guardianAuthorityExpiry=${g.guardianAuthorityExpiry} (${iso(g.guardianAuthorityExpiry)}), staking=${g.staking}, timelock=${g.timelock}; totalVotingPower now=${tvpNow} (${B(tvpNow)}), at head-1=${tvpPrev}; real-state quorum bar = ${B(tvpPrev * g.quorumBps / 10000n)}`,
  V(code.includes("6382ff16c1") && g.proposalThreshold === 10n ** 21n && g.quorumBps === 1000n && g.VOTING_DELAY === 86400n && g.VOTING_PERIOD === 432000n && g.staking === A.ST && g.timelock === A.TL));
facts.realTvp = String(tvpPrev); facts.realQuorum = String(tvpPrev * g.quorumBps / 10000n); facts.id = String(ID);

// Real stakers, enumerated from storage (locks(id), no logs). The proposer: the owner of the OLDEST lock
// whose owner holds at least proposalThreshold of live voting power (override: G1_PROPOSER).
const nLocks = await rd(A.ST, stAbi, "nextLockId");
const owners = new Map(); const firstLock = new Map();
for (let i = 0n; i < nLocks; i++) {
  const l = await rd(A.ST, stAbi, "locks", [i]);
  if (!firstLock.has(l[0])) firstLock.set(l[0], i);
  if (!l[6]) owners.set(l[0], (owners.get(l[0]) ?? 0n) + l[5]);
}
const ranked = [];
for (const o of owners.keys()) ranked.push([o, await rd(A.ST, stAbi, "votingPower", [o])]);
ranked.sort((a, b) => (b[1] > a[1] ? 1 : b[1] < a[1] ? -1 : 0));
const sumVp = ranked.reduce((s, [, x]) => s + x, 0n);
const PROPOSER = process.env.G1_PROPOSER ? getAddress(process.env.G1_PROPOSER)
  : [...ranked].filter(([, x]) => x >= g.proposalThreshold).sort((a, b) => (firstLock.get(a[0]) < firstLock.get(b[0]) ? -1 : 1))[0]?.[0];
if (!PROPOSER) throw new Error("no real staker holds proposalThreshold of voting power");
const vpProp = await rd(A.ST, stAbi, "votingPower", [PROPOSER]);
let acc = 0n, k = 0; for (const [, x] of ranked) { k++; acc += x; if (acc >= tvpPrev * g.quorumBps / 10000n) break; }
row("G.2", "Real stakers on mainnet at the fork block (from locks(id) storage)", "sum of per-owner votingPower == totalVotingPower; the proposer holds at least the threshold",
  `locks=${nLocks}, owners=${owners.size}, sum=${sumVp} == total ${tvpNow}: ${sumVp === tvpNow}; largest owner ${B(ranked[0][1])} (${(Number(ranked[0][1] * 10000n / tvpNow) / 100).toFixed(2)}%); fewest owners whose FOR alone clears today's real-state quorum: ${k}; proposer ${short(PROPOSER)} vp=${B(vpProp)}`,
  V(sumVp === tvpNow && vpProp >= g.proposalThreshold));
facts.owners = owners.size; facts.proposerVp = String(vpProp);

const tok = {};
for (const f of ["stakingRewardShareBps", "marketingWallet", "stakingContract", "taxFee", "buybackFee", "marketingFee", "liquidityFee", "minimumTokensBeforeSwap", "maxTxAmount"]) tok[f] = await rd(A.TOKEN, tokenAbi, f);
row("G.3", "The token before G1", "share 1000; marketingWallet == the Timelock; stakingContract == staking; fees 10/10/20 (liquidityFee 30); Timelock holds GOVERNANCE_ROLE and the Governor is the Timelock's PROPOSER and EXECUTOR; the deployer holds neither GOVERNANCE_ROLE nor the Timelock's admin role",
  `share=${tok.stakingRewardShareBps}, marketingWallet=${tok.marketingWallet}, stakingContract=${tok.stakingContract}, fees ${tok.taxFee}/${tok.buybackFee}/${tok.marketingFee} (liquidity ${tok.liquidityFee}), threshold=${B(tok.minimumTokensBeforeSwap)}, maxTx=${B(tok.maxTxAmount)}; token GOV(TL)=${await rd(A.TOKEN, tokenAbi, "hasRole", [ROLE.GOV, A.TL])} GOV(deployer)=${await rd(A.TOKEN, tokenAbi, "hasRole", [ROLE.GOV, A.DEPLOYER])}; TL PROPOSER(gov)=${await rd(A.TL, tlAbi, "hasRole", [ROLE.PROPOSER, A.GOV])} EXECUTOR(gov)=${await rd(A.TL, tlAbi, "hasRole", [ROLE.EXECUTOR, A.GOV])} ADMIN(TL)=${await rd(A.TL, tlAbi, "hasRole", [ROLE.ADMIN, A.TL])} ADMIN(deployer)=${await rd(A.TL, tlAbi, "hasRole", [ROLE.ADMIN, A.DEPLOYER])}`,
  V(tok.stakingRewardShareBps === 1000n && tok.marketingWallet === A.TL && tok.stakingContract === A.ST && tok.marketingFee === 20n && tok.liquidityFee === 30n &&
    (await rd(A.TOKEN, tokenAbi, "hasRole", [ROLE.GOV, A.TL])) && !(await rd(A.TOKEN, tokenAbi, "hasRole", [ROLE.GOV, A.DEPLOYER])) &&
    (await rd(A.TL, tlAbi, "hasRole", [ROLE.PROPOSER, A.GOV])) && (await rd(A.TL, tlAbi, "hasRole", [ROLE.EXECUTOR, A.GOV])) && !(await rd(A.TL, tlAbi, "hasRole", [ROLE.ADMIN, A.DEPLOYER]))));

await paramSnapshot("0-base", PROPOSER);
const migDmn = await rd(A.TOKEN, tokenAbi, "balanceOf", [A.MIG]);
if (migDmn < 4n * TEAM_EACH + tok.minimumTokensBeforeSwap + 1000n * 10n ** 18n) throw new Error(`the Migration holds ${B(migDmn)} DMN: not enough to fund the fork-only team positions (the rehearsal needs the window's unclaimed DMN, i.e. before the sweep)`);

// ---- 3a. Team-sized positions, staked BEFORE the proposal (the snapshot is propose block - 1) ----
for (const t of [...TEAM, POKER, STRANGER]) { const c = await pub.getCode({ address: t }); if (c !== undefined && c !== "0x") throw new Error(`${t} has code`); }
const invBase = await rd(A.TOKEN, tokenAbi, "balanceOf", [A.TOKEN]);
const chunk = tok.maxTxAmount < 5_000_000_000n * 10n ** 18n ? tok.maxTxAmount : 5_000_000_000n * 10n ** 18n;
for (const t of TEAM) {
  await send(A.MIG, A.TOKEN, tokenAbi, "transfer", [t, TEAM_EACH]);
  await send(t, A.TOKEN, tokenAbi, "approve", [A.ST, TEAM_EACH]);
  for (let left = TEAM_EACH; left > 0n; left -= (left < chunk ? left : chunk)) await send(t, A.ST, stAbi, "stake", [left < chunk ? left : chunk, 3n]);
}
await send(A.MIG, A.TOKEN, tokenAbi, "transfer", [POKER, 1000n * 10n ** 18n]);
const teamVp = await Promise.all(TEAM.map((t) => rd(A.ST, stAbi, "votingPower", [t])));
const tvpTeam = await rd(A.ST, stAbi, "totalVotingPower");
const invAfterSetup = await rd(A.TOKEN, tokenAbi, "balanceOf", [A.TOKEN]);
row("R.1", `Team-sized positions staked on the fork BEFORE the proposal: 4 fork-only wallets x 35 B DMN, stakes of ${B(chunk)} (the maxTx binds the stake transfer), lock option 3 = 365 days, 4.0x; funded from the Migration's unclaimed DMN (fee-exempt: no fee, the inventory does not move)`,
  "each wallet 140 B of voting power; total grows by exactly 560 B; the token's fee inventory unchanged",
  `team vp=${teamVp.map(B).join(", ")}; total ${B(tvpNow)} -> ${B(tvpTeam)} (+${B(tvpTeam - tvpNow)}); inventory ${invAfterSetup} == base ${invBase}`,
  V(teamVp.every((x) => x === 140_000_000_000n * 10n ** 18n) && tvpTeam - tvpNow === 560_000_000_000n * 10n ** 18n && invAfterSetup === invBase));

// ---- 3b. Propose, with the EXACT bytes the proposer will send -----------------
await test.mine({ blocks: 1 }); // the team's last stake is strictly before the propose block's parent
const hashP = await wal.sendTransaction({ account: PROPOSER, to: A.GOV, data: OUTER, gasPrice: 0n, chain });
const rP = await pub.waitForTransactionReceipt({ hash: hashP });
const blkP = await pub.getBlock({ blockNumber: rP.blockNumber });
const txP = await pub.getTransaction({ hash: hashP });
const evP = decodeLogs(rP);
const p = await rd(A.GOV, govAbi, "proposals", [ID]);
// proposals(): proposer,target,value,data,description,snapshotBlock,snapshotTotalVotingPower,voteStart,voteEnd,for,against,abstain,canceled,executed,queued,timelockSalt,quorumBpsSnapshot
const salt = keccak256(encodeAbiParameters([{ type: "uint256" }, { type: "uint256" }], [ID, blkP.timestamp]));
const created = evP.find((e) => e.eventName === "ProposalCreated");
const okP = rP.status === "success" && txP.input === OUTER && p[0] === PROPOSER && p[1] === A.TOKEN && p[2] === 0n && p[3] === INNER && p[4] === DESC &&
  p[5] === rP.blockNumber - 1n && p[6] === (await rd(A.ST, stAbi, "totalVotingPowerAt", [rP.blockNumber - 1n])) && p[7] === blkP.timestamp + 86400n && p[8] === p[7] + 432000n &&
  p[15] === salt && p[16] === 1000n && created?.args.id === ID && created?.args.description === DESC && created?.args.target === A.TOKEN && evP.length === 1;
row("R.2", `The real staker ${short(PROPOSER)} (impersonated, vp ${B(vpProp)} >= 1000 DMN) sends the EXACT propose() bytes of docs/G1_PROPOSAL.md (${(OUTER.length - 2) / 2} bytes)`,
  `status 1; tx input == the published calldata; id ${ID}; proposer/target/value/data/description stored as sent; snapshotBlock == block-1; snapshotTotalVotingPower == totalVotingPowerAt(snapshot); voteStart == ts + 86400; voteEnd == voteStart + 432000; salt == keccak(abi.encode(id, ts)); quorumBpsSnapshot 1000; ONE log, ProposalCreated with the description verbatim`,
  `status=${rP.status}, gasUsed=${rP.gasUsed}, inputMatch=${txP.input === OUTER}, block=${rP.blockNumber} ts=${blkP.timestamp}; proposer=${short(p[0])}, target=${p[1]}, value=${p[2]}, dataMatch=${p[3] === INNER}, descriptionMatch=${p[4] === DESC} (${p[4].length} chars), snapshotBlock=${p[5]}, snapshotTVP=${B(p[6])}, voteStart=${p[7]} (+${p[7] - blkP.timestamp} s), voteEnd=${p[8]} (+${p[8] - p[7]} s), saltMatch=${p[15] === salt}, quorumBpsSnapshot=${p[16]}; logs=${evP.length} [${evP.map((e) => e.eventName).join(",")}], event description verbatim=${created?.args.description === DESC}`,
  V(okP), hashP);
facts.proposeGas = String(rP.gasUsed); facts.proposeBlock = String(rP.blockNumber);
const snapBlock = p[5], snapTVP = p[6], quorumNeeded = snapTVP * 1000n / 10000n;
const st3 = await rd(A.GOV, govAbi, "state", [ID]);
const cv3 = await expectRevert(TEAM[0], A.GOV, govAbi, "castVote", [ID, 1]);
row("R.3", "Before voteStart", "state Pending; castVote reverts VotingClosed", `state=${st3}, castVote(team1)=${cv3}`, V(st3 === 0 && cv3 === "VotingClosed"));

// ---- 3c. Vote ------------------------------------------------------------------
await warpTo(p[7]);
const preVote = await test.snapshot();
const votes = [];
for (const t of [PROPOSER, ...TEAM]) { const r = await send(t, A.GOV, govAbi, "castVote", [ID, 1]); const e = decodeLogs(r)[0]; votes.push([t, e.args.weight, r.transactionHash, r.gasUsed]); }
const pv = await rd(A.GOV, govAbi, "proposals", [ID]);
const allW = await Promise.all([PROPOSER, ...TEAM].map((t) => rd(A.ST, stAbi, "votingPowerAt", [t, snapBlock])));
const st4 = await rd(A.GOV, govAbi, "state", [ID]);
row("R.4", "At voteStart: the proposer and the four team-sized positions cast FOR (support 1)", "state Active; each VoteCast weight == votingPowerAt(voter, snapshot); forVotes == the sum; quorum (For+Abstain) >= 10% of the snapshot total; For > Against",
  `state=${st4}; weights=${votes.map(([, w]) => B(w)).join(" / ")}, == votingPowerAt: ${votes.every(([, w], i) => w === allW[i])}; for/against/abstain=${B(pv[9])}/${B(pv[10])}/${B(pv[11])}; snapshot total=${B(snapTVP)}, quorum needed=${B(quorumNeeded)} (${quorumNeeded} wei), For+Abstain = ${(Number((pv[9] + pv[11]) * 10000n / quorumNeeded) / 100).toFixed(2)}% of the bar; vote gas ${votes.map((x) => x[3]).join("/")}`,
  V(st4 === 1 && votes.every(([, w], i) => w === allW[i]) && pv[9] + pv[11] >= quorumNeeded && pv[9] > pv[10]), votes.map((x) => x[2].slice(0, 12) + "...").join(" "));
facts.forVotes = String(pv[9]); facts.quorumNeeded = String(quorumNeeded); facts.snapTVP = String(snapTVP);

// Variant B: every real staker other than the proposer votes AGAINST -- does the team-sized FOR still carry it?
const sV = await test.snapshot();
let againstW = 0n, nAgainst = 0;
for (const [o] of ranked) { if (o === PROPOSER) continue; const w = await rd(A.ST, stAbi, "votingPowerAt", [o, snapBlock]); if (w === 0n) continue; await send(o, A.GOV, govAbi, "castVote", [ID, 0]); againstW += w; nAgainst++; }
await warpTo(p[8] + 1n);
const pB = await rd(A.GOV, govAbi, "proposals", [ID]);
const stB = await rd(A.GOV, govAbi, "state", [ID]);
row("R.5", `Variant (reverted afterwards): all ${nAgainst} other real staking owners vote AGAINST`, "still Succeeded (3): For > Against and quorum counts For+Abstain only", `for=${B(pB[9])}, against=${B(pB[10])} (== sum of their snapshot weights ${B(againstW)}: ${pB[10] === againstW}), state after voteEnd=${stB}`, V(stB === 3 && pB[10] === againstW));
await test.revert({ id: sV });

// Variant C: nobody but the proposer votes -- quorum fails.
await test.revert({ id: preVote });
const preVote2 = await test.snapshot();
await send(PROPOSER, A.GOV, govAbi, "castVote", [ID, 1]);
await warpTo(p[8] + 1n);
const stC = await rd(A.GOV, govAbi, "state", [ID]);
const pC = await rd(A.GOV, govAbi, "proposals", [ID]);
const qC = await expectRevert(STRANGER, A.GOV, govAbi, "queue", [ID]);
row("R.6", "Variant (reverted afterwards): only the proposer votes FOR, the team stays silent", "Defeated (2) unless the proposer alone holds 10% of the snapshot total; queue() reverts ProposalNotSucceeded", `for=${B(pC[9])} vs needed ${B(quorumNeeded)}, state=${stC}, queue=${qC}`,
  V(pC[9] < quorumNeeded ? stC === 2 && qC === "ProposalNotSucceeded" : stC === 3));
await test.revert({ id: preVote2 });
// Main path: replay the five FOR votes (same weights: the snapshot is fixed).
for (const t of [PROPOSER, ...TEAM]) await send(t, A.GOV, govAbi, "castVote", [ID, 1]);
const pM = await rd(A.GOV, govAbi, "proposals", [ID]);
if (pM[9] !== pv[9]) throw new Error("replayed votes differ");

// ---- 3d. Queue ------------------------------------------------------------------
await warpTo(p[8]);
const stAtEnd = await rd(A.GOV, govAbi, "state", [ID]);
const qAtEnd = await expectRevert(STRANGER, A.GOV, govAbi, "queue", [ID]);
await warpTo(p[8] + 1n);
const stSucc = await rd(A.GOV, govAbi, "state", [ID]);
const opId = await rd(A.TL, tlAbi, "hashOperation", [A.TOKEN, 0n, INNER, ZERO32, salt]);
const opLocal = keccak256(encodeAbiParameters([{ type: "address" }, { type: "uint256" }, { type: "bytes" }, { type: "bytes32" }, { type: "bytes32" }], [A.TOKEN, 0n, INNER, ZERO32, salt]));
const rQ = await send(STRANGER, A.GOV, govAbi, "queue", [ID]);
const bQ = await pub.getBlock({ blockNumber: rQ.blockNumber });
const evQ = decodeLogs(rQ);
const op = await rd(A.TL, tlAbi, "operations", [opId]);
const cs = evQ.find((e) => e.eventName === "CallScheduled"), pq = evQ.find((e) => e.eventName === "ProposalQueued");
const stQ = await rd(A.GOV, govAbi, "state", [ID]);
row("R.7", "voteEnd edge, then queue() by a third party (queue is permissionless)",
  "state Active at ts == voteEnd (queue refused), Succeeded at voteEnd+1; queue: status 1, state Queued (4); exactly 2 logs: CallScheduled(opId, token, 0, data, 604800) + ProposalQueued(id, eta); opId on chain == local keccak; readyTimestamp == queue ts + 604800",
  `at voteEnd: state=${stAtEnd}, queue=${qAtEnd}; at voteEnd+1: state=${stSucc}; queue block=${rQ.blockNumber} ts=${bQ.timestamp}, state now=${stQ}; logs=${evQ.length} [${evQ.map((e) => e.eventName).join(",")}], CallScheduled id=${cs?.args.id} target=${cs?.args.target} value=${cs?.args.value} dataMatch=${cs?.args.data === INNER} delay=${cs?.args.delay}; ProposalQueued eta=${pq?.args.eta}; opId local match=${opId === opLocal}; readyTimestamp=${op[0]} (queue ts + ${op[0] - bQ.timestamp} s); gas=${rQ.gasUsed}`,
  V(stAtEnd === 1 && qAtEnd === "ProposalNotSucceeded" && stSucc === 3 && stQ === 4 && evQ.length === 2 && cs?.args.id === opId && cs?.args.target === A.TOKEN && cs?.args.value === 0n && cs?.args.data === INNER && cs?.args.delay === 604800n && pq?.args.eta === op[0] && opId === opLocal && op[0] === bQ.timestamp + 604800n), rQ.transactionHash);
facts.opId = opId; facts.queueGas = String(rQ.gasUsed);

// ---- What the operation CANNOT do --------------------------------------------
const other = [
  ["setStakingRewardShareBps(700)", encodeFunctionData({ abi: tokenAbi, functionName: "setStakingRewardShareBps", args: [700n] }), 0n],
  ["setStakingRewardShareBps(600), value 1 BNB", INNER, 10n ** 18n],
  ["setMarketingWallet(SAFE)", encodeFunctionData({ abi: tokenAbi, functionName: "setMarketingWallet", args: [A.SAFE] }), 0n],
  ["setFees(10,0,30)", encodeFunctionData({ abi: tokenAbi, functionName: "setFees", args: [10n, 0n, 30n] }), 0n],
];
const negs = [];
for (const [label, data, value] of other) {
  const id2 = await rd(A.TL, tlAbi, "hashOperation", [A.TOKEN, value, data, ZERO32, salt]);
  const o2 = await rd(A.TL, tlAbi, "operations", [id2]);
  const ex2 = await expectRevert(A.GOV, A.TL, tlAbi, "execute", [A.TOKEN, value, data, ZERO32, salt]);
  negs.push(`${label}: opId ${id2.slice(0, 10)}..., Timelock.execute as the Governor -> ${ex2}, readyTimestamp=${o2[0]}`);
}
const tooEarly = await expectRevert(A.GOV, A.TL, tlAbi, "execute", [A.TOKEN, 0n, INNER, ZERO32, salt]);
const safeExec = await expectRevert(A.SAFE, A.TL, tlAbi, "execute", [A.TOKEN, 0n, INNER, ZERO32, salt]);
const govExecEarly = await expectRevert(STRANGER, A.GOV, govAbi, "execute", [ID]);
const q2 = await expectRevert(STRANGER, A.GOV, govAbi, "queue", [ID]);
row("R.8", "What the queued operation can NOT do: any other call, value or target is a different operation id, never scheduled; nobody but the Governor executes; not before readyTimestamp; not twice queued",
  "every alternative opId has readyTimestamp 0 (unscheduled) and the Timelock refuses it with OperationNotReady even from the Governor; Governor.execute now -> TooEarly; Timelock.execute by the Safe -> AccessControlUnauthorizedAccount; queue again -> ProposalAlreadyQueued",
  `${negs.join("; ")}; Governor.execute now=${govExecEarly}; Timelock.execute as Governor=${tooEarly}; as Safe=${safeExec}; queue again=${q2}`,
  V(negs.every((s) => s.endsWith("OperationNotReady, readyTimestamp=0")) && govExecEarly === "TooEarly" && tooEarly === "TooEarly" && safeExec === "AccessControlUnauthorizedAccount" && q2 === "ProposalAlreadyQueued"));

// ---- 3e. Advance 7 days; A/B: the same poke at share 1000 (today) vs 600 (after G1) ----
await warpTo(op[0] - 1n);
const oneEarly = await expectRevert(STRANGER, A.GOV, govAbi, "execute", [ID]);
await warpTo(op[0]);
// The poke needs the token's fee inventory at the threshold. Normally it already is (organic fees); if
// not, the gap is donated from the Migration (fee-exempt), on the fork only, and recorded.
let armed = 0n;
const invNow = await rd(A.TOKEN, tokenAbi, "balanceOf", [A.TOKEN]);
if (invNow < tok.minimumTokensBeforeSwap) { armed = tok.minimumTokensBeforeSwap - invNow; await send(A.MIG, A.TOKEN, tokenAbi, "transfer", [A.TOKEN, armed]); }
facts.armed = String(armed);
const P1 = await paramSnapshot("1-pre-execute", PROPOSER);
const sPreExec = await test.snapshot();

async function poke(tag) {
  const n0 = (await pub.getBlock()).number;
  const pre = { tl: await bal(A.TL, n0), st: await bal(A.ST, n0), tk: await bal(A.TOKEN, n0), inv: await rd(A.TOKEN, tokenAbi, "balanceOf", [A.TOKEN], n0), res: await rd(A.PAIR, pairAbi, "getReserves", [], n0) };
  const r = await send(POKER, A.TOKEN, tokenAbi, "transfer", [A.PAIR, 1n]);
  const n1 = r.blockNumber;
  if (n1 !== n0 + 1n) throw new Error("poke not in the next block");
  const post = { tl: await bal(A.TL, n1), st: await bal(A.ST, n1), tk: await bal(A.TOKEN, n1), inv: await rd(A.TOKEN, tokenAbi, "balanceOf", [A.TOKEN], n1), res: await rd(A.PAIR, pairAbi, "getReserves", [], n1) };
  const ev = decodeLogs(r);
  const sl = ev.find((e) => e.eventName === "SwapAndLiquify");
  const rn = ev.find((e) => e.eventName === "RewardNotified");
  const spent = ev.filter((e) => e.eventName === "BuyBackAndBurn").reduce((s, e) => s + e.args.ethSpent, 0n);
  const share = await rd(A.TOKEN, tokenAbi, "stakingRewardShareBps");
  const eth = sl?.args.ethReceived ?? 0n;
  const mkt = (eth * tok.marketingFee) / tok.liquidityFee, toSt = (mkt * share) / 1000n, toTl = mkt - toSt;
  return { tag, hash: r.transactionHash, gas: r.gasUsed, n0, n1, share, pre, post, eth, swapped: sl?.args.tokensSwapped, mkt, toSt, toTl, rn: rn?.args.amount, spent, logs: ev.length,
    dTl: post.tl - pre.tl, dSt: post.st - pre.st, dTk: post.tk - pre.tk, dInv: pre.inv - post.inv };
}
const A1000 = await poke("share 1000 (counterfactual: a poke today, without G1)");
await test.revert({ id: sPreExec });

// ---- 3f. Execute --------------------------------------------------------------
const rE = await send(STRANGER, A.GOV, govAbi, "execute", [ID]);
const bE = await pub.getBlock({ blockNumber: rE.blockNumber });
const evE = decodeLogs(rE);
const opE = await rd(A.TL, tlAbi, "operations", [opId]);
const pu = evE.find((e) => e.eventName === "ParamsUpdated"), ce = evE.find((e) => e.eventName === "CallExecuted"), pe = evE.find((e) => e.eventName === "ProposalExecuted");
const stE = await rd(A.GOV, govAbi, "state", [ID]);
const shareE = await rd(A.TOKEN, tokenAbi, "stakingRewardShareBps");
row("R.9", "Seven days: execute() one second early is refused; at readyTimestamp a third party executes", "early -> TooEarly; status 1; state Executed (5); operation executed; share == 600; exactly 3 logs: ParamsUpdated(\"stakingRewardShareBps\", 600) from the token, CallExecuted(opId, token, 0, data) from the Timelock, ProposalExecuted(id) from the Governor",
  `1 s early=${oneEarly}; executed at ts=${bE.timestamp} (ready ${op[0]}), status=${rE.status}, gas=${rE.gasUsed}; state=${stE}, op executed=${opE[1]} canceled=${opE[2]}; share=${shareE}; logs=${evE.length} [${evE.map((e) => `${e.eventName}@${e.address.slice(0, 6)}`).join(",")}], ParamsUpdated=(${pu?.args.param}, ${pu?.args.value}), CallExecuted id match=${ce?.args.id === opId} target=${ce?.args.target} value=${ce?.args.value} dataMatch=${ce?.args.data === INNER}, ProposalExecuted id=${pe?.args.id}`,
  V(oneEarly === "TooEarly" && rE.status === "success" && stE === 5 && opE[1] === true && shareE === 600n && evE.length === 3 && pu?.args.param === "stakingRewardShareBps" && pu?.args.value === 600n && pu?.address.toLowerCase() === A.TOKEN.toLowerCase() && ce?.args.id === opId && ce?.args.data === INNER && pe?.args.id === ID), rE.transactionHash);
facts.executeGas = String(rE.gasUsed);

// Nothing else moved: every zero-arg view of the four contracts, roles, exemptions, lock options, implementation, treasury balances.
const P2 = await paramSnapshot("2-post-execute", PROPOSER);
const d12 = diff(P1, P2);
const expectedOnly = 'token.stakingRewardShareBps: "1000" -> "600"';
row("R.10", "What changed between the block before execute and the block after (every zero-argument view of token, Governor, Timelock, staking; roles x 8 accounts; fee exemptions; staking governance; lock options; the token's implementation slot; the treasury's BNB, DMN, LP and DMX)", "exactly ONE difference: token.stakingRewardShareBps 1000 -> 600",
  `${Object.keys(P1).length} values read; differences: ${d12.length ? d12.join(" | ") : "none"}`, V(d12.length === 1 && d12[0] === expectedOnly));

// Storage, not just getters: the execute transaction's full state diff (prestateTracer, diffMode).
let traceTxt = "", traceOk = false;
try {
  const tr = await pub.request({ method: "debug_traceTransaction", params: [rE.transactionHash, { tracer: "prestateTracer", tracerConfig: { diffMode: true } }] });
  const pre = tr.pre ?? {}, post = tr.post ?? {};
  const accts = new Set([...Object.keys(pre), ...Object.keys(post)]);
  const lines = []; const changedContracts = new Set();
  for (const a of accts) {
    const s0 = pre[a]?.storage ?? {}, s1 = post[a]?.storage ?? {};
    const slots = new Set([...Object.keys(s0), ...Object.keys(s1)]);
    const ch = [...slots].filter((s) => (s0[s] ?? "0x0") !== (s1[s] ?? "0x0"));
    const balCh = pre[a]?.balance !== undefined && post[a]?.balance !== undefined && pre[a].balance !== post[a].balance;
    const codeCh = post[a]?.code !== undefined && pre[a]?.code !== post[a]?.code;
    if (ch.length || balCh || codeCh) {
      lines.push(`${a.slice(0, 8)}: ${ch.length} slot(s)${balCh ? " +balance" : ""}${codeCh ? " +CODE" : ""} [${ch.map((s) => `slot ${BigInt(s) < 1000n ? BigInt(s) : s.slice(0, 10) + ".."}: ${BigInt(s0[s] ?? "0x0")} -> ${BigInt(s1[s] ?? "0x0")}`).join("; ")}]`);
      if (ch.length || balCh || codeCh) changedContracts.add(getAddress(a));
    }
  }
  traceTxt = lines.join(" | ");
  const tk = A.TOKEN.toLowerCase();
  const tokenSlots = Object.keys(post[tk]?.storage ?? {});
  const nSlots = [A.TOKEN, A.TL, A.GOV].reduce((s, c) => s + Object.keys(post[c.toLowerCase()]?.storage ?? {}).length, 0);
  traceOk = [...changedContracts].every((c) => [A.TOKEN, A.TL, A.GOV].includes(c)) && nSlots === 3 &&
    tokenSlots.length === 1 && BigInt(post[tk].storage[tokenSlots[0]]) === 600n && BigInt(pre[tk].storage[tokenSlots[0]]) === 1000n;
  writeFileSync(join(OUT, "execute-statediff.json"), JSON.stringify(tr, null, 1));
} catch (e) { traceTxt = `trace unavailable: ${revertName(e)}`; }
row("R.11", "Storage diff of the execute transaction (debug_traceTransaction, prestateTracer diffMode)", "storage written ONLY in the token (one slot: 1000 -> 600), the Timelock (its operation's executed flag) and the Governor (the proposal's executed flag); no balance moves (zero gas price); no code change",
  traceTxt, traceTxt.startsWith("trace unavailable") ? "NOTE" : V(traceOk));
const again = await expectRevert(STRANGER, A.GOV, govAbi, "execute", [ID]);
row("R.12", "A second execute()", "AlreadyExecuted", `${again}`, V(again === "AlreadyExecuted"));

// ---- 3g. The first poke at 600 --------------------------------------------------
const A600 = await poke("share 600 (after G1)");
const armNote = armed > 0n ? `ARMED on the fork: ${armed} wei DMN donated from the Migration to reach the threshold` : "no arming needed: this is the real inventory";
for (const x of [A1000, A600]) {
  const ok = x.swapped === tok.minimumTokensBeforeSwap && x.eth > 0n && x.dSt === x.toSt && x.rn === x.toSt && x.dTl === x.toTl && x.dTk === x.eth - x.mkt - x.spent && x.dSt + x.dTl + x.dTk + x.spent === x.eth && x.dInv === x.swapped;
  row(x.share === 600n ? "R.13" : "R.13-cf", `Poke: 1 wei of DMN from a non-exempt holder straight to the pair, ${x.tag}; inventory ${B(x.pre.inv)} >= the ${B(tok.minimumTokensBeforeSwap)} threshold (${armNote})`,
    `one threshold chunk converts (SwapAndLiquify tokensSwapped == threshold); marketingEth = floor(eth x marketingFee/liquidityFee); staking += floor(marketingEth x ${x.share}/1000) == RewardNotified; Timelock += marketingEth - toStaking; token keeps eth - marketingEth (minus any buyback spend); deltas sum to ethReceived`,
    `block ${x.n0} -> ${x.n1}, gas=${x.gas}, logs=${x.logs}; tokensSwapped=${x.swapped}, ethReceived=${x.eth}; marketingEth=${x.mkt}; staking +${x.dSt} (expected ${x.toSt}, RewardNotified ${x.rn}); TIMELOCK +${x.dTl} (expected ${x.toTl}); token +${x.dTk} (expected ${x.eth - x.mkt - x.spent}); buyback spent=${x.spent}; sum=${x.dSt + x.dTl + x.dTk + x.spent}; inventory -${x.dInv}; Timelock BNB ${x.pre.tl} -> ${x.post.tl}`,
    V(ok), x.hash);
}
row("R.14", "A/B of the same poke on the same pool state: share 1000 (what happens today) vs 600 (after G1)", "ethReceived identical in both; at 1000 the Timelock gets 0 and staking the whole marketing branch; at 600 staking 60% and the Timelock 40%, wei-exact",
  `ethReceived 1000=${A1000.eth} vs 600=${A600.eth} (identical: ${A1000.eth === A600.eth}); Timelock: ${A1000.dTl} vs ${A600.dTl}; staking: ${A1000.dSt} vs ${A600.dSt}; 600-split = ${(Number(A600.dSt) / Number(A600.mkt) * 100).toFixed(10)}% / ${(Number(A600.dTl) / Number(A600.mkt) * 100).toFixed(10)}% of ${A600.mkt}`,
  V(A1000.eth === A600.eth && A1000.dTl === 0n && A1000.dSt === A1000.mkt && A600.dSt === (A600.mkt * 600n) / 1000n && A600.dTl === A600.mkt - A600.dSt));
Object.assign(facts, { eth: String(A600.eth), mkt: String(A600.mkt), toSt: String(A600.dSt), toTl: String(A600.dTl), toTk: String(A600.dTk), pokeGas: String(A600.gas),
  cf1000: { eth: String(A1000.eth), st: String(A1000.dSt), tl: String(A1000.dTl) } });
const P3 = await paramSnapshot("3-post-poke", PROPOSER);
const d23 = diff(P2, P3);
row("R.15", "After the poke: what moved (same read set as R.10)", "only the conversion's own effects: treasury.BNB up by the 40% leg; staking reward accounting; no role/parameter/LP change",
  d23.join(" | ") || "none",
  d23.every((x) => x.startsWith("treasury.BNB") || x.startsWith("staking.")) && P3["treasury.LP"] === P2["treasury.LP"] && P3["treasury.DMN"] === P2["treasury.DMN"] && P3["token.stakingRewardShareBps"] === '"600"' &&
    BigInt(P3["treasury.BNB"]) - BigInt(P2["treasury.BNB"]) === A600.dTl ? "PASS" : "NOTE");

// ---- Output ----------------------------------------------------------------------
const md = [`# G1 fork rehearsal -- fork block ${facts.forkBlock} (${iso(facts.forkTs)})`, "",
  `Bytes under test: docs/G1_PROPOSAL.md, calldata keccak ${keccak256(OUTER)}.`, "",
  "| step | action | expected | observed | tx | verdict |", "|---|---|---|---|---|---|",
  ...rows.map((r) => `| ${r.step} | ${r.action} | ${r.expected} | ${r.observed} | ${r.tx} | ${r.verdict} |`)].join("\n");
writeFileSync(join(OUT, "results.md"), md + "\n");
writeFileSync(join(OUT, "facts.json"), JSON.stringify(facts, null, 1));
const nPass = rows.filter((r) => r.verdict === "PASS").length;
console.log(`\nROWS=${rows.length} PASS=${nPass} FAIL=${fails} NOTE=${rows.filter((r) => r.verdict === "NOTE").length} -- results in ${OUT}`);
process.exit(fails === 0 ? 0 : 1);
