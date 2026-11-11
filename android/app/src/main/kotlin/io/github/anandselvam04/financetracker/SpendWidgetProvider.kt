package io.github.anandselvam04.financetracker

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.widget.RemoteViews

// The home-screen widget: this month's spending, today's, and an Add button.
//
// The app works the figures out and saves them as text through the
// home_widget plugin (lib/services/home_widget_service.dart), which keeps
// them in the "HomeWidgetPreferences" shared preferences and then asks this
// provider to redraw. Tapping the widget opens the app; Add opens it on the
// Add Expense form. The launch action is the plugin's, so its Dart side
// reports which link opened the app.
class SpendWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        val prefs = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.spend_widget)
            views.setTextViewText(
                R.id.widget_title,
                prefs.getString("title", null) ?: "Finance Tracker",
            )
            views.setTextViewText(
                R.id.widget_amount,
                prefs.getString("amount", null) ?: "Open the app",
            )
            views.setTextViewText(R.id.widget_detail, prefs.getString("detail", null) ?: "")
            views.setOnClickPendingIntent(
                R.id.widget_root,
                launch(context, "financetracker://open", REQUEST_OPEN),
            )
            views.setOnClickPendingIntent(
                R.id.widget_add,
                launch(context, "financetracker://add", REQUEST_ADD),
            )
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    private fun launch(context: Context, uri: String, requestCode: Int): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
        intent.action = LAUNCH_ACTION
        intent.data = Uri.parse(uri)
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags = flags or PendingIntent.FLAG_IMMUTABLE
        }
        return PendingIntent.getActivity(context, requestCode, intent, flags)
    }

    private companion object {
        // Where the home_widget plugin keeps saved widget data.
        const val PREFERENCES = "HomeWidgetPreferences"

        // The plugin's launch action: its Dart side reads the link from it.
        const val LAUNCH_ACTION = "es.antonborri.home_widget.action.LAUNCH"

        const val REQUEST_OPEN = 0
        const val REQUEST_ADD = 1
    }
}
