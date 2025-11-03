// SPDX-FileCopyrightText: 2023 Foundation Devices Inc.
// SPDX-FileCopyrightText: 2024 Foundation Devices Inc.
// SPDX-FileCopyrightText: 2025 0xChat
//
// SPDX-License-Identifier: MIT

// Generated code by flutter_rust_bridge
#[path = "generated/frb_generated.rs"]
mod frb_generated;

// Public API module (exposed to Dart via FRB)
pub mod api;

// Internal implementation modules
pub mod manager;

// Internal modules
#[macro_use]
mod error;
mod proxy_provider;
mod util;

// Re-export API types for frb_generated.rs
pub use api::{ProxyInfo, ProxyType};

// Re-export util functions for platform-specific features
#[cfg(not(target_os = "windows"))]
pub use crate::util::{tor_get_nofile_limit, tor_set_nofile_limit};

// Note: All FFI functions have been migrated to FRB.
// The API surface is now 100% in api module (FRB).
// No more manual FFI callback handling!
