use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

fn temp_dir(label: &str) -> PathBuf {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let dir = std::env::temp_dir().join(format!("living-docs-project-hook-{label}-{nanos}"));
    fs::create_dir_all(&dir).unwrap();
    dir
}

fn corpus_hook(name: &str) -> String {
    let path = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .join("skills/living-docs/hooks")
        .join(name);
    fs::read_to_string(path).unwrap()
}

fn path_without_living_docs() -> std::ffi::OsString {
    let current = std::env::var_os("PATH").unwrap_or_default();
    let filtered: Vec<PathBuf> = std::env::split_paths(&current)
        .filter(|dir| !dir.join("living-docs").is_file() && !dir.join("living-docs.exe").is_file())
        .collect();
    std::env::join_paths(filtered).unwrap()
}

#[test]
fn hook_scripts_resolve_the_project_local_binary_before_target_release() {
    let pre_commit = corpus_hook("pre-commit");
    let session = corpus_hook("session-context.sh");
    for body in [&pre_commit, &session] {
        assert!(body.contains("$ROOT/.living-docs/living-docs"));
        assert!(body.contains("$ROOT/.living-docs/living-docs.exe"));
        assert!(body.contains("$ROOT/target/release/living-docs.exe"));
        assert!(!body.contains("tools/living-docs"));
    }
    assert!(pre_commit.contains("check --plain"));
}

fn git_repo(label: &str) -> PathBuf {
    let project = temp_dir(label);
    let init = Command::new("git")
        .args(["init", "-q"])
        .current_dir(&project)
        .status()
        .unwrap();
    assert!(init.success());
    project
}

fn write_stub_binary(project: &Path) {
    let bin_dir = project.join(".living-docs");
    fs::create_dir_all(&bin_dir).unwrap();
    let bin = bin_dir.join("living-docs");
    fs::write(
        &bin,
        "#!/usr/bin/env bash\nprintf '%s\\n' \"$*\" > invoked.txt\n",
    )
    .unwrap();
    let chmod = Command::new("bash")
        .current_dir(project)
        .args(["-c", "chmod +x .living-docs/living-docs"])
        .status()
        .unwrap();
    assert!(chmod.success());
}

fn pre_commit_script() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .join("skills/living-docs/hooks/pre-commit")
}

#[test]
fn pre_commit_invokes_the_project_local_binary_when_path_has_none() {
    let project = git_repo("local-bin");
    write_stub_binary(&project);
    let output = Command::new("bash")
        .arg(pre_commit_script())
        .current_dir(&project)
        .env("PATH", path_without_living_docs())
        .output()
        .unwrap();
    assert!(output.status.success(), "{output:?}");
    let invoked = fs::read_to_string(project.join("invoked.txt")).unwrap();
    assert!(invoked.contains("check --plain"), "got: {invoked}");
    let _ = fs::remove_dir_all(&project);
}
