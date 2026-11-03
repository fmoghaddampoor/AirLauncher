# Air Launcher

A native Rust desktop launcher for coding agents using your JetBrains AI subscription.

Double-click **AirLauncher.exe** or the **Air Launcher** desktop shortcut. Choose a project folder, select an agent, and click **Open**. A new Windows Terminal window opens PowerShell in that folder. If Windows Terminal is unavailable, the launcher opens PowerShell directly. The startup script and its parameters are passed as one encoded command; launching never depends on an extracted script file.

Use **Sign in** once to connect your JetBrains account. Complete the browser flow before starting an agent. Recent folders, your agent choice, and Codex options are saved under `%APPDATA%\AirLauncher\settings.json`; credentials are handled by JetBrains. Existing preferences from `%USERPROFILE%\.air-launcher\settings.json` are imported when the new file does not exist.

Use the **Codex**, **Claude Code**, and **Gemini CLI** tabs to choose an agent; the last selected tab is remembered. The **Codex** tab lets you edit the model ID, reasoning effort, and permissions. Defaults are `gpt-6.1-sol`, `medium`, and **Full access** (no sandbox or approval prompts). **Workspace write** and **Read only** keep approval prompts for additional access. Changes are saved automatically, including when you close the launcher without opening an agent. Available models and reasoning levels depend on your gateway/account. These settings are passed only to Codex sessions launched here. Claude Code and Gemini CLI use their installed CLI settings.

The launcher forwards `--model <model> -c model_reasoning_effort=<effort>` through `central run codex --`, plus `--dangerously-bypass-approvals-and-sandbox` for Full access or `--sandbox <mode> --ask-for-approval on-request` for the other modes. See the [official Codex CLI reference](https://developers.openai.com/codex/cli/reference) and [configuration reference](https://developers.openai.com/codex/config-reference).

The launcher starts `central run <agent>` with inherited console handles for each interactive session. Output-filtering proxies such as RTK must not wrap the interactive agent: they turn stdout into a pipe, which Codex rejects with `stdout is not a terminal`. RTK is used for noninteractive diagnostics. Usage consumes JetBrains AI credits. **Gateway status** opens connection details in a terminal.

Codex uses a separate CLI installation at `%USERPROFILE%\.air-launcher\tools` and settings at `%USERPROFILE%\.air-launcher\codex`. This avoids the older system CLI's `service_tier = "default"` parsing error and its inability to load the gateway's separate profile files. Existing `.codex` settings remain intact. Sessions and trust choices are separate from the desktop app. Existing JetBrains authentication is reused. The user-folder location is accessible from both packaged applications and Windows Terminal; LocalAppData can be redirected into an application's private cache.

Requirements: Windows PowerShell, RTK, JetBrains Air Gateway / Central CLI, and the selected agent. Build.ps1 installs Codex 0.166.0 separately for the launcher; Claude Code and Gemini CLI must be installed on PATH. A different computer needs these tools and its own JetBrains sign-in.

Gateway setup: https://www.jetbrains.com/help/central-cli/quickstart.html

Build with Rust and npm, then install the desktop shortcut:

```powershell
rtk proxy powershell -NoProfile -ExecutionPolicy Bypass -File .\Build.ps1
rtk proxy powershell -NoProfile -ExecutionPolicy Bypass -File .\InstallShortcut.ps1
```

Run `rtk cargo test --release --locked`, `rtk cargo fmt --check`, and `rtk cargo clippy --release --all-targets --locked -- -D warnings` for checks. Run `powershell -NoProfile -File tests/TerminalArguments.ps1` to verify the terminal script's argument forwarding for each permission mode and the other agents without making a model request. Cargo.lock records Rust dependency versions. Previous executables are backed up under `legacy` before replacement.

To increment the patch version, build, verify, and publish a single executable, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Publish.ps1
```

Every publish increments the package version in `Cargo.toml` and synchronizes `Cargo.lock` before compiling. The window title shows `Air Launcher v<version>`. The outputs are `publish\<version>\AirLauncher.exe` and `publish\AirLauncher.exe` (the latest copy). Existing versioned releases are preserved. Each invocation increments the version, including retries after a failed build. Repository rules in `AGENTS.md` require a version bump and verified publish after every completed change.

The executable's icon and terminal script are embedded; no companion app files are needed. The destination computer still needs the tools listed above and its own sign-in. Publish output is excluded from Git. The taskbar and Explorer use the same bundled icon. To regenerate the icon assets, run `GenerateIcon.ps1` before building. Windows may cache icons for existing shortcuts; recreate the desktop shortcut with `InstallShortcut.ps1` if necessary.

The build also runs the release executable with `--verify-terminal`. This opens the actual Windows Terminal handoff, checks that PowerShell is attached to terminal stdout, loads the gateway configuration without a model request, and verifies a completion receipt under `%USERPROFILE%\.air-launcher`. Successful check windows close automatically. Failure details appear in `terminal-check-error.txt`. Build.ps1 migrates the previous launcher's tools and preferences while preserving the originals.
