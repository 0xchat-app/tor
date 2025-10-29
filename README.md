<!--
SPDX-FileCopyrightText: 2022-2023 Foundation Devices Inc.
SPDX-FileCopyrightText: 2024 Foundation Devices Inc.

SPDX-License-Identifier: MIT
-->

# tor

[foundation-Devices/tor](https://github.com/Foundation-Devices/tor) is a multi-platform Flutter plugin for managing a Tor proxy.  Based on [arti](https://gitlab.torproject.org/tpo/core/arti).

## Getting started

### [Install rust](https://www.rust-lang.org/tools/install)

Use `rustup`, not `homebrew`.

### Install cargo ndk

```sh
cargo install cargo-ndk
```

### Cargokit

[Cargokit](https://github.com/irondash/cargokit) handles building, just `flutter run` it or run it in Android Studio or VS Code (untested).

To update Cargokit in the future, use:
```sh
git subtree pull --prefix cargokit https://github.com/irondash/cargokit.git main --squash
```

## Development

### FRB codegen

Generate Dart bindings from Rust FRB APIs:

```bash
flutter_rust_bridge_codegen generate \
  --rust-input crate::bridge \
  --rust-root rust/ \
  --dart-output lib/dart_api/bridge_generated.dart
```

## Example app

`flutter run` in `example` to run the example app

See `example/lib/main.dart` for usage.
