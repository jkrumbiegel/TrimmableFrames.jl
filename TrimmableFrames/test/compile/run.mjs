import fs from 'node:fs';
import { pathToFileURL } from 'node:url';

const [hostPath, wasmPath, fn, ...args] = process.argv.slice(2);
const { instantiate } = await import(pathToFileURL(hostPath).href);
const { instance } = await instantiate(fs.readFileSync(wasmPath));

for (const arg of args.length ? args : [null]) {
  const value = arg === null ? instance.exports[fn]() : instance.exports[fn](BigInt(arg));
  console.log('RESULT', String(value));
}
