# Air Launcher

A native Rust desktop launcher for coding agents using your JetBrains AI subscription.

Double-click **AirLauncher.exe** or the **Air Launcher** desktop shortcut. Choose a project folder, select an agent, and click **Open**. A new Windows Terminal window opens PowerShell in that folder. If Windows Terminal is unavailable, the launcher opens PowerShell directly. The startup script and its parameters are passed as one encoded command; launching never depends on an extracted script file.

Use **Sign in** once to connect your JetBrains account. Complete the browser flow before starting an agent. Recent folders and your agent choice are saved under `%USERPROFILE%\.air-launcher\settings.json`; credentials are handled by JetBrains.

The launcher starts `central run <agent>` with inherited console handles for each interactive session. Output-filtering proxies such as RTK must not wrap the interactive agent: they turn stdout into a pipe, which Codex rejects with `stdout is not a terminal`. RTK is used for noninteractive diagnostics. Usage consumes JetBrains AI credits. **Gateway status** opens connection details in a terminal.

Codex uses a separate CLI installation at `%USERPROFILE%\.air-launcher\tools` and settings at `%USERPROFILE%\.air-launcher\codex`. This avoids the older system CLI's `service_tier = "default"` parsing error and its inability to load the gateway's separate profile files. Existing `.codex` settings remain intact. Sessions and trust choices are separate from the desktop app. Existing JetBrains authentication is reused. The user-folder location is accessible from both packaged applications and Windows Terminal; LocalAppData can be redirected into an application's private cache.

Requirements: Windows PowerShell, RTK, JetBrains Air Gateway / Central CLI, and the selected agent. Build.ps1 installs Codex 0.163.0 separately for the launcher; Claude Code and Gemini CLI must be installed on PATH. A different computer needs these tools and its own JetBrains sign-in.

Gateway setup: https://www.jetbrains.com/help/central-cli/quickstart.html

Build with Rust and npm, then install the desktop shortcut:

```powershell
rtk proxy powershell -NoProfile -ExecutionPolicy Bypass -File .\Build.ps1
rtk proxy powershell -NoProfile -ExecutionPolicy Bypass -File .\InstallShortcut.ps1
```

Run `rtk cargo test --release --locked`, `rtk cargo fmt --check`, and `rtk cargo clippy --release --all-targets --locked -- -D warnings` for checks. Cargo.lock records Rust dependency versions. Previous executables are backed up under `legacy` before replacement.

The build also runs the release executable with `--verify-terminal`. This opens the actual Windows Terminal handoff, checks that PowerShell is attached to terminal stdout, loads the gateway configuration without a model request, and verifies a completion receipt under `%USERPROFILE%\.air-launcher`. Successful check windows close automatically. Failure details appear in `terminal-check-error.txt`. Build.ps1 migrates the previous launcher's tools and preferences while preserving the originals.
