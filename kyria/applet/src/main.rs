// SPDX-License-Identifier: GPL-3.0-only
use cosmic::cosmic_config::{Config, ConfigGet, ConfigSet};
use cosmic::iced::{Alignment, Border, Color, Subscription, time};
use cosmic::prelude::*;
use serde::Deserialize;
use std::{path::PathBuf, time::Duration};

const APP_ID: &str = "io.github.SMFloris.KyriaLayer";
const LABEL_CHARS: usize = 20;
const LABEL_SIZE: f32 = 14.0;
const BADGE_WIDTH: f32 = LABEL_CHARS as f32 * LABEL_SIZE * 0.6 + 16.0;
type Wings = (Vec<String>, Vec<String>);

#[derive(Debug, Deserialize)]
struct Status {
    connected: bool,
    layer: Option<u8>,
    #[serde(default)]
    name: Option<String>,
}

#[derive(Debug, PartialEq)]
enum Indicator {
    Offline,
    Number(u8),
    Named(u8, String),
}

fn indicator(status: Status) -> Indicator {
    match (status.connected, status.layer) {
        (true, Some(layer @ 0..=7)) => {
            let name: String = status.name.unwrap_or_default()
                .chars()
                .filter(|c| !c.is_control())
                .collect();
            let number = layer + 1;
            if name.trim().is_empty() {
                Indicator::Number(number)
            } else {
                let label = name.trim().to_string();
                let label = if label.chars().count() > LABEL_CHARS {
                    format!("{}…", label.chars().take(LABEL_CHARS - 1).collect::<String>())
                } else {
                    label
                };
                Indicator::Named(number, label)
            }
        }
        _ => Indicator::Offline,
    }
}

fn read_indicator(path: &std::path::Path) -> Indicator {
    let fresh = std::fs::metadata(path)
        .and_then(|m| m.modified())
        .ok()
        .and_then(|t| t.elapsed().ok())
        .is_some_and(|age| age < Duration::from_secs(5));
    if fresh {
        if let Ok(data) = std::fs::read(path) {
            if let Ok(status) = serde_json::from_slice(&data) {
                return indicator(status);
            }
        }
    }
    Indicator::Offline
}

const KEYBOARD_ICON: &[u8] = include_bytes!("../assets/keyboard-symbolic.svg");

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
    indicator: Indicator,
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
        let indicator = read_indicator(&path);
        (Self { core, path, indicator }, Task::none())
    }
    fn view(&self) -> Element<'_, Message> {
        let padding = self.core.applet.suggested_padding(true);
        let size = self.core.applet.suggested_size(true).0;
        let (number, label, connected) = match &self.indicator {
            Indicator::Named(number, label) => (number.to_string(), label.clone(), true),
            Indicator::Number(number) => (number.to_string(), String::new(), true),
            Indicator::Offline => ("—".into(), String::new(), false),
        };
        let keyboard = cosmic::widget::icon::from_svg_bytes(KEYBOARD_ICON)
            .symbolic(true).icon().size(size)
            .class(cosmic::theme::Svg::custom(move |_theme| {
                cosmic::widget::svg::Style {
                    color: Some(Color::from_rgba(0.90, 0.91, 0.92, if connected { 1.0 } else { 0.55 })),
                }
            }));
        // Leave room below and beside the keyboard for its small layer number.
        let icon_width = f32::from(size) + 4.0;
        let icon = cosmic::widget::container(keyboard)
            .width(icon_width).height(icon_width);
        let number = cosmic::widget::container(
            cosmic::widget::text(number).font(cosmic::font::bold()).size(11),
        )
        .width(icon_width).height(icon_width)
        .align_x(Alignment::End).align_y(Alignment::End)
        .class(cosmic::style::Container::Custom(Box::new(move |theme| {
            cosmic::widget::container::Style {
                text_color: Some(if connected {
                    theme.cosmic().accent_color().into()
                } else {
                    Color::from_rgba(0.90, 0.91, 0.92, 0.55)
                }),
                ..Default::default()
            }
        })));
        let keyboard = cosmic::iced::widget::stack([icon.into(), number.into()]);
        let badge = cosmic::widget::container(
            cosmic::widget::text(label).font(cosmic::font::mono()).size(LABEL_SIZE),
        )
        .width(BADGE_WIDTH)
        .align_x(Alignment::Center)
        .padding([2, 8])
        .class(cosmic::style::Container::Custom(Box::new(move |theme| {
            cosmic::widget::container::Style {
                border: Border {
                    color: Color::from_rgba(0.90, 0.91, 0.92, 0.30),
                    width: 1.0,
                    radius: 8.0.into(),
                },
                text_color: Some(theme.cosmic().accent_color().into()),
                ..Default::default()
            }
        })));
        let content: Element<'_, Message> = if self.core.applet.is_horizontal() {
            cosmic::widget::row([keyboard.into(), badge.into()])
                .spacing(6).align_y(Alignment::Center).into()
        } else {
            cosmic::widget::column([keyboard.into(), badge.into()])
                .spacing(4).align_x(Alignment::Center).into()
        };
        let padding = if self.core.applet.is_horizontal() {
            [padding.1, padding.0]
        } else {
            [padding.0, padding.1]
        };
        let content = cosmic::widget::container(content)
            .padding(padding);
        self.core.applet.autosize_window(content).into()
    }
    fn subscription(&self) -> Subscription<Message> {
        time::every(Duration::from_millis(100)).map(|_| Message::Tick)
    }
    fn update(&mut self, _: Message) -> Task<cosmic::Action<Message>> {
        self.indicator = read_indicator(&self.path);
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
                Indicator::Named(4, "Navigation".into()),
            ),
            (r#"{"connected":false,"layer":null}"#, Indicator::Offline),
            (r#"{"connected":true,"layer":8}"#, Indicator::Offline),
            (r#"{"connected":true,"layer":0,"name":""}"#, Indicator::Number(1)),
            (r#"{"connected":true,"layer":7}"#, Indicator::Number(8)),
            (r#"{"connected":true,"layer":1,"name":null}"#, Indicator::Number(2)),
            (r#"{"connected":true,"layer":2,"name":"  \n  "}"#, Indicator::Number(3)),
            (r#"{"connected":true,"layer":0,"name":"Typing\n"}"#, Indicator::Named(1, "Typing".into())),
            (r#"{"connected":true,"layer":0,"name":"abcdefghijklmnopqrst"}"#, Indicator::Named(1, "abcdefghijklmnopqrst".into())),
            (r#"{"connected":true,"layer":7,"name":"abcdefghijklmnopqrstu"}"#, Indicator::Named(8, "abcdefghijklmnopqrs…".into())),
            (r#"{"connected":true,"layer":1,"name":"αβγδεζηθικλμνξοπρσ"}"#, Indicator::Named(2, "αβγδεζηθικλμνξοπρσ".into())),
        ] {
            assert_eq!(indicator(serde_json::from_str(json).unwrap()), expected);
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
        assert_eq!(read_indicator(&path), Indicator::Offline);
        std::fs::write(&path, b"invalid").unwrap();
        assert_eq!(read_indicator(&path), Indicator::Offline);
        std::fs::write(&path, br#"{"connected":true,"layer":2,"name":"COSMIC"}"#).unwrap();
        assert_eq!(read_indicator(&path), Indicator::Named(3, "COSMIC".into()));
        let file = std::fs::OpenOptions::new().write(true).open(&path).unwrap();
        file.set_times(
            std::fs::FileTimes::new()
                .set_modified(std::time::SystemTime::now() - Duration::from_secs(6)),
        )
        .unwrap();
        assert_eq!(read_indicator(&path), Indicator::Offline);
        std::fs::remove_file(path).unwrap();
    }
}
