use std::io;
use std::path::Path;

pub(crate) fn set_script_mode(dest: &Path, mode: u32) -> io::Result<()> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(dest, std::fs::Permissions::from_mode(mode))?;
    }
    #[cfg(not(unix))]
    {
        let _ = (dest, mode);
    }
    Ok(())
}
