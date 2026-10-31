// Servidor local mínimo para probar la app: node servidor.mjs  →  http://localhost:5173
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join, normalize, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const raiz = fileURLToPath(new URL('.', import.meta.url));
const puerto = Number(process.env.PORT) || 5173;
const tipos = { '.html': 'text/html', '.css': 'text/css', '.js': 'text/javascript', '.mjs': 'text/javascript', '.svg': 'image/svg+xml', '.json': 'application/json' };

createServer(async (req, res) => {
  const ruta = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  const archivo = normalize(join(raiz, ruta === '/' ? 'index.html' : ruta));
  if (!archivo.startsWith(raiz.endsWith(sep) ? raiz : raiz + sep)) { res.writeHead(403).end(); return; }
  try {
    const cuerpo = await readFile(archivo);
    res.writeHead(200, { 'Content-Type': (tipos[extname(archivo)] || 'application/octet-stream') + '; charset=utf-8' }).end(cuerpo);
  } catch {
    res.writeHead(404).end('No encontrado');
  }
}).listen(puerto, () => console.log(`Parque Solar Valle Aurora en http://localhost:${puerto}`));
