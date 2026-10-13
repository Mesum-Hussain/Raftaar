# Three.js

`three-0.180.0.min.js` bundles the Three.js 0.180.0 exports used by `site/hero.js`.
The MIT license is included in `LICENSE-three.txt`.

To update the bundle, install the pinned Three.js and esbuild packages in a local build directory. Create an entry that re-exports the Three.js symbols imported by `site/hero.js`, then bundle it with esbuild using `--bundle --minify --format=esm --target=es2020 --legal-comments=external`. Copy the package license with the bundle. The site build requires no package installation.
