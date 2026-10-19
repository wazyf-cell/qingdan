import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 正式签名：有 android/key.properties 就用它，没有就退回 debug 签名。
//
// 为什么要做成条件式：直接写死 release keystore 会让所有本地构建（以及 CI 上
// 没有密钥的那条路）当场失败；而继续无条件用 debug 签名更糟——一旦有了自动更新
// 通道，debug keystore 的口令是公开默认值，任何人能签出本机认作合法升级的 APK。
// 所以：密钥到位前照旧能构建，但每次配置期都会吼一声，不允许"悄悄用 debug 签了
// 一个看起来是 release 的包"。
val keystoreProperties = Properties()
val keystorePropertiesFile: File = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.qingdan.qingdan"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications (core library desugaring).
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.qingdan.qingdan"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hasReleaseKeystore) {
                // storeFile 按 Flutter 惯例相对本模块目录（android/app/）解析，
                // 写在 key.properties 里，例如 storeFile=qingdan-release.jks。
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        getByName("release") {
            if (hasReleaseKeystore) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                signingConfig = signingConfigs.getByName("debug")
                // 不静默降级。**必须用 quiet 级别**：Flutter 是以 `gradle --quiet` 调起来的，
                // 而 Gradle 的日志序是 DEBUG<INFO<WARN<QUIET<ERROR —— `logger.warn` 在
                // `--quiet` 下会被整个吞掉（实测构建日志里一个字都不出现），
                // 一条永远不响的警告等于没有警告。
                logger.quiet(
                    "WARNING: qingdan release 构建正在使用 **debug 签名**（缺少 " +
                        "android/key.properties）。这种包不能对外发：debug keystore " +
                        "的口令是公开默认值，拿到它的人能签出本机认作合法升级的 APK。"
                )
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Required by flutter_local_notifications (see compileOptions above).
    // Version 2.1.4 already present in local Gradle cache
    // (GRADLE_USER_HOME\caches\modules-2\files-2.1\com.android.tools\desugar_jdk_libs).
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
