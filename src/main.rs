#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use base64::{Engine, engine::general_purpose::STANDARD};
use eframe::egui::{self, Color32, FontId, RichText, Vec2};
use serde::{Deserialize, Serialize};
use std::{env, fs, io, path::PathBuf, process::Command};

const MINT: Color32 = Color32::from_rgb(156, 230, 210);
const BACKGROUND: Color32 = Color32::from_rgb(16, 24, 28);
const MUTED: Color32 = Color32::from_rgb(159, 175, 181);

#[derive(Default, Deserialize, Serialize)]
#[serde(default)]
struct Settings {
    #[serde(rename = "RecentFolders")]
    recent: Vec<String>,
    #[serde(rename = "Agent")]
    agent: String,
}

struct Launcher {
    settings: Settings,
    project: String,
    status: String,
    failed: bool,
}

fn app_directory() -> PathBuf {
    // Packaged applications can redirect LocalAppData to a private cache invisible to Windows Terminal.
    let base = env::var_os("USERPROFILE").unwrap_or_else(|| env::temp_dir().into_os_string());
    PathBuf::from(base).join(".air-launcher")
}

fn load_settings() -> Settings {
    let path = app_directory().join("settings.json");
    let bytes = fs::read(path).unwrap_or_default();
    parse_settings(&bytes)
}

fn parse_settings(bytes: &[u8]) -> Settings {
    let content = bytes.strip_prefix(&[0xef, 0xbb, 0xbf]).unwrap_or(bytes);
    serde_json::from_slice(content).unwrap_or_default()
}

fn normalize_project(input: &str) -> io::Result<PathBuf> {
    let trimmed = input.trim().trim_matches('"');
    let directory = PathBuf::from(trimmed);
    if !directory.is_dir() {
        return Err(io::Error::other("Choose an existing project folder first."));
    }
    // Avoid canonicalization: extended Windows paths are confusing to terminal tools.
    std::path::absolute(directory)
}

fn encoded_script(
    project: &std::path::Path,
    agent: &str,
    action: &str,
    receipt: Option<&std::path::Path>,
) -> String {
    let directory = app_directory();
    let payload = serde_json::json!({
        "project": project.to_string_lossy(),
        "agent": agent,
        "action": action,
        "app_directory": directory.to_string_lossy(),
        "receipt": receipt.map(|path| path.to_string_lossy().into_owned()).unwrap_or_default(),
    });
    let payload_json = payload.to_string();
    let payload_base64 = STANDARD.encode(payload_json.as_bytes());
    let script = format!(
        "$json = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('{payload_base64}'))\n\
         $launch = $json | ConvertFrom-Json\n\
         $parameters = @{{Project=$launch.project; Agent=$launch.agent; Action=$launch.action; AppDirectory=$launch.app_directory; ReceiptPath=$launch.receipt}}\n\
         & {{\n{}\n}} @parameters",
        include_str!("terminal.ps1")
    );
    let utf16_bytes: Vec<u8> = script.encode_utf16().flat_map(u16::to_le_bytes).collect();
    STANDARD.encode(utf16_bytes)
}

fn shell_arguments(
    project: &std::path::Path,
    agent: &str,
    action: &str,
    receipt: Option<&std::path::Path>,
) -> Vec<String> {
    let encoded_command = encoded_script(project, agent, action, receipt);
    let mut arguments = vec!["-NoLogo".into(), "-NoProfile".into()];
    if action != "check" {
        arguments.push("-NoExit".into());
    }
    arguments.extend([
        "-ExecutionPolicy".into(),
        "Bypass".into(),
        "-EncodedCommand".into(),
        encoded_command,
    ]);
    arguments
}

fn open_terminal(
    project: &std::path::Path,
    agent: &str,
    action: &str,
    receipt: Option<&std::path::Path>,
) -> io::Result<()> {
    let directory = app_directory();
    fs::create_dir_all(&directory)?;
    let arguments = shell_arguments(project, agent, action, receipt);
    let shell = "powershell.exe";
    let terminal = Command::new("wt.exe")
        .args(["-w", "new", "new-tab", shell])
        .args(&arguments)
        .current_dir(project)
        .spawn();
    if terminal.is_ok() {
        return Ok(());
    }

    use std::os::windows::process::CommandExt;
    Command::new(shell)
        .args(arguments)
        .current_dir(project)
        .creation_flags(0x00000010) // CREATE_NEW_CONSOLE
        .spawn()?;
    Ok(())
}

impl Launcher {
    fn new(context: &eframe::CreationContext<'_>) -> Self {
        let mut visuals = egui::Visuals::dark();
        visuals.panel_fill = BACKGROUND;
        visuals.window_fill = BACKGROUND;
        visuals.override_text_color = Some(Color32::from_rgb(234, 244, 242));
        visuals.extreme_bg_color = Color32::from_rgb(24, 39, 45);
        visuals.widgets.inactive.bg_fill = Color32::from_rgb(29, 46, 52);
        visuals.widgets.inactive.weak_bg_fill = Color32::from_rgb(29, 46, 52);
        visuals.widgets.inactive.bg_stroke = egui::Stroke::new(1.0, Color32::from_rgb(48, 72, 78));
        visuals.widgets.hovered.bg_fill = Color32::from_rgb(38, 66, 67);
        visuals.widgets.hovered.weak_bg_fill = Color32::from_rgb(38, 66, 67);
        visuals.widgets.hovered.bg_stroke = egui::Stroke::new(1.0, MINT);
        visuals.widgets.active.bg_fill = Color32::from_rgb(44, 82, 79);
        visuals.widgets.active.weak_bg_fill = Color32::from_rgb(44, 82, 79);
        visuals.widgets.active.bg_stroke = egui::Stroke::new(1.0, MINT);
        visuals.hyperlink_color = MINT;
        for widget in [
            &mut visuals.widgets.noninteractive,
            &mut visuals.widgets.inactive,
            &mut visuals.widgets.hovered,
            &mut visuals.widgets.active,
            &mut visuals.widgets.open,
        ] {
            widget.corner_radius = egui::CornerRadius::same(10);
        }
        visuals.selection.bg_fill = Color32::from_rgb(40, 90, 80);
        context.egui_ctx.set_visuals(visuals);
        let mut settings = load_settings();
        if !["codex", "claude", "gemini"].contains(&settings.agent.as_str()) {
            settings.agent = "codex".into();
        }
        let default_directory = env::current_dir().unwrap_or_default();
        let project = settings
            .recent
            .first()
            .cloned()
            .unwrap_or_else(|| default_directory.to_string_lossy().into_owned());
        Self {
            settings,
            project,
            status: "Ready when you are.".into(),
            failed: false,
        }
    }

    fn launch(&mut self, action: &str) {
        let project = match normalize_project(&self.project) {
            Ok(directory) => directory,
            Err(error) => {
                self.status = error.to_string();
                self.failed = true;
                return;
            }
        };
        if let Err(error) = open_terminal(&project, &self.settings.agent, action, None) {
            self.status = format!("Could not open PowerShell: {error}");
            self.failed = true;
            return;
        }
        self.failed = false;
        self.status = match action {
            "login" => "Complete JetBrains sign-in in the browser, then open your agent.",
            "status" => "Gateway connection details opened in a terminal.",
            _ => "Terminal opened. Codex uses its own compatible settings and CLI.",
        }
        .into();
        if action != "run" {
            return;
        }

        self.project = project.to_string_lossy().into_owned();
        self.settings
            .recent
            .retain(|entry| !entry.eq_ignore_ascii_case(&self.project));
        self.settings.recent.insert(0, self.project.clone());
        self.settings.recent.truncate(10);
        let save_result = (|| -> Result<(), Box<dyn std::error::Error>> {
            let bytes = serde_json::to_vec_pretty(&self.settings)?;
            fs::write(app_directory().join("settings.json"), bytes)?;
            Ok(())
        })();
        if save_result.is_err() {
            self.status.push_str(" Recent folders could not be saved.");
        }
    }
}

impl eframe::App for Launcher {
    fn ui(&mut self, ui: &mut egui::Ui, _frame: &mut eframe::Frame) {
        egui::CentralPanel::default()
            .frame(egui::Frame::new().fill(BACKGROUND).inner_margin(32.0))
            .show(ui, |ui| {
                ui.spacing_mut().item_spacing = Vec2::new(12.0, 14.0);
                ui.spacing_mut().button_padding = Vec2::new(14.0, 10.0);
                ui.spacing_mut().interact_size.y = 40.0;
                ui.horizontal(|ui| {
                    ui.label(RichText::new("air / launcher").size(20.0).color(MINT));
                    ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                        egui::Frame::new()
                            .fill(Color32::from_rgb(28, 57, 53))
                            .corner_radius(8)
                            .inner_margin(egui::Margin::symmetric(12, 6))
                            .show(ui, |ui| {
                                ui.label(RichText::new("JETBRAINS AI").size(10.0).color(MINT));
                            });
                    });
                });
                ui.add_space(12.0);
                ui.heading(RichText::new("A fresh space to build.").size(30.0));
                ui.label(RichText::new("Choose your project. Start your agent.").color(MUTED));
                ui.add_space(16.0);
                ui.label(RichText::new("PROJECT FOLDER").size(11.0).color(MUTED));
                ui.horizontal(|ui| {
                    let width = (ui.available_width() - 100.0).max(100.0);
                    ui.add_sized(
                        [width, 42.0],
                        egui::TextEdit::singleline(&mut self.project)
                            .font(FontId::proportional(14.0))
                            .vertical_align(egui::Align::Center)
                            .margin(egui::Margin::symmetric(12, 10))
                            .hint_text("Choose a project folder"),
                    );
                    if ui
                        .add_sized([84.0, 42.0], egui::Button::new("Browse..."))
                        .clicked()
                    {
                        let selected = rfd::FileDialog::new()
                            .set_directory(&self.project)
                            .pick_folder();
                        if let Some(directory) = selected {
                            self.project = directory.to_string_lossy().into_owned();
                        }
                    }
                });
                if !self.settings.recent.is_empty() {
                    egui::ComboBox::from_id_salt("recent")
                        .selected_text(RichText::new("Recent projects").size(13.0).color(MINT))
                        .width(ui.available_width())
                        .icon(|ui, rect, _visuals, is_open| {
                            let center = rect.center();
                            let direction = if is_open { -1.0 } else { 1.0 };
                            let left = center + egui::vec2(-4.0, -2.0 * direction);
                            let middle = center + egui::vec2(0.0, 2.0 * direction);
                            let right = center + egui::vec2(4.0, -2.0 * direction);
                            let stroke = egui::Stroke::new(1.5, MINT);
                            ui.painter().line_segment([left, middle], stroke);
                            ui.painter().line_segment([middle, right], stroke);
                        })
                        .show_ui(ui, |ui| {
                            for directory in &self.settings.recent {
                                let path = std::path::Path::new(directory);
                                let project_name =
                                    path.file_name().unwrap_or_default().to_string_lossy();
                                let selected = self.project.eq_ignore_ascii_case(directory);
                                let label = RichText::new(project_name).size(14.0);
                                if ui
                                    .add_sized(
                                        [ui.available_width(), 40.0],
                                        egui::Button::new(label).selected(selected),
                                    )
                                    .on_hover_text(directory)
                                    .clicked()
                                {
                                    self.project = directory.clone();
                                }
                            }
                        });
                }
                ui.add_space(6.0);
                ui.label(RichText::new("CODING AGENT").size(11.0).color(MUTED));
                ui.horizontal(|ui| {
                    let button_width = (ui.available_width() - 24.0) / 3.0;
                    for (agent, label) in [
                        ("codex", "Codex"),
                        ("claude", "Claude Code"),
                        ("gemini", "Gemini CLI"),
                    ] {
                        let selected = self.settings.agent == agent;
                        if ui
                            .add_sized(
                                [button_width, 40.0],
                                egui::Button::new(label).selected(selected),
                            )
                            .clicked()
                        {
                            self.settings.agent = agent.into();
                        }
                    }
                });
                ui.add_space(12.0);
                ui.horizontal(|ui| {
                    let agent_label = match self.settings.agent.as_str() {
                        "claude" => "Claude Code",
                        "gemini" => "Gemini CLI",
                        _ => "Codex",
                    };
                    let label = format!("Open {agent_label}");
                    let text = RichText::new(label).strong().color(BACKGROUND);
                    let width = (ui.available_width() - 112.0).max(160.0);
                    if ui
                        .add_sized([width, 46.0], egui::Button::new(text).fill(MINT))
                        .clicked()
                    {
                        self.launch("run");
                    }
                    if ui
                        .add_sized([96.0, 46.0], egui::Button::new("Sign in"))
                        .clicked()
                    {
                        self.launch("login");
                    }
                });
                let status_color = if self.failed {
                    Color32::from_rgb(240, 186, 146)
                } else {
                    MINT
                };
                ui.label(RichText::new(&self.status).color(status_color).size(13.0));
                ui.add_space(8.0);
                if ui.link("Gateway status").clicked() {
                    self.launch("status");
                }
                ui.label(
                    RichText::new("PowerShell sessions / JetBrains AI credits")
                        .color(MUTED)
                        .size(11.0),
                );
            });
    }
}

fn main() -> eframe::Result {
    if env::args().any(|argument| argument == "--verify-terminal") {
        let result = verify_terminal_handoff();
        if let Err(error) = result {
            let _ = fs::write(
                app_directory().join("terminal-check-error.txt"),
                error.to_string(),
            );
            std::process::exit(1);
        }
        std::process::exit(0);
    }
    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_inner_size([700.0, 620.0])
            .with_min_inner_size([660.0, 600.0]),
        renderer: eframe::Renderer::Glow,
        ..Default::default()
    };
    eframe::run_native(
        "Air Launcher",
        options,
        Box::new(|context| Ok(Box::new(Launcher::new(context)))),
    )
}

fn verify_terminal_handoff() -> io::Result<()> {
    let project = env::current_dir()?;
    let timestamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(io::Error::other)?
        .as_millis();
    let receipt = app_directory().join(format!("terminal-check-{timestamp}.txt"));
    open_terminal(&project, "codex", "check", Some(&receipt))?;
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(45);
    while std::time::Instant::now() < deadline {
        if let Ok(contents) = fs::read_to_string(&receipt) {
            if contents.trim() != "0" {
                return Err(io::Error::other(
                    "Terminal opened, but the gateway configuration check failed.",
                ));
            }
            return Ok(());
        }
        std::thread::sleep(std::time::Duration::from_millis(200));
    }
    Err(io::Error::other(
        "Windows Terminal did not return a startup receipt within 45 seconds.",
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_powershell_preferences_with_utf8_bom() {
        // Arrange: reproduce the previous launcher's encoding and actual project path.
        let fixture = br#"{"Agent":"codex","RecentFolders":["C:\\Users\\farzad.moghaddampoor\\Documents\\Repo\\AirCodexUsage"]}"#;
        let bytes = [&[0xef, 0xbb, 0xbf][..], fixture].concat();

        // Act: migrate the saved preferences into the Rust launcher.
        let settings = parse_settings(&bytes);

        // Assert: preserve both the chosen agent and the recent project.
        assert_eq!(settings.agent, "codex");
        assert_eq!(
            settings.recent,
            [r"C:\Users\farzad.moghaddampoor\Documents\Repo\AirCodexUsage"]
        );
    }

    #[test]
    fn encodes_windows_paths_without_a_temporary_script_dependency() {
        // Arrange: use the installed PowerShell location with its embedded space.
        let project = PathBuf::from(r"C:\Program Files\PowerShell\7");

        // Act: construct terminal arguments and decode the actual embedded launch payload.
        let arguments = shell_arguments(&project, "codex", "run", None);
        let payload = decode_launch_payload(&arguments);

        // Assert: preserve the complete path without passing a script filename to PowerShell.
        assert_eq!(payload["project"], project.to_string_lossy().as_ref());
        assert!(!arguments.iter().any(|argument| argument == "-File"));
        assert!(arguments.iter().any(|argument| argument == "-NoExit"));
    }

    #[test]
    fn configuration_check_finishes_without_leaving_an_interactive_shell() {
        // Arrange: use the real launcher workspace for a noninteractive configuration check.
        let project = PathBuf::from(r"C:\Users\farzad.moghaddampoor\Documents\Repo\AirCodexUsage");

        // Act: construct the same terminal script invocation used by the build check.
        let arguments = shell_arguments(&project, "codex", "check", None);
        let payload = decode_launch_payload(&arguments);

        // Assert: the check action is selected and PowerShell can exit when it finishes.
        assert!(!arguments.iter().any(|argument| argument == "-NoExit"));
        assert_eq!(payload["action"], "check");
    }

    #[test]
    fn sign_in_uses_the_embedded_script_with_the_selected_project() {
        // Arrange: use the exact project shown in the failed sign-in screenshot.
        let project = PathBuf::from(r"C:\Users\farzad.moghaddampoor\Documents\Repo\AirCodexUsage");

        // Act: build and decode the same command used by the Sign in button.
        let arguments = shell_arguments(&project, "codex", "login", None);
        let payload = decode_launch_payload(&arguments);

        // Assert: route sign-in correctly without the missing terminal-v2.ps1 handoff.
        assert_eq!(payload["action"], "login");
        assert_eq!(payload["project"], project.to_string_lossy().as_ref());
        assert!(
            !arguments
                .iter()
                .any(|argument| argument.contains("terminal-v2.ps1"))
        );
    }

    fn decode_launch_payload(arguments: &[String]) -> serde_json::Value {
        let encoded_position = arguments
            .iter()
            .position(|argument| argument == "-EncodedCommand")
            .unwrap();
        let command_bytes = STANDARD.decode(&arguments[encoded_position + 1]).unwrap();
        let code_units: Vec<u16> = command_bytes
            .chunks_exact(2)
            .map(|pair| u16::from_le_bytes([pair[0], pair[1]]))
            .collect();
        let script = String::from_utf16(&code_units).unwrap();
        let payload_base64 = script.split('\'').nth(1).unwrap();
        let payload_bytes = STANDARD.decode(payload_base64).unwrap();
        serde_json::from_slice(&payload_bytes).unwrap()
    }
}
