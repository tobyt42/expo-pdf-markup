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
 *     sees it (pdfjs-dist v4 uses it in a Node.js-only code path that is dead
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
  // sees the source. `({}).url` → undefined, which is harmless: the method
  // that uses it (NodeCanvasFactory._createCanvas) is Node.js-only dead code.
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

  // 2. Copy the pdfjs worker to <projectRoot>/public/ so it is served at
  //    /pdf.worker.min.mjs (same-origin). Only copies if not already present,
  //    so repeated Metro restarts are fast.
  const projectRoot = config.projectRoot ?? process.cwd();
  const publicDir = path.join(projectRoot, 'public');
  const dest = path.join(publicDir, 'pdf.worker.min.mjs');

  if (!fs.existsSync(dest)) {
    let workerSrc;
    try {
      workerSrc = require.resolve('pdfjs-dist/build/pdf.worker.min.mjs');
    } catch {
      console.warn(
        '[expo-pdf-markup] Could not find pdfjs-dist. ' +
          'Install it as a dependency to enable web PDF rendering.'
      );
      return config;
    }
    if (!fs.existsSync(publicDir)) {
      fs.mkdirSync(publicDir, { recursive: true });
    }
    fs.copyFileSync(workerSrc, dest);
    console.log('[expo-pdf-markup] Copied pdfjs worker → ' + dest);
  }

  return config;
};
