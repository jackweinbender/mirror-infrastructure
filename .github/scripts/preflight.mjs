#!/usr/bin/env node
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

const root = path.resolve(import.meta.dirname, '../..');
const stacksDir = path.join(root, 'compose-stacks');
const namePattern = /^[a-z0-9][a-z0-9_-]*$/;
const mergeScript = path.join(root, '.github/scripts/merge-dotenv.mjs');

function fail(message) {
  console.error(`preflight: ${message}`);
  process.exit(1);
}
function command(program, args, options = {}) {
  const result = spawnSync(program, args, { encoding: 'utf8', ...options });
  if (result.error || result.status !== 0) {
    throw new Error(result.error?.message || result.stderr.trim() || `${program} exited with ${result.status}`);
  }
  return result.stdout;
}
function parseInventory() {
  let inventory;
  try {
    inventory = JSON.parse(command('ansible-inventory', ['--list', '-i', path.join(root, 'ansible/inventory.yaml')]));
  } catch (error) {
    fail(`could not read parsed Ansible inventory: ${error.message}`);
  }
  const hostvars = inventory._meta?.hostvars || {};
  const hosts = [];
  for (const hostname of inventory.workloads?.hosts || []) {
    const data = hostvars[hostname] || {};
    if (!(data.host_roles || []).includes('deploy')) continue;
    const id = hostname.split('.')[0];
    if (!namePattern.test(id) || id === 'docker-host') fail(`invalid or reserved deploy host identifier: ${id}`);
    hosts.push({ id, address: data.ansible_host || hostname });
  }
  if (!hosts.length) fail('no workload hosts have the deploy role');
  if (new Set(hosts.map((host) => host.id)).size !== hosts.length) fail('deploy host identifiers are not unique');
  return hosts.sort((a, b) => a.id.localeCompare(b.id));
}
function mergedEnv(shared, assignment) {
  try {
    return command('node', [mergeScript, shared, assignment]);
  } catch (error) {
    fail(`dotenv validation failed for ${assignment}: ${error.message}`);
  }
}
function validateCompose(stack, host, compose, envText) {
  const representative = envText.replace(/op:\/\/[^\s]+/g, 'example-secret');
  const envFile = path.join(os.tmpdir(), `compose-${stack}-${host}-${process.pid}.env`);
  fs.writeFileSync(envFile, representative, { mode: 0o600 });
  try {
    command('docker', ['compose', '--project-name', stack, '--env-file', envFile, '-f', compose, 'config', '--quiet'], { stdio: ['ignore', 'ignore', 'pipe'] });
  } catch (error) {
    fail(`Compose validation failed for ${stack}/${host}: ${error.message}`);
  } finally {
    fs.rmSync(envFile, { force: true });
  }
}
function main() {
  const hosts = parseInventory();
  const hostIds = new Set(hosts.map((host) => host.id));
  const stacks = [];
  for (const entry of fs.readdirSync(stacksDir, { withFileTypes: true })) {
    if (!entry.isDirectory() || entry.name === 'docker-host') continue;
    const stack = entry.name;
    const stackDir = path.join(stacksDir, stack);
    if (!namePattern.test(stack)) fail(`invalid stack name: ${stack}`);
    const compose = path.join(stackDir, 'docker-compose.yaml');
    if (!fs.existsSync(compose)) fail(`application stack ${stack} has no docker-compose.yaml`);
    const deployments = path.join(stackDir, 'deployments');
    const shared = path.join(deployments, '_shared.env');
    if (fs.existsSync(shared) && !fs.statSync(shared).isFile()) fail(`${shared} is not a regular file`);
    if (fs.existsSync(deployments)) {
      for (const assignmentEntry of fs.readdirSync(deployments, { withFileTypes: true })) {
        if (assignmentEntry.name === '_shared.env') continue;
        const assignment = path.join(deployments, assignmentEntry.name);
        if (!assignmentEntry.isFile() || !assignmentEntry.name.endsWith('.env')) fail(`invalid deployment file: ${assignment}`);
        const host = assignmentEntry.name.slice(0, -4);
        if (!namePattern.test(host) || host === 'docker-host') fail(`invalid deployment host filename: ${assignmentEntry.name}`);
        if (!hostIds.has(host)) fail(`unknown deployment host ${host} in ${assignment}`);
        validateCompose(stack, host, compose, mergedEnv(shared, assignment));
      }
    }
    stacks.push(stack);
  }
  if (!stacks.length) fail('no application Compose stacks found');
  const output = { hosts, stacks: stacks.sort() };
  if (process.env.GITHUB_OUTPUT) {
    fs.appendFileSync(process.env.GITHUB_OUTPUT, `hosts=${JSON.stringify(output.hosts)}\nstacks=${JSON.stringify(output.stacks)}\n`);
  }
  console.log(JSON.stringify(output));
}
main();
