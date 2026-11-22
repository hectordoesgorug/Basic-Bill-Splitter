package com.hectordoesgorug.basic_bill_splitter

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import java.io.File
import java.util.UUID
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
    private var pendingDocumentResult: MethodChannel.Result? = null
    private var pendingBackupRecords: List<String>? = null

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
                    "sharePng" -> sharePng(call.argument<ByteArray>("png"), result)
                    "replaceSavedBills" -> storage(result) {
                        val records = call.argument<List<String>>("records")
                            ?: error("Missing replacement records")
                        savedBills.replaceAll(records)
                    }
                    "wipeSavedBills" -> storage(result) { savedBills.deleteAll() }
                    "getDarkMode" -> storage(result) {
                        getSharedPreferences(PREFERENCES, MODE_PRIVATE)
                            .getBoolean(DARK_MODE, false)
                    }
                    "setDarkMode" -> storage(result) {
                        val enabled = call.argument<Boolean>("enabled")
                            ?: error("Missing appearance value")
                        getSharedPreferences(PREFERENCES, MODE_PRIVATE)
                            .edit()
                            .putBoolean(DARK_MODE, enabled)
                            .commit()
                    }
                    "createBackup" -> {
                        val records = call.argument<List<String>>("records")
                            ?: error("Missing backup records")
                        val filename = call.argument<String>("filename")
                            ?: error("Missing backup filename")
                        startDocumentPicker(
                            Intent(Intent.ACTION_CREATE_DOCUMENT)
                                .addCategory(Intent.CATEGORY_OPENABLE)
                                .setType(BACKUP_MIME_TYPE)
                                .putExtra(Intent.EXTRA_TITLE, filename),
                            records,
                            result
                        )
                    }
                    "pickBackup" -> startDocumentPicker(
                        Intent(Intent.ACTION_OPEN_DOCUMENT)
                            .addCategory(Intent.CATEGORY_OPENABLE)
                            .setType(BACKUP_MIME_TYPE),
                        null,
                        result
                    )
                    else -> result.notImplemented()
                }
            }
    }

    @Suppress("DEPRECATION")
    private fun startDocumentPicker(
        intent: Intent,
        backupRecords: List<String>?,
        result: MethodChannel.Result
    ) {
        if (pendingDocumentResult != null) {
            result.error("OPERATION_BUSY", "Another document operation is active.", null)
            return
        }
        pendingDocumentResult = result
        pendingBackupRecords = backupRecords
        try {
            startActivityForResult(intent, DOCUMENT_REQUEST)
        } catch (_: ActivityNotFoundException) {
            pendingDocumentResult = null
            pendingBackupRecords = null
            result.error("DOCUMENT_PICKER_UNAVAILABLE", "The Android document picker is unavailable.", null)
        } catch (_: SecurityException) {
            pendingDocumentResult = null
            pendingBackupRecords = null
            result.error("DOCUMENT_ACCESS_FAILED", "The document picker could not be opened.", null)
        }
    }

    @Deprecated("Handled for Android Storage Access Framework results")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != DOCUMENT_REQUEST) return
        val result = pendingDocumentResult ?: return
        val backupRecords = pendingBackupRecords
        pendingDocumentResult = null
        pendingBackupRecords = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        if (backupRecords != null) {
            storage(result) {
                val output = contentResolver.openOutputStream(uri, "wt")
                    ?: error("Could not open the selected backup destination")
                SavedBillBackup.write(output, packageName, backupRecords)
                true
            }
        } else {
            storage(result) {
                val input = contentResolver.openInputStream(uri)
                    ?: error("Could not read the selected backup")
                val records = SavedBillBackup.read(input, packageName)
                mapOf(
                    "formatVersion" to SavedBillBackup.FORMAT_VERSION,
                    "recordCount" to records.size,
                    "records" to records
                )
            }
        }
    }

    private fun sharePng(bytes: ByteArray?, result: MethodChannel.Result) {
        if (bytes == null || !hasPngSignature(bytes)) {
            result.error("SHARE_FAILED", "The bill image is invalid.", null)
            return
        }
        if (bytes.size > MAX_SHARE_BYTES) {
            result.error("SHARE_FAILED", "The bill image is too large to share.", null)
            return
        }

        storageExecutor.execute {
            var file: File? = null
            try {
                val directory = File(cacheDir, SHARE_DIRECTORY)
                if (!directory.exists() && !directory.mkdirs()) {
                    error("Could not create share cache")
                }
                pruneOldShareFiles(directory)
                val shareFile = File(directory, "bill-${UUID.randomUUID()}.png")
                file = shareFile
                shareFile.outputStream().use { output ->
                    output.write(bytes)
                    output.flush()
                }

                val uri = FileProvider.getUriForFile(
                    applicationContext,
                    "$packageName.billshare",
                    shareFile
                )
                val shareIntent = Intent(Intent.ACTION_SEND).apply {
                    type = "image/png"
                    putExtra(Intent.EXTRA_STREAM, uri)
                    clipData = ClipData.newUri(contentResolver, "Bill summary", uri)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                if (packageManager.queryIntentActivities(shareIntent, 0).isEmpty()) {
                    file.delete()
                    mainHandler.post {
                        result.error(
                            "SHARE_UNAVAILABLE",
                            "No application can receive a PNG image.",
                            null
                        )
                    }
                    return@execute
                }
                val chooser = Intent.createChooser(shareIntent, "Share bill").apply {
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    clipData = ClipData.newUri(contentResolver, "Bill summary", uri)
                }
                mainHandler.post {
                    try {
                        if (isFinishing || isDestroyed) {
                            file?.delete()
                            result.error("SHARE_FAILED", "The app is no longer active.", null)
                        } else {
                            startActivity(chooser)
                            result.success(null)
                        }
                    } catch (_: ActivityNotFoundException) {
                        file?.delete()
                        result.error(
                            "SHARE_UNAVAILABLE",
                            "No application can receive a PNG image.",
                            null
                        )
                    } catch (_: SecurityException) {
                        file?.delete()
                        result.error("SHARE_FAILED", "The bill image could not be shared.", null)
                    }
                }
            } catch (_: Exception) {
                file?.delete()
                mainHandler.post {
                    result.error("SHARE_FAILED", "The bill image could not be shared.", null)
                }
            }
        }
    }

    private fun hasPngSignature(bytes: ByteArray): Boolean {
        val signature = byteArrayOf(
            0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A
        )
        return bytes.size >= signature.size &&
            signature.indices.all { bytes[it] == signature[it] }
    }

    private fun pruneOldShareFiles(directory: File) {
        val cutoff = System.currentTimeMillis() - SHARE_FILE_TTL_MS
        directory.listFiles()?.forEach { candidate ->
            if (candidate.isFile &&
                candidate.name.startsWith("bill-") &&
                candidate.name.endsWith(".png") &&
                candidate.lastModified() < cutoff
            ) {
                candidate.delete()
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
        pendingDocumentResult?.error(
            "DOCUMENT_OPERATION_INTERRUPTED",
            "The document operation was interrupted.",
            null
        )
        pendingDocumentResult = null
        pendingBackupRecords = null
        super.onDestroy()
        if (savedBillsDelegate.isInitialized()) {
            storageExecutor.execute { savedBills.close() }
        }
        storageExecutor.shutdown()
    }

    companion object {
        private const val CHANNEL = "basic_bill_splitter/app"
        private const val SHARE_DIRECTORY = "bill-share"
        private const val MAX_SHARE_BYTES = 32 * 1024 * 1024
        private const val SHARE_FILE_TTL_MS = 24 * 60 * 60 * 1000L
        private const val DOCUMENT_REQUEST = 7410
        private const val BACKUP_MIME_TYPE = "application/zip"
        private const val PREFERENCES = "splitter_preferences"
        private const val DARK_MODE = "dark_mode"
    }
}
