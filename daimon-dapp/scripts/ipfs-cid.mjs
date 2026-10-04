/*
 * The CID of a directory, and a CAR file of it, computed locally with the
 * UnixFS parameters below -- the same every IPFS node produces for
 * `ipfs add -r --cid-version 1` (CIDv1, sha2-256, raw leaves, 256 KiB
 * chunks, balanced layout with at most 174 links per node, directories as
 * plain dag-pb nodes, no HAMT below 256 KiB of links). Nothing here depends
 * on the machine: no timestamps, no modes, no absolute paths, files in sorted
 * order -- the CID is a pure function of the directory's bytes.
 *
 *   node scripts/ipfs-cid.mjs <dir> [out.car]     prints the root CID
 *
 * Also imported by scripts/build-ipfs.mjs. The CAR carries every block, so a
 * pinning service that imports it as-is reports exactly this CID; one that
 * re-adds the files with other parameters would print a different CID for
 * the same bytes, which is why the parameters are spelled out.
 */
import { createReadStream, createWriteStream } from "node:fs";
import { readdir, stat } from "node:fs/promises";
import { join, relative, resolve, sep } from "node:path";
import { Readable } from "node:stream";
import { pipeline } from "node:stream/promises";
import { fileURLToPath } from "node:url";
import { importer } from "ipfs-unixfs-importer";
import { fixedSize } from "ipfs-unixfs-importer/chunker";
import { balanced } from "ipfs-unixfs-importer/layout";
import { CarWriter } from "@ipld/car";

export const UNIXFS_PARAMETERS = {
  cidVersion: 1,
  rawLeaves: true,
  chunkSize: 262144,
  maxChildrenPerNode: 174,
  layout: "balanced",
  shardSplitThresholdBytes: 262144,
  hasher: "sha2-256",
};

/*
 * The blocks, in the order the importer produces them (the order the CAR
 * gets them). A plain map: the importer only needs put/get/has.
 */
class BlockMap {
  blocks = new Map();
  async put(cid, bytes) {
    this.blocks.set(cid.toString(), { cid, bytes });
    return cid;
  }
  async get(cid) {
    return this.blocks.get(cid.toString())?.bytes;
  }
  async has(cid) {
    return this.blocks.has(cid.toString());
  }
}

/** Every file under `dir`, as "a/b/c.ext" paths, sorted bytewise. */
export async function listFiles(dir) {
  const out = [];
  async function walk(d) {
    for (const name of await readdir(d)) {
      const p = join(d, name);
      if ((await stat(p)).isDirectory()) await walk(p);
      else out.push(relative(dir, p).split(sep).join("/"));
    }
  }
  await walk(dir);
  return out.sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
}

/**
 * Imports `dir` into memory and returns the root CID
 * (the directory itself, as `ipfs add -r --cid-version 1 <dir>` prints it).
 * With `carPath`, writes a CAR of all blocks with that CID as its root.
 */
export async function packDirectory(dir, carPath) {
  const root = resolve(dir);
  const files = await listFiles(root);
  if (files.length === 0) throw new Error(`${dir}: no files`);
  const blockstore = new BlockMap();
  const entries = files.map((path) => ({ path, content: createReadStream(join(root, path)) }));
  let rootCid;
  let bytes = 0;
  for (const path of files) bytes += (await stat(join(root, path))).size;
  for await (const entry of importer(entries, blockstore, {
    cidVersion: UNIXFS_PARAMETERS.cidVersion,
    rawLeaves: UNIXFS_PARAMETERS.rawLeaves,
    chunker: fixedSize({ chunkSize: UNIXFS_PARAMETERS.chunkSize }),
    layout: balanced({ maxChildrenPerNode: UNIXFS_PARAMETERS.maxChildrenPerNode }),
    shardSplitThresholdBytes: UNIXFS_PARAMETERS.shardSplitThresholdBytes,
    reduceSingleLeafToSelf: true,
    wrapWithDirectory: true,
  })) {
    if (entry.path === "") rootCid = entry.cid;
  }
  if (!rootCid) throw new Error("importer yielded no root directory");

  if (carPath) {
    const { writer, out } = CarWriter.create([rootCid]);
    const done = pipeline(Readable.from(out), createWriteStream(carPath));
    for (const block of blockstore.blocks.values()) await writer.put(block);
    await writer.close();
    await done;
  }
  return { cid: rootCid.toString(), files, bytes };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [dir, car] = process.argv.slice(2);
  if (!dir) {
    console.error("usage: node scripts/ipfs-cid.mjs <dir> [out.car]");
    process.exit(2);
  }
  const r = await packDirectory(dir, car);
  console.log(r.cid);
}
