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

// Generate numbered dart-define pairs for a range: (dartNamePrefix, propPrefix, envPrefix, count)
fun numberedPairs(
    dartName: String,
    propName: String,
    envName: String,
    count: Int,
): List<Pair<String, String>> =
    (1..count).map { i ->
        "${dartName}_$i" to propOrEnv("${propName}.$i", "${envName}_$i")
    }

val dartDefinePairs: List<Pair<String, String>> = (listOf(
    // Build-time secrets
    "TLS_PIN_SHA256" to propOrEnv("tls.pin.sha256", "TLS_PIN_SHA256"),
    // ── TSP Agent (connectivity to backend) ────────────────
    "TSP_OPS_BASE_URL" to propOrEnv("tsp.ops.base.url", "TSP_OPS_BASE_URL"),
    "TSP_OPS_INGEST_SECRET" to propOrEnv("tsp.ops.ingest.secret", "TSP_OPS_INGEST_SECRET"),
    "TSP_OPS_CHANNEL" to propOrEnv("tsp.ops.channel", "TSP_OPS_CHANNEL"),
    // ── TSP Attestation ──────────────────────────────────────
    "TSP_ATTEST_BASE_URL" to propOrEnv("tsp.attest.base.url", "TSP_ATTEST_BASE_URL"),
    "TSP_ATTEST_BEARER_TOKEN" to propOrEnv("tsp.attest.bearer.token", "TSP_ATTEST_BEARER_TOKEN"),
    // Explorer keys (numbered)
) + numberedPairs("ETHERSCAN_API_KEY", "etherscan.api.key", "ETHERSCAN_API_KEY", 5) +
    numberedPairs("BSCSCAN_API_KEY", "bscscan.api.key", "BSCSCAN_API_KEY", 4) +
    numberedPairs("POLYGONSCAN_API_KEY", "polygonscan.api.key", "POLYGONSCAN_API_KEY", 3) +
    numberedPairs("AVALANCHE_API_KEY", "snowtrace.api.key", "AVALANCHE_API_KEY", 3) +
    numberedPairs("ARBITRUMSCAN_API_KEY", "arbiscan.api.key", "ARBITRUMSCAN_API_KEY", 3) +
    // TronGrid (12 keys)
    numberedPairs("TRONGRID_API_KEY", "trongrid.api.key", "TRONGRID_API_KEY", 12) +
    // Polkadot (7 keys)
    numberedPairs("SUBSCAN_API_KEY", "subscan.api.key", "SUBSCAN_API_KEY", 7) +
    // Bitcoin — BlockCypher (6 keys)
    numberedPairs("BLOCKCYPHER_API_KEY", "blockcypher.api.key", "BLOCKCYPHER_API_KEY", 6) +
    // CoinGecko (6 keys)
    numberedPairs("COINGECKO_API_KEY", "coingecko.api.key", "COINGECKO_API_KEY", 6) +
    // dRPC (7 keys)
    numberedPairs("DRPC_API_KEY", "drpc.api.key", "DRPC_API_KEY", 7) +
    // Ankr (7 keys)
    numberedPairs("ANKR_API_KEY", "ankr.api.key", "ANKR_API_KEY", 7) +
    // Tenderly — 3 accounts × (1 key + 8 URLs each)
    numberedPairs("TENDERLY_API_KEY", "tenderly.api.key", "TENDERLY_API_KEY", 3) +
    numberedPairs("TENDERLY_ETH_RPC_URL", "tenderly.eth.rpc", "TENDERLY_ETH_RPC_URL", 3) +
    numberedPairs("TENDERLY_ETH_WSS_URL", "tenderly.eth.wss", "TENDERLY_ETH_WSS_URL", 3) +
    numberedPairs("TENDERLY_POLYGON_RPC_URL", "tenderly.polygon.rpc", "TENDERLY_POLYGON_RPC_URL", 3) +
    numberedPairs("TENDERLY_POLYGON_WSS_URL", "tenderly.polygon.wss", "TENDERLY_POLYGON_WSS_URL", 3) +
    numberedPairs("TENDERLY_ARBITRUM_RPC_URL", "tenderly.arbitrum.rpc", "TENDERLY_ARBITRUM_RPC_URL", 3) +
    numberedPairs("TENDERLY_ARBITRUM_WSS_URL", "tenderly.arbitrum.wss", "TENDERLY_ARBITRUM_WSS_URL", 3) +
    numberedPairs("TENDERLY_AVALANCHE_RPC_URL", "tenderly.avalanche.rpc", "TENDERLY_AVALANCHE_RPC_URL", 3) +
    numberedPairs("TENDERLY_AVALANCHE_WSS_URL", "tenderly.avalanche.wss", "TENDERLY_AVALANCHE_WSS_URL", 3) +
    // Etox — 6 accounts × (1 key + 6 URLs each)
    numberedPairs("ETOX_API_KEY", "etox.api.key", "ETOX_API_KEY", 6) +
    numberedPairs("ETOX_ETH_RPC_URL", "etox.eth.rpc", "ETOX_ETH_RPC_URL", 6) +
    numberedPairs("ETOX_ETH_WSS_URL", "etox.eth.wss", "ETOX_ETH_WSS_URL", 6) +
    numberedPairs("ETOX_ARB_RPC_URL", "etox.arb.rpc", "ETOX_ARB_RPC_URL", 6) +
    numberedPairs("ETOX_ARB_WSS_URL", "etox.arb.wss", "ETOX_ARB_WSS_URL", 6) +
    numberedPairs("ETOX_POLYGON_RPC_URL", "etox.polygon.rpc", "ETOX_POLYGON_RPC_URL", 6) +
    numberedPairs("ETOX_POLYGON_WSS_URL", "etox.polygon.wss", "ETOX_POLYGON_WSS_URL", 6) +
    // Solana — 3 RPC + 3 WS
    numberedPairs("SOLANA_RPC_URL", "solana.rpc.url", "SOLANA_RPC_URL", 3) +
    numberedPairs("SOLANA_WS_URL", "solana.ws.url", "SOLANA_WS_URL", 3) +
    // Helius (9 keys)
    numberedPairs("HELIUS_API_KEY", "helius.api.key", "HELIUS_API_KEY", 9) +
    // Single-key providers
    listOf(
        "CHAINSTACK_ETH_TOKEN" to propOrEnv("chainstack.eth.token", "CHAINSTACK_ETH_TOKEN"),
        "CHAINSTACK_BTC_TOKEN" to propOrEnv("chainstack.btc.token", "CHAINSTACK_BTC_TOKEN"),
        "TLS_PIN_SHA256" to propOrEnv("tls.pin.sha256", "TLS_PIN_SHA256"),
    )
).filter { (_, v) -> v.isNotEmpty() }.distinctBy { it.first }

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
        targetSdk = 35
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
        // libc++_shared.so conflict resolution:
        // Multiple AARs (wallet-core, Flutter plugins, etc.) bundle their own
        // libc++_shared.so, potentially compiled with different NDK versions.
        // Using the WRONG version for the process ABI (e.g. a libc++ from NDK r23
        // on a library compiled with NDK r29) corrupts memory and causes SIGABRT.
        //
        // Solution: We bundle NDK 29's libc++_shared.so into jniLibs via a
        // pre-build task (see copyLibCxxShared task below). The project-source
        // jniLibs are merged BEFORE AARs, so our NDK 29 copy wins pickFirst.
        // NDK r29's libc++ is backward ABI-compatible with older versions.
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
