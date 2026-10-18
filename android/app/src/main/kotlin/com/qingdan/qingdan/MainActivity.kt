package com.qingdan.qingdan

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        SystemIntents.register(this, engine)
        FileIntents.register(this, engine)
    }

    /** SAF「另存为」的结果回传（`FileIntents` 是唯一用请求码的入口）。 */
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (!FileIntents.handleActivityResult(requestCode, resultCode, data)) {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }
}
