import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, readFile, rm, symlink } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, posix } from 'node:path';
import { createHash, createHmac } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import ssh2 from 'ssh2';
const { Server, utils } = ssh2;
import { hostVerifier, validateRoot, readExport, publishDocumentation, connectSftp,
  deploymentConfiguration, documentationSourceConfiguration, validateDocumentationExports,
  validateStableDocumentationSource, fetchStableDocumentationCompanions, validateDocumentationRenderer,
  recovery111, recovery111After3h, recoveryContext, validateRecoveryOrigin, validateRecoveryContinuation, verifyRecoveryOrigin, recoveryOptions, recoveryDownloadUrl,
  writeVerifiedRecoveryArchive, inspectRecoveryDestination, reclaimRecoveryLock, validateRecoveryPlanArtifact,
  failureClass } from './deploy-sftp.mjs';
const revision = 'a'.repeat(40), nextRevision = 'b'.repeat(40);
class MemorySftp {
  constructor() {
    this.files = new Map(); this.dirs = new Map([['/www', 0o755]]); this.operations = []; this.fail = null;
    this.metadata = new Map(); this.links = new Set(); this.removed = [];
  }
  async stat(path) {
    if (!this.files.has(path) && !this.dirs.has(path)) return null;
    return { ...this.metadata.get(path), isFile: () => this.files.has(path), isDirectory: () => this.dirs.has(path),
      isSymbolicLink: () => this.links.has(path) };
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
  async readdir(path) {
    return [...new Set([...this.files.keys(), ...this.dirs.keys()].filter(item => posix.dirname(item) === path))]
      .map(item => ({ filename: posix.basename(item) }));
  }
  async rmdir(path) {
    if ((await this.readdir(path)).length) throw new Error('not empty');
    this.removed.push(path); this.dirs.delete(path);
  }
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
const recoveryEnv = () => ({ GITHUB_ACTIONS: 'true', GITHUB_EVENT_NAME: 'workflow_dispatch', GITHUB_REF: 'refs/heads/main',
  GITHUB_REPOSITORY: recovery111.repository, GITHUB_SHA: nextRevision, GITHUB_RUN_ID: '90000000001', GITHUB_RUN_ATTEMPT: '1',
  PERFCHECKER_DOCS_RECOVERY: 'recover-1.1.1' });
const recoveryOrigin = () => ({
  recoveryRun: { id: 90000000001, event: 'workflow_dispatch', head_branch: 'main', head_sha: nextRevision,
    path: '.github/workflows/Documentation.yml', run_attempt: 1, status: 'in_progress' },
  run: { id: recovery111.run, head_sha: recovery111.revision, head_branch: recovery111.version, event: 'push',
    path: '.github/workflows/Documentation.yml', run_attempt: 1, status: 'completed', conclusion: 'cancelled' },
  producer: { id: recovery111.producerJob, run_id: recovery111.run, head_sha: recovery111.revision, run_attempt: 1, status: 'completed', conclusion: 'success' },
  publisher: { id: recovery111.publisherJob, run_id: recovery111.run, head_sha: recovery111.revision, run_attempt: 1, status: 'completed', conclusion: 'cancelled',
    started_at: recovery111.publisherStarted, completed_at: recovery111.publisherCompleted },
  artifact: { id: recovery111.artifact, name: recovery111.name, expired: false, size_in_bytes: recovery111.bytes,
    digest: `sha256:${recovery111.sha256}`, workflow_run: { id: recovery111.run, head_sha: recovery111.revision } },
  commit: { sha: recovery111.revision, commit: { tree: { sha: recovery111.tree } } },
  tag: { sha: recovery111.revision, commit: { tree: { sha: recovery111.tree } } },
  annotations: [{ annotation_level: 'failure', message: 'The job has exceeded the maximum execution time of 2h0m0s' }], publishers: []
});
const previousRecovery = () => {
  const previous = recovery111After3h;
  return {
    run: { id: previous.run, head_sha: previous.revision, head_branch: 'main', event: 'workflow_dispatch',
      path: '.github/workflows/Documentation.yml', run_attempt: 1, status: 'completed', conclusion: 'cancelled' },
    job: { id: previous.job, run_id: previous.run, head_sha: previous.revision, run_attempt: 1,
      name: 'Recover the retained v1.1.1 documentation exports', status: 'completed', conclusion: 'cancelled',
      started_at: previous.started, completed_at: previous.completed },
    commit: { sha: previous.revision, commit: { tree: { sha: previous.tree } } },
    annotations: [{ annotation_level: 'failure', message: 'The job has exceeded the maximum execution time of 3h0m0s' }],
    artifact: { id: previous.inspectionArtifact, name: 'documentation-recovery-111-inspection', expired: false,
      size_in_bytes: previous.inspectionBytes, digest: `sha256:${previous.inspectionSha256}`,
      workflow_run: { id: previous.run, head_sha: previous.revision } },
    log: [previous.inspectionLog, previous.uploadLog, previous.cancelledLog, ''].join('\n')
  };
};
const continuationOrigin = () => ({ ...recoveryOrigin(), previousRecovery: previousRecovery() });
const continuationContext = () => recoveryContext({ ...recoveryEnv(), PERFCHECKER_DOCS_RECOVERY: 'recover-1.1.1-after-3h' });
test('the continuation keeps the original export and requires the exact previous cancellation, source and saved receipt', () => {
  const context = continuationContext(), data = continuationOrigin();
  const proof = validateRecoveryOrigin(data, context);
  assert.equal(proof.sourceRun, recovery111.run); assert.equal(proof.artifactId, recovery111.artifact);
  assert.equal(proof.sourceRevision, recovery111.revision); assert.equal(proof.previousRecoveryRun, recovery111After3h.run);
  assert(Object.values(proof).every(value => ['string', 'number', 'boolean'].includes(typeof value)));
  assert.throws(() => recoveryContext({ ...recoveryEnv(), PERFCHECKER_DOCS_RECOVERY: 'recover-1.1.1-after-3h',
    PERFCHECKER_RECOVERY_RECLAIM_LOCK: 'true' }), /original cancellation-lock opt-in/);
  assert.throws(() => recoveryContext({ ...recoveryEnv(), GITHUB_RUN_ID: String(recovery111After3h.run) }));
  const changes = [d => d.run.id++, d => d.run.head_sha = revision, d => d.run.head_branch = 'other',
    d => d.run.event = 'push', d => d.run.path = 'other', d => d.run.run_attempt++, d => d.run.status = 'in_progress',
    d => d.run.conclusion = 'failure', d => d.job.id++, d => d.job.run_id++, d => d.job.head_sha = revision,
    d => d.job.run_attempt++, d => d.job.name = 'other', d => d.job.conclusion = 'success',
    d => d.job.started_at = recovery111.publisherStarted, d => d.job.completed_at = recovery111.publisherCompleted,
    d => d.commit.sha = revision, d => d.commit.commit.tree.sha = revision, d => d.annotations = [],
    d => d.annotations[0].message = 'The job has exceeded the maximum execution time of 2h0m0s',
    d => d.artifact.id++, d => d.artifact.expired = true, d => d.artifact.size_in_bytes--,
    d => d.artifact.digest = `sha256:${'a'.repeat(64)}`, d => d.artifact.workflow_run.id++,
    d => d.artifact.workflow_run.head_sha = revision];
  for (const change of changes) { const altered = previousRecovery(); change(altered); assert.throws(() => validateRecoveryContinuation(altered)); }
  assert.throws(() => validateRecoveryOrigin(recoveryOrigin(), context));
  data.publishers.push({ run_id: 123, name: 'Recover the retained v1.1.1 documentation exports', status: 'in_progress' });
  assert.throws(() => validateRecoveryOrigin(data, context), /Another documentation publisher/);
});
test('the continuation refuses absent, ambiguous, reordered or completed transfer journal evidence', () => {
  const previous = recovery111After3h, original = previousRecovery();
  for (const log of ['', original.log.replace(previous.uploadLog, ''), original.log + previous.inspectionLog,
    [previous.uploadLog, previous.inspectionLog, previous.cancelledLog].join('\n'),
    original.log + '\nRetained export recovery completed; stable=v1.1.1',
    original.log + '\nUploading version: 7151 files', 'x'.repeat(1024 * 1024 + 1)])
    assert.throws(() => validateRecoveryContinuation({ ...original, log }));
  assert.match(validateRecoveryContinuation(original).previousRecoveryLogSha256, /^[a-f0-9]{64}$/);
});
test('the continuation reads only fixed GitHub journal metadata and never forwards its token to storage', async t => {
  const original = recoveryOrigin(), previous = previousRecovery(), base = `https://api.github.com/repos/${recovery111.repository}/`;
  const previousCheck = `${base}check-runs/${recovery111After3h.job}`;
  const metadata = new Map([
    [`actions/runs/${recovery111.run}`, original.run], [`actions/jobs/${recovery111.producerJob}`, original.producer],
    [`actions/jobs/${recovery111.publisherJob}`, { ...original.publisher, check_run_url: `${base}check-runs/123` }],
    [`actions/artifacts/${recovery111.artifact}`, original.artifact], [`commits/${recovery111.revision}`, original.commit],
    [`commits/${recovery111.version}`, original.tag], ['actions/runs/90000000001', original.recoveryRun],
    ['check-runs/123/annotations?per_page=100', original.annotations],
    [`actions/runs/${recovery111After3h.run}`, previous.run],
    [`actions/jobs/${recovery111After3h.job}`, { ...previous.job, check_run_url: previousCheck }],
    [`commits/${recovery111After3h.revision}`, previous.commit],
    [`actions/artifacts/${recovery111After3h.inspectionArtifact}`, previous.artifact],
    [`check-runs/${recovery111After3h.job}/annotations?per_page=100`, previous.annotations]
  ]);
  const storage = 'https://fixture.blob.core.windows.net/previous-journal', calls = [];
  let redirect = storage, log = previous.log;
  t.mock.method(globalThis, 'fetch', async (url, options) => {
    const address = String(url); calls.push({ address, authorization: options.headers?.Authorization });
    if (address === storage) { assert.equal(options.headers, undefined); assert.equal(options.redirect, 'error'); return new Response(log); }
    assert(address.startsWith(base)); assert.equal(options.headers.Authorization, 'Bearer fixture-read-only-token');
    const path = address.slice(base.length);
    if (path === `actions/jobs/${recovery111After3h.job}/logs`) {
      assert.equal(options.redirect, 'manual'); return new Response(null, { status: 302, headers: { location: redirect } });
    }
    if (path.startsWith('actions/workflows/Documentation.yml/runs?'))
      return Response.json({ total_count: 0, workflow_runs: [] });
    assert(metadata.has(path), `Unexpected metadata request: ${path}`); return Response.json(metadata.get(path));
  });
  const env = { ...recoveryEnv(), GH_TOKEN: 'fixture-read-only-token', PERFCHECKER_DOCS_RECOVERY: 'recover-1.1.1-after-3h' };
  const proof = await verifyRecoveryOrigin(env);
  assert.equal(proof.previousRecoveryRun, recovery111After3h.run);
  assert.equal(calls.filter(call => call.address === storage).length, 1);
  assert(!calls.some(call => call.address.includes(`/actions/artifacts/${recovery111After3h.inspectionArtifact}/zip`)));
  redirect = 'https://untrusted.invalid/journal'; await assert.rejects(verifyRecoveryOrigin(env), /storage URL/);
  assert(!calls.some(call => call.address.startsWith('https://untrusted.invalid/')));
  redirect = storage; log = 'x'.repeat(1024 * 1024 + 1);
  await assert.rejects(verifyRecoveryOrigin(env), /size limit/);
});
test('artifact-only recovery retains the actual dispatch identity and refuses arbitrary sources or attempts', () => {
  const env = recoveryEnv(), context = recoveryContext(env);
  assert.deepEqual(context, { workflowRevision: nextRevision, recoveryRun: 90000000001 });
  for (const change of [{ GITHUB_EVENT_NAME: 'push' }, { GITHUB_REF: 'refs/tags/v1.1.1' }, { GITHUB_ACTIONS: 'false' },
    { GITHUB_REPOSITORY: 'other/repository' }, { GITHUB_RUN_ID: String(recovery111.run) }, { GITHUB_RUN_ATTEMPT: '2' },
    { GITHUB_SHA: 'main' }, { PERFCHECKER_DOCS_RECOVERY: 'recover-any' }, { PERFCHECKER_DOCS_SOURCE_VERSION: 'v1.1.1' },
    { PERFCHECKER_DOCS_SOURCE_REVISION: recovery111.revision }, { PERFCHECKER_DOCS_STABLE_REFRESH: 'true' }])
    assert.throws(() => recoveryContext({ ...env, ...change }));
  const identity = validateRecoveryOrigin(recoveryOrigin(), context);
  assert.equal(identity.sourceRevision, recovery111.revision); assert.equal(identity.workflowRevision, nextRevision);
  const changes = [data => data.run.head_sha = revision, data => data.run.path = '.github/workflows/Other.yml',
    data => data.recoveryRun.head_sha = recovery111.revision, data => data.recoveryRun.event = 'push',
    data => data.recoveryRun.head_branch = 'other', data => data.recoveryRun.run_attempt = 2,
    data => data.run.conclusion = 'success', data => data.run.run_attempt = 2, data => data.producer.conclusion = 'failure',
    data => data.producer.head_sha = revision, data => data.publisher.head_sha = revision,
    data => data.publisher.status = 'in_progress', data => data.publisher.completed_at = '2026-10-14T10:00:00Z',
    data => data.artifact.expired = true, data => data.artifact.id++, data => data.artifact.size_in_bytes--,
    data => data.artifact.digest = `sha256:${'a'.repeat(64)}`, data => data.artifact.workflow_run.head_sha = revision,
    data => data.tag.commit.tree.sha = revision, data => data.commit.sha = revision, data => data.annotations = [],
    data => data.publishers.push({ run_id: 123, name: 'Publish canonical documentation through SFTP', status: 'in_progress' }),
    data => data.publishers.push({ run_id: 123, name: 'Recover the retained v1.1.1 documentation exports', status: 'in_progress' })];
  for (const change of changes) { const data = recoveryOrigin(); change(data); assert.throws(() => validateRecoveryOrigin(data, context)); }
});
test('recovery configuration validates real main credentials without impersonating the tag event', () => {
  const key = Buffer.alloc(32, 1).toString('base64');
  const env = { ...recoveryEnv(), GITHUB_RUN_NUMBER: '100', PERFCHECKER_DOCS_SFTP_DEPLOY: 'true',
    PERFCHECKER_DOCS_SFTP_HOST: 'fixture.invalid', PERFCHECKER_DOCS_SFTP_USER: 'docs', PERFCHECKER_DOCS_SFTP_ROOT: '/www',
    PERFCHECKER_DOCS_SFTP_PASSWORD: 'fixture-only', PERFCHECKER_DOCS_SFTP_KNOWN_HOSTS: `fixture.invalid ssh-ed25519 ${key}` };
  const before = { ...env }, options = recoveryOptions(env);
  assert.deepEqual(env, before); assert.equal(deploymentConfiguration(env).channel, 'dev');
  assert.equal(options.channel, 'release'); assert.equal(options.recovery, true);
  assert.equal(options.revision, recovery111.revision); assert.equal(options.workflowRevision, nextRevision);
  assert.equal(options.reclaimCancelledLock, false);
  assert.equal(recoveryOptions({ ...env, PERFCHECKER_RECOVERY_RECLAIM_LOCK: 'true' }).reclaimCancelledLock, true);
  for (const changed of [{ PERFCHECKER_DOCS_SFTP_DEPLOY: 'false' }, { PERFCHECKER_DOCS_SFTP_KNOWN_HOSTS: '' },
    { PERFCHECKER_DOCS_SFTP_ROOT: '/www/../other' }]) assert.throws(() => recoveryOptions({ ...env, ...changed }));
});
test('recovery downloads hash the streamed ZIP bytes and never accept arbitrary storage URLs', async t => {
  const root = await mkdtemp(join(tmpdir(), 'perfchecker-doc-zip-')); t.after(() => rm(root, { recursive: true, force: true }));
  const bytes = Buffer.from('original retained artifact fixture'), expected = { bytes: bytes.length,
    sha256: createHash('sha256').update(bytes).digest('hex') };
  assert.deepEqual(await writeVerifiedRecoveryArchive(new Response(bytes), join(root, 'archive.zip'), expected), expected);
  assert.deepEqual(await readFile(join(root, 'archive.zip')), bytes);
  await assert.rejects(writeVerifiedRecoveryArchive(new Response(bytes), join(root, 'archive.zip'), expected), /EEXIST/);
  for (const [name, receipt] of [['long', { ...expected, bytes: bytes.length - 1 }],
    ['short', { ...expected, bytes: bytes.length + 1 }], ['digest', { ...expected, sha256: '0'.repeat(64) }]])
    await assert.rejects(writeVerifiedRecoveryArchive(new Response(bytes), join(root, name), receipt), /byte|digest/);
  assert.equal(recoveryDownloadUrl('https://fixture.blob.core.windows.net/artifact?sig=fixture').protocol, 'https:');
  for (const url of ['http://fixture.blob.core.windows.net/a', 'https://github.com/a',
    'https://fixture.blob.core.windows.net.evil.invalid/a', 'https://user@fixture.blob.core.windows.net/a',
    'https://fixture.blob.core.windows.net:444/a']) assert.throws(() => recoveryDownloadUrl(url));
});
test('a saved inspection receipt must belong to the actual new recovery run', () => {
  const context = recoveryContext(recoveryEnv()), artifact = { id: 123, name: 'documentation-recovery-111-inspection',
    size_in_bytes: 100, expired: false, digest: `sha256:${'c'.repeat(64)}`, workflow_run: { id: context.recoveryRun, head_sha: context.workflowRevision } };
  validateRecoveryPlanArtifact(artifact, context, 'c'.repeat(64));
  for (const changed of [{ name: recovery111.name }, { expired: true }, { digest: null }, { id: 0 },
    { size_in_bytes: 0 }, { workflow_run: { id: recovery111.run, head_sha: recovery111.revision } }])
    assert.throws(() => validateRecoveryPlanArtifact({ ...artifact, ...changed }, context, 'c'.repeat(64)));
  assert.throws(() => validateRecoveryPlanArtifact(artifact, context, 'd'.repeat(64)));
});
async function recoverableDestination(t) {
  const exports = await exportsFor(t, '1.1.1', recovery111.revision), sftp = new MemorySftp();
  await publishDocumentation(sftp, release(await exportsFor(t)));
  sftp.fail = path => path === '/www/guide.html';
  await assert.rejects(publishDocumentation(sftp, release(exports, recovery111.version, recovery111.revision)), /injected/);
  sftp.fail = null;
  const options = { ...release(exports, recovery111.version, recovery111.revision), recovery: true, reclaimCancelledLock: true };
  options.validatedExports = await validateDocumentationExports(options);
  return { sftp, options };
}
test('retained-archive recovery resumes only stable files and preserves the original archive byte for byte', async t => {
  const { sftp, options } = await recoverableDestination(t);
  const archive = new Map([...sftp.files].filter(([path]) => path.startsWith('/www/v1.1.1/'))
    .map(([path, file]) => [path, Buffer.from(file.bytes)]));
  const inspected = await inspectRecoveryDestination(sftp, options);
  assert.equal(inspected.committed.value.version, 'v1.0.0'); assert.equal(inspected.lock, null);
  sftp.operations = [];
  await publishDocumentation(sftp, options);
  assert(sftp.operations.includes('/www/guide.html'));
  assert(!sftp.operations.some(path => path.startsWith('/www/v1.1.1/')));
  for (const [path, bytes] of archive) assert.deepEqual(sftp.files.get(path).bytes, bytes);
  assert.equal(JSON.parse(sftp.files.get('/www/.perfchecker-stable.json').bytes).version, recovery111.version);
  assert.equal(JSON.parse(sftp.files.get('/www/.perfchecker-releases.json').bytes).stable, recovery111.version);
  sftp.operations = []; await publishDocumentation(sftp, options);
  assert(!sftp.operations.some(path => path.startsWith('/www/v1.1.1/') || path.endsWith('/guide.html')));
  assert(sftp.operations.includes('/www/versions.js'));
});
test('recovery inspects only the exact cancelled empty real lock and refuses changed or ambiguous ownership', async t => {
  const { sftp, options } = await recoverableDestination(t), lock = '/www/.perfchecker-docs-lock';
  const mtime = Date.parse(recovery111.publisherStarted) / 1000 + 60;
  await sftp.mkdir(lock); sftp.metadata.set(lock, { mtime, mode: 0o40755, uid: 1000, gid: 1000 });
  const before = new Map(sftp.files), inspected = await inspectRecoveryDestination(sftp, options);
  assert.equal(inspected.lock.mtime, mtime); assert.deepEqual(sftp.files, before);
  await assert.rejects(reclaimRecoveryLock(sftp, { ...options, reclaimCancelledLock: false }, inspected.lock), /opt-in/);
  sftp.metadata.get(lock).mtime++;
  await assert.rejects(reclaimRecoveryLock(sftp, options, inspected.lock), /changed/); sftp.metadata.get(lock).mtime = mtime;
  await sftp.write(posix.join(lock, 'owner'), 'unexpected');
  await assert.rejects(inspectRecoveryDestination(sftp, options), /nonempty/); await sftp.unlink(posix.join(lock, 'owner'));
  sftp.links.add(lock); await assert.rejects(inspectRecoveryDestination(sftp, options), /symbolic link/); sftp.links.delete(lock);
  for (const invalid of [undefined, mtime - 100000, Date.parse(recovery111.publisherCompleted) / 1000 + 1]) {
    sftp.metadata.get(lock).mtime = invalid; await assert.rejects(inspectRecoveryDestination(sftp, options), /time/);
  }
  sftp.metadata.get(lock).mtime = mtime;
  assert.equal(await reclaimRecoveryLock(sftp, options, inspected.lock), true); assert(!sftp.dirs.has(lock));
  assert.equal(await reclaimRecoveryLock(sftp, options, null), false);
  // A new owner winning the atomic mkdir is still protected by the usual lock.
  await sftp.mkdir(lock); await assert.rejects(publishDocumentation(sftp, options), /holds the SFTP lock/);
});
test('the later empty lock needs the full verified cancellation evidence and separate opt-in, not its timestamp alone', async t => {
  const { sftp, options } = await recoverableDestination(t), lock = '/www/.perfchecker-docs-lock', previous = recovery111After3h;
  const proof = validateRecoveryOrigin(continuationOrigin(), continuationContext());
  const later = { ...options, ...continuationContext(), continuationProof: proof };
  await sftp.mkdir(lock);
  const metadata = { mtime: Date.parse(previous.lockEarliest) / 1000 + 30, mode: previous.lockMode, uid: previous.lockUid, gid: previous.lockGid };
  sftp.metadata.set(lock, { ...metadata });
  const removedBeforeInspection = [...sftp.removed];
  // The original route must continue refusing the later cancellation window.
  await assert.rejects(inspectRecoveryDestination(sftp, options), /time/);
  await assert.rejects(inspectRecoveryDestination(sftp, { ...later, continuationProof: undefined }), /verified previous/);
  const inspected = await inspectRecoveryDestination(sftp, later);
  assert.equal(inspected.lock.mtime, metadata.mtime); assert.deepEqual(sftp.removed, removedBeforeInspection);
  await assert.rejects(reclaimRecoveryLock(sftp, { ...later, reclaimCancelledLock: false }, inspected.lock), /opt-in/);
  for (const change of [{ mode: 0o40700 }, { uid: 0 }, { gid: 0 }, { mtime: Date.parse(previous.lockEarliest) / 1000 - 1 },
    { mtime: Date.parse(previous.lockLatest) / 1000 + 1 }]) {
    sftp.metadata.set(lock, { ...metadata, ...change }); await assert.rejects(inspectRecoveryDestination(sftp, later));
  }
  sftp.metadata.set(lock, { ...metadata });
  await sftp.write(posix.join(lock, 'unexpected'), 'never remove');
  await assert.rejects(inspectRecoveryDestination(sftp, later), /nonempty/); await sftp.unlink(posix.join(lock, 'unexpected'));
  sftp.links.add(lock); await assert.rejects(inspectRecoveryDestination(sftp, later), /symbolic link/); sftp.links.delete(lock);
  sftp.metadata.set(lock, { ...metadata, mtime: metadata.mtime + 1 });
  await assert.rejects(reclaimRecoveryLock(sftp, later, inspected.lock), /changed/);
  sftp.metadata.set(lock, { ...metadata });
  assert.equal(await reclaimRecoveryLock(sftp, later, inspected.lock), true);
  await assert.rejects(reclaimRecoveryLock(sftp, later, inspected.lock), /changed/);
  assert.equal(await reclaimRecoveryLock(sftp, later, null), false);
  await sftp.mkdir(lock); await assert.rejects(publishDocumentation(sftp, later), /Another documentation publisher/);
});
test('the continuation recopies stable completely, writes markers last and never mutates any version-archive path', async t => {
  const { sftp, options } = await recoverableDestination(t);
  const later = { ...options, ...continuationContext(), continuationProof: validateRecoveryOrigin(continuationOrigin(), continuationContext()) };
  const archive = new Map([...sftp.files].filter(([path]) => path.startsWith('/www/v1.1.1/'))
    .map(([path, file]) => [path, Buffer.from(file.bytes)]));
  const mutations = [];
  for (const method of ['mkdir', 'chmod', 'write', 'put', 'replace', 'unlink', 'rmdir']) {
    const original = sftp[method].bind(sftp);
    sftp[method] = async (...args) => {
      const paths = method === 'put' ? [args[1]] : method === 'replace' ? args.slice(0, 2) : [args[0]];
      mutations.push(...paths); return original(...args);
    };
  }
  sftp.operations = [];
  sftp.fail = path => path === '/www/guide.html';
  await assert.rejects(publishDocumentation(sftp, later), /injected/);
  assert.equal(JSON.parse(sftp.files.get('/www/.perfchecker-stable.json').bytes).version, 'v1.0.0');
  sftp.fail = null; await publishDocumentation(sftp, later);
  for (const path of ['assets/app.js', 'assets/chunks/@localSearchIndexroot.fixture.js', 'build-info.json', 'guide.html', 'index.html', 'siteinfo.js'])
    assert(sftp.operations.includes('/www/' + path));
  const stableMarker = sftp.operations.indexOf('/www/.perfchecker-stable.json');
  assert(stableMarker > sftp.operations.lastIndexOf('/www/index.html'));
  assert(sftp.operations.lastIndexOf('/www/.perfchecker-releases.json') > stableMarker);
  assert(sftp.operations.lastIndexOf('/www/versions.js') > stableMarker);
  assert(!mutations.some(path => path === '/www/v1.1.1' || path.startsWith('/www/v1.1.1/')));
  for (const [path, bytes] of archive) assert.deepEqual(sftp.files.get(path).bytes, bytes);
});
test('recovery refuses missing or different archive markers, newer releases and stable refreshes before writing', async t => {
  const { sftp, options } = await recoverableDestination(t);
  const marker = '/www/v1.1.1/.perfchecker-docs.json', original = sftp.files.get(marker);
  await sftp.unlink(marker); await assert.rejects(inspectRecoveryDestination(sftp, options), /matching completed/);
  sftp.files.set(marker, original); sftp.links.add(marker);
  await assert.rejects(inspectRecoveryDestination(sftp, options), /regular file/); sftp.links.delete(marker);
  const mutations = [
    ['/www/.perfchecker-promotion.json', { version: 'v1.1.2', revision, digest: 'a'.repeat(64) }],
    ['/www/.perfchecker-stable.json', { version: 'v1.1.2', revision, digest: 'a'.repeat(64) }],
    ['/www/.perfchecker-stable-refresh.json', { version: recovery111.version, revision, digest: 'a'.repeat(64), sequence: 30, status: 'pending' }],
    [marker, { revision, digest: 'a'.repeat(64) }]
  ];
  for (const [path, value] of mutations) {
    const prior = sftp.files.get(path); await sftp.write(path, JSON.stringify(value)); sftp.operations = [];
    await assert.rejects(publishDocumentation(sftp, options)); assert.deepEqual(sftp.operations, []);
    if (prior) sftp.files.set(path, prior); else sftp.files.delete(path);
  }
  await assert.rejects(publishDocumentation(sftp, { ...options, version: 'v1.1.2' }), /restricted/);
});
test('recovery refuses a missing remote catalogue without any SFTP writes or reconstruction', async t => {
  const { sftp, options } = await recoverableDestination(t), catalogue = '/www/.perfchecker-releases.json';
  await sftp.unlink(catalogue);
  const before = new Map(sftp.files), mutations = [];
  for (const method of ['mkdir', 'chmod', 'put', 'write', 'replace', 'unlink', 'rmdir']) {
    const original = sftp[method].bind(sftp);
    sftp[method] = async (...args) => { mutations.push(method); return original(...args); };
  }
  await assert.rejects(inspectRecoveryDestination(sftp, options), /Invalid remote publication state/);
  assert.deepEqual(mutations, []); assert.deepEqual(sftp.files, before);
  assert.equal(await sftp.stat(catalogue), null);
});
test('a failure during retained-export recovery keeps the old catalogue and can resume without archive writes', async t => {
  const { sftp, options } = await recoverableDestination(t), catalogue = Buffer.from(sftp.files.get('/www/versions.js').bytes);
  sftp.operations = []; sftp.fail = path => path === '/www/index.html';
  await assert.rejects(publishDocumentation(sftp, options), /injected/);
  assert.deepEqual(sftp.files.get('/www/versions.js').bytes, catalogue);
  assert.equal(JSON.parse(sftp.files.get('/www/.perfchecker-stable.json').bytes).version, 'v1.0.0');
  assert(!sftp.operations.some(path => path.startsWith('/www/v1.1.1/')));
  sftp.fail = null; await publishDocumentation(sftp, options);
  assert.equal(JSON.parse(sftp.files.get('/www/.perfchecker-stable.json').bytes).version, recovery111.version);
});
test('the recovery workflow skips producers, retains the publisher mutex and saves its receipt before applying', async () => {
  const workflow = await readFile(new URL('../.github/workflows/Documentation.yml', import.meta.url), 'utf8');
  assert.match(workflow, /options: \[dev, stable, recover-1\.1\.1, recover-1\.1\.1-after-3h\]/);
  const build = workflow.split('  documentation:\n')[1].split('  sftp:\n')[0];
  assert.match(build, /if: github\.event\.deleted != true && !\(github\.event_name == 'workflow_dispatch' && \(inputs\.publication == 'recover-1\.1\.1' \|\| inputs\.publication == 'recover-1\.1\.1-after-3h' \|\| inputs\.reviewed_export_asset != ''\)\)/);
  const reviewed = workflow.split('  publish-reviewed:\n')[1].split('  recover-111:\n')[0];
  assert.match(reviewed, /github\.event_name == 'workflow_dispatch' && github\.ref == 'refs\/heads\/main'/);
  assert.match(reviewed, /inputs\.publication == 'stable' && inputs\.reviewed_export_asset != ''/);
  assert.match(reviewed, /group: perfchecker-documentation-sftp/);
  assert.match(reviewed, /cancel-in-progress: false/);
  assert(!/needs: documentation|npm run test|website\/make\.jl/.test(reviewed));
  const recovery = workflow.split('  recover-111:\n')[1];
  assert(recovery); assert.match(recovery, /timeout-minutes: \$\{\{ inputs\.publication == 'recover-1\.1\.1-after-3h' && 360 \|\| 180 \}\}/);
  assert.match(recovery, /PERFCHECKER_RECOVERY_RECLAIM_AFTER3H_LOCK: \$\{\{ inputs\.reclaim_3h_recovery_lock \}\}/);
  assert.match(recovery, /environment: documentation-sftp/); assert.match(recovery, /group: perfchecker-documentation-sftp/);
  assert.match(recovery, /cancel-in-progress: false/); assert.match(recovery, /ref: \$\{\{ github\.sha \}\}/);
  assert(!/julia|website\/make\.jl|GITHUB_SHA\s*:|GITHUB_EVENT_NAME\s*:|actions\/download-artifact/.test(recovery));
  const verify = recovery.indexOf('run: node website/deploy-sftp.mjs recovery-download');
  const inspect = recovery.indexOf('run: node website/deploy-sftp.mjs recovery-inspect');
  const save = recovery.indexOf('name: documentation-recovery-111-inspection');
  const apply = recovery.indexOf('run: node website/deploy-sftp.mjs recovery-apply');
  assert(verify > 0 && inspect > verify && save > inspect && apply > save);
  assert.match(recovery, /PERFCHECKER_RECOVERY_PLAN_ARTIFACT: \$\{\{ steps\.receipt\.outputs\.artifact-id \}\}/);
});
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
test('stable source permits only the named documentation plot generators', async t => {
  const root = await mkdtemp(join(tmpdir(), 'perfchecker-doc-generators-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const git = (...args) => execFileSync('git', ['-C', root, '-c', 'user.name=Documentation test',
    '-c', 'user.email=docs@example.invalid', '-c', 'commit.gpgsign=false', '-c', 'core.hooksPath=/dev/null', ...args],
  { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
  git('init'); await writeFile(join(root, 'Project.toml'), 'version = "1.1.0"\n');
  await mkdir(join(root, 'src')); await writeFile(join(root, 'src/Core.jl'), 'immutable package source');
  git('add', '.'); git('commit', '-m', 'release'); const release = git('rev-parse', 'HEAD'); git('tag', 'v1.1.0');
  for (const name of ['export', 'publish-evidence', 'network-export', 'diagnostic-export',
    'native-export', 'extra-export', 'collector-export', 'observation-export']) {
    const path = `examples/kitchen-sink/${name}.jl`;
    await mkdir(join(root, posix.dirname(path)), { recursive: true }); await writeFile(join(root, path), 'render recorded data');
  }
  await mkdir(join(root, 'qualification/shared'), { recursive: true });
  await writeFile(join(root, 'qualification/shared/recorded-plots.mjs'), 'check recorded documentation views');
  await writeFile(join(root, 'qualification/shared/recorded-plots.test.mjs'), 'test recorded documentation inventory');
  await mkdir(join(root, 'qualification/scripts'), { recursive: true });
  await writeFile(join(root, 'qualification/scripts/run.jl'), 'run maintained documentation plot tests');
  git('add', '.'); git('commit', '-m', 'recorded plot exporters');
  assert.equal(await validateStableDocumentationSource(root, 'v1.1.0', git('rev-parse', 'HEAD')), release);
  await mkdir(join(root, 'website'));
  await writeFile(join(root, 'website/new-page.md'), 'untracked documentation');
  assert.equal(await validateStableDocumentationSource(root, 'v1.1.0', git('rev-parse', 'HEAD')), release);
  await rm(join(root, 'website/new-page.md'));
  for (const path of ['src/new.jl', 'packages/PerfCheckerWeb/src/untracked.jl']) {
    await mkdir(join(root, posix.dirname(path)), { recursive: true }); await writeFile(join(root, path), 'untracked code');
    await assert.rejects(validateStableDocumentationSource(root, 'v1.1.0', git('rev-parse', 'HEAD')), /outside documentation/);
    await rm(join(root, path));
  }
  git('mv', 'src/Core.jl', 'website/Core.jl'); git('commit', '-m', 'disguised Core rename');
  await assert.rejects(validateStableDocumentationSource(root, 'v1.1.0', git('rev-parse', 'HEAD')), /outside documentation/);
  git('revert', '--no-edit', 'HEAD');
  git('rm', 'src/Core.jl'); git('commit', '-m', 'Core deletion');
  await assert.rejects(validateStableDocumentationSource(root, 'v1.1.0', git('rev-parse', 'HEAD')), /outside documentation/);
  git('revert', '--no-edit', 'HEAD');
  for (const path of ['examples/kitchen-sink/oxygen/measure.jl', 'examples/kitchen-sink/another-export.jl',
    'examples/other/export.jl', 'test/plot.jl', 'packages/PerfCheckerWeb/src/changed.jl',
    'qualification/shared/another-check.mjs', 'qualification/shared/another-check.test.mjs',
    'qualification/scripts/another-runner.jl']) {
    await mkdir(join(root, posix.dirname(path)), { recursive: true }); await writeFile(join(root, path), 'changed');
    git('add', '.'); git('commit', '-m', 'outside named exporters');
    await assert.rejects(validateStableDocumentationSource(root, 'v1.1.0', git('rev-parse', 'HEAD')), /outside documentation/);
    git('revert', '--no-edit', 'HEAD');
  }
});
test('a documentation renderer must exactly match its fetched independent stable tag', async t => {
  const root = await mkdtemp(join(tmpdir(), 'perfchecker-doc-renderer-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const git = (...args) => execFileSync('git', ['-C', root, '-c', 'user.name=Documentation test',
    '-c', 'user.email=docs@example.invalid', '-c', 'commit.gpgsign=false', '-c', 'core.hooksPath=/dev/null', ...args],
  { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
  const directory = 'packages/PerfCheckerMakie', projectPath = join(root, directory, 'Project.toml');
  const sourcePath = join(root, directory, 'src/PerfCheckerMakie.jl');
  const coreProject = await readFile(new URL('../Project.toml', import.meta.url), 'utf8');
  const makieProject = await readFile(new URL('../packages/PerfCheckerMakie/Project.toml', import.meta.url), 'utf8');
  const coreVersion = /^version = "([^"]+)"/m.exec(coreProject)[1];
  git('init'); await mkdir(join(root, directory, 'src'), { recursive: true });
  await writeFile(join(root, 'Project.toml'), coreProject); await writeFile(projectPath, makieProject);
  await writeFile(sourcePath, 'module PerfCheckerMakie\nend\n');
  git('add', '.'); git('commit', '-m', 'Core release'); const release = git('rev-parse', 'HEAD'); git('tag', `v${coreVersion}`);
  assert.equal(await validateStableDocumentationSource(root, `v${coreVersion}`, release), release,
    'The real Core Project.toml is parsed before its compat sections');
  const untracked = join(root, directory, 'untracked.jl'); await writeFile(untracked, 'untracked');
  await assert.rejects(validateStableDocumentationSource(root, `v${coreVersion}`, release), /uncommitted or untracked/);
  await rm(untracked);
  const rendererProject = makieProject.replace(/^version = ".*"/m, 'version = "1.0.2"');
  await writeFile(projectPath, rendererProject); await writeFile(sourcePath, 'module PerfCheckerMakie\n# new renderer\nend\n');
  git('add', '.'); git('commit', '-m', 'independent renderer'); const renderer = git('rev-parse', 'HEAD');
  await assert.rejects(validateStableDocumentationSource(root, `v${coreVersion}`, renderer));
  const tag = 'PerfCheckerMakie-v1.0.2'; git('tag', tag);
  const sources = [];
  assert.equal(await validateStableDocumentationSource(root, `v${coreVersion}`, renderer,
    { onCompanionSource: source => sources.push(source) }), release);
  assert.deepEqual(sources, [{ name: 'PerfCheckerMakie', version: '1.0.2', tag, revision: renderer,
    tree: git('rev-parse', `${renderer}:${directory}`) }]);
  const remoteRoot = await mkdtemp(join(tmpdir(), 'perfchecker-doc-origin-'));
  t.after(() => rm(remoteRoot, { recursive: true, force: true }));
  const remote = join(remoteRoot, 'public-origin.git'); git('clone', '--bare', root, remote); git('remote', 'add', 'origin', remote);
  git('tag', '-d', tag);
  assert.equal(await fetchStableDocumentationCompanions(root, `v${coreVersion}`, renderer), tag);
  assert.equal(git('rev-parse', `${tag}^{commit}`), renderer, 'Fetch uses the exact companion tag from origin');
  const original = await readFile(sourcePath, 'utf8');
  await writeFile(sourcePath, original + '# dirty worktree\n');
  await assert.rejects(validateStableDocumentationSource(root, `v${coreVersion}`, renderer), /uncommitted or untracked/);
  git('add', sourcePath); await writeFile(sourcePath, original);
  await assert.rejects(validateStableDocumentationSource(root, `v${coreVersion}`, renderer), /uncommitted or untracked/,
    'An index-only change is rejected even if the worktree matches HEAD');
  git('restore', '--source=HEAD', '--staged', '--worktree', sourcePath);
  await writeFile(sourcePath, original + '# not in the published tag\n'); git('add', sourcePath); git('commit', '-m', 'unreleased renderer change');
  await assert.rejects(validateStableDocumentationSource(root, `v${coreVersion}`, git('rev-parse', 'HEAD')), /differs from its published/);
  git('revert', '--no-edit', 'HEAD');
  for (const change of [rendererProject.replace('version = "1.0.2"', 'version = "1.0.2-rc1"'),
    rendererProject.replace('name = "PerfCheckerMakie"', 'name = "OtherRenderer"')]) {
    await writeFile(projectPath, change); git('add', projectPath); git('commit', '-m', 'invalid renderer identity');
    await assert.rejects(validateStableDocumentationSource(root, `v${coreVersion}`, git('rev-parse', 'HEAD')), /stable PerfCheckerMakie/);
    git('revert', '--no-edit', 'HEAD');
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
test('published renderer provenance must match the exact independently validated source', () => {
  const source = { name: 'PerfCheckerMakie', version: '1.0.2', tag: 'PerfCheckerMakie-v1.0.2',
    revision, tree: nextRevision };
  const info = Object.fromEntries(Object.entries(source).map(([key, value]) => [`renderer_${key}`, value]));
  validateDocumentationRenderer(info, source);
  for (const key of Object.keys(source)) {
    const missing = { ...info }; delete missing[`renderer_${key}`];
    assert.throws(() => validateDocumentationRenderer(missing, source), /renderer differs/);
    assert.throws(() => validateDocumentationRenderer({ ...info, [`renderer_${key}`]: 'different' }, source), /renderer differs/);
  }
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
        stream.on('OPENDIR', (id, name) => operation(id, async () => {
          const entries = await Promise.all((await fs.readdir(path(name))).map(async filename =>
            ({ filename, longname: filename, attrs: attrs(await fs.lstat(join(path(name), filename))) })));
          const buffer = Buffer.alloc(4); buffer.writeUInt32BE(++count);
          handles.set(buffer.toString('hex'), { entries, close: async () => {} }); stream.handle(id, buffer);
        }));
        stream.on('READDIR', (id, buffer) => operation(id, async () => {
          const directory = handle(buffer);
          if (directory.entries.length) { stream.name(id, directory.entries); directory.entries = []; }
          else stream.status(id, 1);
        }));
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
  assert((await transport.readdir('/www/dev')).some(entry => entry.filename === 'index.html'));
  const cancellationLock = '/www/.perfchecker-docs-lock'; await transport.mkdir(cancellationLock);
  const mtime = Date.parse(recovery111.publisherStarted) / 1000 + 60;
  await fs.utimes(path(cancellationLock), mtime, mtime);
  const lock = await transport.stat(cancellationLock);
  assert.deepEqual(await transport.readdir(cancellationLock), []);
  assert.equal(await reclaimRecoveryLock(transport, { root: '/www', channel: 'release', recovery: true,
    version: recovery111.version, revision: recovery111.revision, reclaimCancelledLock: true },
  { mtime: lock.mtime, mode: lock.mode, uid: lock.uid, gid: lock.gid, entries: [] }), true);
  assert.equal(await transport.stat(cancellationLock), null);
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
