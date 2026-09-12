// Serve only the completed HTML artifact, including VitePress clean URLs.
import { createServer } from 'node:http';
import { createReadStream } from 'node:fs';
import { cp, mkdtemp, realpath, rm, stat } from 'node:fs/promises';
import { dirname, extname, resolve, sep, join } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';

const source = await realpath(process.env.PERFCHECKER_PREVIEW_SOURCE ??
  resolve(dirname(fileURLToPath(import.meta.url)), 'build/site'));
// Documenter replaces build/ while compiling. Serve a completed snapshot so
// readers can keep navigating during a subsequent build. Restart to refresh.
const temporary = await mkdtemp(join(tmpdir(), 'perfchecker-doc-preview-'));
await cp(source, temporary, { recursive: true });
const root = await realpath(temporary);
const port = Number(process.env.PORT ?? 8870);
const mount = process.env.PERFCHECKER_DOCS_BASE ?? '/';
if (!/^\/(?:[A-Za-z0-9._-]+\/)*$/.test(mount)) throw new Error('Invalid documentation base');
if (!Number.isInteger(port) || port < 0 || port > 65535) throw new Error('Invalid PORT');
const types = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript',
  '.css': 'text/css', '.json': 'application/json', '.svg': 'image/svg+xml',
  '.png': 'image/png', '.jpg': 'image/jpeg', '.webp': 'image/webp',
  '.webm': 'video/webm', '.mp4': 'video/mp4', '.vtt': 'text/vtt; charset=utf-8',
  '.woff2': 'font/woff2', '.ico': 'image/x-icon' };
const inside = path => path === root || path.startsWith(root + sep);
const server = createServer(async (request, response) => {
  if (!['GET', 'HEAD'].includes(request.method)) {
    response.writeHead(405, { Allow: 'GET, HEAD' }).end();
    return;
  }
  try {
    let pathname = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
    // Preview only: Documenter supplies these files at publication time.
    if (mount !== '/' && (pathname === '/versions.js' || pathname === mount + 'siteinfo.js')) {
      const script = pathname === '/versions.js'
        ? 'window.DOC_VERSIONS ||= ["dev"];'
        : 'window.DOCUMENTER_CURRENT_VERSION ||= "dev";';
      response.writeHead(200, {'Content-Type':'text/javascript'}).end(request.method === 'HEAD' ? '' : script);
      return;
    }
    if (mount !== '/' && pathname.startsWith(mount)) pathname = '/' + pathname.slice(mount.length);
    const path = resolve(root, '.' + pathname);
    if (!inside(path)) { response.writeHead(403).end(); return; }
    let file;
    for (const candidate of [path, path + '.html', resolve(path, 'index.html')]) {
      try {
        const canonical = await realpath(candidate);
        if (inside(canonical) && (await stat(canonical)).isFile()) { file = canonical; break; }
      } catch { /* Try the next clean-URL representation. */ }
    }
    let status = file ? 200 : 404;
    file ??= resolve(root, '404.html');
    const { size } = await stat(file);
    let start = 0, end = size - 1;
    const headers = { 'Content-Type': types[extname(file)] ?? 'application/octet-stream',
      'Cache-Control': 'no-cache', 'Accept-Ranges': 'bytes', 'Content-Length': size };
    if (status === 200 && request.method === 'GET' && request.headers.range) {
      const range = /^bytes=(\d*)-(\d*)$/.exec(request.headers.range);
      if (!range || (!range[1] && !range[2])) {
        response.writeHead(416, { 'Content-Range': `bytes */${size}` }).end(); return;
      }
      start = range[1] ? Number(range[1]) : Math.max(0, size - Number(range[2]));
      end = range[1] && range[2] ? Math.min(Number(range[2]), size - 1) : size - 1;
      if (!Number.isSafeInteger(start) || !Number.isSafeInteger(end) || start > end || start >= size) {
        response.writeHead(416, { 'Content-Range': `bytes */${size}` }).end(); return;
      }
      status = 206;
      headers['Content-Range'] = `bytes ${start}-${end}/${size}`;
      headers['Content-Length'] = end - start + 1;
    }
    response.writeHead(status, headers);
    if (request.method === 'HEAD') response.end();
    else createReadStream(file, status === 206 ? { start, end } : {})
      .on('error', () => response.destroy()).pipe(response);
  } catch { response.writeHead(400).end(); }
});
server.on('error', error => { console.error(error.message); process.exitCode = 1; });
const cleanup = async () => {
  server.close();
  server.closeAllConnections();
  await rm(temporary, { recursive: true, force: true });
};
process.once('SIGINT', cleanup);
process.once('SIGTERM', cleanup);
server.listen(port, '127.0.0.1', () => console.log(`PerfChecker documentation: http://127.0.0.1:${server.address().port}${mount}`));
