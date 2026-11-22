package com.hectordoesgorug.basic_bill_splitter

import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.security.MessageDigest
import java.time.Instant
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream

internal object SavedBillBackup {
    const val FORMAT_VERSION = 1
    const val RECORD_SCHEMA_VERSION = 1
    const val MAX_RECORDS = 5000
    private const val MAX_ARCHIVE_BYTES = 40 * 1024 * 1024
    private const val MAX_MANIFEST_BYTES = 64 * 1024
    private const val MAX_BILLS_BYTES = 32 * 1024 * 1024

    fun write(
        output: OutputStream,
        applicationId: String,
        records: List<String>,
        createdAt: String = Instant.now().toString()
    ) {
        require(records.size <= MAX_RECORDS) { "Backup contains too many bills" }
        val sorted = records.sortedWith(
            compareBy<String> { JSONObject(it).getString("category") }
                .thenBy { JSONObject(it).getInt("assignedYear") }
                .thenBy { JSONObject(it).getInt("assignedMonth") }
                .thenBy { JSONObject(it).getString("id") }
        )
        val bills = JSONArray()
        sorted.forEach { bills.put(JSONObject(it)) }
        val billsBytes = bills.toString().toByteArray(Charsets.UTF_8)
        require(billsBytes.size <= MAX_BILLS_BYTES) { "Backup is too large" }
        val manifest = JSONObject()
            .put("formatVersion", FORMAT_VERSION)
            .put("applicationId", applicationId)
            .put("createdAtUtc", createdAt)
            .put("recordSchemaVersion", RECORD_SCHEMA_VERSION)
            .put("recordCount", sorted.size)
            .put("billsSha256", sha256(billsBytes))
            .toString()
            .toByteArray(Charsets.UTF_8)

        ZipOutputStream(output).use { zip ->
            zip.putNextEntry(ZipEntry("manifest.json"))
            zip.write(manifest)
            zip.closeEntry()
            zip.putNextEntry(ZipEntry("bills.json"))
            zip.write(billsBytes)
            zip.closeEntry()
        }
    }

    fun read(input: InputStream, applicationId: String): List<String> {
        val entries = mutableMapOf<String, ByteArray>()
        val boundedInput = LimitedInputStream(input, MAX_ARCHIVE_BYTES)
        ZipInputStream(boundedInput).use { zip ->
            while (true) {
                val entry = zip.nextEntry ?: break
                if (entry.isDirectory || entry.name !in setOf("manifest.json", "bills.json") ||
                    entries.containsKey(entry.name)
                ) {
                    throw IOException("Backup archive structure is invalid")
                }
                val limit = if (entry.name == "manifest.json") {
                    MAX_MANIFEST_BYTES
                } else {
                    MAX_BILLS_BYTES
                }
                entries[entry.name] = readEntry(zip, limit)
                zip.closeEntry()
            }
            // Consume the central-directory and any trailing data through the same cap.
            boundedInput.drain()
        }
        val manifestBytes = entries["manifest.json"]
            ?: throw IOException("Backup manifest is missing")
        val billsBytes = entries["bills.json"]
            ?: throw IOException("Backup bill data is missing")
        if (entries.size != 2) throw IOException("Backup archive structure is invalid")

        val manifest = JSONObject(String(manifestBytes, Charsets.UTF_8))
        if (manifest.getInt("formatVersion") != FORMAT_VERSION) {
            throw IOException("Unsupported backup format")
        }
        if (manifest.getString("applicationId") != applicationId ||
            manifest.getInt("recordSchemaVersion") != RECORD_SCHEMA_VERSION
        ) {
            throw IOException("Backup is not compatible with this application")
        }
        Instant.parse(manifest.getString("createdAtUtc"))
        if (manifest.getString("billsSha256") != sha256(billsBytes)) {
            throw IOException("Backup checksum does not match")
        }

        val bills = JSONArray(String(billsBytes, Charsets.UTF_8))
        val count = manifest.getInt("recordCount")
        if (count !in 0..MAX_RECORDS || bills.length() != count) {
            throw IOException("Backup record count is invalid")
        }
        val ids = mutableSetOf<String>()
        val keys = mutableSetOf<String>()
        return List(count) { index ->
            val record = bills.getJSONObject(index)
            if (record.getInt("schemaVersion") != RECORD_SCHEMA_VERSION) {
                throw IOException("Unsupported saved bill schema")
            }
            val id = record.getString("id")
            val category = record.getString("category")
            val year = record.getInt("assignedYear")
            val month = record.getInt("assignedMonth")
            if (id.isBlank() || category.isBlank() || year < 1 || month !in 1..12 ||
                !ids.add(id) || !keys.add("$category:$year:$month")
            ) {
                throw IOException("Backup contains invalid or duplicate bills")
            }
            record.toString()
        }
    }

    private fun readEntry(input: InputStream, maxBytes: Int): ByteArray {
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        while (true) {
            val count = input.read(buffer)
            if (count < 0) break
            if (output.size() + count > maxBytes) {
                throw IOException("Backup entry exceeds the supported size")
            }
            output.write(buffer, 0, count)
        }
        return output.toByteArray()
    }

    private fun sha256(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(bytes)
            .joinToString("") { "%02x".format(it) }

    private class LimitedInputStream(
        input: InputStream,
        private val maximum: Int
    ) : java.io.FilterInputStream(input) {
        private var consumed = 0

        fun drain() {
            val buffer = ByteArray(8192)
            while (read(buffer, 0, buffer.size) >= 0) {
                // Keep reading so the archive-wide limit also covers trailing ZIP data.
            }
        }

        override fun read(): Int {
            val value = super.read()
            if (value >= 0 && ++consumed > maximum) {
                throw IOException("Backup archive exceeds the supported size")
            }
            return value
        }

        override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
            if (consumed >= maximum) {
                val extra = super.read()
                if (extra < 0) return -1
                throw IOException("Backup archive exceeds the supported size")
            }
            val count = super.read(buffer, offset, minOf(length, maximum - consumed))
            if (count > 0) consumed += count
            return count
        }
    }
}
