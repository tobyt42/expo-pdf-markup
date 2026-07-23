// Learn more https://docs.expo.io/guides/customizing-metro
const { getDefaultConfig } = require('expo/metro-config');
// @tobyt/expo-pdf-markup is resolved through node_modules: example/package.json
// depends on it via "file:..", so npm symlinks the repo root into
// example/node_modules/@tobyt/expo-pdf-markup. That lets Metro resolve the built
// entry (build/index.js) — and its platform-specific .web files — exactly like a
// real consumer would. metro.config.js itself runs in plain Node.js before Metro
// starts, so it requires the plugin by relative path; real consumers use
// require('@tobyt/expo-pdf-markup/metro').
const { withPdfMarkup } = require('../metro');
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

// Watch the repo root so Metro can hash the package's built files, which the
// example/node_modules/@tobyt/expo-pdf-markup symlink resolves to.
config.watchFolders = [path.resolve(__dirname, '..')];

config.transformer.getTransformOptions = async () => ({
  transform: {
    inlineRequires: true,
  },
});

module.exports = withPdfMarkup(config);
