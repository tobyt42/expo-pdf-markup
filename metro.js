/**
 * Metro config plugin for @tobyt/expo-pdf-markup.
 *
 * Add to your metro.config.js:
 *
 *   const { getDefaultConfig } = require('expo/metro-config');
 *   const { withPdfMarkup } = require('@tobyt/expo-pdf-markup/metro');
 *   const config = getDefaultConfig(__dirname);
 *   module.exports = withPdfMarkup(config);
 *
 * This does two things:
 *  1. Patches `import.meta` in pdfjs-dist source before Babel/hermes-parser
 *     sees it (pdfjs-dist uses it in a Node.js-only code path that is dead
 *     code in the browser, but Metro bundles as a non-module script so the
 *     browser's JS engine refuses to parse the bundle).
 *  2. Copies the pdfjs worker file to <projectRoot>/public/pdf.worker.min.mjs
 *     so it is served at /pdf.worker.min.mjs (same-origin, no CORS issues).
 */

'use strict';

const fs = require('fs');
const path = require('path');

// ---------------------------------------------------------------------------
// Babel transformer interface
// Metro loads this file as the babelTransformer, so it must export `transform`.
// ---------------------------------------------------------------------------

let _upstream = null;
function upstream(projectRoot) {
  if (_upstream) return _upstream;
  // Resolve @expo/metro-config from the consumer's project root. Using
  // require.resolve with a paths option works in both standard installs (where
  // @expo/metro-config is a transitive dep reachable from the project) and hoisted
  // monorepos (where it is deduplicated to the workspace root). Hard-coding the
  // path through expo's own node_modules directory breaks in the monorepo case.
  _upstream = require(
    require.resolve('@expo/metro-config/build/babel-transformer', { paths: [projectRoot] })
  );
  return _upstream;
}

module.exports.transform = function transform({ filename, src, options, plugins }) {
  // Replace `import.meta` with `({})` in pdfjs-dist files before any parser
  // sees the source. `({}).url` → undefined, which is harmless: the only use
  // (NodeCanvasFactory._createCanvas → createRequire(import.meta.url)) is
  // Node.js-only dead code that never runs in the browser.
  if (filename.includes('pdfjs-dist') && src.includes('import.meta')) {
    src = src.replace(/import\.meta/g, '({})');
  }
  return upstream(options.projectRoot).transform({ filename, src, options, plugins });
};

// ---------------------------------------------------------------------------
// Metro config helper
// ---------------------------------------------------------------------------

module.exports.withPdfMarkup = function withPdfMarkup(config) {
  // 1. Swap in this file as the babel transformer so import.meta is patched.
  config.transformer.babelTransformerPath = require.resolve('./metro.js');

  const projectRoot = config.projectRoot ?? process.cwd();
  const publicDir = path.join(projectRoot, 'public');

  // Locate the installed pdfjs-dist so we can copy its runtime assets.
  let pdfjsDir;
  try {
    pdfjsDir = path.dirname(require.resolve('pdfjs-dist/package.json'));
  } catch {
    console.warn(
      '[expo-pdf-markup] Could not find pdfjs-dist. ' +
        'Install it as a dependency to enable web PDF rendering.'
    );
    return config;
  }

  // 2. Copy the pdfjs worker to <projectRoot>/public/ so it is served at
  //    /pdf.worker.min.mjs (same-origin). Only copies if not already present,
  //    so repeated Metro restarts are fast.
  const workerDest = path.join(publicDir, 'pdf.worker.min.mjs');
  if (!fs.existsSync(workerDest)) {
    if (!fs.existsSync(publicDir)) {
      fs.mkdirSync(publicDir, { recursive: true });
    }
    fs.copyFileSync(path.join(pdfjsDir, 'build', 'pdf.worker.min.mjs'), workerDest);
    console.log('[expo-pdf-markup] Copied pdfjs worker → ' + workerDest);
  }

  // 3. Copy the pdfjs WebAssembly assets to <projectRoot>/public/wasm/ so they
  //    are served at /wasm/ (same-origin). pdfjs-dist v6 decodes JBIG2/CCITT
  //    fax, JPEG2000 and ICC data in WebAssembly and fetches these files at
  //    runtime; without them such image data (e.g. scanned pages, some music
  //    notation) renders blank. Copies any files not already present.
  const wasmSrcDir = path.join(pdfjsDir, 'wasm');
  const wasmDestDir = path.join(publicDir, 'wasm');
  if (fs.existsSync(wasmSrcDir)) {
    let copied = 0;
    for (const file of fs.readdirSync(wasmSrcDir)) {
      const dest = path.join(wasmDestDir, file);
      if (!fs.existsSync(dest)) {
        if (!fs.existsSync(wasmDestDir)) {
          fs.mkdirSync(wasmDestDir, { recursive: true });
        }
        fs.copyFileSync(path.join(wasmSrcDir, file), dest);
        copied++;
      }
    }
    if (copied > 0) {
      console.log('[expo-pdf-markup] Copied ' + copied + ' pdfjs wasm file(s) → ' + wasmDestDir);
    }
  }

  return config;
};
