// The 3DS HOME menu opening Azahar: the shell (LÖVE) calls
// love.system.openURL("fold3ds-azahar://<what>?<args>") and this invisible
// activity does it, then goes away, so whatever it opened sits right on top
// of the HOME menu and Back returns there.
//
//   play?key=K               start the 3DS game K (a key from games.tsv)
//   manual?key=K             the game's options (Azahar's About sheet)
//   settings?menu=M          an Azahar settings page (config = all of them)
//   install                  install CIA files
//   games_folder             choose the 3DS games folder
//   share_log                share Azahar's log
//   artic                    connect to an Artic Base server
//   azahar?open=X            Azahar's own screens (Fold3dsMain)
//   refresh                  scan the library again
package org.citra.citra_emu.fold3ds

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.LayoutInflater
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.widget.doOnTextChanged
import androidx.documentfile.provider.DocumentFile
import androidx.preference.PreferenceManager
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequest
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkManager
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import org.citra.citra_emu.R
import org.citra.citra_emu.activities.EmulationActivity
import org.citra.citra_emu.contracts.OpenFileResultContract
import org.citra.citra_emu.databinding.DialogSoftwareKeyboardBinding
import org.citra.citra_emu.features.settings.SettingKeys
import org.citra.citra_emu.features.settings.ui.SettingsActivity
import org.citra.citra_emu.features.settings.utils.SettingsFile
import org.citra.citra_emu.model.Game
import org.citra.citra_emu.ui.main.MainActivity
import org.citra.citra_emu.utils.CiaInstallWorker
import org.citra.citra_emu.utils.FileBrowserHelper
import org.citra.citra_emu.utils.GameHelper
import org.citra.citra_emu.utils.Log
import org.citra.citra_emu.utils.PermissionsHandler

class Fold3dsLinkActivity : AppCompatActivity() {
    private val ciaPicker = registerForActivityResult(OpenFileResultContract()) { result ->
        if (result != null) installCia(result)
        done()
    }

    private val gamesFolderPicker =
        registerForActivityResult(ActivityResultContracts.OpenDocumentTree()) { result ->
            if (result != null) setGamesFolder(result)
            done()
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val uri = intent?.data
        // LÖVE opens links with NO_HISTORY, which would drop a picker's
        // result: come back once without it
        if ((intent.flags and Intent.FLAG_ACTIVITY_NO_HISTORY) != 0) {
            startActivity(Intent(this, Fold3dsLinkActivity::class.java).setData(uri))
            finish()
            overridePendingTransition(0, 0)
            return
        }
        if (savedInstanceState != null) return // a picker is (still) open
        if (uri == null || uri.scheme != SCHEME) {
            done()
            return
        }
        try {
            handle(uri)
        } catch (e: Exception) {
            android.util.Log.e("fold3ds", "could not open $uri", e)
            done()
        }
    }

    private fun handle(uri: Uri) {
        val what = uri.host ?: ""
        if (what == "refresh") {
            Fold3dsBridge.refresh(applicationContext)
            done()
            return
        }
        // everything else needs Azahar's folder: until it is chosen, Azahar's
        // own first-run setup comes up instead
        if (what != "azahar" && !Fold3dsBridge.ready(applicationContext)) {
            openMain(null, null)
            done()
            return
        }
        when (what) {
            "play" -> play(uri.getQueryParameter("key"))
            "manual" -> openMain(Fold3dsMain.OPEN_LIBRARY, uri.getQueryParameter("key"))
            "settings" -> {
                val menu = uri.getQueryParameter("menu")
                SettingsActivity.launch(
                    this,
                    if (menu.isNullOrEmpty() || menu == "config") SettingsFile.FILE_NAME_CONFIG else menu,
                    ""
                )
            }
            "install" -> {
                ciaPicker.launch(true)
                return
            }
            "games_folder" -> {
                gamesFolderPicker.launch(null)
                return
            }
            "share_log" -> shareLog()
            "artic" -> {
                artic()
                return
            }
            "azahar" -> openMain(uri.getQueryParameter("open"), null)
        }
        done()
    }

    private fun done() {
        finish()
        overridePendingTransition(0, 0)
    }

    private fun openMain(open: String?, gameKey: String?) {
        startActivity(
            Intent(this, MainActivity::class.java).apply {
                if (open != null) putExtra(Fold3dsMain.EXTRA_OPEN, open)
                if (gameKey != null) putExtra(Fold3dsMain.EXTRA_GAME, gameKey)
            }
        )
    }

    private fun play(key: String?) {
        val game = key?.let { Fold3dsBridge.find(applicationContext, it) }
        if (game == null) {
            Toast.makeText(this, R.string.no_game_present, Toast.LENGTH_SHORT).show()
            Fold3dsBridge.refresh(applicationContext)
            return
        }
        start(game)
    }

    private fun start(game: Game) {
        PreferenceManager.getDefaultSharedPreferences(applicationContext).edit()
            .putLong(game.keyLastPlayedTime, System.currentTimeMillis())
            .apply()
        startActivity(
            Intent(this, EmulationActivity::class.java).putExtra("game", game)
        )
    }

    // as MainActivity.ciaFileInstaller
    private fun installCia(result: Intent) {
        val selected =
            FileBrowserHelper.getSelectedFiles(result, applicationContext, listOf("cia", "zcia"))
        if (selected == null) {
            Toast.makeText(applicationContext, R.string.cia_file_not_found, Toast.LENGTH_LONG)
                .show()
            return
        }
        WorkManager.getInstance(applicationContext).enqueueUniqueWork(
            "installCiaWork",
            ExistingWorkPolicy.APPEND_OR_REPLACE,
            OneTimeWorkRequest.Builder(CiaInstallWorker::class.java)
                .setInputData(Data.Builder().putStringArray("CIA_FILES", selected).build())
                .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
                .build()
        )
    }

    // as HomeSettingsFragment.getGamesDirectory
    private fun setGamesFolder(result: Uri) {
        contentResolver.takePersistableUriPermission(result, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        PreferenceManager.getDefaultSharedPreferences(applicationContext).edit()
            .putString(GameHelper.KEY_GAME_PATH, result.toString())
            .apply()
        Toast.makeText(applicationContext, R.string.games_dir_selected, Toast.LENGTH_LONG).show()
        Fold3dsBridge.refresh(applicationContext)
    }

    // as HomeSettingsFragment.shareLog
    private fun shareLog() {
        val logDirectory =
            DocumentFile.fromTreeUri(this, PermissionsHandler.citraDirectory)?.findFile("log")
        val currentLog = logDirectory?.findFile("azahar_log.txt")
        val oldLog = logDirectory?.findFile("azahar_log.old.txt")
        val log = if (!Log.gameLaunched && oldLog?.exists() == true) {
            oldLog
        } else if (currentLog?.exists() == true) {
            currentLog
        } else {
            null
        }
        if (log == null) {
            Toast.makeText(this, R.string.share_log_not_found, Toast.LENGTH_SHORT).show()
            return
        }
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_STREAM, log.uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(Intent.createChooser(intent, getText(R.string.share_log)))
    }

    // as HomeSettingsFragment's Artic Base entry
    private fun artic() {
        val prefs = PreferenceManager.getDefaultSharedPreferences(applicationContext)
        val input = DialogSoftwareKeyboardBinding.inflate(LayoutInflater.from(this))
        var address = prefs.getString(SettingKeys.last_artic_base_addr(), "") ?: ""
        input.editTextInput.setText(address)
        input.editTextInput.doOnTextChanged { text, _, _, _ -> address = text.toString() }
        MaterialAlertDialogBuilder(this)
            .setView(input.root)
            .setTitle(R.string.artic_base_enter_address)
            .setPositiveButton(android.R.string.ok) { _, _ ->
                if (address.isNotEmpty()) {
                    prefs.edit().putString(SettingKeys.last_artic_base_addr(), address).apply()
                    start(
                        Game(
                            title = getString(R.string.artic_base),
                            path = "articbase://$address",
                            filename = ""
                        )
                    )
                }
            }
            .setNegativeButton(android.R.string.cancel, null)
            .setOnDismissListener { done() }
            .show()
    }

    companion object {
        const val SCHEME = "fold3ds-azahar"
    }
}
