unsafe extern "C" {
    fn shelf_run();
}

fn main() {
    // AppKit owns the main thread and native event loop.
    unsafe { shelf_run() };
}
