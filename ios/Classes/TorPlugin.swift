//
//  SystemProxyPlugin.swift
//  tor
//
//  Created by w on 2025/10/28.
//

import Flutter
import UIKit

public class TorPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        SystemProxyPlugin.register(with: registrar)
    }
}
