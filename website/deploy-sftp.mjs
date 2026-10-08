// Publish completed documentation through SFTP only; no remote shell is needed.
import ssh2 from 'ssh2';
const { Client } = ssh2;
import { createHash, createHmac, randomUUID, timingSafeEqual } from 'node:crypto';
import { readFile, readdir, lstat, realpath } from 'node:fs/promises';
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
// Permit documentation changes while checking every other path against the
// immutable release tree, including package metadata and optional providers.
export async function validateStableDocumentationSource(repository, version, revision) {
  assert(versionPattern.test(version) && revisionPattern.test(revision), 'Invalid stable documentation identity');
  const git = async args => (await promisify(execFile)('git', ['-C', repository, ...args],
    { encoding: 'utf8', maxBuffer: 4 * 1024 * 1024 })).stdout;
  assert((await git(['rev-parse', 'HEAD'])).trim() === revision, 'Documentation checkout differs from the selected source');
  const releaseRevision = (await git(['rev-parse', '--verify', `${version}^{commit}`])).trim();
  const changes = ((await git(['diff', '--name-only', '-z', releaseRevision, revision])) +
    (await git(['diff', '--name-only', '-z', revision]))).split('\0').filter(Boolean);
  const allowed = path => path.startsWith('website/') || path === 'README.md' ||
    path === '.github/workflows/Documentation.yml' || path === 'qualification/shared/canonical-documentation.mjs' ||
    path === 'qualification/shared/static-website-browser.mjs';
  assert(changes.every(allowed), 'Stable documentation source changes files outside documentation and its checks');
  // Project.toml is already required to match the immutable release exactly.
  const project = await readFile(join(repository, 'Project.toml'), 'utf8');
  const packageVersion = /^version\s*=\s*"([^"]+)"\s*(?:#.*)?$/m.exec(project.split(/^\s*\[/m)[0])?.[1];
  assert(`v${packageVersion}` === version, 'Documentation package version differs from the selected stable tag');
  return releaseRevision;
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
export async function publishDocumentation(transport, options) {
  const root = validateRoot(options.root), remote = name => posix.join(root, name);
  assert(revisionPattern.test(options.revision), 'Invalid publication revision');
  assert(['dev', 'release', 'stable-refresh'].includes(options.channel), 'Invalid publication channel');
  if (options.channel !== 'dev') assert(versionPattern.test(options.version), 'Invalid release tag');
  if (options.channel !== 'release') assert(Number.isSafeInteger(options.sequence) && options.sequence > 0, 'Invalid documentation run sequence');
  if (options.channel === 'stable-refresh') assert(revisionPattern.test(options.releaseRevision), 'Unverified stable release source');
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
      await upload(primary, destination);
      await json(posix.join(destination, markerName), record);
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
    const configuration = deploymentConfiguration(process.env);
    const options = { ...configuration, site: process.env.PERFCHECKER_DOCS_SITE,
      stableSite: process.env.PERFCHECKER_DOCS_STABLE_SITE, progress: message => console.log(message) };
    phase = 'export-validation';
    console.log('Validating completed documentation exports before connecting');
    options.validatedExports = await validateDocumentationExports(options);
    if (options.channel === 'stable-refresh') {
      phase = 'source-validation';
      options.releaseRevision = await validateStableDocumentationSource(options.sourceRepository ?? process.cwd(), options.version, options.revision);
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
