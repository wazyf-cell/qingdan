package com.qingdan.qingdan

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        SystemIntents.register(this, engine)
        FileIntents.register(this, engine)
        AppNav.register(engine)
        com.qingdan.qingdan.widgets.WidgetsChannel.register(engine, this)
    }

    /** 冷启动：快捷方式带来的 intent 只能在这里取。 */
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        AppNav.handle(intent)
    }

    /** 热启动（singleTop）：应用已在后台时点快捷方式走到这里。 */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        AppNav.handle(intent)
    }

    /** SAF「另存为」的结果回传（`FileIntents` 是唯一用请求码的入口）。 */
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (!FileIntents.handleActivityResult(requestCode, resultCode, data)) {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }
}
