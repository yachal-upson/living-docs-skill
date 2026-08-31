//! Guards the in-repo Claude Code plugin bundle (ADR 0023, decision 1):
//! `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, and
//! `hooks/hooks.json` must keep parsing, stay plugin-rooted, and point only
//! at hook scripts that exist and are executable.

use serde_json::Value;
use std::fs;
#[cfg(unix)]
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};

#[cfg(unix)]
const PLUGIN_ROOT_PREFIX: &str = "\"${CLAUDE_PLUGIN_ROOT}\"/";

/// Resolves the repository root from the `cli` crate's manifest directory.
fn repo_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("cli crate has a parent directory")
        .to_path_buf()
}

/// Reads a repo-relative file and parses it as JSON, panicking with the
/// offending path on any I/O or parse failure.
fn read_json(relative_path: &str) -> Value {
    let path = repo_root().join(relative_path);
    let contents = fs::read_to_string(&path)
        .unwrap_or_else(|err| panic!("failed to read {}: {err}", path.display()));
    serde_json::from_str(&contents)
        .unwrap_or_else(|err| panic!("failed to parse {} as JSON: {err}", path.display()))
}

/// Flattens every nested `hooks[].command` string out of a parsed
/// `hooks.json` document, across all event groups (`PreToolUse`,
/// `SessionStart`, ...).
#[cfg(unix)]
fn collect_hook_commands(hooks_json: &Value) -> Vec<String> {
    let mut commands = Vec::new();
    let Some(groups) = hooks_json["hooks"].as_object() else {
        return commands;
    };
    for entries in groups.values() {
        let Some(entries) = entries.as_array() else {
            continue;
        };
        for entry in entries {
            let Some(nested) = entry["hooks"].as_array() else {
                continue;
            };
            for hook in nested {
                if let Some(command) = hook["command"].as_str() {
                    commands.push(command.to_string());
                }
            }
        }
    }
    commands
}

#[test]
fn manifests_parse_and_plugin_identifies_itself() {
    let plugin = read_json(".claude-plugin/plugin.json");
    read_json(".claude-plugin/marketplace.json");
    read_json("hooks/hooks.json");

    assert_eq!(plugin["name"], Value::String("living-docs".to_string()));

    let version = fs::read_to_string(repo_root().join("VERSION"))
        .expect("VERSION file exists")
        .trim()
        .to_string();
    assert_eq!(plugin["version"], Value::String(version));
}

#[test]
#[cfg(unix)]
fn hook_commands_are_plugin_rooted_and_point_at_executable_files() {
    let hooks_json = read_json("hooks/hooks.json");
    let commands = collect_hook_commands(&hooks_json);

    assert!(
        commands.len() >= 2,
        "expected at least two hook commands, found {}",
        commands.len()
    );

    for command in &commands {
        assert!(
            command.starts_with(PLUGIN_ROOT_PREFIX),
            "command does not start with the plugin-root prefix: {command}"
        );
        let relative_path = command.trim_start_matches(PLUGIN_ROOT_PREFIX);
        let script_path = repo_root().join(relative_path);
        let metadata = fs::metadata(&script_path).unwrap_or_else(|err| {
            panic!("hook script missing at {}: {err}", script_path.display())
        });
        assert!(
            metadata.is_file(),
            "{} is not a file",
            script_path.display()
        );
        assert!(
            metadata.permissions().mode() & 0o100 != 0,
            "{} is not owner-executable",
            script_path.display()
        );
    }
}

#[test]
fn marketplace_lists_exactly_one_self_hosted_living_docs_plugin() {
    let marketplace = read_json(".claude-plugin/marketplace.json");
    let plugins = marketplace["plugins"]
        .as_array()
        .expect("marketplace.json plugins is an array");

    assert_eq!(plugins.len(), 1, "expected exactly one plugin entry");

    let plugin = &plugins[0];
    assert_eq!(plugin["name"], Value::String("living-docs".to_string()));
    let source = plugin["source"].as_str().expect("source is a string");
    assert_eq!(source, "./");

    let plugin_manifest = repo_root().join(source).join(".claude-plugin/plugin.json");
    assert!(
        plugin_manifest.is_file(),
        "marketplace source does not resolve to a directory containing .claude-plugin/plugin.json: {}",
        plugin_manifest.display()
    );
}
