// fold3ds-eden:// links from the HOME menu (Steam Dev). A no-UI activity: it does the one
// thing the link asks, then finishes, so the shell is what stays on screen.
//
//   play?key=K     start that Switch game in Eden, straight into the game (no Eden screens),
//                  launched adjacent so Eden takes the other pane (the bottom one, half-folded)
//   games_folder   pick the Switch games folder (the system folder picker, ours, not Eden's)
//   refresh        rescan it (and, like every shell resume, recheck what is running)
//   setup          games_folder once Eden is installed; until then, say so
//
// Eden is its own app and unchanged: a game is opened the way any file manager opens one,
// VIEW on the file's content:// URI with a read grant (Eden's EmulationActivity filter).
package org.citra.citra_emu.fold3ds

import android.app.Activity
import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.util.Log
import android.widget.Toast

class EdenLinkActivity : Activity() {
    companion object {
        private const val TAG = "fold3ds-eden"
        private const val PICK_TREE = 1
        const val EMULATION = "org.yuzu.yuzu_emu.activities.EmulationActivity"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val link = intent?.data
        if (link == null) { finish(); return }
        val what = link.host ?: ""
        Log.i(TAG, "link $link")
        when (what) {
            "play" -> { play(link.getQueryParameter("key"), link.getQueryParameter("skin")); finish() }
            "games_folder" -> pickFolder()
            "refresh" -> { EdenBridge.refresh(applicationContext); finish() }
            "setup" -> if (EdenBridge.edenPackage(this) == null) {
                say("Install Eden, the Switch emulator, then come back here"); finish()
            } else pickFolder()
            else -> finish()
        }
    }

    private fun say(text: String) = Toast.makeText(applicationContext, text, Toast.LENGTH_LONG).show()

    private fun play(key: String?, skin: String? = null) {
        val pkg = EdenBridge.edenPackage(this) ?: return say("Eden isn't installed")
        val game = key?.let(EdenBridge::find) ?: run {
            EdenBridge.refresh(applicationContext)
            return say("That game isn't in the Switch games folder any more")
        }
        val isSwitchSkin = (skin == "switch")
        val view = Intent(Intent.ACTION_VIEW).apply {
            component = ComponentName(pkg, EMULATION)
            setDataAndType(Uri.parse(game.file), "application/octet-stream")
            var flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_MULTIPLE_TASK
            if (!isSwitchSkin) {
                flags = flags or Intent.FLAG_ACTIVITY_LAUNCH_ADJACENT
            }
            addFlags(flags)
        }
        try { startActivity(view); EdenBridge.started(applicationContext, game) }
        catch (e: Exception) { Log.w(TAG, "Eden would not open ${game.file}", e); say("Eden couldn't start that game") }
    }

    private fun pickFolder() {
        val pick = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        try { startActivityForResult(pick, PICK_TREE) }
        catch (e: Exception) { Log.w(TAG, "no folder picker", e); finish() }
    }

    @Deprecated("Activity result API is not in this module's dependencies")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        val tree = data?.data
        if (requestCode == PICK_TREE && resultCode == RESULT_OK && tree != null) {
            try { contentResolver.takePersistableUriPermission(tree, Intent.FLAG_GRANT_READ_URI_PERMISSION) }
            catch (e: SecurityException) { Log.w(TAG, "could not keep access to $tree", e) }
            EdenBridge.setTree(applicationContext, tree)
        }
        finish()
    }
}
