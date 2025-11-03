// SPDX-FileCopyrightText: 2025 0xChat
//
// SPDX-License-Identifier: MIT

//! Public API module for Tor FFI
//! 
//! This module contains all the public APIs exposed to Dart via flutter_rust_bridge.
//! 
//! ## Organization
//! - `types`: Data types (ProxyInfo, ProxyType)
//! - `tor`: Tor service APIs (start, stop, setProxy, etc.)

pub mod types;
pub mod tor;

// Re-export public types and functions
pub use types::{ProxyInfo, ProxyType};
pub use tor::{
    tor_hello_frb,
    tor_start_frb,
    tor_set_proxy_frb,
    tor_stop_frb,
    tor_set_dormant_frb,
};

