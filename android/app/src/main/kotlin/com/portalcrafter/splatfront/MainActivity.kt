package com.portalcrafter.splatfront

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Opens the Play Games app, so a player can reach their own account.
 *
 * This exists because **Play Games Services v2 has no sign-out.** Sign-in is
 * automatic and owned by the Play Games app rather than by the game, so a
 * game cannot disconnect an account, switch one, or log anybody out. The
 * honest thing a game can do is hand the player to the place where they can.
 *
 * Returns false rather than throwing when Play Games is not installed, which
 * is a real state on a device with no Google services: the caller hides the
 * row instead of offering a button that goes nowhere.
 */
class MainActivity : FlutterActivity() {
    private companion object {
        const val CHANNEL = "splatfront/accounts"
        const val PLAY_GAMES = "com.google.android.play.games"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openPlayGames" -> result.success(openPlayGames())
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * The Play Games app if it is there, otherwise its store listing.
     *
     * **The standalone app is genuinely absent on a lot of phones.** Play
     * Games *Services* ships inside `com.google.android.gms`, so a device can
     * run the whole sign-in and achievement stack with no Play Games app
     * installed at all — which is the case on the Samsung this was first
     * tested on. Sending such a player to the store listing is the honest
     * answer: it is where the app they need comes from, and installing it is
     * the only route to the account screen.
     *
     * Note this needs `<queries>` in the manifest. From Android 11, package
     * visibility hides other apps from us, and `getLaunchIntentForPackage`
     * signals that by returning null — the same value it returns for an app
     * that really is not installed, so a missing `<queries>` entry looks
     * exactly like a missing app and is very easy to misdiagnose.
     */
    private fun openPlayGames(): Boolean {
        // A new task either way, so pressing back comes straight to the game
        // rather than walking out through another app's screens.
        val launch = packageManager.getLaunchIntentForPackage(PLAY_GAMES)
        if (launch != null) {
            launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (start(launch)) return true
        }

        val store = Intent(
            Intent.ACTION_VIEW,
            Uri.parse("market://details?id=$PLAY_GAMES"),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (start(store)) return true

        // No Play Store either, which happens on devices with no Google
        // services at all. The browser is the last thing left to try.
        val web = Intent(
            Intent.ACTION_VIEW,
            Uri.parse("https://play.google.com/store/apps/details?id=$PLAY_GAMES"),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return start(web)
    }

    private fun start(intent: Intent): Boolean = try {
        startActivity(intent)
        true
    } catch (e: android.content.ActivityNotFoundException) {
        false
    }
}
