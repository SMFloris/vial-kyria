// SPDX-License-Identifier: GPL-3.0-only
use cosmic::cosmic_config::{Config, ConfigGet, ConfigSet};
use cosmic::iced::{Subscription, time};
use cosmic::prelude::*;
use serde::Deserialize;
use std::{path::PathBuf, time::Duration};

const APP_ID: &str = "io.github.SMFloris.KyriaLayer";
type Wings = (Vec<String>, Vec<String>);

#[derive(Debug, Deserialize)]
struct Status {
    connected: bool,
    layer: Option<u8>,
    #[serde(default)]
    name: String,
}

fn label(status: Status) -> String {
    match (status.connected, status.layer) {
        (true, Some(layer @ 0..=7)) => {
            let name: String = status
                .name
                .chars()
                .filter(|c| !c.is_control())
                .take(24)
                .collect();
            if name.is_empty() {
                format!("L{layer}")
            } else {
                format!("L{layer} · {name}")
            }
        }
        _ => "Kyria offline".into(),
    }
}

fn read_label(path: &std::path::Path) -> String {
    let fresh = std::fs::metadata(path)
        .and_then(|m| m.modified())
        .ok()
        .and_then(|t| t.elapsed().ok())
        .is_some_and(|age| age < Duration::from_secs(5));
    if fresh {
        if let Ok(data) = std::fs::read(path) {
            if let Ok(status) = serde_json::from_slice(&data) {
                return label(status);
            }
        }
    }
    "Kyria offline".into()
}

fn add_to_wings(wings: &mut Wings) -> bool {
    if wings.0.iter().chain(&wings.1).any(|id| id == APP_ID) {
        return false;
    }
    let position = wings
        .1
        .iter()
        .position(|id| id == "com.system76.CosmicAppletStatusArea")
        .unwrap_or(wings.1.len());
    wings.1.insert(position, APP_ID.into());
    true
}

fn install_panel(panel: &str) -> Result<(), Box<dyn std::error::Error>> {
    let config = Config::new(&format!("com.system76.CosmicPanel.{panel}"), 1)?;
    // Fail rather than replace an unknown or absent panel layout.
    let mut wings = config
        .get::<Option<Wings>>("plugins_wings")?
        .ok_or("Panel has no plugin wings; configure the panel first")?;
    if add_to_wings(&mut wings) {
        config.set("plugins_wings", Some(wings))?;
    }
    Ok(())
}

struct App {
    core: cosmic::Core,
    path: PathBuf,
    label: String,
}

#[derive(Debug, Clone)]
enum Message {
    Tick,
}

impl cosmic::Application for App {
    type Executor = cosmic::executor::Default;
    type Flags = PathBuf;
    type Message = Message;
    const APP_ID: &'static str = APP_ID;

    fn core(&self) -> &cosmic::Core {
        &self.core
    }
    fn core_mut(&mut self) -> &mut cosmic::Core {
        &mut self.core
    }
    fn init(core: cosmic::Core, path: PathBuf) -> (Self, Task<cosmic::Action<Message>>) {
        let label = read_label(&path);
        (Self { core, path, label }, Task::none())
    }
    fn view(&self) -> Element<'_, Message> {
        let padding = self.core.applet.suggested_padding(true);
        cosmic::widget::container(self.core.applet.text(&self.label))
            .padding([padding.0 as u16, padding.1 as u16])
            .into()
    }
    fn subscription(&self) -> Subscription<Message> {
        time::every(Duration::from_millis(100)).map(|_| Message::Tick)
    }
    fn update(&mut self, _: Message) -> Task<cosmic::Action<Message>> {
        self.label = read_label(&self.path);
        Task::none()
    }
    fn style(&self) -> Option<cosmic::iced::theme::Style> {
        Some(cosmic::applet::style())
    }
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.first().map(String::as_str) == Some("--install-panel") {
        return install_panel(args.get(1).map(String::as_str).unwrap_or("Panel"));
    }
    let runtime = std::env::var("XDG_RUNTIME_DIR")?;
    let path = PathBuf::from(
        std::env::var("KYRIA_LAYER_STATUS_FILE")
            .unwrap_or_else(|_| "%t/kyria-layer.json".into())
            .replace("%t", &runtime),
    );
    cosmic::applet::run::<App>(path)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn labels_validate_connection_and_layer() {
        for (json, expected) in [
            (
                r#"{"connected":true,"layer":3,"name":"Navigation"}"#,
                "L3 · Navigation",
            ),
            (r#"{"connected":false,"layer":null}"#, "Kyria offline"),
            (r#"{"connected":true,"layer":8}"#, "Kyria offline"),
            (r#"{"connected":true,"layer":0,"name":""}"#, "L0"),
        ] {
            assert_eq!(label(serde_json::from_str(json).unwrap()), expected);
        }
    }
    #[test]
    fn panel_install_preserves_order_and_is_idempotent() {
        let mut wings = (
            vec!["left".into()],
            vec![
                "input".into(),
                "com.system76.CosmicAppletStatusArea".into(),
                "audio".into(),
            ],
        );
        assert!(add_to_wings(&mut wings));
        assert_eq!(wings.0, ["left"]);
        assert_eq!(
            wings.1,
            [
                "input",
                APP_ID,
                "com.system76.CosmicAppletStatusArea",
                "audio"
            ]
        );
        assert!(!add_to_wings(&mut wings));
    }
    #[test]
    fn missing_or_invalid_status_is_offline() {
        let path = std::env::temp_dir().join(format!("kyria-applet-test-{}", std::process::id()));
        assert_eq!(read_label(&path), "Kyria offline");
        std::fs::write(&path, b"invalid").unwrap();
        assert_eq!(read_label(&path), "Kyria offline");
        std::fs::write(&path, br#"{"connected":true,"layer":2,"name":"COSMIC"}"#).unwrap();
        assert_eq!(read_label(&path), "L2 · COSMIC");
        let file = std::fs::OpenOptions::new().write(true).open(&path).unwrap();
        file.set_times(
            std::fs::FileTimes::new()
                .set_modified(std::time::SystemTime::now() - Duration::from_secs(6)),
        )
        .unwrap();
        assert_eq!(read_label(&path), "Kyria offline");
        std::fs::remove_file(path).unwrap();
    }
}
