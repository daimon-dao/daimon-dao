// A JSON-RPC proxy for anvil's --fork-url when only non-archive public RPCs are at hand: anvil asks
// for state at its pinned fork block, which a full node forgets within minutes ("missing trie node");
// this proxy forwards state reads at "latest" instead. The fork then drifts a little from a single
// block, which the UI checks do not mind (the DAO's state changes slowly; the test wallet is synthetic).
//
//   node fork-proxy.mjs [--port 8547] [--upstream https://bsc-dataseed.binance.org]
//   anvil --fork-url http://127.0.0.1:8547 ...
import { createServer } from "node:http";

const args = process.argv.slice(2);
const opt = (name, dflt) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : dflt; };
const PORT = Number(opt("--port", "8547"));
const UPSTREAM = opt("--upstream", "https://bsc-dataseed.binance.org");
const STATE_METHODS = new Map([["eth_getBalance", 1], ["eth_getCode", 1], ["eth_getTransactionCount", 1], ["eth_getStorageAt", 2], ["eth_call", 1]]);

function rewrite(req) {
  const idx = STATE_METHODS.get(req.method);
  if (idx !== undefined && Array.isArray(req.params) && typeof req.params[idx] === "string" && req.params[idx].startsWith("0x")) {
    req.params = [...req.params];
    req.params[idx] = "latest";
  }
  return req;
}

createServer((req, res) => {
  let body = "";
  req.on("data", (c) => (body += c));
  req.on("end", async () => {
    try {
      const parsed = JSON.parse(body);
      const out = Array.isArray(parsed) ? parsed.map(rewrite) : rewrite(parsed);
      const r = await fetch(UPSTREAM, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(out) });
      const text = await r.text();
      res.writeHead(r.status, { "content-type": "application/json" });
      res.end(text);
    } catch (e) {
      res.writeHead(502, { "content-type": "application/json" });
      res.end(JSON.stringify({ jsonrpc: "2.0", id: null, error: { code: -32000, message: String(e) } }));
    }
  });
}).listen(PORT, "127.0.0.1", () => console.log(`fork proxy on http://127.0.0.1:${PORT} -> ${UPSTREAM} (state reads at latest)`));
