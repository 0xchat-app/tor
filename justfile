# SPDX-FileCopyrightText: 2022 Foundation Devices Inc.
# SPDX-FileCopyrightText: 2025 0xChat
#
# SPDX-License-Identifier: MIT

# Generate FRB bindings
generate:
    flutter_rust_bridge_codegen generate \
        --rust-input crate::bridge \
        --rust-root rust/ \
        --dart-output lib/dart_api/bridge_generated.dart

# Build Rust library for development (host platform)
build:
    cd rust && cargo build --release

# Format code
format:
    cargo fmt --manifest-path rust/Cargo.toml && \
    dart format . && \
    dart analyze

# Clean build artifacts
clean:
    rm -rf android/build
    rm -rf example/build
    rm -rf rust/target
    cd example && flutter clean

# Build for Android (all architectures via cargokit)
build-android:
    cd example && flutter build apk --debug

# Build for iOS
build-ios:
    cd rust && cargo build --release --target aarch64-apple-ios
    cd rust && cargo build --release --target x86_64-apple-ios

# Run example app
run:
    cd example && flutter run

# Full rebuild (clean + generate + build)
rebuild: clean generate build

# Quick test (for development)
test:
    cd rust && cargo test
    dart test
