# Expo maintenance

Dependabot's Expo-family patch groups are notifications and inputs to a deliberate upgrade workflow. A green bot PR does not authorise directly merging Expo-managed changes, even patches.

Discover the installed skill by its identity **`upgrading-expo`**, through the executing agent's skill catalog/tooling. If unavailable, hold the Expo work and explain that prerequisite; continue independent approved updates. Do not substitute a remembered recipe or commit a machine-specific plugin path.

Before invoking it, establish the approved exact target and affected npm project(s), their current SDKs and relevant companion versions. Consult each project's installed SDK compatibility data (`expo/bundledNativeModules.json`), peers and upstream upgrade notes. The library and example can remain on different SDKs; evaluate each separately. Include related Expo/React/React Native packages, types, web and other managed companions when needed for that project's compatibility.

Use `upgrading-expo` for actual Expo-managed maintenance, including patch updates, within the approved target and repair scope. Its generic latest-SDK instructions remain subordinate to that target. If the required resolution would cross the approved SDK/React Native target or introduce a substantial migration, prepare the findings and hold for a new decision. Keep public library peer requirements compatible with the intended consumers.

Review resulting manifests, both relevant lockfiles, native configuration, patches and Metro-refreshed worker/rendering assets. Apply the parent skill's actual hosted build, native and browser evidence gates to the resulting head. Retain the original notification until the checked resulting PR merges and fully supersedes its current intended changes, following [consolidation](consolidation.md).
