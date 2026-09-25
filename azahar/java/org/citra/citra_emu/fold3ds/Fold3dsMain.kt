// Azahar's own screens, opened from the 3DS HOME menu's Azahar folder:
// MainActivity starts with EXTRA_OPEN naming the screen (and, for a game's
// options, EXTRA_GAME naming the game).  Once the player comes back from
// that screen to Azahar's games list, MainActivity closes and the HOME menu
// is there again.
package org.citra.citra_emu.fold3ds

import android.app.Activity
import android.content.Intent
import android.widget.Toast
import androidx.navigation.NavController
import androidx.preference.PreferenceManager
import androidx.recyclerview.widget.RecyclerView
import org.citra.citra_emu.R
import org.citra.citra_emu.adapters.GameAdapter
import org.citra.citra_emu.features.settings.model.Settings
import org.citra.citra_emu.model.Game
import org.citra.citra_emu.ui.main.MainActivity
import org.citra.citra_emu.utils.GpuDriverHelper
import org.citra.citra_emu.utils.PermissionsHandler

object Fold3dsMain {
    const val EXTRA_OPEN = "fold3ds_open"
    const val EXTRA_GAME = "fold3ds_game"

    const val OPEN_LIBRARY = "library"

    // MainActivity.onCreate, after its navigation is set up
    fun onMainCreated(activity: MainActivity, nav: NavController, intent: Intent?) {
        val open = intent?.getStringExtra(EXTRA_OPEN) ?: return
        intent.removeExtra(EXTRA_OPEN)
        // the first-run setup comes first; it ends on the games list
        val prefs = PreferenceManager.getDefaultSharedPreferences(activity.applicationContext)
        if (prefs.getBoolean(Settings.PREF_FIRST_APP_LAUNCH, true)) return
        val dest = when (open) {
            "system_files" -> R.id.systemFilesFragment
            "drivers" -> {
                if (!GpuDriverHelper.supportsCustomDriverLoading()) {
                    Toast.makeText(
                        activity,
                        R.string.custom_driver_not_supported,
                        Toast.LENGTH_LONG
                    ).show()
                    null
                } else {
                    R.id.driverManagerFragment
                }
            }
            "about" -> R.id.aboutFragment
            "tools" -> R.id.homeSettingsFragment
            "multiplayer" -> {
                activity.displayMultiplayerDialog()
                null
            }
            "user_folder" -> {
                PermissionsHandler.compatibleSelectDirectory(activity.openCitraDirectory)
                null
            }
            else -> null // library: the games list is where MainActivity starts
        }
        if (dest == null) return
        nav.navigate(dest)
        // back from that screen to the games list: back to the HOME menu
        var shown = false
        nav.addOnDestinationChangedListener { _, d, _ ->
            if (d.id == dest) shown = true
            if (shown && d.id == R.id.gamesFragment && !activity.isFinishing) activity.finish()
        }
    }

    // GamesFragment, once a list is on screen: a game's options asked for
    // from the HOME menu (its Manual button) open on that game
    fun onGamesListed(activity: Activity, grid: RecyclerView, games: List<Game>) {
        val key = activity.intent?.getStringExtra(EXTRA_GAME) ?: return
        val idx = games.indexOfFirst { Fold3dsBridge.key(it) == key }
        if (idx < 0) return
        activity.intent.removeExtra(EXTRA_GAME)
        grid.scrollToPosition(idx)
        grid.post {
            val holder = grid.findViewHolderForAdapterPosition(idx) as? GameAdapter.GameViewHolder
            holder?.binding?.cardGame?.performLongClick()
        }
    }
}
