import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { resolve, extname, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../site/example/', import.meta.url));
const config = JSON.parse(await readFile(new URL('../../example/app.json', import.meta.url)));
export const basePath = config.expo.experiments.baseUrl;
const types = {
  '.html': 'text/html',
  '.js': 'text/javascript',
  '.mjs': 'text/javascript',
  '.css': 'text/css',
  '.pdf': 'application/pdf',
  '.wasm': 'application/wasm',
  '.ttf': 'font/ttf',
  '.ico': 'image/x-icon',
  '.png': 'image/png',
};

createServer(async (req, res) => {
  try {
    const pathname = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
    if (!pathname.startsWith(`${basePath}/`)) throw new Error('Outside deployment base');
    const relative = pathname.slice(basePath.length + 1) || 'index.html';
    const filename = resolve(root, relative);
    if (!filename.startsWith(resolve(root) + sep)) throw new Error('Outside export');
    const body = await readFile(filename);
    res.writeHead(200, { 'Content-Type': types[extname(filename)] ?? 'application/octet-stream' });
    res.end(body);
  } catch {
    res.writeHead(404);
    res.end('Not found');
  }
}).listen(4173, '127.0.0.1');
