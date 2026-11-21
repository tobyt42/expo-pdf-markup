const expoConfig = require('eslint-config-expo/flat');
const { defineConfig } = require('eslint/config');
const globals = require('globals');

module.exports = defineConfig([
  expoConfig,
  {
    ignores: ['build/'],
  },
  {
    files: ['src/**/__tests__/**/*.{ts,tsx}', 'scripts/release/__tests__/**/*.ts'],
    languageOptions: {
      globals: globals.jest,
    },
  },
]);
