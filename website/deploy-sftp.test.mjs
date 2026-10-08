import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, readFile, rm, symlink } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, posix } from 'node:path';
import { createHmac } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import ssh2 from 'ssh2';
const { Server, utils } = ssh2;
import { hostVerifier, validateRoot, readExport, publishDocumentation, connectSftp,
  deploymentConfiguration, documentationSourceConfiguration, validateDocumentationExports,
  validateStableDocumentationSource, failureClass } from './deploy-sftp.mjs';
const revision = 'a'.repeat(40), nextRevision = 'b'.repeat(40);
class MemorySftp {
  constructor() { this.files = new Map(); this.dirs = new Map([['/www', 0o755]]); this.operations = []; this.fail = null; }
  async stat(path) {
    if (!this.files.has(path) && !this.dirs.has(path)) return null;
    return { isFile: () => this.files.has(path), isDirectory: () => this.dirs.has(path), isSymbolicLink: () => false };
  }
  async read(path) { return this.files.get(path)?.bytes ?? null; }
  async mkdir(path) { if (this.dirs.has(path)) throw new Error('exists'); this.dirs.set(path, 0o755); }
  async chmod(path, mode) { if (this.files.has(path)) this.files.get(path).mode = mode; else this.dirs.set(path, mode); }
  async write(path, bytes) { this.files.set(path, { bytes: Buffer.from(bytes), mode: 0o644 }); }
  async put(local, path) { await this.write(path, await readFile(local)); }
  async replace(from, to) {
    if (this.fail?.(to)) throw new Error('injected transfer failure');
    this.operations.push(to); this.files.set(to, this.files.get(from)); this.files.delete(from);
  }
  async unlink(path) { this.files.delete(path); }
  async rmdir(path) { this.dirs.delete(path); }
}
async function exportsFor(t, version = '1.0.0', sha = revision) {
  const root = await mkdtemp(join(tmpdir(), 'perfchecker-sftp-test-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const make = async channel => {
    const dir = join(root, channel); await mkdir(join(dir, 'assets'), { recursive: true });
    const base = channel === 'dev' ? '/dev/' : channel === 'version' ? `/v${version}/` : '/';
    await writeFile(join(dir, 'build-info.json'), JSON.stringify({ schema: 'perfchecker-doc-export/1',
      channel, base, version, revision: sha, url: 'https://perfchecker.mirageinteractive.fr' + base }));
    await writeFile(join(dir, 'assets/app.js'), `asset ${sha}`);
    await mkdir(join(dir, 'assets/chunks'));
    await writeFile(join(dir, 'assets/chunks/@localSearchIndexroot.fixture.js'), 'local search index');
    await writeFile(join(dir, 'guide.html'), `guide ${version} ${channel}`);
    await writeFile(join(dir, 'index.html'), `index ${version} ${channel}`);
    await writeFile(join(dir, 'siteinfo.js'), `var DOCUMENTER_CURRENT_VERSION = ${JSON.stringify(channel === 'dev' ? 'dev' : `v${version}`)};`);
    await writeFile(join(dir, 'versions.js'), 'offline catalogue, never remote inventory');
    return dir;
  };
  return { dev: await make('dev'), site: await make('version'), stableSite: await make('stable') };
}
const release = (exports, version = 'v1.0.0', sha = revision) => ({ ...exports, root: '/www', channel: 'release', version, revision: sha });
const refresh = (exports, sequence = 20) => ({ root: '/www', channel: 'stable-refresh', version: 'v1.0.0',
  revision: nextRevision, releaseRevision: revision, sequence, site: exports.stableSite });
const protectedFiles = sftp => new Map([...sftp.files].filter(([path]) => path.startsWith('/www/v1.0.0/') ||
  path.startsWith('/www/dev/') || ['/www/.perfchecker-releases.json', '/www/.perfchecker-promotion.json',
    '/www/.perfchecker-stable.json', '/www/versions.js'].includes(path))
  .map(([path, file]) => [path, Buffer.from(file.bytes)]));
test('stable source validation accepts only documentation differences from an existing tag', async t => {
  const root = await mkdtemp(join(tmpdir(), 'perfchecker-doc-source-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const git = (...args) => execFileSync('git', ['-C', root, '-c', 'user.name=Documentation test',
    '-c', 'user.email=docs@example.invalid', '-c', 'commit.gpgsign=false', '-c', 'core.hooksPath=/dev/null', ...args],
  { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
  git('init'); await mkdir(join(root, 'website'));
  await writeFile(join(root, 'Project.toml'), 'version = "1.0.0"\n');
  await writeFile(join(root, 'website/guide.md'), 'first guide');
  git('add', '.'); git('commit', '-m', 'release'); const tagRevision = git('rev-parse', 'HEAD'); git('tag', 'v1.0.0');
  await writeFile(join(root, 'website/guide.md'), 'illustrated guide'); git('add', '.'); git('commit', '-m', 'docs');
  const docsRevision = git('rev-parse', 'HEAD');
  assert.equal(await validateStableDocumentationSource(root, 'v1.0.0', docsRevision), tagRevision);
  git('tag', 'v1.0.1', tagRevision);
  await assert.rejects(validateStableDocumentationSource(root, 'v1.0.1', docsRevision), /package version differs/);
  await writeFile(join(root, 'Project.toml'), 'uncommitted package change');
  await assert.rejects(validateStableDocumentationSource(root, 'v1.0.0', docsRevision), /outside documentation/);
  await writeFile(join(root, 'Project.toml'), 'version = "1.0.0"\n');
  await assert.rejects(validateStableDocumentationSource(root, 'v1.0.0', revision), /checkout differs/);
  await assert.rejects(validateStableDocumentationSource(root, 'v9.9.9', docsRevision));
  for (const path of ['Project.toml', 'src/new.jl', 'ext/NewExt.jl', 'bin/perfchecker.jl',
    'packages/Provider/Project.toml', 'schemas/result.json', '.github/workflows/CI.yml']) {
    await mkdir(join(root, posix.dirname(path)), { recursive: true }); await writeFile(join(root, path), 'changed');
    git('add', '.'); git('commit', '-m', 'non-documentation change');
    await assert.rejects(validateStableDocumentationSource(root, 'v1.0.0', git('rev-parse', 'HEAD')), /outside documentation/);
    git('revert', '--no-edit', 'HEAD');
    assert.equal(await validateStableDocumentationSource(root, 'v1.0.0', git('rev-parse', 'HEAD')), tagRevision);
  }
});
test('explicit source inputs require a complete immutable pair on a stable main dispatch', () => {
  const env = { GITHUB_ACTIONS: 'true', GITHUB_EVENT_NAME: 'workflow_dispatch', GITHUB_REF: 'refs/heads/main',
    GITHUB_SHA: revision, PERFCHECKER_DOCS_STABLE_REFRESH: 'true',
    PERFCHECKER_DOCS_SOURCE_VERSION: 'v1.0.0', PERFCHECKER_DOCS_SOURCE_REVISION: nextRevision };
  const before = JSON.stringify(env);
  assert.deepEqual(documentationSourceConfiguration(env), { explicit: true, version: 'v1.0.0', revision: nextRevision });
  assert.equal(JSON.stringify(env), before, 'The Actions revision is never replaced by the documentation revision');
  for (const change of [{ PERFCHECKER_DOCS_SOURCE_VERSION: '' }, { PERFCHECKER_DOCS_SOURCE_REVISION: '' },
    { PERFCHECKER_DOCS_SOURCE_VERSION: '1.0.0' }, { PERFCHECKER_DOCS_SOURCE_VERSION: 'v1.0.0-rc1' },
    { PERFCHECKER_DOCS_SOURCE_VERSION: 'v1.0.0\n' },
    { PERFCHECKER_DOCS_SOURCE_REVISION: 'main' }, { PERFCHECKER_DOCS_SOURCE_REVISION: 'b'.repeat(39) },
    { PERFCHECKER_DOCS_SOURCE_REVISION: 'b'.repeat(40) + '\n' }, { GITHUB_SHA: '' },
    { GITHUB_EVENT_NAME: 'push' }, { GITHUB_EVENT_NAME: 'pull_request' },
    { GITHUB_REF: 'refs/tags/v1.0.0' }, { GITHUB_REF: 'refs/heads/other' },
    { PERFCHECKER_DOCS_STABLE_REFRESH: 'false' }, { GITHUB_ACTIONS: 'false' }])
    assert.throws(() => documentationSourceConfiguration({ ...env, ...change }));
  for (const event of ['push', 'pull_request', 'workflow_dispatch'])
    assert.deepEqual(documentationSourceConfiguration({ GITHUB_SHA: revision, GITHUB_EVENT_NAME: event }),
      { explicit: false, version: undefined, revision }, 'Ordinary sources retain the Actions revision');
});
test('explicit stable exports bind the documentation SHA rather than the Actions SHA', async t => {
  const source = documentationSourceConfiguration({ GITHUB_ACTIONS: 'true', GITHUB_EVENT_NAME: 'workflow_dispatch',
    GITHUB_REF: 'refs/heads/main', GITHUB_SHA: revision, PERFCHECKER_DOCS_STABLE_REFRESH: 'true',
    PERFCHECKER_DOCS_SOURCE_VERSION: 'v1.0.0', PERFCHECKER_DOCS_SOURCE_REVISION: nextRevision });
  const actionsExport = await exportsFor(t), sourceExport = await exportsFor(t, '1.0.0', source.revision);
  const options = { channel: 'stable-refresh', version: source.version, revision: source.revision };
  await assert.rejects(validateDocumentationExports({ ...options, site: actionsExport.stableSite }), /source or channel/);
  const { primary, stable } = await validateDocumentationExports({ ...options, site: sourceExport.stableSite });
  assert.equal(primary.info.revision, nextRevision); assert.equal(primary.info.version, '1.0.0');
  assert.equal(primary.info.base, '/'); assert.equal(stable, null, 'No version archive is required or selected');
});
test('an explicit stable refresh updates only root files and its own provenance marker', async t => {
  const old = await exportsFor(t), updated = await exportsFor(t, '1.0.0', nextRevision), sftp = new MemorySftp();
  await publishDocumentation(sftp, release(old));
  await publishDocumentation(sftp, { root: '/www', channel: 'dev', revision, sequence: 1, site: old.dev });
  const protectedBefore = protectedFiles(sftp), operationsBefore = sftp.operations.length;
  await publishDocumentation(sftp, refresh(updated));
  assert.deepEqual(protectedFiles(sftp), protectedBefore);
  const writes = sftp.operations.slice(operationsBefore);
  assert.ok(writes.includes('/www/index.html'));
  assert.equal(writes.some(path => protectedBefore.has(path)), false);
  assert.equal(JSON.parse(await sftp.read('/www/build-info.json')).revision, nextRevision);
  const marker = JSON.parse(await sftp.read('/www/.perfchecker-stable-refresh.json'));
  assert.equal(marker.status, 'complete'); assert.equal(marker.revision, nextRevision);
  assert.equal(marker.version, 'v1.0.0'); assert.equal(marker.sequence, 20);
  assert.equal(sftp.dirs.has('/www/.perfchecker-docs-lock'), false);
  const snapshot = Buffer.from(await sftp.read('/www/build-info.json'));
  await publishDocumentation(sftp, release(old));
  assert.deepEqual(await sftp.read('/www/build-info.json'), snapshot, 'same-tag rerun preserves refreshed root');
  assert.equal((await publishDocumentation(sftp, refresh(updated, 19))).skipped, true);
  const newer = await exportsFor(t, '1.0.1', 'c'.repeat(40));
  await publishDocumentation(sftp, release(newer, 'v1.0.1', 'c'.repeat(40)));
  assert.equal(JSON.parse(await sftp.read('/www/build-info.json')).version, '1.0.1');
});
test('a completed tag rerun does not upload root files and an unfinished first promotion can resume', async t => {
  const exports = await exportsFor(t), sftp = new MemorySftp();
  await publishDocumentation(sftp, release(exports)); const before = sftp.operations.length;
  await publishDocumentation(sftp, release(exports));
  assert.equal(sftp.operations.slice(before).some(path => path === '/www/index.html' || path === '/www/guide.html' ||
    path.startsWith('/www/assets/')), false);
  const manual = new MemorySftp(); await manual.write('/www/siteinfo.js', 'var DOCUMENTER_CURRENT_VERSION = "v1.0.0";');
  await manual.write('/www/index.html', 'manual documentation');
  manual.fail = destination => destination === '/www/guide.html';
  await assert.rejects(publishDocumentation(manual, release(exports)), /injected/);
  manual.fail = null; await publishDocumentation(manual, release(exports));
  assert.equal((await manual.read('/www/index.html')).toString(), 'index 1.0.0 stable');
});
test('stable refresh refuses unknown releases, wrong tag source and incomplete or newer promotion metadata', async t => {
  const old = await exportsFor(t), updated = await exportsFor(t, '1.0.0', nextRevision);
  for (const problem of ['unknown', 'wrong-source', 'missing-archive', 'missing-completion', 'newer-intent']) {
    const sftp = new MemorySftp(); if (problem !== 'unknown') await publishDocumentation(sftp, release(old));
    const options = refresh(updated);
    if (problem === 'wrong-source') options.releaseRevision = 'c'.repeat(40);
    if (problem === 'missing-archive') sftp.files.delete('/www/v1.0.0/.perfchecker-docs.json');
    if (problem === 'missing-completion') sftp.files.delete('/www/.perfchecker-stable.json');
    if (problem === 'newer-intent') await sftp.write('/www/.perfchecker-promotion.json', JSON.stringify({
      version: 'v1.0.1', revision: 'c'.repeat(40), digest: 'd'.repeat(64) }));
    const snapshot = new Map([...sftp.files].map(([path, file]) => [path, Buffer.from(file.bytes)]));
    const writes = sftp.operations.length;
    await assert.rejects(publishDocumentation(sftp, options), /published stable|absent or incomplete/);
    assert.deepEqual(new Map([...sftp.files].map(([path, file]) => [path, file.bytes])), snapshot, problem);
    assert.equal(sftp.operations.length, writes, problem);
    assert.equal(sftp.dirs.has('/www/.perfchecker-docs-lock'), false);
  }
});
test('interrupted stable refresh preserves archive identities, blocks old tag rollback and can resume', async t => {
  for (const boundary of ['watermark', 'page', 'completion']) {
    const old = await exportsFor(t), updated = await exportsFor(t, '1.0.0', nextRevision), sftp = new MemorySftp();
    await publishDocumentation(sftp, release(old)); const archive = protectedFiles(sftp); let markers = 0;
    sftp.fail = destination => boundary === 'page' ? destination === '/www/guide.html' :
      destination === '/www/.perfchecker-stable-refresh.json' && ++markers === (boundary === 'watermark' ? 1 : 2);
    await assert.rejects(publishDocumentation(sftp, refresh(updated)), /injected/);
    assert.deepEqual(protectedFiles(sftp), archive, boundary);
    assert.equal(sftp.dirs.has('/www/.perfchecker-docs-lock'), false);
    assert.equal([...sftp.files.keys()].some(path => path.includes('.perfchecker-upload-')), false);
    sftp.fail = null;
    if (boundary !== 'watermark') {
      const root = Buffer.from(await sftp.read('/www/build-info.json'));
      await publishDocumentation(sftp, release(old)); assert.deepEqual(await sftp.read('/www/build-info.json'), root);
    }
    await publishDocumentation(sftp, refresh(updated));
    assert.equal(JSON.parse(await sftp.read('/www/.perfchecker-stable-refresh.json')).status, 'complete');
    assert.deepEqual(protectedFiles(sftp), archive);
  }
});
test('first dev deployment preserves the manual root and advertises only available channels', async t => {
  const exports = await exportsFor(t), sftp = new MemorySftp();
  await sftp.write('/www/index.html', 'manual root'); await sftp.write('/www/notes.txt', 'user file');
  await sftp.write('/www/siteinfo.js', 'var DOCUMENTER_CURRENT_VERSION = "v0.2.0";');
  await publishDocumentation(sftp, { root: '/www', channel: 'dev', revision, sequence: 1, site: exports.dev });
  assert.equal((await sftp.read('/www/index.html')).toString(), 'manual root');
  assert.equal((await sftp.read('/www/notes.txt')).toString(), 'user file');
  assert.match((await sftp.read('/www/versions.js')).toString(), /"v0.2.0":"\/"/);
  assert.match((await sftp.read('/www/versions.js')).toString(), /"dev":"\/dev\/"/);
  assert.doesNotMatch((await sftp.read('/www/versions.js')).toString(), /v1\.0\.0/);
  assert.equal(sftp.dirs.has('/www/.perfchecker-docs-lock'), false);
});
test('dev bootstrap without a stable version does not invent a stable channel', async t => {
  const exports = await exportsFor(t), sftp = new MemorySftp();
  await publishDocumentation(sftp, { root: '/www', channel: 'dev', revision, sequence: 1, site: exports.dev });
  assert.match((await sftp.read('/www/versions.js')).toString(), /DOC_VERSIONS = \["dev"\]/);
});
test('late old tag cannot regress stable or erase dev, archives, and user files', async t => {
  const old = await exportsFor(t), newer = await exportsFor(t, '1.0.1', nextRevision), sftp = new MemorySftp();
  await sftp.write('/www/user.html', 'owned by user');
  await publishDocumentation(sftp, { root: '/www', channel: 'dev', revision, sequence: 10, site: old.dev });
  await publishDocumentation(sftp, release(old));
  await publishDocumentation(sftp, release(newer, 'v1.0.1', nextRevision));
  const root = Buffer.from(await sftp.read('/www/index.html')), dev = Buffer.from(await sftp.read('/www/dev/index.html'));
  await publishDocumentation(sftp, release(old));
  assert.deepEqual(await sftp.read('/www/index.html'), root);
  assert.deepEqual(await sftp.read('/www/dev/index.html'), dev);
  assert.match((await sftp.read('/www/v1.0.1/index.html')).toString(), /1\.0\.1/);
  assert.equal((await sftp.read('/www/user.html')).toString(), 'owned by user');
  const state = JSON.parse(await sftp.read('/www/.perfchecker-releases.json'));
  assert.equal(state.stable, 'v1.0.1'); assert.equal(Object.keys(state.versions).length, 2);
  assert.match((await sftp.read('/www/versions.js')).toString(), /"v1.0.0":"\/v1.0.0\/"/);
  for (const file of sftp.files.values()) assert.equal(file.mode, 0o644);
  for (const mode of sftp.dirs.values()) assert.equal(mode, 0o755);
});
test('failed transfer does not advance catalogue/state and retry repairs it', async t => {
  const old = await exportsFor(t), newer = await exportsFor(t, '1.0.1', nextRevision), sftp = new MemorySftp();
  await publishDocumentation(sftp, release(old));
  const state = Buffer.from(await sftp.read('/www/.perfchecker-releases.json'));
  const catalogue = Buffer.from(await sftp.read('/www/versions.js'));
  sftp.fail = destination => destination === '/www/guide.html';
  await assert.rejects(publishDocumentation(sftp, release(newer, 'v1.0.1', nextRevision)), /injected/);
  assert.deepEqual(await sftp.read('/www/.perfchecker-releases.json'), state);
  assert.deepEqual(await sftp.read('/www/versions.js'), catalogue);
  assert.equal([...sftp.files.keys()].some(p => p.includes('.perfchecker-upload-')), false);
  assert.equal(sftp.dirs.has('/www/.perfchecker-docs-lock'), false);
  sftp.fail = null; await publishDocumentation(sftp, release(newer, 'v1.0.1', nextRevision));
  assert.equal(JSON.parse(await sftp.read('/www/.perfchecker-releases.json')).stable, 'v1.0.1');
});
test('assets precede pages, index follows pages, and metadata follows complete uploads', async t => {
  const exports = await exportsFor(t), sftp = new MemorySftp();
  await publishDocumentation(sftp, release(exports));
  const order = sftp.operations;
  assert.ok(order.indexOf('/www/assets/app.js') < order.indexOf('/www/guide.html'));
  assert.ok(order.indexOf('/www/guide.html') < order.indexOf('/www/index.html'));
  assert.ok(order.indexOf('/www/index.html') < order.indexOf('/www/versions.js'));
});
test('immutable archives, stale dev runs, and a competing publisher are rejected safely', async t => {
  const exports = await exportsFor(t), changed = await exportsFor(t, '1.0.0', nextRevision), sftp = new MemorySftp();
  await publishDocumentation(sftp, release(exports));
  await assert.rejects(publishDocumentation(sftp, release(changed, 'v1.0.0', nextRevision)), /cannot be replaced/);
  await publishDocumentation(sftp, { root: '/www', channel: 'dev', revision, sequence: 2, site: exports.dev });
  assert.equal((await publishDocumentation(sftp, { root: '/www', channel: 'dev', revision, sequence: 1, site: exports.dev })).skipped, true);
  await sftp.mkdir('/www/.perfchecker-docs-lock');
  await assert.rejects(publishDocumentation(sftp, release(exports)), /holds the SFTP lock/);
  assert.equal(sftp.dirs.has('/www/.perfchecker-docs-lock'), true);
});
test('exports reject mismatched identity, symbolic links and reserved remote paths', async t => {
  const exports = await exportsFor(t);
  await assert.rejects(readExport(exports.site, 'version', nextRevision, 'v1.0.0'), /source or channel/);
  await assert.rejects(readExport(exports.site, 'version', revision, 'v1.0.1'), /version differs/);
  await symlink('index.html', join(exports.site, 'link.html'));
  await assert.rejects(readExport(exports.site, 'version', revision, 'v1.0.0'), /symbolic/);
  await rm(join(exports.site, 'link.html')); await mkdir(join(exports.site, 'dev'));
  await assert.rejects(readExport(exports.site, 'version', revision, 'v1.0.0'), /reserved/);
  for (const path of ['www', '/www/../other', '/www/./docs', '/www//docs', '/www;command', '/www\n']) assert.throws(() => validateRoot(path));
});
test('host keys are pinned by host and port, with hashed entries and revocation', () => {
  const key = Buffer.alloc(32, 7), other = Buffer.alloc(32, 8), host = 'example.org', port = 2222;
  const line = `[${host}]:${port} ssh-ed25519 ${key.toString('base64')}`;
  assert.equal(hostVerifier(line, host, port)(key), true);
  assert.equal(hostVerifier(line, host, port)(other), false);
  assert.throws(() => hostVerifier(line, host, 22), /No pinned/);
  assert.equal(hostVerifier(`${line}\n@revoked ${line}`, host, port)(key), false);
  const salt = Buffer.alloc(20, 9), hash = createHmac('sha1', salt).update(`[${host}]:${port}`).digest('base64');
  assert.equal(hostVerifier(`|1|${salt.toString('base64')}|${hash} ssh-ed25519 ${key.toString('base64')}`, host, port)(key), true);
});
test('CI credentials cannot be used by PRs, arbitrary refs or disabled deployments', () => {
  const key = Buffer.alloc(32, 7), env = { GITHUB_ACTIONS: 'true', GITHUB_EVENT_NAME: 'push', GITHUB_REF: 'refs/heads/main',
    GITHUB_SHA: revision, GITHUB_RUN_NUMBER: '1', PERFCHECKER_DOCS_SFTP_DEPLOY: 'true',
    PERFCHECKER_DOCS_SFTP_HOST: 'example.org', PERFCHECKER_DOCS_SFTP_PORT: '2222', PERFCHECKER_DOCS_SFTP_USER: 'docs',
    PERFCHECKER_DOCS_SFTP_ROOT: '/www', PERFCHECKER_DOCS_SFTP_PASSWORD: 'test-only',
    PERFCHECKER_DOCS_SFTP_KNOWN_HOSTS: `[example.org]:2222 ssh-ed25519 ${key.toString('base64')}` };
  assert.equal(deploymentConfiguration(env).channel, 'dev');
  assert.equal(deploymentConfiguration({ ...env, PERFCHECKER_DOCS_REF_DELETED: 'false' }).channel, 'dev');
  const tagged = { ...env, GITHUB_REF: 'refs/tags/v1.0.0', GITHUB_REF_NAME: 'v1.0.0' };
  assert.equal(deploymentConfiguration(tagged).channel, 'release');
  const manual = { ...env, GITHUB_EVENT_NAME: 'workflow_dispatch', PERFCHECKER_DOCS_STABLE_REFRESH: 'true',
    PERFCHECKER_DOCS_STABLE_VERSION: 'v1.0.0' };
  assert.equal(deploymentConfiguration(manual).channel, 'stable-refresh');
  assert.equal(deploymentConfiguration(manual).revision, revision);
  const explicit = { ...manual, PERFCHECKER_DOCS_SOURCE_VERSION: 'v1.0.0',
    PERFCHECKER_DOCS_SOURCE_REVISION: nextRevision, PERFCHECKER_DOCS_SOURCE_REPOSITORY: 'stable-doc-source' };
  assert.equal(deploymentConfiguration(explicit).revision, nextRevision);
  assert.equal(deploymentConfiguration(explicit).sourceRepository, 'stable-doc-source');
  assert.equal(explicit.GITHUB_SHA, revision);
  assert.throws(() => deploymentConfiguration({ ...explicit, PERFCHECKER_DOCS_STABLE_VERSION: 'v1.0.1' }), /version differs/);
  for (const ordinary of [env, tagged, { ...env, GITHUB_EVENT_NAME: 'workflow_dispatch' }])
    assert.throws(() => deploymentConfiguration({ ...ordinary, PERFCHECKER_DOCS_SOURCE_VERSION: 'v1.0.0',
      PERFCHECKER_DOCS_SOURCE_REVISION: nextRevision }), /stable dispatch on main/);
  for (const change of [{ GITHUB_REF: 'refs/heads/dev' }, { GITHUB_EVENT_NAME: 'push' },
    { GITHUB_EVENT_NAME: 'pull_request' }, { PERFCHECKER_DOCS_STABLE_VERSION: '1.0.0' }])
    assert.throws(() => deploymentConfiguration({ ...manual, ...change }));
  assert.throws(() => deploymentConfiguration({ ...tagged, PERFCHECKER_DOCS_REF_DELETED: 'true' }), /Deleted refs/);
  for (const change of [{ GITHUB_EVENT_NAME: 'pull_request' }, { GITHUB_REF: 'refs/heads/other' },
    { PERFCHECKER_DOCS_SFTP_DEPLOY: 'false' }, { PERFCHECKER_DOCS_SFTP_KNOWN_HOSTS: '' },
    { PERFCHECKER_DOCS_REF_DELETED: 'true' }])
    assert.throws(() => deploymentConfiguration({ ...env, ...change }));
});
test('real SSH password authentication opens only SFTP and rejects a wrong pinned key', async t => {
  // A temporary platform-generated OpenSSH host key exercises the real wire protocol.
  const temporary = await mkdtemp(join(tmpdir(), 'perfchecker-sftp-server-'));
  t.after(() => rm(temporary, { recursive: true, force: true }));
  const { execFileSync } = await import('node:child_process');
  execFileSync('ssh-keygen', ['-q', '-t', 'ed25519', '-N', '', '-f', join(temporary, 'key')]);
  const key = await readFile(join(temporary, 'key')), publicKey = utils.parseKey(key).getPublicSSH();
  let sessions = 0, execs = 0;
  const server = new Server({ hostKeys: [key] }, client => {
    client.on('error', () => {});
    client.on('authentication', ctx => ctx.method === 'password' && ctx.username === 'docs' && ctx.password === 'test-only' ? ctx.accept() : ctx.reject());
    client.on('ready', () => client.on('session', accept => {
      const session = accept(); session.on('exec', (_, reject) => { execs++; reject(); });
      session.on('sftp', acceptSftp => {
        sessions++; const stream = acceptSftp();
        stream.on('LSTAT', (id, path) => path === '/www'
          ? stream.attrs(id, { mode: 0o40755, uid: 0, gid: 0, size: 0, atime: 0, mtime: 0 })
          : stream.status(id, 2));
      });
    }));
  });
  await new Promise(ok => server.listen(0, '127.0.0.1', ok)); t.after(() => new Promise(ok => server.close(ok)));
  const port = server.address().port;
  const config = { host: '127.0.0.1', port, username: 'docs', password: 'test-only', privateKey: '', readyTimeout: 1000,
    hostVerifier: hostVerifier(`[127.0.0.1]:${port} ssh-ed25519 ${publicKey.toString('base64')}`, '127.0.0.1', port) };
  const transport = await connectSftp(config);
  assert.equal((await transport.stat('/www')).isDirectory(), true); assert.equal(await transport.stat('/absent'), null);
  transport.close();
  await assert.rejects(connectSftp({ ...config, hostVerifier: () => false }), /verification failed/i);
  assert.equal(sessions, 1); assert.equal(execs, 0);
});

test('failures at promotion boundaries never let an old tag regress the root', async t => {
  for (const boundary of ['/www/.perfchecker-promotion.json', '/www/guide.html',
    '/www/.perfchecker-stable.json', '/www/.perfchecker-releases.json', '/www/versions.js']) {
    const old = await exportsFor(t), newer = await exportsFor(t, '1.0.1', nextRevision), sftp = new MemorySftp();
    await publishDocumentation(sftp, release(old));
    sftp.fail = destination => destination === boundary;
    await assert.rejects(publishDocumentation(sftp, release(newer, 'v1.0.1', nextRevision)), /injected/);
    const snapshot = Buffer.from(await sftp.read('/www/index.html'));
    sftp.fail = null;
    await publishDocumentation(sftp, release(old));
    assert.deepEqual(await sftp.read('/www/index.html'), snapshot, boundary);
    await publishDocumentation(sftp, release(newer, 'v1.0.1', nextRevision));
    assert.equal(JSON.parse(await sftp.read('/www/.perfchecker-releases.json')).stable, 'v1.0.1');
    assert.match((await sftp.read('/www/versions.js')).toString(), /"v1.0.1":"\/"/);
  }
});

test('main development exports accept Julia prerelease versions', async t => {
  const exports = await exportsFor(t, '1.0.1-DEV'), sftp = new MemorySftp();
  await publishDocumentation(sftp, { root: '/www', channel: 'dev', revision, sequence: 1, site: exports.dev });
  assert.equal(JSON.parse(await sftp.read('/www/.perfchecker-releases.json')).dev.revision, revision);
});
test('pre-authentication server disconnect rejects promptly rather than hanging', async t => {
  const temporary = await mkdtemp(join(tmpdir(), 'perfchecker-sftp-disconnect-'));
  t.after(() => rm(temporary, { recursive: true, force: true }));
  const { execFileSync } = await import('node:child_process');
  execFileSync('ssh-keygen', ['-q', '-t', 'ed25519', '-N', '', '-f', join(temporary, 'key')]);
  const key = await readFile(join(temporary, 'key')), publicKey = utils.parseKey(key).getPublicSSH();
  const server = new Server({ hostKeys: [key] }, client => {
    client.on('error', () => {}); client.on('authentication', () => client.end());
  });
  await new Promise(ok => server.listen(0, '127.0.0.1', ok)); t.after(() => new Promise(ok => server.close(ok)));
  const port = server.address().port;
  await assert.rejects(connectSftp({ host: '127.0.0.1', port, username: 'docs', password: 'test-only', readyTimeout: 300,
    hostVerifier: hostVerifier(`[127.0.0.1]:${port} ssh-ed25519 ${publicKey.toString('base64')}`, '127.0.0.1', port) }), /closed before authentication/);
});
test('real SFTP uploads dev files with web modes and refuses unsafe replacement without the rename extension', async t => {
  const temporary = await mkdtemp(join(tmpdir(), 'perfchecker-sftp-wire-'));
  t.after(() => rm(temporary, { recursive: true, force: true }));
  const { execFileSync } = await import('node:child_process');
  const fs = await import('node:fs/promises'), { constants } = await import('node:fs');
  execFileSync('ssh-keygen', ['-q', '-t', 'ed25519', '-N', '', '-f', join(temporary, 'key')]);
  const key = await readFile(join(temporary, 'key')), publicKey = utils.parseKey(key).getPublicSSH();
  const remote = join(temporary, 'remote'); await mkdir(join(remote, 'www'), { recursive: true });
  const path = value => { assert.ok(value.startsWith('/www') && !value.split('/').includes('..')); return join(remote, value); };
  const attrs = stat => ({ mode: stat.mode, uid: stat.uid, gid: stat.gid, size: stat.size,
    atime: Math.floor(stat.atimeMs / 1000), mtime: Math.floor(stat.mtimeMs / 1000) });
  let execs = 0, renames = 0;
  const server = new Server({ hostKeys: [key] }, client => {
    client.on('error', () => {});
    client.on('authentication', ctx => ctx.method === 'password' && ctx.password === 'test-only' ? ctx.accept() : ctx.reject());
    client.on('ready', () => client.on('session', accept => {
      const session = accept(); session.on('exec', (_, reject) => { execs++; reject(); });
      session.on('sftp', acceptSftp => {
        const stream = acceptSftp(), handles = new Map(); let count = 0;
        const handle = buffer => { const result = handles.get(buffer.toString('hex')); assert.ok(result); return result; };
        const operation = (id, fn) => Promise.resolve().then(fn).catch(error =>
          stream.status(id, error.code === 'ENOENT' ? 2 : error.code === 'EACCES' ? 3 : 4));
        stream.on('LSTAT', (id, name) => operation(id, async () => stream.attrs(id, attrs(await fs.lstat(path(name))))));
        stream.on('STAT', (id, name) => operation(id, async () => stream.attrs(id, attrs(await fs.stat(path(name))))));
        stream.on('MKDIR', (id, name, mode) => operation(id, async () => { await fs.mkdir(path(name), mode); stream.status(id, 0); }));
        stream.on('RMDIR', (id, name) => operation(id, async () => { await fs.rmdir(path(name)); stream.status(id, 0); }));
        stream.on('REMOVE', (id, name) => operation(id, async () => { await fs.unlink(path(name)); stream.status(id, 0); }));
        stream.on('SETSTAT', (id, name, mode) => operation(id, async () => { await fs.chmod(path(name), mode.mode); stream.status(id, 0); }));
        stream.on('OPEN', (id, name, flags, mode) => operation(id, async () => {
          let f = flags & 2 ? flags & 1 ? constants.O_RDWR : constants.O_WRONLY : constants.O_RDONLY;
          if (flags & 4) f |= constants.O_APPEND; if (flags & 8) f |= constants.O_CREAT;
          if (flags & 16) f |= constants.O_TRUNC; if (flags & 32) f |= constants.O_EXCL;
          const file = await fs.open(path(name), f, mode.mode); const buffer = Buffer.alloc(4); buffer.writeUInt32BE(++count);
          handles.set(buffer.toString('hex'), file); stream.handle(id, buffer);
        }));
        stream.on('FSTAT', (id, buffer) => operation(id, async () => stream.attrs(id, attrs(await handle(buffer).stat()))));
        stream.on('READ', (id, buffer, offset, length) => operation(id, async () => {
          const data = Buffer.alloc(length), { bytesRead } = await handle(buffer).read(data, 0, length, offset);
          if (bytesRead) stream.data(id, data.subarray(0, bytesRead)); else stream.status(id, 1);
        }));
        stream.on('WRITE', (id, buffer, offset, data) => operation(id, async () => {
          await handle(buffer).write(data, 0, data.length, offset); stream.status(id, 0);
        }));
        stream.on('CLOSE', (id, buffer) => operation(id, async () => {
          await handle(buffer).close(); handles.delete(buffer.toString('hex')); stream.status(id, 0);
        }));
        stream.on('RENAME', (id, from, to) => operation(id, async () => { await fs.rename(path(from), path(to)); renames++; stream.status(id, 0); }));
      });
    }));
  });
  await new Promise(ok => server.listen(0, '127.0.0.1', ok)); t.after(() => new Promise(ok => server.close(ok)));
  const port = server.address().port;
  const transport = await connectSftp({ host: '127.0.0.1', port, username: 'docs', password: 'test-only', readyTimeout: 1000,
    hostVerifier: hostVerifier(`[127.0.0.1]:${port} ssh-ed25519 ${publicKey.toString('base64')}`, '127.0.0.1', port) });
  t.after(() => transport.close());
  const exports = await exportsFor(t), options = { root: '/www', channel: 'dev', revision, sequence: 1, site: exports.dev };
  await publishDocumentation(transport, options);
  const installed = join(remote, 'www/dev/index.html');
  assert.match(await readFile(installed, 'utf8'), /index 1.0.0 dev/);
  assert.equal((await fs.stat(installed)).mode & 0o777, 0o644);
  assert.equal((await fs.stat(join(remote, 'www/dev'))).mode & 0o777, 0o755);
  assert.ok(renames > 0); assert.equal(execs, 0);
  await assert.rejects(publishDocumentation(transport, { ...options, sequence: 2 }), /needs posix-rename/);
  assert.match(await readFile(installed, 'utf8'), /index 1.0.0 dev/);
  transport.close();
});

test('SFTP preflight accepts actual search chunks while rejecting controls and separators', async t => {
  const exports = await exportsFor(t);
  const prepared = await validateDocumentationExports(release(exports));
  assert.ok(prepared.primary.files.some(file => file.path === 'assets/chunks/@localSearchIndexroot.fixture.js'));
  for (const name of ['bad name.js', 'bad\\name.js', 'bad\nname.js']) {
    await writeFile(join(exports.site, 'assets', name), 'unsafe');
    await assert.rejects(readExport(exports.site, 'version', revision, 'v1.0.0'), /Unsafe export filename/);
    await rm(join(exports.site, 'assets', name));
  }
  await writeFile(join(exports.stableSite, 'build-info.json'), '{}');
  await assert.rejects(validateDocumentationExports(release(exports)), /source or channel/);
});
test('PR prerelease previews validate paths while stable publication requires a matching stable tag', async t => {
  const exports = await exportsFor(t, '1.0.1-DEV');
  await readExport(exports.site, 'version', revision);
  await readExport(exports.stableSite, 'stable', revision);
  await assert.rejects(validateDocumentationExports(release(exports, 'v1.0.1')), /version differs/);
  await assert.rejects(validateDocumentationExports(release(exports, 'v1.0.1-DEV')), /Invalid release tag/);
});
test('failure diagnostics never log arbitrary server error codes or names', () => {
  assert.equal(failureClass({code:'secret-value',name:'secret-value',message:'secret-value'}), 'validation-or-transport');
  assert.equal(failureClass({code:'__proto__'}), 'validation-or-transport');
  assert.equal(failureClass({code:'ENOENT'}), 'missing-local-file');
  assert.equal(failureClass({code:3}), 'remote-permission');
});
