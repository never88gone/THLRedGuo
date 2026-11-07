import java.util.Properties
import java.util.Base64

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val dartDefines = providers.gradleProperty("dart-defines").orNull.orEmpty()
    .split(",").filter { it.isNotEmpty() }
    .associate {
        val decoded = String(Base64.getDecoder().decode(it), Charsets.UTF_8)
        decoded.substringBefore("=") to decoded.substringAfter("=", "")
    }
val allSources = dartDefines["ALL_SOURCES"] == "true"

val publicGoogleDir = sequenceOf(
    File("/Volumes/MacintoshData/Work/MY/Project/publicinfo/google"),
    rootProject.file("../../publicinfo/google"),
    rootProject.file("../../../publicinfo/google")
).firstOrNull { it.isDirectory }

fun resolveStoreFile(pathStr: String): File {
    val raw = File(pathStr)
    return sequenceOf(
        raw,
        rootProject.file(pathStr),
        rootProject.file("../$pathStr"),
        publicGoogleDir?.let { File(it, pathStr) }
    ).filterNotNull().firstOrNull { it.exists() } ?: raw
}

val localReleaseKey = rootProject.file("key.properties")
val projectRootReleaseKey = rootProject.file("../key.properties")
val publicReleaseKey = publicGoogleDir?.let { File(it, "key.properties") }
val releaseKey = sequenceOf(
    localReleaseKey,
    projectRootReleaseKey,
    publicReleaseKey
).filterNotNull().firstOrNull { it.exists() }

val releaseProperties = Properties()
if (releaseKey != null && releaseKey.exists()) {
    releaseKey.inputStream().use { releaseProperties.load(it) }
}

val localDebugKey = rootProject.file("key_debug.properties")
val projectRootDebugKey = rootProject.file("../key_debug.properties")
val publicDebugKey = publicGoogleDir?.let { File(it, "key_debug.properties") }
val debugKey = sequenceOf(
    localDebugKey,
    projectRootDebugKey,
    publicDebugKey
).filterNotNull().firstOrNull { it.exists() }

val debugProperties = Properties()
if (debugKey != null && debugKey.exists()) {
    debugKey.inputStream().use { debugProperties.load(it) }
}

val envKeystore = System.getenv("ANDROID_KEYSTORE_PATH")
val envStorePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
val envKeyAlias = System.getenv("ANDROID_KEY_ALIAS")
val envKeyPassword = System.getenv("ANDROID_KEY_PASSWORD")
val hasEnvSigning = !envKeystore.isNullOrBlank() && File(envKeystore).exists()

android {
    namespace = "com.duanju.duanju_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.never88gone.redlook"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        val rawCode = runCatching { flutter.versionCode }.getOrNull()
        versionCode = if (rawCode != null && rawCode > 0 && rawCode < 2100000000) rawCode else (System.currentTimeMillis() / 1000).toInt()
        versionName = flutter.versionName ?: "1.0.0"
        manifestPlaceholders["appLabel"] = "糖葫芦Haw"
        manifestPlaceholders["appBanner"] = if (allSources) "@drawable/tv_banner_all_sources" else "@drawable/tv_banner"
    }

    signingConfigs {
        val hasReleaseSigning = (releaseKey != null && releaseKey.exists()) || hasEnvSigning
        if (hasReleaseSigning) {
            val storeFileResolved = if (hasEnvSigning) {
                File(envKeystore!!)
            } else {
                resolveStoreFile(requireNotNull(releaseProperties.getProperty("storeFile")))
            }
            val storePass = if (hasEnvSigning) envStorePassword ?: "thl123456" else requireNotNull(releaseProperties.getProperty("storePassword"))
            val alias = if (hasEnvSigning) envKeyAlias ?: "thl" else requireNotNull(releaseProperties.getProperty("keyAlias"))
            val keyPass = if (hasEnvSigning) envKeyPassword ?: "thl123456" else requireNotNull(releaseProperties.getProperty("keyPassword"))

            create("release") {
                storeFile = storeFileResolved
                storePassword = storePass
                keyAlias = alias
                keyPassword = keyPass
            }
            // 开发构建 (debug) 默认复用正式发布签名，确保开发包与发布包签名指纹完全一致，支持直接无缝覆盖安装
            getByName("debug") {
                storeFile = storeFileResolved
                storePassword = storePass
                keyAlias = alias
                keyPassword = keyPass
            }
        } else if (debugKey != null && debugKey.exists()) {
            getByName("debug") {
                val rawStore = requireNotNull(debugProperties.getProperty("storeFile"))
                storeFile = resolveStoreFile(rawStore)
                storePassword = requireNotNull(debugProperties.getProperty("storePassword"))
                keyAlias = requireNotNull(debugProperties.getProperty("keyAlias"))
                keyPassword = requireNotNull(debugProperties.getProperty("keyPassword"))
            }
        }
    }

    buildTypes {
        debug {
            // 保持包名统一为 com.never88gone.redlook，禁止添加 .debug 后缀以确保开发包与发布包相互覆盖安装
            signingConfig = signingConfigs.getByName("debug")
        }
        release {
            signingConfig = signingConfigs.getByName(if ((releaseKey != null && releaseKey.exists()) || hasEnvSigning) "release" else "debug")
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter { source = "../.." }

tasks.withType<JavaCompile>().configureEach {
    if (name.contains("Release")) {
        doFirst {
            val registrant = file("src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java")
            if (registrant.exists()) {
                val generated = registrant.readText()
                val integrationPlugin = Regex(
                    """(?s)    try \{\s*flutterEngine\.getPlugins\(\)\.add\(new dev\.flutter\.plugins\.integration_test\.IntegrationTestPlugin\(\)\);\s*\} catch \(Exception e\) \{[^}]*\}\s*"""
                )
                val release = generated.replace(integrationPlugin, "")
                if (release != generated) registrant.writeText(release)
            }
        }
    }
}
