use std::{
    cell::RefCell,
    collections::{HashMap, HashSet},
    ffi::{CStr, CString, c_char, c_int},
    fs::{self, OpenOptions},
    io,
    path::{Path, PathBuf},
    time::{Duration, SystemTime, UNIX_EPOCH},
};

const TIMEOUT: Duration = Duration::from_secs(600);

unsafe extern "C" {
    fn shelf_run(capture: *const c_char, save: *const c_char);
    fn shelf_render(path: *const c_char, index: usize, count: usize, bytes: u64);
    fn shelf_error(message: *const c_char);
}

struct State {
    root: PathBuf,
    capture: PathBuf,
    save: PathBuf,
    pending: Vec<PathBuf>,
    selected: usize,
    known: HashSet<PathBuf>,
    candidates: HashMap<PathBuf, (u64, SystemTime)>,
    last_action: SystemTime,
    dragging: bool,
}

thread_local! {
    static STATE: RefCell<Option<State>> = const { RefCell::new(None) };
}

fn cstring(path: &Path) -> CString {
    use std::os::unix::ffi::OsStrExt;
    CString::new(path.as_os_str().as_bytes()).expect("A file path cannot contain a null byte")
}

fn report(error: impl std::fmt::Display) {
    let message =
        CString::new(error.to_string().replace('\0', " ")).expect("Error text has no null bytes");
    unsafe { shelf_error(message.as_ptr()) };
}

fn image_paths(directory: &Path) -> io::Result<Vec<PathBuf>> {
    let mut paths = Vec::new();
    for entry in fs::read_dir(directory)? {
        let entry = entry?;
        let path = entry.path();
        // Do not follow links or accept directories in the capture folder.
        if entry.file_type()?.is_file()
            && path.extension().and_then(|s| s.to_str()).is_some_and(|s| {
                ["png", "jpg", "jpeg", "heic", "tiff", "tif"]
                    .contains(&s.to_ascii_lowercase().as_str())
            })
        {
            paths.push(path);
        }
    }
    paths.sort();
    Ok(paths)
}

impl State {
    fn new() -> io::Result<Self> {
        let home = PathBuf::from(
            std::env::var_os("HOME").ok_or_else(|| io::Error::other("HOME is not set"))?,
        );
        let root = home.join("Library/Application Support/Screenshot Shelf");
        let capture = home.join("Pictures/Screenshot Shelf/Capture");
        let default_save = home.join("Pictures/Screenshot Shelf/Saved");
        for directory in [&root, &root.join("Pending"), &capture, &default_save] {
            fs::create_dir_all(directory)?;
        }
        let save = fs::read_to_string(root.join("save-folder"))
            .map(PathBuf::from)
            .unwrap_or(default_save);
        let pending = image_paths(&root.join("Pending"))?;
        let last_action = fs::read_to_string(root.join("last-action"))
            .ok()
            .and_then(|s| s.parse::<u64>().ok())
            .and_then(|s| UNIX_EPOCH.checked_add(Duration::from_secs(s)))
            .unwrap_or(UNIX_EPOCH);
        let known = image_paths(&capture)?.into_iter().collect();
        Ok(Self {
            root,
            capture,
            save,
            pending,
            selected: 0,
            known,
            candidates: HashMap::new(),
            last_action,
            dragging: false,
        })
    }

    fn touch(&mut self) {
        self.last_action = SystemTime::now();
        if let Ok(elapsed) = self.last_action.duration_since(UNIX_EPOCH)
            && let Err(error) =
                fs::write(self.root.join("last-action"), elapsed.as_secs().to_string())
        {
            report(error);
        }
    }

    fn render(&self) {
        let path = self.pending.get(self.selected).map(|p| cstring(p));
        let bytes = self
            .pending
            .iter()
            .filter_map(|p| fs::metadata(p).ok())
            .map(|m| m.len())
            .sum();
        unsafe {
            shelf_render(
                path.as_ref().map_or(std::ptr::null(), |p| p.as_ptr()),
                self.selected,
                self.pending.len(),
                bytes,
            )
        };
    }

    fn remove_selected(&mut self) -> io::Result<()> {
        if let Some(path) = self.pending.get(self.selected) {
            match fs::remove_file(path) {
                Ok(()) => {}
                Err(error) if error.kind() == io::ErrorKind::NotFound => {}
                Err(error) => return Err(error),
            }
            self.pending.remove(self.selected);
            self.selected = self.selected.min(self.pending.len().saturating_sub(1));
        }
        Ok(())
    }

    fn expire(&mut self) {
        if self.dragging || self.pending.is_empty() {
            return;
        }
        if SystemTime::now()
            .duration_since(self.last_action)
            .unwrap_or_default()
            < TIMEOUT
        {
            return;
        }
        // Delete only files owned by the app. Keep failed deletions available.
        self.pending.retain(|path| match fs::remove_file(path) {
            Ok(()) => false,
            Err(error) if error.kind() == io::ErrorKind::NotFound => false,
            Err(error) => {
                report(error);
                true
            }
        });
        self.selected = 0;
        self.render();
    }

    fn scan(&mut self) -> io::Result<bool> {
        let paths = image_paths(&self.capture)?;
        let present: HashSet<_> = paths.iter().cloned().collect();
        self.known.retain(|path| present.contains(path));
        self.candidates.retain(|path, _| present.contains(path));
        let mut retry = false;
        let mut changed = false;
        for path in paths {
            if self.known.contains(&path) {
                continue;
            }
            let metadata = fs::metadata(&path)?;
            let signature = (metadata.len(), metadata.modified()?);
            // Require two matching observations before taking a completed capture.
            if metadata.len() == 0 || self.candidates.get(&path) != Some(&signature) {
                self.candidates.insert(path, signature);
                retry = true;
                continue;
            }
            let stamp = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_nanos();
            let target = self.root.join("Pending").join(format!(
                "{stamp}-{}",
                path.file_name().unwrap_or_default().to_string_lossy()
            ));
            fs::rename(&path, &target)?;
            self.candidates.remove(&path);
            self.pending.push(target);
            self.selected = self.pending.len() - 1;
            self.touch();
            changed = true;
        }
        if changed {
            self.render();
        }
        Ok(retry)
    }

    fn save_selected(&mut self) -> io::Result<()> {
        let Some(source) = self.pending.get(self.selected) else {
            return Ok(());
        };
        fs::create_dir_all(&self.save)?;
        let name = source
            .file_name()
            .ok_or_else(|| io::Error::other("Screenshot has no file name"))?;
        let target = self.save.join(name);
        // create_new prevents an existing saved image from being overwritten.
        let mut output = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&target)?;
        let result = (|| {
            let mut input = fs::File::open(source)?;
            io::copy(&mut input, &mut output)?;
            output.sync_all()
        })();
        if let Err(error) = result {
            let _ = fs::remove_file(&target);
            return Err(error);
        }
        self.remove_selected()
    }
}

// AppKit calls these functions on the main thread. The adapter never holds Rust state.
#[unsafe(no_mangle)]
pub extern "C" fn rs_scan() -> c_int {
    STATE.with(|cell| {
        let mut state = cell.borrow_mut();
        let Some(state) = state.as_mut() else {
            return 0;
        };
        match state.scan() {
            Ok(retry) => retry.into(),
            Err(error) => {
                report(error);
                0
            }
        }
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn rs_action(action: c_int) {
    STATE.with(|cell| {
        let mut state = cell.borrow_mut();
        let Some(state) = state.as_mut() else {
            return;
        };
        if state.dragging && action != 5 && action != 6 {
            return;
        }
        state.touch();
        let result = match action {
            0 | 6 => state.remove_selected(),
            1 => state.save_selected(),
            2 => {
                state.selected = state.selected.saturating_sub(1);
                Ok(())
            }
            3 => {
                state.selected = (state.selected + 1).min(state.pending.len().saturating_sub(1));
                Ok(())
            }
            4 => {
                state.dragging = true;
                Ok(())
            }
            5 => {
                state.dragging = false;
                Ok(())
            }
            _ => Ok(()),
        };
        if action == 6 {
            state.dragging = false;
        }
        if let Err(error) = result {
            report(error);
        }
        state.render();
    });
}

#[unsafe(no_mangle)]
pub extern "C" fn rs_tick() {
    STATE.with(|cell| {
        if let Some(state) = cell.borrow_mut().as_mut() {
            state.expire();
        }
    });
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn rs_save_folder(path: *const c_char) {
    if path.is_null() {
        return;
    }
    use std::os::unix::ffi::OsStrExt;
    let path = PathBuf::from(std::ffi::OsStr::from_bytes(
        unsafe { CStr::from_ptr(path) }.to_bytes(),
    ));
    STATE.with(|cell| {
        if let Some(state) = cell.borrow_mut().as_mut() {
            if path == state.capture || path.starts_with(state.root.join("Pending")) {
                report("Select a save folder outside the capture and pending folders.");
                return;
            }
            if let Err(error) =
                fs::write(state.root.join("save-folder"), path.as_os_str().as_bytes())
            {
                report(error);
                return;
            }
            state.save = path;
        }
    });
}

#[unsafe(no_mangle)]
pub extern "C" fn rs_restore() {
    STATE.with(|cell| {
        if let Some(state) = cell.borrow_mut().as_mut() {
            state.expire();
            state.render();
        }
    });
}

fn main() {
    let state = match State::new() {
        Ok(state) => state,
        Err(error) => {
            eprintln!("Screenshot Shelf: {error}");
            return;
        }
    };
    let capture = cstring(&state.capture);
    let save = cstring(&state.save);
    STATE.with(|cell| *cell.borrow_mut() = Some(state));
    unsafe { shelf_run(capture.as_ptr(), save.as_ptr()) };
}
