// Learn more https://docs.expo.io/guides/customizing-metro
const { getDefaultConfig } = require('expo/metro-config');
const path = require('path');

const config = getDefaultConfig(__dirname);

// npm v7+ will install ../node_modules/react and ../node_modules/react-native because of peerDependencies.
// To prevent the incompatible react-native between ./node_modules/react-native and ../node_modules/react-native,
// excludes the one from the parent folder when bundling.
config.resolver.blockList = [
  ...Array.from(config.resolver.blockList ?? []),
  new RegExp(`${path.resolve('..', 'node_modules', 'react')}[/\\\\]`),
  new RegExp(`${path.resolve('..', 'node_modules', 'react-dom')}[/\\\\]`),
  new RegExp(`${path.resolve('..', 'node_modules', 'react-native')}[/\\\\]`),
];

config.resolver.nodeModulesPaths = [
  path.resolve(__dirname, './node_modules'),
  path.resolve(__dirname, '../node_modules'),
];

config.resolver.extraNodeModules = {
  '@tobyt/expo-pdf-markup': '..',
};

config.watchFolders = [path.resolve(__dirname, '..')];

config.transformer.getTransformOptions = async () => ({
  transform: {
    experimentalImportSupport: false,
    inlineRequires: true,
  },
});

// pdfjs-dist v4 uses `import.meta` in a Node.js-only code path. Metro bundles
// everything as a non-module script so the browser throws a SyntaxError at
// runtime. Patch the source text before Babel/hermes-parser ever sees it.
config.transformer.babelTransformerPath = require.resolve('./scripts/pdfjs-metro-transformer.js');

module.exports = config;
