package com.mrwebapp.al_quran_mp3

import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Register plugin (handles BOTH channels)
        flutterEngine.plugins.add(AzanServicePlugin())
        Log.d(TAG, "✅ AzanServicePlugin registered (both channels)")
    }

    companion object {
        private const val TAG = "MainActivity"
    }
}