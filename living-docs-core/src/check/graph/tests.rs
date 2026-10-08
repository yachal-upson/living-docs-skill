use super::*;

#[test]
fn normpath_collapses_dot_and_dotdot_segments() {
    assert_eq!(normpath("docs/./a.md"), "docs/a.md");
    assert_eq!(
        normpath("docs/tables/../datasets/index.md"),
        "docs/datasets/index.md"
    );
    assert_eq!(normpath("/docs/../index.md"), "/index.md");
}

#[test]
fn normpath_treats_windows_separators_as_logical_separators() {
    assert_eq!(
        normpath(r"C:\repo\docs\adr\..\index.md"),
        "C:/repo/docs/index.md"
    );
}

#[test]
fn resolve_link_skips_external_and_anchor_only_targets() {
    assert_eq!(
        resolve_link("docs/index.md", "https://example.com/x", "docs"),
        None
    );
    assert_eq!(resolve_link("docs/index.md", "#section", "docs"), None);
    assert_eq!(
        resolve_link("docs/index.md", "mailto:a@b.com", "docs"),
        None
    );
}

#[test]
fn resolve_link_resolves_bundle_relative_and_file_relative_targets() {
    assert_eq!(
        resolve_link("docs/a/index.md", "/b/index.md", "docs"),
        Some("docs/b/index.md".to_string())
    );
    assert_eq!(
        resolve_link("docs/a/index.md", "./c.md", "docs"),
        Some("docs/a/c.md".to_string())
    );
}

#[test]
fn resolve_link_matches_windows_paths_with_logical_paths() {
    assert_eq!(
        resolve_link(
            r"C:\repo\docs\adr\index.md",
            "0001-decision.md",
            r"C:\repo\docs"
        ),
        Some("C:/repo/docs/adr/0001-decision.md".to_string())
    );
}

#[test]
fn links_in_excludes_targets_inside_fenced_code_blocks() {
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let path = std::env::temp_dir().join(format!("living-docs-graph-test-{nanos}.md"));
    fs::write(&path, "[live](live.md)\n```\n[fenced](fenced.md)\n```\n").unwrap();

    assert_eq!(links_in(&path), vec!["live.md".to_string()]);

    let _ = fs::remove_file(&path);
}
