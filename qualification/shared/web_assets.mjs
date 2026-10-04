import { readdirSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { execFileSync } from 'node:child_process';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const assets = resolve(root, 'packages/PerfCheckerWeb/src/assets');
for (const name of readdirSync(assets).filter(name => name.endsWith('.js'))) {
  execFileSync(process.execPath, ['--check', resolve(assets, name)], { stdio: 'inherit' });
}
const schemas = resolve(root, 'schemas');
for (const name of readdirSync(schemas).filter(name => name.endsWith('.json'))) {
  JSON.parse(readFileSync(resolve(schemas, name), 'utf8'));
}
console.log('Web JavaScript syntax and JSON schemas passed.');
