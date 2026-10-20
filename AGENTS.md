# Release requirements

- After every completed change to this repository, increment the application version and publish a verified release before reporting completion.
- Use `powershell -NoProfile -ExecutionPolicy Bypass -File .\Publish.ps1`. It increments the patch version in `Cargo.toml`, synchronizes `Cargo.lock`, builds, verifies the Windows Terminal handoff, and publishes the executable. Do not manually bump the patch version before running it.
- Keep the window title tied to `CARGO_PKG_VERSION` so it displays `Air Launcher v<version>`. Never hardcode a separate title version.
- Preserve each release at `publish\<version>\AirLauncher.exe` and update `publish\AirLauncher.exe` to the same executable. Never overwrite an existing versioned release.
- Include the new version and full executable path in the completion message. If publishing fails, resolve the failure before claiming the work is complete.
