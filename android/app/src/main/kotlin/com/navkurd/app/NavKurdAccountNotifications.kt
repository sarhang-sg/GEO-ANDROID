package com.navkurd.app

import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import org.json.JSONArray

/** Bounded delivery receipts, isolated per account. No credentials are retained. */
object NavKurdAccountNotifications {
    private const val TAG = "nav-kurd-account:"

    fun sync(context: Context, userId: String, items: List<Map<*, *>>): Boolean {
        val prefs = context.getSharedPreferences("nav_kurd_account_notifications", Context.MODE_PRIVATE)
        val manager = context.getSystemService(NotificationManager::class.java)
        if (prefs.getString("user", "") != userId) {
            manager.activeNotifications.filter { it.tag?.startsWith(TAG) == true }
                .forEach { manager.cancel(it.tag, it.id) }
            prefs.edit().putString("user", userId).remove("receipts").apply()
        }
        if (userId.isBlank()) return true
        if (!NavKurdNotifications.canNotify(context, NavKurdNotifications.CHANNEL_ACCOUNT)) return false
        val receipts = try { JSONArray(prefs.getString("receipts", "[]")) } catch (_: Exception) { JSONArray() }
        val seen = linkedSetOf<String>()
        for (i in 0 until receipts.length()) seen.add(receipts.optString(i))
        var delivered = 0
        for (item in items.take(100)) {
            val id = (item["id"] as? String)?.take(80) ?: continue
            if (!id.matches(Regex("[a-zA-Z0-9_-]+"))) continue
            if (item["read"] == true) { manager.cancel(TAG + userId, id.hashCode()); continue }
            if (id in seen || delivered >= 5) continue
            val at = (item["at"] as? Number)?.toLong() ?: continue
            if (System.currentTimeMillis() - at !in 0..7L * 24L * 60L * 60L * 1000L) continue
            val title = (item["title"] as? String)?.trim()?.take(160).orEmpty()
            val body = (item["body"] as? String)?.trim()?.take(700).orEmpty()
            if (title.isBlank()) continue
            val intent = Intent(context, MainActivity::class.java).apply {
                action = Intent.ACTION_VIEW
                data = Uri.parse("navkurd://open?action=account")
                flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            val pending = PendingIntent.getActivity(context, 900006, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val notification = NotificationCompat.Builder(context, NavKurdNotifications.CHANNEL_ACCOUNT)
                .setSmallIcon(R.drawable.ic_notification).setContentTitle(title).setContentText(body)
                .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
                .setContentIntent(pending).setAutoCancel(true).setOnlyAlertOnce(true).build()
            try { NotificationManagerCompat.from(context).notify(TAG + userId, id.hashCode(), notification) }
            catch (_: SecurityException) { return false }
            seen.add(id); delivered++
        }
        prefs.edit().putString("receipts", JSONArray(seen.toList().takeLast(200)).toString()).apply()
        return true
    }
}
