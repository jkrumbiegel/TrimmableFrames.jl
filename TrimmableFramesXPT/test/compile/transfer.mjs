import fs from 'node:fs';
import { pathToFileURL } from 'node:url';

const [hostPath, wasmPath, inputPath] = process.argv.slice(2);
const { instantiate } = await import(pathToFileURL(hostPath).href);
const { instance } = await instantiate(fs.readFileSync(wasmPath));
const { reset_input, push_word, read_input } = instance.exports;

const bytes = new Uint8Array(fs.readFileSync(inputPath));
const padded = new Uint8Array(Math.ceil(bytes.length / 8) * 8);
padded.set(bytes);
const words = new BigInt64Array(padded.buffer);

const start = performance.now();
reset_input(BigInt(padded.length));
for (let i = 0; i < words.length; i++) push_word(words[i]);
const copied = performance.now();
const count = read_input(BigInt(bytes.length));
const parsed = performance.now();

console.log(`bytes ${bytes.length}`);
console.log(`rows ${count}`);
console.log(`copy ${(copied - start).toFixed(0)} ms, parse ${(parsed - copied).toFixed(0)} ms`);
