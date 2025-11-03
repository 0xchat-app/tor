//
//  SystemProxyPlugin.swift
//  tor
//
//  Created by w on 2025/10/28.
//

import Foundation
import Flutter
import UIKit

public class SystemProxyPlugin: NSObject, FlutterPlugin {
    
    // MARK: - Constants
    
    private enum Constants {
        static let channelName = "com.oxchat.tor/system_proxy"
        
        enum Method {
            static let getSystemProxy = "getSystemProxy"
            static let isVpnActive = "isVpnActive"
        }
        
        enum ConfigKey {
            static let host = "host"
            static let port = "port"
            static let username = "username"
            static let password = "password"
        }
        
        enum ProxyType {
            static let http = "http"
            static let https = "https"
            static let socks5 = "socks5"
        }
        
        enum EnvVar {
            static let socksProxy = "SOCKS_PROXY"
            static let httpProxy = "HTTP_PROXY"
            static let httpsProxy = "HTTPS_PROXY"
        }
        
        enum VPN {
            static let scopedKey = "__SCOPED__"
            static let interfacePrefixes = ["utun", "ipsec", "ppp", "tun"]
        }
        
        enum DefaultPort {
            static let https = 443
            static let http = 80
            static let socks5 = 1080
            static let invalid = 0
        }
        
        // CFNetworkProxies keys (using string literals as constants are unavailable in iOS)
        enum SystemProxyKey {
            static let httpEnable = "HTTPEnable"
            static let httpProxy = "HTTPProxy"
            static let httpPort = "HTTPPort"
            
            static let httpsEnable = "HTTPSEnable"
            static let httpsProxy = "HTTPSProxy"
            static let httpsPort = "HTTPSPort"
            
            static let socksEnable = "SOCKSEnable"
            static let socksProxy = "SOCKSProxy"
            static let socksPort = "SOCKSPort"
        }
        
        static let proxyEnabled = 1
        static let testUrl = "https://www.apple.com"
    }
    
    // MARK: - Registration
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: Constants.channelName,
            binaryMessenger: registrar.messenger()
        )
        let instance = SystemProxyPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    // MARK: - Method Handling
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case Constants.Method.getSystemProxy:
            let proxyInfo = getSystemProxy()
            result(proxyInfo)
        case Constants.Method.isVpnActive:
            let vpnActive = isVpnActive()
            result(vpnActive)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - Helper Methods
    
    private func createEmptyConfig() -> [String: Any] {
        return [
            Constants.ConfigKey.host: "",
            Constants.ConfigKey.port: Constants.DefaultPort.invalid,
            Constants.ConfigKey.username: "",
            Constants.ConfigKey.password: ""
        ]
    }
    
    // MARK: - Proxy Detection
    
    /**
     * Get system proxy settings
     *
     * Returns a Dictionary with all proxy configurations (http, https, socks5)
     * Each type returns its host and port, or empty string if not configured
     */
    private func getSystemProxy() -> [String: Any] {
        var httpConfig = createEmptyConfig()
        var httpsConfig = createEmptyConfig()
        var socks5Config = createEmptyConfig()
        
        // Get proxy from CFNetworkCopySystemProxySettings
        if let proxySettings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] {
            // Check for HTTP proxy
            // Note: Using string constants as kCFNetworkProxiesHTTP* may be unavailable in iOS
            if let httpEnable = proxySettings[Constants.SystemProxyKey.httpEnable] as? Int,
               httpEnable == Constants.proxyEnabled,
               let httpHost = proxySettings[Constants.SystemProxyKey.httpProxy] as? String,
               let httpPort = proxySettings[Constants.SystemProxyKey.httpPort] as? Int {
                
                httpConfig[Constants.ConfigKey.host] = httpHost
                httpConfig[Constants.ConfigKey.port] = httpPort
            }
            
            // Check for HTTPS proxy
            // Note: kCFNetworkProxiesHTTPS* constants are unavailable in iOS
            if let httpsEnable = proxySettings[Constants.SystemProxyKey.httpsEnable] as? Int,
               httpsEnable == Constants.proxyEnabled,
               let httpsHost = proxySettings[Constants.SystemProxyKey.httpsProxy] as? String,
               let httpsPort = proxySettings[Constants.SystemProxyKey.httpsPort] as? Int {
                
                httpsConfig[Constants.ConfigKey.host] = httpsHost
                httpsConfig[Constants.ConfigKey.port] = httpsPort
            }
            
            // Check for SOCKS proxy
            // Note: Using string constants as kCFNetworkProxiesSOCKS* may be unavailable in iOS
            if let socksEnable = proxySettings[Constants.SystemProxyKey.socksEnable] as? Int,
               socksEnable == Constants.proxyEnabled,
               let socksHost = proxySettings[Constants.SystemProxyKey.socksProxy] as? String,
               let socksPort = proxySettings[Constants.SystemProxyKey.socksPort] as? Int {
                
                socks5Config[Constants.ConfigKey.host] = socksHost
                socks5Config[Constants.ConfigKey.port] = socksPort
            }
        }
        
        // Try to get VPN proxy settings
        if isVpnActive() {
            extractVpnProxies(httpConfig: &httpConfig, httpsConfig: &httpsConfig, socks5Config: &socks5Config)
        }
        
        // Build final result with all proxy types
        return [
            Constants.ProxyType.http: httpConfig,
            Constants.ProxyType.https: httpsConfig,
            Constants.ProxyType.socks5: socks5Config
        ]
    }
    
    private func extractVpnProxies(
        httpConfig: inout [String: Any],
        httpsConfig: inout [String: Any],
        socks5Config: inout [String: Any]
    ) {
        guard let url = URL(string: Constants.testUrl),
              let proxySettings = CFNetworkCopySystemProxySettings()?.takeRetainedValue(),
              let proxyDict = CFNetworkCopyProxiesForURL(url as CFURL, proxySettings)
                .takeRetainedValue() as? [[String: Any]] else {
            return
        }
        
        // CFProxy keys (system-provided constants)
        let typeKey = kCFProxyTypeKey as String
        let hostKey = kCFProxyHostNameKey as String
        let portKey = kCFProxyPortNumberKey as String
        
        // CFProxy type constants
        let httpType = kCFProxyTypeHTTP as String
        let httpsType = kCFProxyTypeHTTPS as String
        let socksType = kCFProxyTypeSOCKS as String
        
        for proxy in proxyDict {
            guard let proxyType = proxy[typeKey] as? String,
                  let host = proxy[hostKey] as? String,
                  let port = proxy[portKey] as? Int else {
                continue
            }
            
            let config = createConfig(host: host, port: port)
            
            // Only set if not already configured
            switch proxyType {
            case httpType where isConfigEmpty(httpConfig):
                httpConfig = config
            case httpsType where isConfigEmpty(httpsConfig):
                httpsConfig = config
            case socksType where isConfigEmpty(socks5Config):
                socks5Config = config
            default:
                break
            }
        }
    }
    
    private func createConfig(host: String, port: Int) -> [String: Any] {
        return [
            Constants.ConfigKey.host: host,
            Constants.ConfigKey.port: port,
            Constants.ConfigKey.username: "",
            Constants.ConfigKey.password: ""
        ]
    }
    
    private func isConfigEmpty(_ config: [String: Any]) -> Bool {
        return (config[Constants.ConfigKey.host] as? String ?? "").isEmpty
    }
    
    // MARK: - VPN Detection
    
    /**
     * Check if VPN is currently active
     */
    private func isVpnActive() -> Bool {
        return isVpnActiveViaScopedProxy() || isVpnActiveViaInterfaces()
    }
    
    private func isVpnActiveViaScopedProxy() -> Bool {
        guard let proxySettings = CFNetworkCopySystemProxySettings()?
            .takeRetainedValue() as? [String: Any] else {
            return false
        }
        return proxySettings[Constants.VPN.scopedKey] != nil
    }
    
    private func isVpnActiveViaInterfaces() -> Bool {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        guard getifaddrs(&ifaddr) == 0 else {
            return false
        }
        defer { freeifaddrs(ifaddr) }
        
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            
            guard let interface = ptr?.pointee,
                  let namePtr = interface.ifa_name else {
                continue
            }
            
            let name = String(cString: namePtr)
            
            // Check if interface name matches VPN prefixes
            if Constants.VPN.interfacePrefixes.contains(where: { name.hasPrefix($0) }) {
                return true
            }
        }
        
        return false
    }
    
    // MARK: - URL Parsing
    
    /**
     * Parse proxy URL in format: scheme://[user:pass@]host:port
     */
    private func parseProxyUrl(_ urlString: String, defaultType: String) -> [String: Any]? {
        guard let url = URL(string: urlString),
              let host = url.host else {
            return nil
        }
        
        let port = url.port ?? getDefaultPort(for: url.scheme?.lowercased(), fallbackType: defaultType)
        
        guard port > Constants.DefaultPort.invalid else {
            return nil
        }
        
        return [
            Constants.ConfigKey.host: host,
            Constants.ConfigKey.port: port,
            Constants.ConfigKey.username: url.user ?? "",
            Constants.ConfigKey.password: url.password ?? ""
        ]
    }
    
    private func getDefaultPort(for scheme: String?, fallbackType: String) -> Int {
        if let scheme = scheme {
            switch scheme {
            case "https":
                return Constants.DefaultPort.https
            case "http":
                return Constants.DefaultPort.http
            case "socks5", "socks":
                return Constants.DefaultPort.socks5
            default:
                break
            }
        }
        
        return fallbackType == Constants.ProxyType.socks5
            ? Constants.DefaultPort.socks5
            : Constants.DefaultPort.http
    }
}
