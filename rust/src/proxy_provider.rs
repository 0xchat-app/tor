//! Proxy support for Tor network connections
//!
//! This module provides TCP connection support through various proxy protocols
//! including SOCKS5, HTTP CONNECT, and dynamic callback-based proxies.

use std::future::Future;
use std::io::{Error as IoError, ErrorKind, Result as IoResult};
use std::net::{IpAddr, SocketAddr};
use std::pin::Pin;
use std::sync::Arc;

use futures::{AsyncRead, AsyncWrite, FutureExt};
use tor_rtcompat::{NetStreamProvider, StreamOps};

// Enable logging for debugging proxy connections
#[cfg(debug_assertions)]
macro_rules! proxy_log {
    ($($arg:tt)*) => {
        eprintln!("[TOR_PROXY] {}", format!($($arg)*))
    };
}

#[cfg(not(debug_assertions))]
macro_rules! proxy_log {
    ($($arg:tt)*) => {()};
}

/// Proxy configuration types
#[derive(Clone)]
pub enum ProxyConfig {
    /// No proxy, direct connection
    Direct,
    /// SOCKS5 proxy
    Socks5 {
        proxy_addr: SocketAddr,
        auth: Option<ProxyAuth>,
    },
    /// HTTP CONNECT proxy
    HttpConnect {
        proxy_addr: SocketAddr,
        auth: Option<ProxyAuth>,
    },
    /// Dynamic callback-based proxy
    Dynamic(Arc<dyn ProxyCallback>),
}

impl std::fmt::Debug for ProxyConfig {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Direct => write!(f, "ProxyConfig::Direct"),
            Self::Socks5 { proxy_addr, auth } => f
                .debug_struct("ProxyConfig::Socks5")
                .field("proxy_addr", proxy_addr)
                .field("auth", auth)
                .finish(),
            Self::HttpConnect { proxy_addr, auth } => f
                .debug_struct("ProxyConfig::HttpConnect")
                .field("proxy_addr", proxy_addr)
                .field("auth", auth)
                .finish(),
            Self::Dynamic(_) => write!(f, "ProxyConfig::Dynamic(<callback>)"),
        }
    }
}

/// Proxy authentication credentials
#[derive(Debug, Clone)]
pub struct ProxyAuth {
    pub username: String,
    pub password: String,
}

/// Trait for dynamic proxy callback
pub trait ProxyCallback: Send + Sync {
    /// Get proxy address for the target connection
    /// Returns None to use direct connection
    fn get_proxy(&self, target: &SocketAddr) -> Option<ProxyConfig>;
}

/// Implement ProxyCallback for closures
impl<F> ProxyCallback for F
where
    F: Fn(&SocketAddr) -> Option<ProxyConfig> + Send + Sync,
{
    fn get_proxy(&self, target: &SocketAddr) -> Option<ProxyConfig> {
        self(target)
    }
}

/// Hybrid TCP provider that supports proxy connections
#[derive(Clone)]
pub struct ProxyTcpProvider<T> {
    inner: T,
    proxy_config: Arc<ProxyConfig>,
}

impl<T> ProxyTcpProvider<T> {
    /// Create a new proxy TCP provider
    pub fn new(inner: T, proxy_config: ProxyConfig) -> Self {
        Self {
            inner,
            proxy_config: Arc::new(proxy_config),
        }
    }

    /// Create a direct connection provider (no proxy)
    #[allow(dead_code)]
    pub fn direct(inner: T) -> Self {
        Self::new(inner, ProxyConfig::Direct)
    }
}

impl<T> NetStreamProvider for ProxyTcpProvider<T>
where
    T: NetStreamProvider + Clone + Send + Sync + 'static,
    T::Stream: Send + Unpin + AsyncRead + AsyncWrite + StreamOps + 'static,
{
    type Stream = T::Stream;
    type Listener = T::Listener;

    fn connect<'a, 'b, 'c>(
        &'a self,
        addr: &'b SocketAddr,
    ) -> Pin<Box<dyn Future<Output = IoResult<Self::Stream>> + Send + 'c>>
    where
        'a: 'c,
        'b: 'c,
        Self: 'c,
    {
        let addr = *addr;
        let proxy_config = Arc::clone(&self.proxy_config);
        let inner = self.inner.clone();

        async move {
            // Resolve proxy configuration (handle dynamic case)
            let effective_config = match proxy_config.as_ref() {
                ProxyConfig::Dynamic(callback) => {
                    proxy_log!("Resolving dynamic proxy for target: {}", addr);
                    let resolved = callback.get_proxy(&addr).unwrap_or(ProxyConfig::Direct);
                    match &resolved {
                        ProxyConfig::Direct => proxy_log!("Dynamic proxy resolved to: Direct connection"),
                        ProxyConfig::Socks5 { proxy_addr, .. } => proxy_log!("Dynamic proxy resolved to: SOCKS5 via {}", proxy_addr),
                        ProxyConfig::HttpConnect { proxy_addr, .. } => proxy_log!("Dynamic proxy resolved to: HTTP CONNECT via {}", proxy_addr),
                        _ => {}
                    }
                    resolved
                }
                config => config.clone(),
            };

            // Connect through proxy or directly
            match effective_config {
                ProxyConfig::Direct => {
                    // Direct connection
                    proxy_log!("Connecting directly to {}", addr);
                    inner.connect(&addr).await
                }
                ProxyConfig::Socks5 { proxy_addr, auth } => {
                    // Connect via SOCKS5
                    proxy_log!("Connecting to {} via SOCKS5 proxy at {} (auth: {})", 
                              addr, proxy_addr, auth.is_some());
                    let result = connect_socks5(inner, proxy_addr, addr, auth.as_ref()).await;
                    if result.is_ok() {
                        proxy_log!("✓ Successfully connected to {} via SOCKS5 proxy {}", addr, proxy_addr);
                    } else {
                        proxy_log!("✗ Failed to connect to {} via SOCKS5 proxy {}: {:?}", 
                                  addr, proxy_addr, result.as_ref().err());
                    }
                    result
                }
                ProxyConfig::HttpConnect { proxy_addr, auth } => {
                    // Connect via HTTP CONNECT
                    proxy_log!("Connecting to {} via HTTP CONNECT proxy at {} (auth: {})", 
                              addr, proxy_addr, auth.is_some());
                    let result = connect_http(inner, proxy_addr, addr, auth.as_ref()).await;
                    if result.is_ok() {
                        proxy_log!("✓ Successfully connected to {} via HTTP CONNECT proxy {}", addr, proxy_addr);
                    } else {
                        proxy_log!("✗ Failed to connect to {} via HTTP CONNECT proxy {}: {:?}", 
                                  addr, proxy_addr, result.as_ref().err());
                    }
                    result
                }
                ProxyConfig::Dynamic(_) => {
                    unreachable!("Dynamic config should have been resolved")
                }
            }
        }
        .boxed()
    }

    fn listen<'a, 'b, 'c>(
        &'a self,
        addr: &'b SocketAddr,
    ) -> Pin<Box<dyn Future<Output = IoResult<Self::Listener>> + Send + 'c>>
    where
        'a: 'c,
        'b: 'c,
        Self: 'c,
    {
        self.inner.listen(addr)
    }
}

/// Connect to target via SOCKS5 proxy
async fn connect_socks5<T>(
    provider: T,
    proxy_addr: SocketAddr,
    target_addr: SocketAddr,
    auth: Option<&ProxyAuth>,
) -> IoResult<T::Stream>
where
    T: NetStreamProvider,
{
    // Connect to proxy server
    let mut stream = provider.connect(&proxy_addr).await?;

    // SOCKS5 handshake
    // Method selection
    if let Some(auth) = auth {
        // With authentication
        let methods = [0x05, 0x02, 0x00, 0x02]; // Version 5, 2 methods: no auth, username/password
        write_all(&mut stream, &methods).await?;

        let mut response = [0u8; 2];
        read_exact(&mut stream, &mut response).await?;

        if response[0] != 0x05 {
            return Err(IoError::new(ErrorKind::Other, "Invalid SOCKS5 version"));
        }

        if response[1] == 0x02 {
            // Username/password authentication
            let username = auth.username.as_bytes();
            let password = auth.password.as_bytes();

            let mut auth_req = vec![0x01]; // Auth version
            auth_req.push(username.len() as u8);
            auth_req.extend_from_slice(username);
            auth_req.push(password.len() as u8);
            auth_req.extend_from_slice(password);

            write_all(&mut stream, &auth_req).await?;

            let mut auth_resp = [0u8; 2];
            read_exact(&mut stream, &mut auth_resp).await?;

            if auth_resp[1] != 0x00 {
                return Err(IoError::new(ErrorKind::PermissionDenied, "SOCKS5 auth failed"));
            }
        } else if response[1] != 0x00 {
            return Err(IoError::new(ErrorKind::Other, "No acceptable SOCKS5 methods"));
        }
    } else {
        // No authentication
        let methods = [0x05, 0x01, 0x00]; // Version 5, 1 method: no auth
        write_all(&mut stream, &methods).await?;

        let mut response = [0u8; 2];
        read_exact(&mut stream, &mut response).await?;

        if response[0] != 0x05 || response[1] != 0x00 {
            return Err(IoError::new(ErrorKind::Other, "SOCKS5 handshake failed"));
        }
    }

    // Connection request
    let mut request = vec![0x05, 0x01, 0x00]; // Version, CONNECT, reserved

    match target_addr.ip() {
        IpAddr::V4(ip) => {
            request.push(0x01); // IPv4
            request.extend_from_slice(&ip.octets());
        }
        IpAddr::V6(ip) => {
            request.push(0x04); // IPv6
            request.extend_from_slice(&ip.octets());
        }
    }
    request.extend_from_slice(&target_addr.port().to_be_bytes());

    write_all(&mut stream, &request).await?;

    // Read response
    let mut response = [0u8; 10];
    read_exact(&mut stream, &mut response[0..4]).await?;

    if response[0] != 0x05 {
        return Err(IoError::new(ErrorKind::Other, "Invalid SOCKS5 response"));
    }

    if response[1] != 0x00 {
        return Err(IoError::new(
            ErrorKind::Other,
            format!("SOCKS5 connection failed: {}", response[1]),
        ));
    }

    // Skip the rest of the response based on address type
    match response[3] {
        0x01 => read_exact(&mut stream, &mut response[0..6]).await?, // IPv4 + port
        0x04 => read_exact(&mut stream, &mut response[0..18]).await?, // IPv6 + port
        0x03 => {
            // Domain name
            let mut len = [0u8; 1];
            read_exact(&mut stream, &mut len).await?;
            let mut domain = vec![0u8; len[0] as usize + 2]; // domain + port
            read_exact(&mut stream, &mut domain).await?;
        }
        _ => return Err(IoError::new(ErrorKind::Other, "Unknown SOCKS5 address type")),
    }

    Ok(stream)
}

/// Connect to target via HTTP CONNECT proxy
async fn connect_http<T>(
    provider: T,
    proxy_addr: SocketAddr,
    target_addr: SocketAddr,
    auth: Option<&ProxyAuth>,
) -> IoResult<T::Stream>
where
    T: NetStreamProvider,
{
    // Connect to proxy server
    let mut stream = provider.connect(&proxy_addr).await?;

    // Build HTTP CONNECT request
    let mut request = format!(
        "CONNECT {}:{} HTTP/1.1\r\nHost: {}:{}\r\n",
        target_addr.ip(),
        target_addr.port(),
        target_addr.ip(),
        target_addr.port()
    );

    if let Some(auth) = auth {
        use base64::{engine::general_purpose::STANDARD, Engine as _};
        let credentials = format!("{}:{}", auth.username, auth.password);
        let encoded = STANDARD.encode(credentials.as_bytes());
        request.push_str(&format!("Proxy-Authorization: Basic {}\r\n", encoded));
    }

    request.push_str("\r\n");

    write_all(&mut stream, request.as_bytes()).await?;

    // Read response
    let mut response = Vec::new();
    let mut buf = [0u8; 1];

    // Read until \r\n\r\n
    loop {
        read_exact(&mut stream, &mut buf).await?;
        response.push(buf[0]);

        if response.len() >= 4
            && &response[response.len() - 4..] == b"\r\n\r\n"
        {
            break;
        }

        if response.len() > 8192 {
            return Err(IoError::new(ErrorKind::Other, "HTTP response too large"));
        }
    }

    // Parse response
    let response_str = String::from_utf8_lossy(&response);
    if !response_str.starts_with("HTTP/1.1 200")
        && !response_str.starts_with("HTTP/1.0 200")
    {
        return Err(IoError::new(
            ErrorKind::Other,
            format!("HTTP CONNECT failed: {}", response_str.lines().next().unwrap_or("")),
        ));
    }

    Ok(stream)
}

/// Helper to write all bytes
async fn write_all<T>(stream: &mut T, buf: &[u8]) -> IoResult<()>
where
    T: AsyncWrite + Unpin,
{
    use futures::io::AsyncWriteExt;
    stream.write_all(buf).await
}

/// Helper to read exact bytes
async fn read_exact<T>(stream: &mut T, buf: &mut [u8]) -> IoResult<()>
where
    T: AsyncRead + Unpin,
{
    use futures::io::AsyncReadExt;
    stream.read_exact(buf).await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_proxy_config_creation() {
        let config = ProxyConfig::Socks5 {
            proxy_addr: "127.0.0.1:1080".parse().unwrap(),
            auth: None,
        };

        match config {
            ProxyConfig::Socks5 { proxy_addr, .. } => {
                assert_eq!(proxy_addr.port(), 1080);
            }
            _ => panic!("Wrong config type"),
        }
    }
}