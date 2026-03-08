// Learn more https://docs.expo.io/guides/customizing-metro
const { getDefaultConfig } = require('expo/metro-config');
// Use a direct path here — @tobyt/expo-pdf-markup is mapped by extraNodeModules
// inside Metro, but metro.config.js itself runs in plain Node.js before Metro starts.
// Real consumers use: require('@tobyt/expo-pdf-markup/metro')
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

module.exports = withPdfMarkup(config);
