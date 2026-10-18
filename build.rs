fn main() {
    println!("cargo:rerun-if-changed=assets/AirLauncher.ico");
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("windows") {
        winresource::WindowsResource::new()
            .set_icon("assets/AirLauncher.ico")
            .set("ProductName", "Air Launcher")
            .set("FileDescription", "Air Launcher")
            .compile()
            .expect("Failed to embed the Windows application icon");
    }
}
