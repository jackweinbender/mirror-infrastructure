#!/usr/bin/env node
import fs from 'node:fs';

const keyPattern = /^[A-Za-z_][A-Za-z0-9_]*$/;
const values = new Map();

function parse(file) {
  if (!fs.existsSync(file)) return;
  for (const [index, raw] of fs.readFileSync(file, 'utf8').split(/\r?\n/).entries()) {
    let line = raw.trim();
    if (!line || line.startsWith('#')) continue;
    if (line.startsWith('export ')) line = line.slice(7).trimStart();
    const separator = line.indexOf('=');
    if (separator < 0) throw new Error(`malformed dotenv line ${file}:${index + 1}`);
    const key = line.slice(0, separator).trim();
    let value = line.slice(separator + 1).trim();
    if (!keyPattern.test(key)) throw new Error(`invalid dotenv key ${file}:${index + 1}`);
    if (value.startsWith('"') || value.startsWith("'")) {
      const quote = value[0];
      if (value.length < 2 || !value.endsWith(quote)) {
        throw new Error(`unterminated dotenv value ${file}:${index + 1}`);
      }
      value = value.slice(1, -1);
    }
    values.set(key, value);
  }
}

try {
  for (const file of process.argv.slice(2)) parse(file);
  for (const [key, value] of values) process.stdout.write(`${key}=${value}\n`);
} catch (error) {
  console.error(`dotenv merge: ${error.message}`);
  process.exit(1);
}
