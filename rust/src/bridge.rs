// SPDX-FileCopyrightText: 2025 0xChat
//
// SPDX-License-Identifier: MIT

use flutter_rust_bridge::frb;
use crate::manager;

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

/// Minimal FRB-exposed API to validate toolchain
#[frb]
pub fn tor_hello_frb() -> String {
    "hello_from_frb".to_string()
}

/// Start Tor service
/// 
/// If use_system_proxy is true, Tor will use the proxy set via tor_set_proxy_frb().
/// If false or no proxy is set, direct connections will be used.
#[frb]
pub async fn tor_start_frb(
    socks_port: u16,
    state_dir: String,
    cache_dir: String,
    use_system_proxy: bool,
) -> anyhow::Result<u16> {
    manager::start(socks_port, state_dir, cache_dir, use_system_proxy).await
}

/// Update current proxy configuration
/// 
/// Pass None to clear proxy (use direct connection).
/// Pass Some(ProxyInfo) to set/update proxy.
/// 
/// This can be called while Tor is running to update proxy dynamically.
#[frb]
pub fn tor_set_proxy_frb(proxy: Option<ProxyInfo>) {
    manager::set_proxy(proxy);
}

/// Stop Tor service
#[frb]
pub fn tor_stop_frb() {
    manager::stop();
}

/// Set dormant mode
#[frb]
pub fn tor_set_dormant_frb(soft_mode: bool) {
    manager::set_dormant(soft_mode);
}


