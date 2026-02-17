use bindgen::RustEdition;
use std::env;
use std::path::Path;
use std::path::PathBuf;

fn main() {
    let bitcoin_dir = Path::new("bitcoin");

    // Iterate through all files in the Bitcoin Core submodule directory
    println!("cargo:rerun-if-changed={}", bitcoin_dir.display());

    let build_config = "RelWithDebInfo";

    let output_dir = cmake::Config::new("bitcoin")
        .profile(build_config)
        .no_default_flags(true)
        // Prevent the cmake crate from injecting cc-derived compiler flags
        // (e.g. /MD on MSVC) that conflict with Bitcoin Core's own CMakeLists.txt
        // flag management. Defining these prevents the cmake crate from
        // overriding them, and Bitcoin Core's build system manages all
        // necessary compiler flags itself via target_compile_options.
        .define("CMAKE_C_FLAGS", "")
        .define("CMAKE_CXX_FLAGS", "")
        .define("CMAKE_ASM_FLAGS", "")
        .define("BUILD_KERNEL_LIB", "ON")
        .define("BUILD_TESTS", "OFF")
        .define("BUILD_BENCH", "OFF")
        .define("BUILD_KERNEL_TEST", "OFF")
        .define("BUILD_TX", "OFF")
        .define("BUILD_WALLET_TOOL", "OFF")
        .define("ENABLE_WALLET", "OFF")
        .define("ENABLE_EXTERNAL_SIGNER", "OFF")
        .define("BUILD_UTIL", "OFF")
        .define("BUILD_BITCOIN_BIN", "OFF")
        .define("BUILD_DAEMON", "OFF")
        .define("BUILD_UTIL_CHAINSTATE", "OFF")
        .define("BUILD_CLI", "OFF")
        .define("BUILD_FUZZ_BINARY", "OFF")
        .define("BUILD_SHARED_LIBS", "OFF")
        .define("CMAKE_INSTALL_LIBDIR", "lib")
        .define("ENABLE_IPC", "OFF")
        .build();

    // Check if the build system used a multi-config generator
    let lib_dir = if output_dir.join("lib").join(build_config).exists() {
        output_dir.join("lib").join(build_config)
    } else {
        output_dir.join("lib")
    };

    println!("cargo:rustc-link-search=native={}", lib_dir.display());

    println!("cargo:rustc-link-lib=static=bitcoinkernel");

    // Header path for bindgen
    let include_path = output_dir.join("include");
    let header = include_path.join("bitcoinkernel.h");

    #[allow(deprecated)]
    let bindings = bindgen::Builder::default()
        .header(header.to_str().unwrap())
        .clang_arg("-DBITCOINKERNEL_STATIC")
        .rust_target(bindgen::RustTarget::Stable_1_71)
        .rust_edition(RustEdition::Edition2021)
        .generate()
        .expect("Unable to generate bindings");

    let out_path = PathBuf::from(
        env::var("OUT_DIR").expect("OUT_DIR was not defined by the cargo environment!"),
    );
    bindings
        .write_to_file(out_path.join("bindings.rs"))
        .expect("Couldn't write bindings!");

    let compiler = cc::Build::new().get_compiler();
    let target_os = std::env::var("CARGO_CFG_TARGET_OS").unwrap();

    if target_os == "windows" {
        println!("cargo:rustc-link-lib=bcrypt");
        println!("cargo:rustc-link-lib=shell32");
    }

    if compiler.is_like_clang() {
        if target_os == "macos" {
            println!("cargo:rustc-link-lib=dylib=c++");
        } else {
            println!("cargo:rustc-link-lib=dylib=stdc++");
        }
    } else if compiler.is_like_gnu() {
        println!("cargo:rustc-link-lib=dylib=stdc++");
    }
}
