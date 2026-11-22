package com.hectordoesgorug.basic_bill_splitter

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val storageExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val savedBillsDelegate = lazy { SavedBillDatabase(applicationContext) }
    private val savedBills by savedBillsDelegate

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
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
                    "savedBills" -> storage(result) { savedBills.allRecords() }
                    "findSavedBill" -> storage(result) {
                        savedBills.find(
                            call.argument<String>("category") ?: error("Missing category"),
                            call.argument<Int>("year") ?: error("Missing year"),
                            call.argument<Int>("month") ?: error("Missing month")
                        )
                    }
                    "latestSavedBill" -> storage(result) {
                        savedBills.latest(call.argument<String>("category") ?: error("Missing category"))
                    }
                    "overlappingBills" -> storage(result) {
                        savedBills.overlapping(
                            call.argument<String>("category") ?: error("Missing category"),
                            call.argument<String>("startDate") ?: error("Missing start date"),
                            call.argument<String>("endDate") ?: error("Missing end date"),
                            call.argument<String>("excludeId")
                        )
                    }
                    "saveBill" -> storage(result) {
                        val record = call.argument<String>("record") ?: error("Missing saved record")
                        val movingId = call.argument<String>("movingRecordId")
                        val replaceId = call.argument<String>("replaceRecordId")
                        val outcome = savedBills.save(record, movingId, replaceId)
                        mapOf(
                            "status" to outcome.status,
                            "record" to outcome.record,
                            "conflict" to outcome.conflict
                        )
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun storage(
        result: MethodChannel.Result,
        operation: () -> Any?
    ) {
        storageExecutor.execute {
            try {
                val value = operation()
                mainHandler.post { result.success(value) }
            } catch (_: Exception) {
                mainHandler.post {
                    result.error("STORAGE_FAILURE", "Saved bills could not be accessed.", null)
                }
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        if (savedBillsDelegate.isInitialized()) {
            storageExecutor.execute { savedBills.close() }
        }
        storageExecutor.shutdown()
    }

    companion object {
        private const val CHANNEL = "basic_bill_splitter/app"
    }
}
