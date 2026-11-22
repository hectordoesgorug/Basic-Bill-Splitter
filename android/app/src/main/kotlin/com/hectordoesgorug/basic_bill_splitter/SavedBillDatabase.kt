package com.hectordoesgorug.basic_bill_splitter

import android.content.ContentValues
import android.content.Context
import android.database.DatabaseErrorHandler
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import org.json.JSONObject

internal class SavedBillDatabase(context: Context) :
    SQLiteOpenHelper(
        context,
        "saved_bills.db",
        null,
        1,
        DatabaseErrorHandler { _ ->
            throw IllegalStateException("Saved bills database is corrupt")
        }
    ) {

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE saved_bills (
              id TEXT PRIMARY KEY NOT NULL,
              schema_version INTEGER NOT NULL,
              category TEXT NOT NULL,
              assigned_year INTEGER NOT NULL,
              assigned_month INTEGER NOT NULL,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              start_date TEXT NOT NULL,
              end_date TEXT NOT NULL,
              payload TEXT NOT NULL,
              UNIQUE(category, assigned_year, assigned_month)
            )
            """.trimIndent()
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        if (oldVersion != newVersion) {
            throw IllegalStateException("No migration path from $oldVersion to $newVersion")
        }
    }

    fun allRecords(): List<String> = allRecords(readableDatabase)

    private fun allRecords(db: SQLiteDatabase): List<String> {
        val values = mutableListOf<String>()
        db.query(
            TABLE, arrayOf("payload"), null, null, null, null,
            "assigned_year, assigned_month, category"
        ).use { cursor ->
            while (cursor.moveToNext()) values += cursor.getString(0)
        }
        return values
    }

    fun find(category: String, year: Int, month: Int): String? =
        queryOne(
            "category = ? AND assigned_year = ? AND assigned_month = ?",
            arrayOf(category, year.toString(), month.toString())
        )

    fun latest(category: String): String? =
        queryOne("category = ?", arrayOf(category), "end_date DESC, updated_at DESC")

    fun overlapping(category: String, start: String, end: String, excludeId: String?): List<String> {
        val sql = StringBuilder("category = ? AND start_date <= ? AND end_date >= ?")
        val args = mutableListOf(category, end, start)
        if (excludeId != null) {
            sql.append(" AND id != ?")
            args += excludeId
        }
        val values = mutableListOf<String>()
        readableDatabase.query(TABLE, arrayOf("payload"), sql.toString(), args.toTypedArray(), null, null, null)
            .use { cursor ->
                while (cursor.moveToNext()) values += cursor.getString(0)
            }
        return values
    }

    data class SaveOutcome(val status: String, val record: String? = null, val conflict: String? = null)

    @Synchronized
    fun save(encoded: String, movingId: String?, replaceId: String?): SaveOutcome {
        val candidate = JSONObject(encoded)
        val category = candidate.getString("category")
        val year = candidate.getInt("assignedYear")
        val month = candidate.getInt("assignedMonth")
        val db = writableDatabase
        db.beginTransaction()
        try {
            val source = if (movingId == null) null else queryById(db, movingId)
                ?: throw IllegalStateException("The saved record being updated no longer exists")
            val conflict = queryByKey(db, category, year, month)
            if (conflict != null && conflict.id != movingId && conflict.id != replaceId) {
                return SaveOutcome("conflict", conflict = conflict.payload)
            }
            if (source != null &&
                source.json.optJSONObject("snapshot").toString() ==
                candidate.optJSONObject("snapshot").toString() &&
                source.json.getString("category") == category &&
                source.json.getInt("assignedYear") == year &&
                source.json.getInt("assignedMonth") == month
            ) {
                return SaveOutcome("unchanged", source.payload)
            }

            val destination = conflict?.takeIf { it.id != movingId }
            val savedId = source?.id ?: destination?.id ?: candidate.getString("id")
            val createdAt = source?.createdAt ?: destination?.createdAt ?: candidate.getString("createdAt")
            candidate.put("id", savedId)
            candidate.put("createdAt", createdAt)
            val payload = candidate.toString()
            val values = values(candidate, payload)

            if (source != null) {
                if (destination != null) db.delete(TABLE, "id = ?", arrayOf(destination.id))
                db.update(TABLE, values, "id = ?", arrayOf(source.id))
            } else if (destination != null) {
                db.update(TABLE, values, "id = ?", arrayOf(destination.id))
            } else {
                db.insertOrThrow(TABLE, null, values)
            }
            db.setTransactionSuccessful()
            return SaveOutcome("saved", payload)
        } finally {
            db.endTransaction()
        }
    }

    @Synchronized
    fun replaceAll(records: List<String>): List<String> {
        if (records.size > MAX_RECORDS) {
            throw IllegalArgumentException("Backup contains too many bills")
        }
        val ids = mutableSetOf<String>()
        val keys = mutableSetOf<String>()
        val jsonRecords = records.map { encoded ->
            val json = JSONObject(encoded)
            if (json.getInt("schemaVersion") != RECORD_SCHEMA_VERSION) {
                throw IllegalArgumentException("Unsupported saved bill schema")
            }
            val id = json.getString("id")
            val category = json.getString("category")
            val year = json.getInt("assignedYear")
            val month = json.getInt("assignedMonth")
            if (id.isBlank() || category.isBlank() || year < 1 || month !in 1..12 ||
                !ids.add(id) || !keys.add("$category:$year:$month")
            ) {
                throw IllegalArgumentException("Backup contains invalid or duplicate bills")
            }
            json
        }

        val db = writableDatabase
        db.beginTransaction()
        try {
            db.delete(TABLE, null, null)
            for (json in jsonRecords) {
                val payload = json.toString()
                db.insertOrThrow(TABLE, null, values(json, payload))
            }
            val stored = allRecords(db)
            if (stored.size != records.size) {
                throw IllegalStateException("Saved bill replacement could not be verified")
            }
            val storedJson = stored.map(::JSONObject)
            val storedIds = storedJson.map { it.getString("id") }.toSet()
            val storedKeys = storedJson.map {
                "${it.getString("category")}:${it.getInt("assignedYear")}:${it.getInt("assignedMonth")}"
            }.toSet()
            if (storedIds != ids || storedKeys != keys) {
                throw IllegalStateException("Saved bill replacement could not be verified")
            }
            db.setTransactionSuccessful()
            return stored
        } finally {
            db.endTransaction()
        }
    }

    @Synchronized
    fun deleteAll(): Int {
        val db = writableDatabase
        db.beginTransaction()
        try {
            val deleted = db.delete(TABLE, null, null)
            if (db.query(TABLE, arrayOf("id"), null, null, null, null, null).use { it.count } != 0) {
                throw IllegalStateException("Saved bills could not be wiped")
            }
            db.setTransactionSuccessful()
            return deleted
        } finally {
            db.endTransaction()
        }
    }

    private data class Existing(val id: String, val createdAt: String, val payload: String, val json: JSONObject)

    private fun queryByKey(db: SQLiteDatabase, category: String, year: Int, month: Int): Existing? =
        queryOneExisting(db, "category = ? AND assigned_year = ? AND assigned_month = ?", arrayOf(category, "$year", "$month"))

    private fun queryById(db: SQLiteDatabase, id: String): Existing? =
        queryOneExisting(db, "id = ?", arrayOf(id))

    private fun queryOneExisting(db: SQLiteDatabase, where: String, args: Array<String>): Existing? {
        db.query(TABLE, arrayOf("id", "created_at", "payload"), where, args, null, null, null, "1").use { cursor ->
            if (!cursor.moveToFirst()) return null
            val payload = cursor.getString(2)
            return Existing(cursor.getString(0), cursor.getString(1), payload, JSONObject(payload))
        }
    }

    private fun queryOne(where: String, args: Array<String>, order: String? = null): String? {
        readableDatabase.query(TABLE, arrayOf("payload"), where, args, null, null, order, "1").use { cursor ->
            return if (cursor.moveToFirst()) cursor.getString(0) else null
        }
    }

    private fun values(json: JSONObject, payload: String) = ContentValues().apply {
        put("id", json.getString("id"))
        put("schema_version", json.getInt("schemaVersion"))
        put("category", json.getString("category"))
        put("assigned_year", json.getInt("assignedYear"))
        put("assigned_month", json.getInt("assignedMonth"))
        put("created_at", json.getString("createdAt"))
        put("updated_at", json.getString("updatedAt"))
        put("start_date", json.getString("startDate"))
        put("end_date", json.getString("endDate"))
        put("payload", payload)
    }

    companion object {
        private const val TABLE = "saved_bills"
        private const val MAX_RECORDS = 5000
        private const val RECORD_SCHEMA_VERSION = 1
    }
}
