# AsteraDMXMidiBridge

- This is a native macOS Swift package. Run `swift test` and build the app bundle with `Scripts/package-app.zsh` before publishing.
- Land and test changes on `staging` before merging to `main`. Publish stable app bundles from version tags on `main`, using the release version in the app metadata.
- The app displays the version, build number, and build date/time. Increment the build number when packaging a new version. Keep the existing bundle identifier so users retain their saved fixture patches.
- Give each user-facing error a stable code, make its hover text point to the in-app Error list, and document the code in the [public error list](docs/error-list.md).
- Test hardware detection without sending DMX when possible. Report separately whether output was verified on a physical rig.
- Include the working directory when giving commands that should run from a fresh terminal.
