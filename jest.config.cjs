const universalPreset = require('jest-expo/universal/jest-preset');

module.exports = {
  ...universalPreset,
  projects: universalPreset.projects.map(({ watchPlugins, ...project }) => ({
    ...project,
    clearMocks: true,
    roots: ['<rootDir>/src'],
  })),
};
