import java.util.Properties
import java.io.File
import java.util.Base64
import org.gradle.api.GradleException

fun encodeDartDefine(key: String, value: String): String =
    Base64.getEncoder().encodeToString("$key=$value".toByteArray(Charsets.UTF_8))

val androidLocalProperties = Properties()
val androidLocalPropertiesFile = rootProject.file("local.properties")
if (androidLocalPropertiesFile.isFile) {
    androidLocalPropertiesFile.inputStream().use { androidLocalProperties.load(it) }
}
fun propOrEnv(prop: String, env: String): String = sequenceOf(
    androidLocalProperties.getProperty(prop),
    System.getenv(env),
).mapNotNull { it?.trim()?.takeIf { k -> k.isNotEmpty() } }.firstOrNull() ?: ""

val dartDefinePairs: List<Pair<String, String>> = listOf(
    "CLIENT_HMAC_SECRET" to propOrEnv("client.hmac.secret", "CLIENT_HMAC_SECRET"),
    "TLS_PIN_SHA256" to propOrEnv("tls.pin.sha256", "TLS_PIN_SHA256"),
    "ETHERSCAN_API_KEY" to propOrEnv("etherscan.api.key", "ETHERSCAN_API_KEY"),
    "BSCSCAN_API_KEY" to propOrEnv("bscscan.api.key", "BSCSCAN_API_KEY"),
    "POLYGONSCAN_API_KEY" to propOrEnv("polygonscan.api.key", "POLYGONSCAN_API_KEY"),
    "AVALANCHE_API_KEY" to propOrEnv("snowtrace.api.key", "AVALANCHE_API_KEY"),
    "ARBITRUMSCAN_API_KEY" to propOrEnv("arbiscan.api.key", "ARBITRUMSCAN_API_KEY"),
    "TRONGRID_API_KEY" to propOrEnv("trongrid.api.key", "TRONGRID_API_KEY"),
    "SUBSCAN_API_KEY" to propOrEnv("subscan.api.key", "SUBSCAN_API_KEY"),
).filter { (_, v) -> v.isNotEmpty() }

val mergedDartDefines: String = run {
    val extra = dartDefinePairs.map { (k, v) -> encodeDartDefine(k, v) }
    val existing = (project.findProperty("dart-defines") as String?)?.trim().orEmpty()
    listOf(existing, extra.joinToString(",")).filter { it.isNotEmpty() }.joinToString(",")
}
if (mergedDartDefines.isNotEmpty()) {
    project.extensions.extraProperties.set("dart-defines", mergedDartDefines)
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// Load keystore: several common locations (see android/key.properties.example).
val keystoreProperties = Properties()
val androidRootDir: File = rootProject.projectDir

fun resolveStoreFile(propsFile: File, rel: String): File? {
    val r = rel.trim()
    if (r.isEmpty()) return null
    val abs = File(r)
    if (abs.isAbsolute) return abs.takeIf { it.isFile }
    val nextToProps = File(propsFile.parentFile, r)
    if (nextToProps.isFile) return nextToProps
    val underAndroid = File(androidRootDir, r)
    return underAndroid.takeIf { it.isFile }
}

val keystorePropertiesFile: File? = sequenceOf(
    File(androidRootDir, "key.properties"),
    File(androidRootDir, "signing${File.separator}key.properties"),
    File(androidRootDir, "app${File.separator}key.properties"),
    androidRootDir.parentFile?.let { File(it, "key.properties") },
    androidRootDir.parentFile?.let { File(it, "keys${File.separator}key.properties") },
).filterNotNull().firstOrNull { it.isFile }

if (keystorePropertiesFile != null) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

val releaseKeystoreStoreFile: File? =
    keystorePropertiesFile?.let { pf ->
        keystoreProperties.getProperty("storeFile")?.let { resolveStoreFile(pf, it) }
    }

val releaseKeystoreConfigured =
    keystorePropertiesFile != null &&
        releaseKeystoreStoreFile != null &&
        !keystoreProperties.getProperty("storeFile").isNullOrBlank() &&
        !keystoreProperties.getProperty("keyAlias").isNullOrBlank()

android {
    namespace = "com.coinceeper.adl"
    compileSdk = 36
    // NDK r28+ defaults to 16 KB ELF alignment (Play / Android 15+ page size). Match installed SDK sidecar.
    ndkVersion = "29.0.13599879"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        // فعال کردن desugaring
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "11"
    }

    sourceSets {
        named("main") {
            java.srcDirs("src/main/kotlin")
        }
    }

    buildFeatures {
        buildConfig = true
    }

    // Signing configurations (release falls back to debug keystore if key.properties missing — CI / local device tests)
    signingConfigs {
        create("release") {
            if (releaseKeystoreConfigured) {
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?
                storeFile = releaseKeystoreStoreFile
                storePassword = keystoreProperties["storePassword"] as String?
            }
        }
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.coinceeper.adl"
        // You can update the following values to match your application needs.
        // For more information, see: https://docs.flutter.dev/deployment/android#reviewing-the-gradle-build-configuration.
        minSdk = 26
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        
        // پشتیبانی از multidex
        multiDexEnabled = true
        // 0 = attestation stub؛ شماره پروژه Google Cloud (Play Console → app signing)
        buildConfigField("long", "INTEGRITY_CLOUD_PROJECT_NUMBER", "0L")
        // ۶۴ کاراکتر hex = همان TSP_LIB_XOR_KEY در encrypt_jni_tspagent.sh؛ خالی = لود از jniLibs
        val tspLibXor = (project.findProperty("TSP_LIB_XOR_KEY") as String?)?.trim() ?: ""
        buildConfigField("String", "TSP_LIB_XOR_KEY", "\"$tspLibXor\"")
    }
    
    packagingOptions {
        pickFirst("**/libc++_shared.so")
        pickFirst("**/libjsc.so")
        exclude("META-INF/DEPENDENCIES")
        exclude("META-INF/LICENSE")
        exclude("META-INF/LICENSE.txt")
        exclude("META-INF/license.txt")
        exclude("META-INF/NOTICE")
        exclude("META-INF/NOTICE.txt")
        exclude("META-INF/notice.txt")
        exclude("META-INF/ASL2.0")
        exclude("META-INF/*.kotlin_module")
    }

    buildTypes {
        named("release") {
            signingConfig = signingConfigs.named(
                if (releaseKeystoreConfigured) "release" else "debug",
            ).get()
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Core library desugaring
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    
    // MultiDex support
    implementation("androidx.multidex:multidex:2.0.1")
    // Play Integrity (attestation) — opsec.attestation: required
    implementation("com.google.android.play:integrity:1.4.0")
    
    // Force resolution of androidx.activity.ktx to prevent duplicate classes
    constraints {
        implementation("androidx.activity:activity-ktx:1.8.2") {
            because("Force single version to prevent duplicate classes")
        }
    }
}

configurations.all {
    resolutionStrategy {
        force("androidx.activity:activity-ktx:1.8.2")
        force("androidx.core:core-ktx:1.12.0")
    }
}

// Build Go c-shared + JNI into jniLibs before every native merge (fails if Go/NDK missing)
val flutterProjectDir: File = rootProject.projectDir.parentFile
val localProperties = Properties()
val localPropsFile = rootProject.file("local.properties")
if (localPropsFile.exists()) {
    localPropsFile.inputStream().use { localProperties.load(it) }
}
val sdkDirProp = localProperties.getProperty("sdk.dir")
val tspAgentNdkVersion = "29.0.13599879"
val tspAndroidAbis =
    ((project.findProperty("TSP_ANDROID_ABIS") as String?)?.trim())
        .takeUnless { it.isNullOrBlank() }
        ?: "arm64-v8a,armeabi-v7a"
val tspAgentNdkFromSdk =
    sdkDirProp?.let { File(it, "ndk/$tspAgentNdkVersion").absolutePath } ?: ""
val envAndroidNdk = System.getenv("ANDROID_NDK_HOME") ?: ""
// Prefer SDK Manager side-by-side path matching android.ndkVersion (stable CI); env overrides only if missing.
val tspAgentNdkPath: String =
    when {
        tspAgentNdkFromSdk.isNotBlank() && File(tspAgentNdkFromSdk).isDirectory -> tspAgentNdkFromSdk
        envAndroidNdk.isNotBlank() && File(envAndroidNdk).isDirectory -> envAndroidNdk
        else -> tspAgentNdkFromSdk.ifBlank { envAndroidNdk }
    }

fun resolveBashExecutable(): String? {
    val os = System.getProperty("os.name", "").lowercase()
    val candidates = mutableListOf<File>()
    if (os.contains("win")) {
        sequenceOf(
            System.getenv("ProgramFiles"),
            System.getenv("ProgramFiles(x86)"),
            "C:\\Program Files",
            "C:\\Program Files (x86)",
        )
            .filterNotNull()
            .distinct()
            .forEach { base ->
                candidates.add(File(base, "Git/bin/bash.exe"))
                candidates.add(File(base, "Git/usr/bin/bash.exe"))
            }
    }
    candidates.add(File("/bin/bash"))
    candidates.add(File("/usr/local/bin/bash"))
    candidates.add(File("/opt/homebrew/bin/bash"))
    val pathEnv = System.getenv("PATH") ?: ""
    val bashName = if (os.contains("win")) "bash.exe" else "bash"
    for (segment in pathEnv.split(File.pathSeparatorChar)) {
        val trimmed = segment.trim()
        if (trimmed.isNotEmpty()) {
            candidates.add(File(trimmed, bashName))
        }
    }
    return candidates.firstOrNull { it.isFile }?.absoluteFile?.invariantSeparatorsPath
}

afterEvaluate {
    val scriptFile = File(flutterProjectDir, "scripts/build_gobridge.sh")
    if (!scriptFile.isFile) {
        return@afterEvaluate
    }
    val bashPath = resolveBashExecutable()
    val buildTspAgent = tasks.register<Exec>("buildTspAgentNative") {
        group = "build"
        description = "Builds libtspagent.so + libtspagent_jni.so from agent/cmd/mobilehost (Go + NDK)"
        workingDir = flutterProjectDir
        inputs.dir(File(flutterProjectDir, "agent"))
        inputs.dir(File(flutterProjectDir, "android/app/src/main/cpp"))
        inputs.file(scriptFile)
        outputs.dir(File(flutterProjectDir, "android/app/src/main/jniLibs"))
        environment("PATH", System.getenv("PATH") ?: "")
        isIgnoreExitValue = false
        doFirst {
            if (tspAgentNdkPath.isBlank() || !File(tspAgentNdkPath).isDirectory) {
                throw GradleException(
                    "TspAgent: NDK not found. Set sdk.dir in android/local.properties (open project in " +
                        "Android Studio) or export ANDROID_NDK_HOME to your NDK path (e.g. .../ndk/$tspAgentNdkVersion)",
                )
            }
            if (!tspAgentNdkPath.contains(tspAgentNdkVersion)) {
                logger.warn(
                    "TspAgent: NDK path should match android { ndkVersion = \"$tspAgentNdkVersion\" }",
                )
            }
            if (bashPath == null) {
                throw GradleException(
                    "TspAgent: bash not found. Use macOS/Linux, Android Studio on those platforms, " +
                        "or install Git for Windows and ensure bash is on PATH.",
                )
            }
        }
        environment("ANDROID_NDK_HOME", tspAgentNdkPath)
        environment("TSP_ANDROID_ABIS", tspAndroidAbis)
        val goflagsEnv = System.getenv("GOFLAGS")
        environment(
            "GOFLAGS",
            if (goflagsEnv.isNullOrBlank()) "-buildvcs=false" else "$goflagsEnv -buildvcs=false",
        )
        executable = bashPath ?: "/bin/bash"
        args(scriptFile.invariantSeparatorsPath, "--android-only")
    }
    tasks.named("preBuild").configure { dependsOn(buildTspAgent) }
}

// If key.properties is missing, release builds use the debug keystore — Play rejects the AAB.
afterEvaluate {
    arrayOf("bundleRelease", "assembleRelease").forEach { taskName ->
        tasks.findByName(taskName)?.doFirst {
            if (!releaseKeystoreConfigured) {
                logger.warn(
                    "\n" +
                        "================================================================================\n" +
                        "  RELEASE SIGNING: android/key.properties is missing or storeFile is blank.\n" +
                        "  This build is signed with the DEBUG key.\n" +
                        "  Google Play expects your registered upload certificate, e.g. SHA1:\n" +
                        "    48:E3:4E:35:FD:15:C7:F8:C6:4B:8B:4F:92:D2:8B:62:57:D2:CA:05\n" +
                        "  Fix: create android/key.properties — see android/key.properties.example\n" +
                        "================================================================================\n",
                )
            }
        }
    }
}
