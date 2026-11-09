package mg.smartsaha.taranaka

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

/**
 * Screenshots and screen recording are allowed: FLAG_SECURE is cleared
 * explicitly so no other code path (or an older build) can leave it set.
 */
class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }
}
