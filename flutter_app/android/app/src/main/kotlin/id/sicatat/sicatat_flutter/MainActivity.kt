package id.sicatat.sicatat_flutter

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val updateChannel = "id.sicatat.sicatat_flutter/app_update"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updateChannel)
            .setMethodCallHandler { call, result ->
                if (call.method == "supportedAbis") {
                    result.success(Build.SUPPORTED_ABIS.toList())
                    return@setMethodCallHandler
                }
                if (call.method != "installApk") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }

                val path = call.argument<String>("path")
                val apk = path?.let(::File)
                if (apk == null || !apk.isFile) {
                    result.error("missing_apk", "The downloaded APK file was not found.", null)
                    return@setMethodCallHandler
                }
                if (!packageManager.canRequestPackageInstalls()) {
                    startActivity(
                        Intent(
                            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                            Uri.parse("package:$packageName"),
                        ),
                    )
                    result.success("permission_required")
                    return@setMethodCallHandler
                }

                val uri = FileProvider.getUriForFile(
                    this,
                    "$packageName.fileprovider",
                    apk,
                )
                val installIntent = Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, "application/vnd.android.package-archive")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                startActivity(installIntent)
                result.success("installer_opened")
            }
    }
}
