const baseConfig = require('expo-module-scripts/eslint.config.base');
const { defineConfig } = require('eslint/config');

module.exports = defineConfig([
  ...baseConfig,
  {
    ignores: ['build/'],
  },
]);
