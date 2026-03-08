/**
 * Custom Metro babel transformer that patches pdfjs-dist before Babel/hermes-parser
 * ever sees the source. pdfjs-dist v4 contains `import.meta.url` inside a
 * Node.js-only code path (NodeCanvasFactory._createCanvas). Metro bundles everything
 * as a non-module script, so the browser refuses to execute a bundle containing
 * `import.meta` even if the code path is never reached.
 *
 * We replace `import.meta` with `({})` — a plain empty object. The affected code
 * (`process.getBuiltinModule("module").createRequire(({}).url)`) is dead code in
 * a browser context; `process.getBuiltinModule` does not exist there.
 */

// Resolve the upstream Expo transformer relative to the expo package location so
// this works regardless of the machine's absolute paths.
const path = require('path');
const expoDir = path.dirname(require.resolve('expo/package.json'));
const upstreamTransformer = require(
  path.join(expoDir, 'node_modules/@expo/metro-config/build/babel-transformer')
);

module.exports.transform = function transform({ filename, src, options, plugins }) {
  if (filename.includes('pdfjs-dist') && src.includes('import.meta')) {
    src = src.replace(/import\.meta/g, '({})');
  }
  return upstreamTransformer.transform({ filename, src, options, plugins });
};
