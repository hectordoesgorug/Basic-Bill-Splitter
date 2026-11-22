package com.hectordoesgorug.basic_bill_splitter

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "basic_bill_splitter/app")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getVersion" -> {
                        @Suppress("DEPRECATION")
                        val info = packageManager.getPackageInfo(packageName, 0)
                        @Suppress("DEPRECATION")
                        val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            info.longVersionCode
                        } else {
                            info.versionCode.toLong()
                        }
                        result.success("${info.versionName}+$code")
                    }
                    "openRepository" -> {
                        try {
                            startActivity(
                                Intent(
                                    Intent.ACTION_VIEW,
                                    Uri.parse("https://github.com/hectordoesgorug/Basic-Bill-Splitter")
                                ).addCategory(Intent.CATEGORY_BROWSABLE)
                            )
                            result.success(true)
                        } catch (_: ActivityNotFoundException) {
                            result.error("NO_BROWSER", "No browser can open the repository.", null)
                        } catch (_: SecurityException) {
                            result.error("BROWSER_UNAVAILABLE", "The browser could not be opened.", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
