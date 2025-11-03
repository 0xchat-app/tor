use std::sync::{Arc, Mutex};
use once_cell::sync::Lazy;
use arti_client::config::CfgPath;
use arti_client::TorClientConfig;
use tor_rtcompat::tokio::TokioNativeTlsRuntime;
use tor_rtcompat::RuntimeSubstExt;
use tor_config::Listen;
use arti::socks;
use tokio::task::JoinHandle;
use std::net::SocketAddr;

use crate::bridge::{ProxyInfo, ProxyType};
use crate::proxy_provider::{ProxyAuth, ProxyConfig, ProxyTcpProvider};

// Global proxy state that Dart can update at any time
static CURRENT_PROXY: Lazy<Mutex<Option<ProxyInfo>>> = Lazy::new(|| Mutex::new(None));

// Tor service state
static STATE: Lazy<Mutex<Option<(u16, JoinHandle<anyhow::Result<()>>)>>> = 
    Lazy::new(|| Mutex::new(None));

/// Proxy callback implementation that reads from global state
struct StaticProxyProvider;

impl StaticProxyProvider {
    fn get_current_proxy() -> Option<ProxyConfig> {
        let proxy_guard = CURRENT_PROXY.lock().unwrap();
        
        eprintln!("[RUST] get_current_proxy called, CURRENT_PROXY contains: {:?}",
                  proxy_guard.as_ref().map(|p| format!("{}:{} ({:?})", p.address, p.port, p.proxy_type)));
        
        if let Some(proxy_info) = proxy_guard.as_ref() {
            let proxy_addr: SocketAddr = format!("{}:{}", proxy_info.address, proxy_info.port)
                .parse()
                .ok()?;
            
            let auth = if proxy_info.username.is_some() || proxy_info.password.is_some() {
                Some(ProxyAuth {
                    username: proxy_info.username.clone().unwrap_or_default(),
                    password: proxy_info.password.clone().unwrap_or_default(),
                })
            } else {
                None
            };

            let config = match proxy_info.proxy_type {
                ProxyType::Socks5 => Some(ProxyConfig::Socks5 { proxy_addr, auth }),
                ProxyType::HttpConnect => Some(ProxyConfig::HttpConnect { proxy_addr, auth }),
            };
            
            eprintln!("[RUST] ✅ Returning proxy config: {:?}", config);
            config
        } else {
            eprintln!("[RUST] ⚠️ CURRENT_PROXY is None, returning Direct");
            None
        }
    }
}

/// Start Tor service
/// 
/// If use_system_proxy is true, Tor will read proxy from global state (set via set_proxy).
/// If false or no proxy is set, direct connections will be used.
pub async fn start(
    socks_port: u16,
    state_dir: String,
    cache_dir: String,
    use_system_proxy: bool,
) -> anyhow::Result<u16> {
    eprintln!("[RUST] start called: port={}, use_proxy={}", socks_port, use_system_proxy);
    
    // If already started, return existing port
    if let Some((port, _)) = STATE.lock().unwrap().as_ref() {
        eprintln!("[RUST] Already started, returning port {}", port);
        return Ok(*port);
    }

    eprintln!("[RUST] Getting current Tokio runtime from FRB...");
    let base_runtime = TokioNativeTlsRuntime::current()?;
    eprintln!("[RUST] Runtime obtained successfully");
    
    // Always use proxy provider, but with Direct config when proxy is disabled
    let proxy_config = if use_system_proxy {
        eprintln!("[RUST] Setting up proxy provider (reads from global state)");
        
        // Create a ProxyConfig that dynamically reads from CURRENT_PROXY
        ProxyConfig::Dynamic(Arc::new(move |target: &SocketAddr| {
            let proxy = StaticProxyProvider::get_current_proxy();
            if let Some(ref p) = proxy {
                if std::env::var("TOR_PROXY_DEBUG").is_ok() {
                    eprintln!("[RUST] Dynamic proxy for {} -> {:?}", target, p);
                }
            }
            proxy
        }))
    } else {
        eprintln!("[RUST] Using direct connections (no proxy)");
        ProxyConfig::Direct
    };
    
    let proxy_provider = ProxyTcpProvider::new(base_runtime.clone(), proxy_config);
    let runtime = base_runtime.with_tcp_provider(proxy_provider);

    let mut cfg_builder = TorClientConfig::builder();
    cfg_builder
        .storage()
        .state_dir(CfgPath::new(state_dir))
        .cache_dir(CfgPath::new(cache_dir));
    cfg_builder.address_filter().allow_onion_addrs(true);

    let cfg = cfg_builder.build()?;
    eprintln!("[RUST] Config built, creating TorClient...");

    let client = arti_client::TorClient::with_runtime(runtime.clone())
        .config(cfg)
        .create_bootstrapped()
        .await?;
    eprintln!("[RUST] TorClient created and bootstrapped");

    let runtime_clone = runtime.clone();
    let client_clone = client.clone();
    let proxy_handle = tokio::spawn(async move {
        socks::run_socks_proxy(
            runtime_clone,
            client_clone,
            Listen::new_localhost(socks_port),
            None,
        ).await
    });

    *STATE.lock().unwrap() = Some((socks_port, proxy_handle));
    eprintln!("[RUST] start completed successfully, returning port {}", socks_port);
    Ok(socks_port)
}

/// Update current proxy configuration
/// 
/// This can be called at any time (before or during Tor operation).
/// Changes take effect for new connections.
pub fn set_proxy(proxy: Option<ProxyInfo>) {
    let mut current = CURRENT_PROXY.lock().unwrap();
    match &proxy {
        Some(p) => {
            eprintln!("[RUST] ✅ set_proxy called: Setting proxy to {}:{} ({:?})", p.address, p.port, p.proxy_type);
        }
        None => {
            eprintln!("[RUST] ✅ set_proxy called: Clearing proxy (direct connections)");
        }
    }
    *current = proxy;
    
    // Verify it was set
    eprintln!("[RUST] ✅ CURRENT_PROXY updated, now contains: {:?}", 
              current.as_ref().map(|p| format!("{}:{}", p.address, p.port)));
}

/// Stop Tor service
pub fn stop() {
    if let Some((_port, handle)) = STATE.lock().unwrap().take() {
        eprintln!("[RUST] Stopping Tor proxy");
        handle.abort();
    }
}

/// Set dormant mode (placeholder)
pub fn set_dormant(_soft_mode: bool) {
    eprintln!("[RUST] set_dormant not implemented (client not stored)");
}
