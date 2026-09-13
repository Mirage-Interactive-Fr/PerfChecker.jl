import { runTests } from '@vscode/test-electron';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';

// Bound the whole application lifecycle, including failures before activation.
// A separate process lets the supervisor stop precisely this host and its workers.
if (process.env.PERFCHECKER_HOST_CHILD !== '1') {
  const child = spawn(process.execPath, process.argv.slice(1), {
    stdio: 'inherit', windowsHide: true, detached: process.platform !== 'win32',
    env: {...process.env, PERFCHECKER_HOST_CHILD: '1'},
  });
  let expired = false;
  const timer = setTimeout(() => {
    expired = true;
    console.error('VS Code host qualification exceeded its 10-minute deadline');
    if (process.platform === 'win32') {
      spawn('taskkill', ['/PID', String(child.pid), '/T', '/F'], {windowsHide:true});
    } else {
      try { process.kill(-child.pid, 'SIGKILL'); } catch { child.kill('SIGKILL'); }
    }
  }, 600_000);
  child.on('error', error => { clearTimeout(timer); console.error(error); process.exitCode=1; });
  child.on('close', code => { clearTimeout(timer); process.exitCode=expired ? 124 : (code ?? 1); });
  await new Promise(resolve => child.once('close', resolve));
} else {

if (process.argv.length !== 5) throw new Error('Expected CLIENT CONTROLLER OUTPUT arguments');
const [client, controller, output] = process.argv.slice(2).map(p => path.resolve(p));
const session = await fs.mkdtemp(path.join(output, 'vscode-session-'));
const fixture = path.join(session, 'native-item-workspace');
const bibliography = process.env.PERFCHECKER_BIBLIOGRAPHY_WORKSPACE;
await fs.mkdir(fixture); // Every attempt has an independent execution oracle.
await fs.copyFile(path.join(path.dirname(fileURLToPath(import.meta.url)), 'items.jl'), path.join(fixture, 'items.jl'));
await fs.mkdir(path.join(fixture, '.vscode'));
const settings = {
  'perfchecker.runnerProject': controller,
  'perfchecker.juliaExecutable': process.env.PERFCHECKER_JULIA_EXECUTABLE ?? 'julia',
  'perfchecker.testItemSamples': 1,
  'perfchecker.analysisTimeout': 180,
  'telemetry.telemetryLevel': 'off',
  'workbench.startupEditor': 'none',
};
await fs.writeFile(path.join(fixture, '.vscode/settings.json'), JSON.stringify(settings, null, 2));
let workspace = fixture;
if (bibliography) {
  workspace = path.join(session, 'Bibliography.code-workspace');
  await fs.writeFile(workspace, JSON.stringify({folders:[{path:path.resolve(bibliography)}],settings}, null, 2));
}

await runTests({
  extensionDevelopmentPath: client,
  extensionTestsPath: path.join(client, 'test/native-items-vscode.cjs'),
  ...(process.env.PERFCHECKER_VSCODE_EXECUTABLE ? { vscodeExecutablePath: process.env.PERFCHECKER_VSCODE_EXECUTABLE } : {}),
  launchArgs: [workspace, '--new-window', '--disable-extensions', '--disable-workspace-trust',
    '--skip-welcome', '--skip-release-notes', '--disable-gpu',
    `--user-data-dir=${path.join(session, 'vscode-user')}`,
    `--extensions-dir=${path.join(session, 'vscode-extensions')}`],
  extensionTestsEnv: {
    PERFCHECKER_HOST_EVIDENCE: output,
    PERFCHECKER_HOST_MARKER: path.join(fixture, 'calls.txt'),
    PERFCHECKER_HOST_BIBLIOGRAPHY: bibliography ? '1' : '',
    PERFCHECKER_HOST_CAPTURE: process.env.PERFCHECKER_HOST_CAPTURE ?? '',
    JULIA_NUM_THREADS: '1', JULIA_NUM_GC_THREADS: '1', JULIA_NUM_PRECOMPILE_TASKS: '1',
    OPENBLAS_NUM_THREADS: '1', OMP_NUM_THREADS: '1', MKL_NUM_THREADS: '1',
    // Electron bootstrap requires its normal I/O pool; this is not Julia compute.
    UV_THREADPOOL_SIZE: '4',
  },
});
const result = JSON.parse(await fs.readFile(path.join(output, 'vscode-host-result.json'), 'utf8'));
assert.equal(result.status, 'passed');
assert.equal(typeof result.vscode_version, 'string');
console.log(`VS Code ${result.vscode_version}: native item host qualification passed`);
}
