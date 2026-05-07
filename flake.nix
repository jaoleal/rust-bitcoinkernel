{
  description = "rust-bitcoinkernel";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-25.05";
    flake-utils.url = "github:numtide/flake-utils";
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      fenix,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };

        rustVersion = "1.71.0";
        rustToolchainSha256 = "sha256-ks0nMEGGXKrHnfv4Fku+vhQ7gx76ruv6Ij4fKZR3l78=";
        rustToolchain = fenix.packages.${system}.fromToolchainName {
          name = rustVersion;
          sha256 = rustToolchainSha256;
        };
        rustBuildToolchain = fenix.packages.${system}.combine [
          rustToolchain.rustc
          rustToolchain.cargo
          rustToolchain.rust-src
          rustToolchain.rust-std
        ];

        rustBuildToolchainNightly = fenix.packages.${system}.latest.toolchain;

        rustPlatformNightly = pkgs.makeRustPlatform {
          cargo = rustBuildToolchainNightly;
          rustc = rustBuildToolchainNightly;
        };
        rustfilt = rustPlatformNightly.buildRustPackage rec {
          pname = "rustfilt";
          version = "0.2.1";
          src = pkgs.fetchFromGitHub {
            owner = "luser";
            repo = "rustfilt";
            rev = version;
            hash = "sha256-zb1tkeWmeMq7aM8hWssS/UpvGzGbfsaVYCOKBnAKwiQ=";
          };
          cargoLock.lockFile = "${src}/Cargo.lock";
        };
      in
      {
        devShells.default = pkgs.mkShell {
          packages = [
            rustBuildToolchain

            pkgs.cmake
            pkgs.boost.dev
            pkgs.cargo-fuzz
          ];

          LIBCLANG_PATH = "${pkgs.llvmPackages.clang-unwrapped.lib}/lib/";
        };

        devShells.nightly = pkgs.mkShell {
          packages = [
            rustBuildToolchainNightly

            pkgs.cmake
            pkgs.boost.dev
            pkgs.cargo-fuzz

            pkgs.libllvm
            pkgs.cargo-llvm-cov
            rustfilt
          ];

          LIBCLANG_PATH = "${pkgs.llvmPackages.clang-unwrapped.lib}/lib/";
          LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath [
            pkgs.gcc.cc.lib
          ];
        };

        packages =
          # Android build infrastructure (unfree NDK + SDK).
          let
            ndkVersion = "27.2.12479018"; # which NDK release to download
            lockfile = ./Cargo-minimal.lock;
            ANDROID_API_LEVEL = "24";
            crateVersion =
              (builtins.fromTOML (builtins.readFile ./libbitcoinkernel-sys/Cargo.toml)).package.version;

            androidPkgs = import nixpkgs {
              inherit system;
              config.android_sdk.accept_license = true;
              config.allowUnfree = true;
            };
            androidComposition = androidPkgs.androidenv.composeAndroidPackages {
              # platformVersions is the SDK tooling version, not the minimum API level.
              # The NDK target floor is set via ANDROID_API_LEVEL in build.rs (default 24).
              platformVersions = [ "34" ];
              ndkVersions = [ ndkVersion ];
              includeNDK = true;
            };
            androidSdk = androidComposition.androidsdk;
            androidNdk = "${androidSdk}/libexec/android-sdk/ndk/${ndkVersion}";

            mkAndroidPackage =
              rustTarget:
              let
                rustTargetToolchain = fenix.packages.${system}.combine [
                  rustToolchain.rustc
                  rustToolchain.cargo
                  rustToolchain.rust-src
                  rustToolchain.rust-std
                  (fenix.packages.${system}.targets.${rustTarget}.fromToolchainName {
                    name = rustVersion;
                    sha256 = rustToolchainSha256;
                  }).rust-std
                ];
                rustPlatform = androidPkgs.makeRustPlatform {
                  cargo = rustTargetToolchain;
                  rustc = rustTargetToolchain;
                };
              in
              rustPlatform.buildRustPackage {
                pname = "libbitcoinkernel-${rustTarget}";
                version = crateVersion;
                src = ./.;
                cargoLock.lockFile = lockfile;
                postPatch = ''
                  cp ${lockfile} Cargo.lock
                '';
                nativeBuildInputs = [
                  androidPkgs.cmake
                  androidPkgs.boost.dev
                  androidSdk
                ];

                ANDROID_HOME = "${androidSdk}/libexec/android-sdk";
                ANDROID_NDK_HOME = androidNdk;
                CMAKE_PREFIX_PATH = "${androidPkgs.boost.dev}";

                # cargoBuildHook hardcodes the host --target at
                # derivation time, so we bypass it for cross builds.
                dontCargoBuild = true;
                doCheck = false;
                buildPhase = "cargo build -p libbitcoinkernel-sys --target ${rustTarget} --offline --release";
                installPhase = ''
                  mkdir -p $out/lib $out/include
                  find target/${rustTarget}/release -path "*/out/install/lib/*.a" \
                  -exec cp {} $out/lib/ \;
                  find target/${rustTarget}/release -path "*/out/install/include/*" \
                  -exec cp {} $out/include/ \;'';
              };
          in
          {
            android-aarch64 = mkAndroidPackage "aarch64-linux-android";
            android-armv7 = mkAndroidPackage "armv7-linux-androideabi";
            android-x86_64 = mkAndroidPackage "x86_64-linux-android";
            # i686 omitted: not a current target
          };
      }
    );
}
