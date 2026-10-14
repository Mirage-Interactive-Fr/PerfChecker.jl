// Publish completed documentation through SFTP only; no remote shell is needed.
import ssh2 from 'ssh2';
const { Client } = ssh2;
import { createHash, createHmac, randomUUID, timingSafeEqual } from 'node:crypto';
import { readFile, readdir, lstat, realpath, mkdir, writeFile } from 'node:fs/promises';
import { createReadStream, createWriteStream } from 'node:fs';
import { Readable, Transform } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import { posix, resolve, join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const origin = 'https://perfchecker.mirageinteractive.fr';
const versionPattern = /^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/;
const revisionPattern = /^[a-f0-9]{40}$/;
const stateName = '.perfchecker-releases.json';
const markerName = '.perfchecker-docs.json';
const lockName = '.perfchecker-docs-lock';
const intentName = '.perfchecker-promotion.json';
const stableName = '.perfchecker-stable.json';
const refreshName = '.perfchecker-stable-refresh.json';
const assert = (condition, message) => { if (!condition) throw new Error(message); };
// One reviewed failed publication, not a general-purpose artifact publishing input.
export const recovery111 = Object.freeze({
  repository: 'Mirage-Interactive-Fr/PerfChecker.jl', version: 'v1.1.1',
  revision: 'd079efd5c24c3dcac5b7550781822038e0ff780f',
  tree: '749f8eac351ed2a1f0bc110456f2eb37a3bc08ee', run: 38518482302,
  producerJob: 115702546626, publisherJob: 115731474024,
  publisherStarted: '2026-10-14T07:54:24Z', publisherCompleted: '2026-10-14T09:54:55Z',
  artifact: 11876003542, name: 'documentation-sftp-exports', bytes: 1362821498,
  sha256: '2df37458511deb2d978095bdbce53776d0117b192c410527d12f86ce5829fa08'
});
export function recoveryContext(env) {
  assert(env.GITHUB_ACTIONS === 'true' && env.GITHUB_EVENT_NAME === 'workflow_dispatch' &&
    env.GITHUB_REF === 'refs/heads/main' && env.GITHUB_REPOSITORY === recovery111.repository,
  'Recovery requires an explicit dispatch on this repository main');
  assert(env.PERFCHECKER_DOCS_RECOVERY === 'recover-1.1.1' && revisionPattern.test(env.GITHUB_SHA ?? '') &&
    /^\d+$/.test(env.GITHUB_RUN_ID ?? '') && Number(env.GITHUB_RUN_ID) !== recovery111.run && env.GITHUB_RUN_ATTEMPT === '1',
  'Recovery must retain its actual Actions revision and new run identity');
  assert(!env.PERFCHECKER_DOCS_SOURCE_VERSION && !env.PERFCHECKER_DOCS_SOURCE_REVISION &&
    env.PERFCHECKER_DOCS_STABLE_REFRESH !== 'true', 'Recovery cannot be combined with stable refresh inputs');
  return { workflowRevision: env.GITHUB_SHA, recoveryRun: Number(env.GITHUB_RUN_ID) };
}
const publisherJobName = name => name === 'Publish canonical documentation through SFTP' ||
  name === 'Recover the retained v1.1.1 documentation exports';
export function validateRecoveryOrigin({ run, producer, publisher, artifact, commit, tag, annotations, publishers, recoveryRun }, context) {
  const expected = recovery111;
  assert(recoveryRun.id === context.recoveryRun && recoveryRun.event === 'workflow_dispatch' && recoveryRun.head_branch === 'main' &&
    recoveryRun.head_sha === context.workflowRevision && recoveryRun.path === '.github/workflows/Documentation.yml' &&
    recoveryRun.run_attempt === 1 && recoveryRun.status === 'in_progress', 'The actual recovery run identity differs');
  assert(run.id === expected.run && run.head_sha === expected.revision && run.head_branch === expected.version &&
    run.event === 'push' && run.path === '.github/workflows/Documentation.yml' && run.run_attempt === 1 &&
    run.status === 'completed' && run.conclusion === 'cancelled', 'The original tag publication identity differs');
  assert(producer.id === expected.producerJob && producer.run_id === expected.run && producer.run_attempt === 1 && producer.head_sha === expected.revision &&
    producer.status === 'completed' && producer.conclusion === 'success', 'The original export producer did not pass');
  assert(publisher.id === expected.publisherJob && publisher.run_id === expected.run && publisher.run_attempt === 1 && publisher.head_sha === expected.revision &&
    publisher.status === 'completed' && publisher.conclusion === 'cancelled' &&
    publisher.started_at === expected.publisherStarted && publisher.completed_at === expected.publisherCompleted,
  'The original publisher is not the reviewed terminal job');
  assert(annotations.some(item => item.annotation_level === 'failure' &&
    item.message === 'The job has exceeded the maximum execution time of 2h0m0s'), 'The reviewed timeout annotation is absent');
  assert(artifact.id === expected.artifact && artifact.name === expected.name && !artifact.expired &&
    artifact.size_in_bytes === expected.bytes && artifact.digest === `sha256:${expected.sha256}` &&
    artifact.workflow_run?.id === expected.run && artifact.workflow_run?.head_sha === expected.revision,
  'The retained original artifact identity differs');
  assert(commit.sha === expected.revision && commit.commit?.tree?.sha === expected.tree &&
    tag.sha === expected.revision && tag.commit?.tree?.sha === expected.tree, 'The immutable registered tag source differs');
  assert(publishers.every(job => job.run_id === context.recoveryRun || job.status !== 'in_progress' || !publisherJobName(job.name)),
    'Another documentation publisher is active');
  return { ...context, sourceRun: expected.run, sourceRevision: expected.revision, sourceTree: expected.tree,
    sourceVersion: expected.version, artifactId: expected.artifact, artifactSha256: expected.sha256,
    artifactBytes: expected.bytes, sourceProducerJob: expected.producerJob, sourcePublisherJob: expected.publisherJob,
    producerPassed: true, publisherCancelled: true, noOtherPublisher: true,
    publisherStarted: publisher.started_at, publisherCompleted: publisher.completed_at };
}
async function recoveryApi(env, path) {
  assert(env.GH_TOKEN, 'Recovery requires the read-only Actions token');
  const response = await fetch(`https://api.github.com/repos/${recovery111.repository}/${path}`, {
    headers: { Authorization: `Bearer ${env.GH_TOKEN}`, Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28' },
    redirect: 'error', signal: AbortSignal.timeout(30000)
  });
  assert(response.ok, `Recovery metadata request failed: HTTP ${response.status}`);
  return response.json();
}
export async function verifyRecoveryOrigin(env) {
  const context = recoveryContext(env), expected = recovery111;
  const [run, producer, publisher, artifact, commit, tag, recoveryRun] = await Promise.all([
    recoveryApi(env, `actions/runs/${expected.run}`), recoveryApi(env, `actions/jobs/${expected.producerJob}`),
    recoveryApi(env, `actions/jobs/${expected.publisherJob}`), recoveryApi(env, `actions/artifacts/${expected.artifact}`),
    recoveryApi(env, `commits/${expected.revision}`), recoveryApi(env, `commits/${expected.version}`),
    recoveryApi(env, `actions/runs/${context.recoveryRun}`)
  ]);
  assert(new RegExp(`^https://api\\.github\\.com/repos/Mirage-Interactive-Fr/PerfChecker\\.jl/check-runs/\\d+$`).test(publisher.check_run_url ?? ''),
    'The original publication check URL differs');
  const annotations = await recoveryApi(env, publisher.check_run_url.split(`/${expected.repository}/`)[1] + '/annotations?per_page=100');
  const activeRuns = await Promise.all(['in_progress', 'queued', 'pending', 'waiting', 'requested']
    .map(status => recoveryApi(env, `actions/workflows/Documentation.yml/runs?status=${status}&per_page=100`)));
  assert(activeRuns.every(page => page.total_count <= 100 && Array.isArray(page.workflow_runs)),
    'Active documentation publications cannot be inspected completely');
  const ids = [...new Set(activeRuns.flatMap(page => page.workflow_runs.map(item => item.id)))];
  const jobs = await Promise.all(ids.filter(id => id !== context.recoveryRun).map(id => recoveryApi(env, `actions/runs/${id}/jobs?per_page=100`)));
  assert(jobs.every(page => page.total_count <= 100 && Array.isArray(page.jobs)), 'Publisher jobs cannot be inspected completely');
  return validateRecoveryOrigin({ run, producer, publisher, artifact, commit, tag, annotations, recoveryRun,
    publishers: jobs.flatMap(page => page.jobs) }, context);
}
export async function writeVerifiedRecoveryArchive(response, destination, expected) {
  assert(response.ok && response.body, 'The original artifact download failed');
  const hash = createHash('sha256'); let bytes = 0;
  const inspect = new Transform({ transform(chunk, encoding, callback) {
    bytes += chunk.length;
    if (bytes > expected.bytes) { callback(new Error('The artifact exceeds its recorded byte count')); return; }
    hash.update(chunk); callback(null, chunk);
  } });
  await pipeline(Readable.fromWeb(response.body), inspect, createWriteStream(destination, { flags: 'wx' }));
  const sha256 = hash.digest('hex');
  assert(bytes === expected.bytes && sha256 === expected.sha256, 'The downloaded artifact bytes differ from the original digest');
  return { bytes, sha256 };
}
export function recoveryDownloadUrl(location) {
  const url = new URL(location);
  assert(url.protocol === 'https:' && !url.username && !url.password && !url.port &&
    (url.hostname.endsWith('.blob.core.windows.net') || url.hostname.endsWith('.actions.githubusercontent.com')),
  'The artifact redirect is not a GitHub Actions storage URL');
  return url;
}
async function verifyRecoveryArchiveFile(path) {
  const attrs = await lstat(path);
  assert(attrs.isFile() && !attrs.isSymbolicLink() && attrs.size === recovery111.bytes, 'The retained ZIP is not the original regular file');
  const hash = createHash('sha256');
  for await (const chunk of createReadStream(path)) hash.update(chunk);
  assert(hash.digest('hex') === recovery111.sha256, 'The retained ZIP digest changed');
}
async function downloadRecoveryArchive(env) {
  const proof = await verifyRecoveryOrigin(env);
  const directory = resolve('.recovery'); await mkdir(directory, { recursive: true });
  const response = await fetch(`https://api.github.com/repos/${recovery111.repository}/actions/artifacts/${recovery111.artifact}/zip`, {
    headers: { Authorization: `Bearer ${env.GH_TOKEN}`, Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28' },
    redirect: 'manual', signal: AbortSignal.timeout(30000)
  });
  assert(response.status === 302, 'The retained artifact did not return its signed download URL');
  // The read-only GitHub token must never be forwarded to blob storage.
  const archive = await fetch(recoveryDownloadUrl(response.headers.get('location')), {
    redirect: 'error', signal: AbortSignal.timeout(15 * 60 * 1000)
  });
  const bytes = await writeVerifiedRecoveryArchive(archive, join(directory, 'canonical-exports.zip'), recovery111);
  // Extract only the hashed original ZIP, into a directory that did not exist.
  // The resulting file digests are sealed with the download receipt and checked
  // again in both later phases; no build or renderer runs in this route.
  await mkdir(resolve('website/build'), { recursive: true });
  await mkdir(resolve('website/build/sftp'));
  await promisify(execFile)('unzip', ['-q', join(directory, 'canonical-exports.zip'), '-d', resolve('website/build/sftp')]);
  const exports = await recoveryExportDigests();
  await writeFile(join(directory, 'verified-origin.json'), JSON.stringify({ schema: 'perfchecker-doc-recovery-origin/1',
    ...proof, verifiedAt: new Date().toISOString(), archive: bytes, exports }, null, 2) + '\n', { flag: 'wx' });
  console.log('Retained original export verified; no documentation was rebuilt');
}
const documentationGenerators = new Set(['export', 'publish-evidence', 'network-export',
  'diagnostic-export', 'native-export', 'extra-export', 'collector-export', 'observation-export']
  .map(name => `examples/kitchen-sink/${name}.jl`));
const makieDirectory = 'packages/PerfCheckerMakie';
const documentationGit = repository => async args => (await promisify(execFile)('git', ['-C', repository, ...args],
  { encoding: 'utf8', maxBuffer: 4 * 1024 * 1024 })).stdout;
const projectField = (project, field) => new RegExp(`^${field}\\s*=\\s*"([^"]+)"\\s*(?:#.*)?$`, 'm')
  .exec(project.split(/^\s*\[/m)[0])?.[1];
async function documentationMakieTag(git, releaseRevision, revision) {
  if (!(await git(['diff', '--no-renames', '--name-only', releaseRevision, revision, '--', makieDirectory])).trim()) return null;
  const project = await git(['show', `${revision}:${makieDirectory}/Project.toml`]);
  const version = projectField(project, 'version');
  assert(projectField(project, 'name') === 'PerfCheckerMakie' && versionPattern.test(`v${version}`),
    'Documentation renderer must identify a stable PerfCheckerMakie version');
  // TagBot's subdir convention is PACKAGE-vVERSION; it is independent of the Core tag.
  return `PerfCheckerMakie-v${version}`;
}
// The workflow fetches only the companion tag required by its selected source,
// from the same public origin as the Core release, before source validation.
export async function fetchStableDocumentationCompanions(repository, version, revision) {
  assert(versionPattern.test(version) && revisionPattern.test(revision), 'Invalid stable documentation identity');
  const git = documentationGit(repository);
  const releaseRevision = (await git(['rev-parse', '--verify', `${version}^{commit}`])).trim();
  const tag = await documentationMakieTag(git, releaseRevision, revision);
  if (tag) await git(['fetch', '--no-tags', '--depth=1', 'origin', `refs/tags/${tag}:refs/tags/${tag}`]);
  return tag;
}
// A dispatch can document an older stable package without changing the Actions
// revision or trusting that main still contains that package's source.
export function documentationSourceConfiguration(env) {
  assert(revisionPattern.test(env.GITHUB_SHA ?? '') && env.GITHUB_SHA.length === 40, 'Invalid Actions revision');
  const version = env.PERFCHECKER_DOCS_SOURCE_VERSION ?? '';
  const revision = env.PERFCHECKER_DOCS_SOURCE_REVISION ?? '';
  const explicit = !!(version || revision);
  if (explicit) {
    assert(env.GITHUB_ACTIONS === 'true' && env.GITHUB_EVENT_NAME === 'workflow_dispatch' &&
      env.GITHUB_REF === 'refs/heads/main' && env.PERFCHECKER_DOCS_STABLE_REFRESH === 'true',
    'An explicit documentation source requires a stable dispatch on main');
    assert(versionPattern.test(version) && version === version.trim() && revisionPattern.test(revision) && revision.length === 40,
      'Supply a stable version and immutable documentation source SHA together');
  }
  return { explicit, version: explicit ? version : undefined, revision: explicit ? revision : env.GITHUB_SHA };
}
// Keep Core and other providers at the immutable release. A newer documentation
// renderer is permitted only when its complete subtree matches its own fetched tag.
export async function validateStableDocumentationSource(repository, version, revision, { onCompanionSource } = {}) {
  assert(versionPattern.test(version) && revisionPattern.test(revision), 'Invalid stable documentation identity');
  const git = documentationGit(repository);
  assert((await git(['rev-parse', 'HEAD'])).trim() === revision, 'Documentation checkout differs from the selected source');
  const releaseRevision = (await git(['rev-parse', '--verify', `${version}^{commit}`])).trim();
  // Report both ends of a rename as a deletion/addition: moving Core into
  // website must never disguise a package-source change as documentation.
  const changes = ((await git(['diff', '--no-renames', '--name-only', '-z', releaseRevision, revision])) +
    (await git(['diff', '--no-renames', '--name-only', '-z', revision])) +
    (await git(['diff', '--cached', '--no-renames', '--name-only', '-z', revision])) +
    (await git(['ls-files', '--others', '--exclude-standard', '-z']))).split('\0').filter(Boolean);
  const allowed = path => path.startsWith('website/') || path === 'README.md' ||
    path === '.github/workflows/Documentation.yml' || path === 'qualification/shared/canonical-documentation.mjs' ||
    path === 'qualification/shared/static-website-browser.mjs' || path === 'qualification/shared/recorded-plots.mjs' ||
    path === 'qualification/shared/recorded-plots.test.mjs' ||
    path === 'qualification/scripts/run.jl' ||
    documentationGenerators.has(path) ||
    path.startsWith(makieDirectory + '/');
  assert(changes.every(allowed), 'Stable documentation source changes files outside documentation and its checks');
  const dirty = (await git(['diff', '--no-renames', '--name-only', '-z', revision, '--', makieDirectory])) +
    (await git(['diff', '--cached', '--no-renames', '--name-only', '-z', revision, '--', makieDirectory])) +
    (await git(['ls-files', '--others', '--exclude-standard', '-z', '--', makieDirectory]));
  assert(!dirty, 'Documentation renderer has uncommitted or untracked changes');
  if (changes.some(path => path.startsWith(makieDirectory + '/'))) {
    const tag = await documentationMakieTag(git, releaseRevision, revision);
    assert(tag, 'Documentation renderer differs without a companion release');
    const companionRevision = (await git(['rev-parse', '--verify', `${tag}^{commit}`])).trim();
    const tree = (await git(['rev-parse', `${revision}:${makieDirectory}`])).trim();
    assert(tree === (await git(['rev-parse', `${companionRevision}:${makieDirectory}`])).trim(),
      'Documentation renderer differs from its published companion tag');
    onCompanionSource?.({ name: 'PerfCheckerMakie', version: tag.slice('PerfCheckerMakie-v'.length),
      tag, revision: companionRevision, tree });
  }
  // Project.toml is already required to match the immutable release exactly.
  const project = await readFile(join(repository, 'Project.toml'), 'utf8');
  const packageVersion = projectField(project, 'version');
  assert(`v${packageVersion}` === version, 'Documentation package version differs from the selected stable tag');
  return releaseRevision;
}
export function validateDocumentationRenderer(info, source) {
  assert(Object.entries(source).every(([key, value]) => info[`renderer_${key}`] === value),
    'Documentation export renderer differs from its validated companion tag');
}
export function compareVersions(a, b) {
  assert(versionPattern.test(a) && versionPattern.test(b), 'Invalid stable version');
  const aa = a.slice(1).split('.').map(BigInt), bb = b.slice(1).split('.').map(BigInt);
  for (let i = 0; i < 3; i++) if (aa[i] !== bb[i]) return aa[i] > bb[i] ? 1 : -1;
  return 0;
}
export function validateRoot(root) {
  assert(typeof root === 'string' && /^\/(?:[A-Za-z0-9._-]+\/?)*$/.test(root) &&
    posix.normalize(root) === root && !root.split('/').some(p => p === '.' || p === '..'),
  'SFTP root must be a normalized absolute directory');
  return root;
}
// Pin the exact public key, including hashed OpenSSH known_hosts entries.
export function hostVerifier(knownHosts, host, port) {
  assert(/^[A-Za-z0-9.-]+$/.test(host), 'Invalid SFTP host');
  assert(Number.isInteger(port) && port > 0 && port < 65536, 'Invalid SFTP port');
  const token = port === 22 ? host : `[${host}]:${port}`;
  const matching = pattern => {
    if (pattern.startsWith('|1|')) {
      const [, , salt, expected] = pattern.split('|');
      return !!salt && !!expected && createHmac('sha1', Buffer.from(salt, 'base64'))
        .update(token).digest('base64') === expected;
    }
    return pattern === token;
  };
  const keys = [], revoked = [];
  for (const line of knownHosts.split(/\r?\n/)) {
    const parts = line.trim().split(/\s+/);
    if (!parts[0] || parts[0].startsWith('#')) continue;
    const marker = parts[0].startsWith('@') ? parts.shift() : '';
    if (!parts[0]?.split(',').some(matching)) continue;
    assert(!marker || marker === '@revoked', 'Unsupported known_hosts marker');
    assert(parts.length >= 3 && /^ssh-|^ecdsa-/.test(parts[1]), 'Invalid pinned host key');
    const key = Buffer.from(parts[2], 'base64');
    assert(key.length > 16 && key.toString('base64') === parts[2], 'Invalid pinned host key');
    (marker === '@revoked' ? revoked : keys).push(key);
  }
  assert(keys.length, 'No pinned key for the SFTP host and port');
  const equal = (a, b) => a.length === b.length && timingSafeEqual(a, b);
  return key => !revoked.some(k => equal(k, key)) && keys.some(k => equal(k, key));
}
export function deploymentConfiguration(env) {
  const source = documentationSourceConfiguration(env);
  assert(env.PERFCHECKER_DOCS_SFTP_DEPLOY === 'true', 'SFTP deployment is disabled');
  assert(env.PERFCHECKER_DOCS_REF_DELETED !== 'true', 'Deleted refs cannot deploy documentation');
  assert(env.GITHUB_ACTIONS === 'true' && ['push', 'workflow_dispatch'].includes(env.GITHUB_EVENT_NAME),
    'SFTP deployment requires a trusted Actions event');
  const refresh = env.PERFCHECKER_DOCS_STABLE_REFRESH === 'true';
  assert(!refresh || (env.GITHUB_EVENT_NAME === 'workflow_dispatch' && env.GITHUB_REF === 'refs/heads/main'),
    'Stable documentation refresh requires an explicit dispatch on main');
  const channel = refresh ? 'stable-refresh' : env.GITHUB_REF === 'refs/heads/main' ? 'dev' : 'release';
  assert(channel !== 'release' || (env.GITHUB_EVENT_NAME === 'push' &&
    versionPattern.test(env.GITHUB_REF_NAME ?? '') && env.GITHUB_REF === `refs/tags/${env.GITHUB_REF_NAME}`),
  'Only main and stable tag pushes can deploy');
  if (refresh) assert(versionPattern.test(env.PERFCHECKER_DOCS_STABLE_VERSION ?? ''), 'Invalid stable refresh version');
  if (source.explicit) assert(source.version === env.PERFCHECKER_DOCS_STABLE_VERSION,
    'Explicit documentation version differs from the stable refresh version');
  const port = Number(env.PERFCHECKER_DOCS_SFTP_PORT ?? 22);
  const host = env.PERFCHECKER_DOCS_SFTP_HOST ?? '';
  const knownHosts = env.PERFCHECKER_DOCS_SFTP_KNOWN_HOSTS ?? '';
  const verify = hostVerifier(knownHosts, host, port);
  assert(/^[A-Za-z0-9_.-]+$/.test(env.PERFCHECKER_DOCS_SFTP_USER ?? ''), 'Invalid SFTP user');
  assert(env.PERFCHECKER_DOCS_SFTP_PASSWORD || env.PERFCHECKER_DOCS_SFTP_SSH_KEY, 'Missing SFTP authentication');
  return { channel, version: refresh ? env.PERFCHECKER_DOCS_STABLE_VERSION : channel === 'release' ? env.GITHUB_REF_NAME : undefined,
    revision: source.revision, sourceRepository: source.explicit ? env.PERFCHECKER_DOCS_SOURCE_REPOSITORY : undefined,
    root: validateRoot(env.PERFCHECKER_DOCS_SFTP_ROOT ?? ''),
    sequence: Number(env.GITHUB_RUN_NUMBER), connection: { host, port,
      username: env.PERFCHECKER_DOCS_SFTP_USER, hostVerifier: verify,
      password: env.PERFCHECKER_DOCS_SFTP_PASSWORD,
      privateKey: env.PERFCHECKER_DOCS_SFTP_SSH_KEY, readyTimeout: 30000 } };
}
const call = (object, method, ...args) => new Promise((ok, fail) =>
  object[method](...args, (error, result) => error ? fail(error) : ok(result)));
export async function connectSftp(configuration) {
  const client = new Client();
  await new Promise((ok, fail) => {
    const cleanup = () => {
      client.off('ready', ready).off('error', failure).off('end', disconnected).off('close', disconnected);
    };
    const ready = () => { cleanup(); ok(); };
    const failure = error => { cleanup(); client.on('error', () => {}); client.end(); fail(error); };
    const disconnected = () => failure(new Error('SFTP connection closed before authentication completed'));
    client.once('ready', ready).once('error', failure).once('end', disconnected).once('close', disconnected);
    try { client.connect(configuration); } catch (error) { failure(error); }
  });
  // Keep handling connection errors after authentication; SFTP operations reject.
  client.on('error', () => {});
  let sftp;
  try { sftp = await call(client, 'sftp'); } catch (error) { client.end(); throw error; }
  const optional = async (method, ...args) => {
    try { return await call(sftp, method, ...args); }
    catch (error) { if (error.code === 2) return null; throw error; }
  };
  return {
    stat: path => optional('lstat', path),
    read: path => optional('readFile', path),
    readdir: path => call(sftp, 'readdir', path),
    mkdir: path => call(sftp, 'mkdir', path, { mode: 0o755 }),
    chmod: (path, mode) => call(sftp, 'chmod', path, mode),
    put: (local, remote) => call(sftp, 'fastPut', local, remote, { concurrency: 4, mode: 0o644 }),
    write: (path, bytes) => call(sftp, 'writeFile', path, bytes, { mode: 0o644 }),
    replace: async (from, to) => {
      try { await call(sftp, 'ext_openssh_rename', from, to); }
      catch (error) {
        if (error.code !== 8 && error.message !== 'Server does not support this extended request') throw error;
        assert(!(await optional('lstat', to)), 'Server needs posix-rename@openssh.com to replace existing files safely');
        await call(sftp, 'rename', from, to);
      }
    },
    unlink: path => optional('unlink', path),
    rmdir: path => call(sftp, 'rmdir', path),
    close: () => client.end()
  };
}
export async function readExport(directory, channel, revision, version) {
  const root = await realpath(directory);
  const info = JSON.parse(await readFile(join(root, 'build-info.json'), 'utf8'));
  assert(info.schema === 'perfchecker-doc-export/1' && info.channel === channel &&
    info.revision === revision && revisionPattern.test(revision), 'Documentation export source or channel differs');
  // PR previews may document a Julia prerelease; publishing still requires an
  // explicit stable tag which must match this version.
  const validVersion = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-[A-Za-z0-9.-]+)?(?:\+[A-Za-z0-9.-]+)?$/.test(info.version);
  assert(validVersion && (!version || version === `v${info.version}`), 'Export version differs from tag');
  const base = channel === 'dev' ? '/dev/' : channel === 'version' ? `/v${info.version}/` : '/';
  assert(info.base === base && info.url === origin + base, 'Export has an incorrect canonical base');
  const files = [];
  async function visit(relative) {
    for (const entry of (await readdir(join(root, relative), { withFileTypes: true })).sort((a, b) => a.name.localeCompare(b.name))) {
      assert(/^[A-Za-z0-9_.@-]+$/.test(entry.name) && !['.', '..'].includes(entry.name), 'Unsafe export filename');
      const path = posix.join(relative, entry.name), absolute = join(root, path);
      const attrs = await lstat(absolute);
      assert(!attrs.isSymbolicLink(), 'Export must not contain symbolic links');
      assert(relative || !(entry.name === 'dev' || versionPattern.test(entry.name) || entry.name.startsWith('.perfchecker-')),
        'Export contains a reserved deployment path');
      if (attrs.isDirectory()) await visit(path);
      else { assert(attrs.isFile(), 'Export must contain only regular files'); files.push({ path, absolute }); }
    }
  }
  await visit('');
  assert(files.some(file => file.path === 'index.html'), 'Export has no index.html');
  const hash = createHash('sha256');
  for (const file of files) { hash.update(file.path + '\0'); hash.update(await readFile(file.absolute)); hash.update('\0'); }
  return { info, files, digest: hash.digest('hex') };
}
const recordValid = record => record && revisionPattern.test(record.revision) && /^[a-f0-9]{64}$/.test(record.digest);
function validateState(state) {
  assert(state.schema === 'perfchecker-doc-publication/1' && state.versions && typeof state.versions === 'object' && !Array.isArray(state.versions), 'Invalid remote publication state');
  assert(state.stable === null || versionPattern.test(state.stable), 'Invalid remote stable version');
  for (const [version, record] of Object.entries(state.versions)) assert(versionPattern.test(version) && recordValid(record), 'Invalid remote version record');
  assert(state.dev === null || (recordValid(state.dev) && Number.isSafeInteger(state.dev.sequence)), 'Invalid remote dev record');
  return state;
}
export function versionCatalogue(state) {
  const versions = Object.keys(state.versions).sort((a, b) => compareVersions(b, a));
  if (state.stable && !versions.includes(state.stable)) versions.unshift(state.stable);
  if (state.dev) versions.push('dev');
  const urls = Object.fromEntries(versions.map(v => [v, v === 'dev' ? '/dev/' : v === state.stable ? '/' : `/${v}/`]));
  return `var DOC_VERSIONS = ${JSON.stringify(versions)};\nvar DOC_VERSION_URLS = ${JSON.stringify(urls)};\n`;
}
export async function validateDocumentationExports(options) {
  assert(revisionPattern.test(options.revision), 'Invalid publication revision');
  assert(['dev', 'release', 'stable-refresh'].includes(options.channel), 'Invalid publication channel');
  if (options.channel !== 'dev') assert(versionPattern.test(options.version), 'Invalid release tag');
  const primary = await readExport(options.site, options.channel === 'dev' ? 'dev' : options.channel === 'stable-refresh' ? 'stable' : 'version', options.revision, options.version);
  const stable = options.channel === 'release' ? await readExport(options.stableSite, 'stable', options.revision, options.version) : null;
  return { primary, stable };
}
function assertRecoveryOptions(options) {
  assert(options.recovery === true && options.channel === 'release' && options.version === recovery111.version &&
    options.revision === recovery111.revision, 'Recovery is restricted to the reviewed v1.1.1 export');
}
export function recoveryOptions(env) {
  const context = recoveryContext(env);
  // Validate the actual main dispatch and connection configuration, without
  // disguising it as the original tag push or overriding any Actions identity.
  const configuration = deploymentConfiguration(env);
  assert(configuration.channel === 'dev', 'Recovery connection must use the actual main dispatch');
  return { ...configuration, ...context, recovery: true, channel: 'release', version: recovery111.version,
    revision: recovery111.revision, site: resolve('website/build/sftp/version/site'),
    stableSite: resolve('website/build/sftp/stable/site'), reclaimCancelledLock: env.PERFCHECKER_RECOVERY_RECLAIM_LOCK === 'true' };
}
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const byteDigest = bytes => createHash('sha256').update(bytes).digest('hex');
async function inspectRecoveryLock(transport, root) {
  const path = posix.join(root, lockName), attrs = await transport.stat(path);
  if (!attrs) return null;
  assert(attrs.isDirectory() && !attrs.isSymbolicLink(), 'Recovery lock must be a real directory, never a symbolic link');
  const entries = await transport.readdir(path);
  assert(Array.isArray(entries) && entries.every(entry => ['.', '..'].includes(entry.filename)),
    'Recovery refuses a nonempty or uninspectable lock');
  assert(Number.isInteger(attrs.mtime) && attrs.mtime >= Date.parse(recovery111.publisherStarted) / 1000 &&
    attrs.mtime <= Date.parse(recovery111.publisherCompleted) / 1000, 'Recovery lock time is outside the cancelled publisher window');
  return { mtime: attrs.mtime, mode: attrs.mode, uid: attrs.uid, gid: attrs.gid, entries: [] };
}
export async function inspectRecoveryDestination(transport, options, { includeLock = true } = {}) {
  assertRecoveryOptions(options);
  const root = validateRoot(options.root), attrs = await transport.stat(root);
  assert(attrs?.isDirectory() && !attrs.isSymbolicLink(), 'SFTP document root must be a real directory');
  const directory = await transport.stat(posix.join(root, recovery111.version));
  assert(directory?.isDirectory() && !directory.isSymbolicLink(), 'The retained version archive must be a real directory');
  const read = async name => {
    const path = posix.join(root, name), attrs = await transport.stat(path);
    assert(!attrs || (attrs.isFile() && !attrs.isSymbolicLink()), 'Remote recovery metadata must be a regular file');
    const bytes = attrs ? await transport.read(path) : null;
    return { value: bytes ? JSON.parse(bytes.toString()) : null, sha256: bytes ? byteDigest(bytes) : null };
  };
  const archive = await read(`${recovery111.version}/${markerName}`), state = await read(stateName),
    intent = await read(intentName), committed = await read(stableName), refresh = await read(refreshName);
  const record = { revision: options.revision, digest: options.validatedExports.primary.digest };
  assert(archive.value && same(archive.value, record), 'The version archive has no matching completed original export marker');
  validateState(state.value ?? {});
  assert(!state.value.stable || compareVersions(state.value.stable, options.version) <= 0, 'Recovery cannot replace a newer stable release');
  assert(!state.value.versions[options.version] || same(state.value.versions[options.version], record),
    'The release catalogue has different original archive bytes');
  assert(intent.value?.version === options.version && recordValid(intent.value) &&
    intent.value.revision === record.revision && intent.value.digest === record.digest,
  'Recovery requires the matching original pending promotion');
  if (committed.value) {
    assert(versionPattern.test(committed.value.version) && recordValid(committed.value), 'Invalid completed stable marker');
    assert(compareVersions(committed.value.version, options.version) <= 0 &&
      (committed.value.version !== options.version || (committed.value.revision === record.revision && committed.value.digest === record.digest)),
    'Recovery refuses a different or newer completed stable publication');
  }
  if (refresh.value) assert(versionPattern.test(refresh.value.version) && recordValid(refresh.value) &&
    Number.isSafeInteger(refresh.value.sequence) && ['pending', 'complete'].includes(refresh.value.status) &&
    compareVersions(refresh.value.version, options.version) < 0, 'Recovery cannot overwrite refreshed documentation');
  return { root, archive, state, intent, committed, refresh,
    ...(includeLock ? { lock: await inspectRecoveryLock(transport, root) } : {}) };
}
export async function reclaimRecoveryLock(transport, options, inspected) {
  assertRecoveryOptions(options);
  const current = await inspectRecoveryLock(transport, options.root);
  assert(same(current, inspected), 'The inspected cancellation lock changed before recovery');
  if (!current) return false;
  assert(options.reclaimCancelledLock === true, 'Removing the reviewed cancelled lock requires explicit dispatch opt-in');
  // Never recurse, unlink files, follow links, or remove an unknown owner's lock.
  // A competing mkdir after this rmdir still makes publishDocumentation refuse.
  await transport.rmdir(posix.join(options.root, lockName));
  return true;
}
async function verifiedRecoveryOptions(env) {
  const options = recoveryOptions(env);
  const proof = await verifyRecoveryOrigin(env);
  const saved = JSON.parse(await readFile(resolve('.recovery/verified-origin.json'), 'utf8'));
  assert(saved.schema === 'perfchecker-doc-recovery-origin/1' &&
    same(saved.archive, { bytes: recovery111.bytes, sha256: recovery111.sha256 }) &&
    Object.entries(proof).every(([key, value]) => saved[key] === value), 'The verified original artifact receipt differs');
  await verifyRecoveryArchiveFile(resolve('.recovery/canonical-exports.zip'));
  // Recompute every extracted file before opening the authenticated connection.
  options.validatedExports = await validateDocumentationExports(options);
  const dev = await readExport(resolve('website/build/sftp/dev/site'), 'dev', recovery111.revision, recovery111.version);
  assert(same(saved.exports, { dev: dev.digest, version: options.validatedExports.primary.digest,
    stable: options.validatedExports.stable.digest }), 'The extracted original export bytes changed');
  return { options, proof };
}
async function recoveryExportDigests() {
  const [dev, version, stable] = await Promise.all(['dev', 'version', 'stable'].map(channel =>
    readExport(resolve(`website/build/sftp/${channel}/site`), channel, recovery111.revision, recovery111.version)));
  return { dev: dev.digest, version: version.digest, stable: stable.digest };
}
const recoveryPlanName = 'documentation-recovery-111-inspection';
export function validateRecoveryPlanArtifact(artifact, context, uploadedDigest) {
  assert(Number.isSafeInteger(artifact.id) && artifact.id > 0 && artifact.size_in_bytes > 0 && artifact.name === recoveryPlanName && !artifact.expired &&
    artifact.workflow_run?.id === context.recoveryRun && artifact.workflow_run?.head_sha === context.workflowRevision &&
    /^[a-f0-9]{64}$/.test(uploadedDigest ?? '') && artifact.digest === `sha256:${uploadedDigest}`,
  'The inspection receipt was not saved by this recovery run with the uploaded digest');
}
async function inspectRecovery(env) {
  const { options, proof } = await verifiedRecoveryOptions(env);
  const transport = await connectSftp(options.connection);
  try {
    const destination = await inspectRecoveryDestination(transport, options);
    if (destination.lock) assert(options.reclaimCancelledLock, 'The reviewed lock requires explicit dispatch opt-in');
    const plan = { schema: 'perfchecker-doc-recovery-inspection/1', inspectedAt: new Date().toISOString(), proof, destination,
      exports: { version: options.validatedExports.primary.digest, stable: options.validatedExports.stable.digest },
      archivePreserved: true, reclaimCancelledLock: options.reclaimCancelledLock };
    const bytes = Buffer.from(JSON.stringify(plan, null, 2) + '\n');
    await writeFile(resolve('.recovery/inspection.json'), bytes, { flag: 'wx' });
    assert(env.GITHUB_OUTPUT, 'Recovery inspection requires the Actions output file');
    await writeFile(env.GITHUB_OUTPUT, `plan-sha256=${byteDigest(bytes)}\n`, { flag: 'a' });
    console.log('Original archive marker and cancellation lock inspected; no remote writes performed');
  } finally { transport.close(); }
}
async function applyRecovery(env) {
  const { options, proof } = await verifiedRecoveryOptions(env);
  const bytes = await readFile(resolve('.recovery/inspection.json'));
  assert(/^[a-f0-9]{64}$/.test(env.PERFCHECKER_RECOVERY_PLAN_SHA256 ?? '') &&
    byteDigest(bytes) === env.PERFCHECKER_RECOVERY_PLAN_SHA256, 'The saved inspection receipt bytes changed');
  assert(/^\d+$/.test(env.PERFCHECKER_RECOVERY_PLAN_ARTIFACT ?? ''), 'An uploaded inspection receipt is required before changing the lock');
  const artifact = await recoveryApi(env, `actions/artifacts/${env.PERFCHECKER_RECOVERY_PLAN_ARTIFACT}`);
  assert(artifact.id === Number(env.PERFCHECKER_RECOVERY_PLAN_ARTIFACT), 'The saved inspection artifact ID differs');
  validateRecoveryPlanArtifact(artifact, proof, env.PERFCHECKER_RECOVERY_PLAN_ARTIFACT_SHA256);
  const plan = JSON.parse(bytes.toString());
  assert(plan.schema === 'perfchecker-doc-recovery-inspection/1' && same(plan.proof, proof) && plan.archivePreserved === true &&
    plan.reclaimCancelledLock === options.reclaimCancelledLock && same(plan.exports, {
      version: options.validatedExports.primary.digest, stable: options.validatedExports.stable.digest }), 'The recovery plan source or exports differ');
  const transport = await connectSftp(options.connection);
  try {
    const current = await inspectRecoveryDestination(transport, options);
    assert(same(current, plan.destination), 'The inspected remote publication changed before recovery');
    const lockReclaimed = await reclaimRecoveryLock(transport, options, plan.destination.lock);
    const result = await publishDocumentation(transport, { ...options, progress: message => console.log(message) });
    await writeFile(resolve('.recovery/result.json'), JSON.stringify({ schema: 'perfchecker-doc-recovery-result/1',
      proof, completedAt: new Date().toISOString(), inspectionArtifact: artifact.id, inspectionArtifactDigest: artifact.digest,
      inspectionSha256: env.PERFCHECKER_RECOVERY_PLAN_SHA256, lockReclaimed, archivePreserved: true, result }, null, 2) + '\n', { flag: 'wx' });
    console.log(`Retained export recovery completed; stable=${result.stable}`);
  } finally { transport.close(); }
}
export async function publishDocumentation(transport, options) {
  const root = validateRoot(options.root), remote = name => posix.join(root, name);
  assert(revisionPattern.test(options.revision), 'Invalid publication revision');
  assert(['dev', 'release', 'stable-refresh'].includes(options.channel), 'Invalid publication channel');
  if (options.channel !== 'dev') assert(versionPattern.test(options.version), 'Invalid release tag');
  if (options.channel !== 'release') assert(Number.isSafeInteger(options.sequence) && options.sequence > 0, 'Invalid documentation run sequence');
  if (options.channel === 'stable-refresh') assert(revisionPattern.test(options.releaseRevision), 'Unverified stable release source');
  if (options.recovery) assertRecoveryOptions(options);
  const { primary, stable } = options.validatedExports ?? await validateDocumentationExports(options);
  const rootAttrs = await transport.stat(root);
  assert(rootAttrs?.isDirectory() && !rootAttrs.isSymbolicLink(), 'SFTP document root must be a real directory');
  try { await transport.mkdir(remote(lockName)); }
  catch { throw new Error('Another documentation publisher holds the SFTP lock; inspect a stale lock before retrying'); }
  const ensured = new Map([[root, Promise.resolve()]]), run = randomUUID();
  const directory = path => {
    if (ensured.has(path)) return ensured.get(path);
    const pending = (async () => {
      await directory(posix.dirname(path));
      const existing = await transport.stat(path);
      if (existing) assert(existing.isDirectory() && !existing.isSymbolicLink(), 'Remote parent is not a real directory');
      else await transport.mkdir(path);
      await transport.chmod(path, 0o755);
    })();
    ensured.set(path, pending); return pending;
  };
  const read = async path => {
    const attrs = await transport.stat(path);
    assert(!attrs || (attrs.isFile() && !attrs.isSymbolicLink()), 'Remote metadata must be a regular file');
    return attrs ? transport.read(path) : null;
  };
  const replace = async (destination, bytes, local) => {
    await directory(posix.dirname(destination));
    const existing = await transport.stat(destination);
    assert(!existing || (existing.isFile() && !existing.isSymbolicLink()), 'Remote destination is not a regular file');
    const temporary = posix.join(posix.dirname(destination), `.perfchecker-upload-${run}-${posix.basename(destination)}`);
    try {
      if (local) await transport.put(local, temporary); else await transport.write(temporary, bytes);
      await transport.chmod(temporary, 0o644);
      await transport.replace(temporary, destination);
    } finally { await transport.unlink(temporary).catch(() => {}); }
  };
  const json = (destination, value) => replace(destination, JSON.stringify(value, null, 2) + '\n');
  const upload = async (artifact, destination) => {
    options.progress?.(`Uploading ${artifact.info.channel}: ${artifact.files.length} files`);
    let completed = 0;
    const groups = [artifact.files.filter(f => f.path.startsWith('assets/')),
      artifact.files.filter(f => !f.path.startsWith('assets/') && !f.path.endsWith('.html') && f.path !== 'versions.js'),
      artifact.files.filter(f => f.path.endsWith('.html') && f.path !== 'index.html'),
      artifact.files.filter(f => f.path === 'index.html')];
    for (const group of groups) {
      // Wait for all active writes on failure before releasing the publication lock.
      const queue = [...group];
      const results = await Promise.allSettled(Array.from({ length: Math.min(4, queue.length) }, async () => {
        while (queue.length) {
          const file = queue.shift(); await replace(posix.join(destination, file.path), null, file.absolute);
          completed++; if (completed % 500 === 0) options.progress?.(`Transferred ${completed}/${artifact.files.length} files`);
        }
      }));
      const failure = results.find(result => result.status === 'rejected');
      if (failure) throw failure.reason;
    }
  };
  try {
    // Repeat immutable-archive/newer-release guards under the newly acquired
    // lock, even after the separately saved read-only inspection succeeded.
    if (options.recovery) await inspectRecoveryDestination(transport, { ...options, validatedExports: { primary, stable } }, { includeLock: false });
    const raw = await read(remote(stateName));
    let state;
    if (raw) state = validateState(JSON.parse(raw.toString()));
    else {
      const current = (await read(remote('siteinfo.js')))?.toString() ?? '';
      const match = /DOCUMENTER_CURRENT_VERSION\s*=\s*["'](v\d+\.\d+\.\d+)["']/.exec(current);
      state = { schema: 'perfchecker-doc-publication/1', stable: match?.[1] ?? null, versions: {}, dev: null };
      validateState(state);
    }
    const intentRaw = await read(remote(intentName));
    const intent = intentRaw ? JSON.parse(intentRaw.toString()) : null;
    const committedRaw = await read(remote(stableName));
    const committed = committedRaw ? JSON.parse(committedRaw.toString()) : null;
    const refreshRaw = await read(remote(refreshName));
    const refresh = refreshRaw ? JSON.parse(refreshRaw.toString()) : null;
    if (refresh) assert(versionPattern.test(refresh.version) && recordValid(refresh) &&
      Number.isSafeInteger(refresh.sequence) && refresh.sequence > 0 && ['pending', 'complete'].includes(refresh.status),
    'Invalid stable documentation refresh metadata');
    for (const metadata of [intent, committed]) if (metadata)
      assert(versionPattern.test(metadata.version) && recordValid(metadata), 'Invalid remote promotion metadata');
    // A completed root marker recovers the authoritative state after a state-write failure.
    if (committed && (!state.stable || compareVersions(committed.version, state.stable) >= 0)) {
      state.stable = committed.version;
      state.versions[committed.version] = { revision: committed.revision, digest: committed.digest };
    }
    const record = { revision: options.revision, digest: primary.digest };
    if (options.channel === 'stable-refresh') {
      const archive = state.versions[options.version];
      assert(state.stable === options.version && recordValid(archive) && archive.revision === options.releaseRevision,
        'Only the currently published stable release can have its documentation refreshed');
      const archiveRaw = await read(remote(`${options.version}/${markerName}`));
      const archiveMarker = archiveRaw ? JSON.parse(archiveRaw.toString()) : null;
      const matches = metadata => metadata && metadata.revision === archive.revision && metadata.digest === archive.digest;
      assert(matches(archiveMarker) && committed?.version === options.version && matches(committed) &&
        intent?.version === options.version && matches(intent), 'Stable release publication is absent or incomplete');
      if (refresh?.version === options.version) {
        if (options.sequence < refresh.sequence) return { skipped: true, stable: state.stable };
        if (options.sequence === refresh.sequence) assert(refresh.revision === record.revision && refresh.digest === record.digest,
          'A stable refresh retry has different source or bytes');
      }
      const update = { version: options.version, ...record, sequence: options.sequence };
      // This separate watermark prevents an old tag rerun from overwriting a
      // refreshed root, including when an interrupted refresh needs retrying.
      await json(remote(refreshName), { ...update, status: 'pending' });
      await upload(primary, root);
      await json(remote(refreshName), { ...update, status: 'complete' });
      // Archive identities, release state and the live catalogue are untouched.
      return { skipped: false, stable: state.stable, digest: primary.digest };
    }
    if (options.channel === 'dev') {
      if (state.dev && options.sequence < state.dev.sequence) return { skipped: true, stable: state.stable };
      await upload(primary, remote('dev'));
      await json(remote(`dev/${markerName}`), record);
      state.dev = { ...record, sequence: options.sequence };
    } else {
      const destination = remote(options.version);
      const marker = await read(posix.join(destination, markerName));
      const prior = marker ? JSON.parse(marker.toString()) : state.versions[options.version];
      assert(!prior || (prior.revision === record.revision && prior.digest === record.digest), 'A published version cannot be replaced by different source or bytes');
      if (!options.recovery) {
        await upload(primary, destination);
        await json(posix.join(destination, markerName), record);
      }
      const floor = intent && (!state.stable || compareVersions(intent.version, state.stable) > 0)
        ? intent.version : state.stable;
      const newer = !floor || compareVersions(options.version, floor) > 0;
      const unfinished = floor && compareVersions(options.version, floor) === 0 && committed?.version !== options.version;
      if ((newer || unfinished) && refresh?.version !== options.version) {
        if (intent?.version === options.version)
          assert(intent.revision === record.revision && intent.digest === record.digest, 'A pending stable promotion has different source or bytes');
        // Persist a monotonic watermark before touching root files. It is not a catalogue entry.
        await json(remote(intentName), { version: options.version, ...record });
        await upload(stable, root);
        // This completion marker distinguishes a finished tree from an interrupted promotion.
        await json(remote(stableName), { version: options.version, ...record });
        state.stable = options.version;
      }
      state.versions[options.version] = record;
    }
    // Publish the catalogue and state only after every site transfer succeeds.
    await json(remote(stateName), state);
    await replace(remote('versions.js'), versionCatalogue(state));
    return { skipped: false, stable: state.stable, digest: primary.digest };
  } finally { await transport.rmdir(remote(lockName)); }
}
export function failureClass(error) {
  const codes = { ENOTFOUND: 'dns', ECONNREFUSED: 'connection-refused', ETIMEDOUT: 'timeout',
    ECONNRESET: 'connection-reset', ENOENT: 'missing-local-file', 2: 'missing-remote-file',
    3: 'remote-permission', 8: 'unsupported-sftp-operation' };
  const code = typeof error?.code === 'string' || typeof error?.code === 'number' ? error.code : '';
  if (Object.hasOwn(codes, code)) return codes[code];
  if (error?.level === 'client-authentication') return 'authentication';
  if (error?.level === 'handshake') return 'ssh-handshake';
  return 'validation-or-transport';
}
async function main() {
  let phase = 'configuration', transport;
  try {
    if (process.argv[2]) {
      phase = process.argv[2];
      if (phase === 'recovery-download') await downloadRecoveryArchive(process.env);
      else if (phase === 'recovery-inspect') await inspectRecovery(process.env);
      else if (phase === 'recovery-apply') await applyRecovery(process.env);
      else throw new Error('Unknown publication command');
      return;
    }
    const configuration = deploymentConfiguration(process.env);
    const options = { ...configuration, site: process.env.PERFCHECKER_DOCS_SITE,
      stableSite: process.env.PERFCHECKER_DOCS_STABLE_SITE, progress: message => console.log(message) };
    phase = 'export-validation';
    console.log('Validating completed documentation exports before connecting');
    options.validatedExports = await validateDocumentationExports(options);
    if (options.channel === 'stable-refresh') {
      phase = 'source-validation';
      options.releaseRevision = await validateStableDocumentationSource(options.sourceRepository ?? process.cwd(), options.version, options.revision,
        { onCompanionSource: source => {
          validateDocumentationRenderer(options.validatedExports.primary.info, source);
          console.log('Documentation companion source: ' + JSON.stringify(source));
        } });
    }
    phase = 'connection';
    console.log('Connecting to the pinned SFTP host');
    transport = await connectSftp(configuration.connection);
    phase = 'publication';
    const result = await publishDocumentation(transport, options);
    console.log(`Documentation ${result.skipped ? 'already superseded' : 'published'}; stable=${result.stable ?? 'none'}`);
  } catch (error) {
    // Only locally selected phases/classes are logged, never raw server error data.
    console.error(`SFTP documentation publication failed: phase=${phase}, class=${failureClass(error)}`);
    process.exitCode = 1;
  } finally { transport?.close(); }
}
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) await main();
