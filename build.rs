use std::{env, path::PathBuf, process::Command};

fn run(command: &mut Command) {
    assert!(
        command.status().expect("Cannot start build tool").success(),
        "Native adapter build failed"
    );
}

fn main() {
    assert_eq!(
        env::var("CARGO_CFG_TARGET_OS").as_deref(),
        Ok("macos"),
        "This app requires macOS"
    );
    let out = PathBuf::from(env::var_os("OUT_DIR").expect("Missing build directory"));
    let object = out.join("shelf.o");
    run(Command::new("xcrun")
        .args([
            "clang",
            "-fobjc-arc",
            "-fblocks",
            "-Os",
            "-Wall",
            "-Wextra",
            "-Werror",
            "-mmacosx-version-min=26.0",
            "-c",
            "native/shelf.m",
            "-o",
        ])
        .arg(&object));
    run(Command::new("ar")
        .arg("crs")
        .arg(out.join("libshelf.a"))
        .arg(object));
    println!("cargo:rustc-link-search=native={}", out.display());
    println!("cargo:rustc-link-lib=static=shelf");
    for framework in [
        "AppKit",
        "ImageIO",
        "CoreGraphics",
        "ServiceManagement",
        "ApplicationServices",
    ] {
        println!("cargo:rustc-link-lib=framework={framework}");
    }
    println!("cargo:rustc-env=MACOSX_DEPLOYMENT_TARGET=26.0");
    println!("cargo:rerun-if-changed=native/shelf.m");
}
