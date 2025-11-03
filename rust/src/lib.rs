mod frb_generated; /* AUTO INJECTED BY flutter_rust_bridge. This line may not be accurate, and you can change it according to your needs. */
// SPDX-FileCopyrightText: 2023 Foundation Devices Inc.
// SPDX-FileCopyrightText: 2024 Foundation Devices Inc.
// SPDX-FileCopyrightText: 2025 0xChat
//
// SPDX-License-Identifier: MIT

// FRB modules
pub mod bridge;
pub mod manager;

// Re-export FRB types for frb_generated.rs
pub use bridge::{ProxyInfo, ProxyType};

// Legacy modules (still used internally)
#[macro_use]
mod error;
mod proxy_provider;
mod util;

// Re-export util functions for platform-specific features
#[cfg(not(target_os = "windows"))]
pub use crate::util::{tor_get_nofile_limit, tor_set_nofile_limit};

// Note: All FFI functions have been migrated to FRB.
// The API surface is now 100% in bridge.rs (FRB).
// No more manual FFI callback handling!
