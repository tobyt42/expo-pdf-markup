const universalPreset = require('jest-expo/universal/jest-preset');

// The repository scripts (scripts/release/, scripts/repo-settings/) are Node-only tooling and
// never shipped, so their tests (`*.test.node.ts`) run in the Node project only.
const scriptRoots = ['<rootDir>/scripts/release', '<rootDir>/scripts/repo-settings'];
const rootsFor = ({ displayName }) =>
  displayName?.name === 'Node' ? ['<rootDir>/src', ...scriptRoots] : ['<rootDir>/src'];

module.exports = {
  ...universalPreset,
  projects: universalPreset.projects.map(({ watchPlugins, ...project }) => ({
    ...project,
    clearMocks: true,
    roots: rootsFor(project),
  })),
};
