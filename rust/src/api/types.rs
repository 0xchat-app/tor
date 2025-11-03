// SPDX-FileCopyrightText: 2025 0xChat
//
// SPDX-License-Identifier: MIT

use flutter_rust_bridge::frb;

/// Proxy type enumeration
#[frb]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProxyType {
    Socks5,
    HttpConnect,
}

/// Proxy information passed from Dart
#[frb]
#[derive(Debug, Clone)]
pub struct ProxyInfo {
    pub address: String,
    pub port: u16,
    pub proxy_type: ProxyType,
    pub username: Option<String>,
    pub password: Option<String>,
}

