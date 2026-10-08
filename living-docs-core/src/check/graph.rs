//! The OKF structural graph: directory-index membership and bundle-root
//! reachability, built from the inline links in `index.md` files. Mirrors
//! `strip_fences`/`links_in`/`resolve_link`/`normpath` from `lint-docs.sh`.

use super::{file_name_str, is_bundle_singleton, records, Reporter};
use std::collections::{HashSet, VecDeque};
use std::fs;
use std::path::{Path, PathBuf};

/// Every non-reserved concept file must be linked from its own directory's
/// `index.md`. A registry [`crate::doc_type::Identity::Singleton`] file at
/// the bundle root (e.g. `constitution.md`) is deliberately exempt: it is the
/// bundle's own root of trace, and has no directory index to be listed in.
pub(crate) fn check_directory_membership(
    bundle: &Path,
    all_md: &[PathBuf],
    reporter: &mut Reporter,
) {
    for f in all_md {
        if records::is_reserved(&file_name_str(f)) || is_bundle_singleton(bundle, f) {
            continue;
        }
        check_file_is_indexed(bundle, f, reporter);
    }
}

fn check_file_is_indexed(bundle: &Path, f: &Path, reporter: &mut Reporter) {
    let dir = f.parent().unwrap_or_else(|| Path::new("."));
    let dir_index = dir.join("index.md");
    if !dir_index.is_file() {
        reporter.report(
            f,
            format!(
                "no index.md in its directory ({}) — orphan (invariant 3)",
                dir.display()
            ),
        );
        return;
    }
    if !is_listed_in(bundle, &dir_index, f) {
        reporter.report(
            f,
            format!(
                "not listed in {} — orphan (invariant 3)",
                dir_index.display()
            ),
        );
    }
}

fn is_listed_in(bundle: &Path, dir_index: &Path, target: &Path) -> bool {
    let bundle_str = bundle.to_string_lossy();
    let dir_index_str = dir_index.to_string_lossy();
    let target_norm = normpath(&target.to_string_lossy());
    links_in(dir_index).into_iter().any(|tgt| {
        resolve_link(&dir_index_str, &tgt, &bundle_str).is_some_and(|r| r == target_norm)
    })
}

/// Every directory `index.md` must be reachable from the bundle-root `index.md`
/// via BFS over index→index (and index→dir) links.
pub(crate) fn check_reachability(
    bundle: &Path,
    root_index: &Path,
    all_md: &[PathBuf],
    reporter: &mut Reporter,
) {
    if !root_index.is_file() {
        return;
    }
    let reached = reachable_index_set(bundle, root_index);
    for idx in all_md.iter().filter(|f| file_name_str(f) == "index.md") {
        let n = normpath(&idx.to_string_lossy());
        if !reached.contains(&n) {
            reporter.report(
                idx,
                format!(
                    "directory index not reachable from {} (invariant 3)",
                    root_index.display()
                ),
            );
        }
    }
}

fn reachable_index_set(bundle: &Path, root_index: &Path) -> HashSet<String> {
    let bundle_str = bundle.to_string_lossy().to_string();
    let root = normpath(&root_index.to_string_lossy());

    let mut reached = HashSet::new();
    let mut queue = VecDeque::new();
    reached.insert(root.clone());
    queue.push_back(root);

    while let Some(cur) = queue.pop_front() {
        if !Path::new(&cur).is_file() {
            continue;
        }
        for target in reachable_targets_from(&cur, &bundle_str) {
            if reached.insert(target.clone()) {
                queue.push_back(target);
            }
        }
    }
    reached
}

fn reachable_targets_from(cur: &str, bundle_str: &str) -> Vec<String> {
    links_in(Path::new(cur))
        .into_iter()
        .filter_map(|tgt| resolve_link(cur, &tgt, bundle_str))
        .map(|resolved| {
            if Path::new(&resolved).is_dir() {
                normpath(&format!("{resolved}/index.md"))
            } else {
                resolved
            }
        })
        .filter(|resolved| basename(resolved) == "index.md")
        .collect()
}

fn basename(path: &str) -> &str {
    path.rsplit('/').next().unwrap_or(path)
}

pub(crate) fn dirname_str(path: &str) -> String {
    match path.rfind('/') {
        Some(0) => "/".to_string(),
        Some(idx) => path[..idx].to_string(),
        None => ".".to_string(),
    }
}

/// Collapses `.` and `..` segments in a `/`-separated path. Pure string logic —
/// the path need not exist on disk.
pub(crate) fn normpath(path: &str) -> String {
    let path = path.replace('\\', "/");
    let is_abs = path.starts_with('/');
    let mut out: Vec<&str> = Vec::new();
    for seg in path.split('/') {
        match seg {
            "" | "." => {}
            ".." => normpath_pop_or_push(&mut out, is_abs),
            s => out.push(s),
        }
    }
    let joined = out.join("/");
    if is_abs {
        format!("/{joined}")
    } else {
        joined
    }
}

fn normpath_pop_or_push(out: &mut Vec<&str>, is_abs: bool) {
    let last_is_dotdot = out.last() == Some(&"..");
    if !out.is_empty() && !last_is_dotdot {
        out.pop();
    } else if !is_abs {
        out.push("..");
    }
}

/// Resolves a markdown link target (as written in `file`) to a normalized
/// path, or `None` if the link is external / a pure anchor / unsupported.
fn resolve_link(file: &str, raw_target: &str, bundle: &str) -> Option<String> {
    let file = normpath(file);
    let bundle = normpath(bundle);
    let target = extract_link_target(raw_target)?;
    if target.contains("://") || target.starts_with("mailto:") || target.starts_with("tel:") {
        return None;
    }
    let joined = if target.starts_with('/') {
        format!("{bundle}/{target}")
    } else {
        format!("{}/{}", dirname_str(&file), target)
    };
    Some(normpath(&joined))
}

fn extract_link_target(raw_target: &str) -> Option<String> {
    let target = raw_target.trim_start();
    let mut buf = if let Some(rest) = target.strip_prefix('<') {
        let end = rest.find('>').unwrap_or(rest.len());
        rest[..end].to_string()
    } else {
        let end = target.find(char::is_whitespace).unwrap_or(target.len());
        target[..end].to_string()
    };
    if let Some(pos) = buf.find('#') {
        buf.truncate(pos);
    }
    if buf.is_empty() {
        None
    } else {
        Some(buf)
    }
}

/// Strips fenced (``` / ~~~) code-block regions so example links inside them
/// are not mistaken for live links. Indented (4-space) code blocks are out of
/// scope, matching `lint-docs.sh`.
fn strip_fences(content: &str) -> String {
    let mut in_fence = false;
    let mut out = String::new();
    for line in content.lines() {
        let trimmed = line.trim_start();
        if trimmed.starts_with("```") || trimmed.starts_with("~~~") {
            in_fence = !in_fence;
            continue;
        }
        if !in_fence {
            out.push_str(line);
            out.push('\n');
        }
    }
    out
}

/// Every inline markdown link target (the bit inside the parentheses) in
/// `path`, fenced code blocks excluded. Reference-style `[x][ref]` links are
/// not extracted (link *validity* — S5 — will use a real markdown parser).
///
/// Reads `path` straight from the filesystem rather than through
/// `DocStore::read`: `path` here is always an `index.md` (a directory index
/// or the bundle root), and `index.md`/`log.md` are excluded from the
/// record domain by design (`db_store::record::is_reserved`) — no backend
/// ever stores their content, so this traversal has no port to read them
/// through.
fn links_in(path: &Path) -> Vec<String> {
    let Ok(content) = fs::read_to_string(path) else {
        return Vec::new();
    };
    extract_paren_targets(&strip_fences(&content))
}

fn extract_paren_targets(text: &str) -> Vec<String> {
    let mut targets = Vec::new();
    let mut cursor = 0;
    while let Some(rel) = text[cursor..].find("](") {
        let start = cursor + rel + 2;
        let Some(rel_end) = text[start..].find(')') else {
            break;
        };
        let end = start + rel_end;
        if end > start {
            targets.push(text[start..end].to_string());
        }
        cursor = end + 1;
    }
    targets
}

#[cfg(test)]
mod tests;
