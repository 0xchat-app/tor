package com.oxchat.tor

import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin

class TorPlugin : FlutterPlugin {
    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        SystemProxyPlugin().onAttachedToEngine(flutterPluginBinding)
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {}
}