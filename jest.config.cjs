const universalPreset = require('jest-expo/universal/jest-preset');

// The release scripts (scripts/release/) are Node-only tooling and never shipped, so their
// tests run in the Node project only.
const rootsFor = ({ displayName }) =>
  displayName?.name === 'Node' ? ['<rootDir>/src', '<rootDir>/scripts/release'] : ['<rootDir>/src'];

module.exports = {
  ...universalPreset,
  projects: universalPreset.projects.map(({ watchPlugins, ...project }) => ({
    ...project,
    clearMocks: true,
    roots: rootsFor(project),
  })),
};
