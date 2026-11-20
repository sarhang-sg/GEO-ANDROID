import java.util.Properties
import javax.inject.Inject
import org.gradle.process.ExecOperations

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

if (file("google-services.json").isFile) {
    apply(plugin = "com.google.gms.google-services")
    apply(plugin = "com.google.firebase.crashlytics")
}
val sourceRoot = rootProject.projectDir.parentFile

abstract class PrepareNavKurdRoadGraph : DefaultTask() {
    @get:InputFile @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val scriptFile: RegularFileProperty
    @get:InputFile @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val manifestFile: RegularFileProperty
    @get:OutputDirectory abstract val assetsDirectory: DirectoryProperty
    @get:Inject abstract val execOperations: ExecOperations

    @TaskAction fun prepare() {
        execOperations.exec {
            commandLine("python3", scriptFile.get().asFile, "--out", assetsDirectory.dir("road-graph").get().asFile)
        }
    }
}

androidComponents.onVariants { variant ->
    val prepare = tasks.register<PrepareNavKurdRoadGraph>("prepare${variant.name.replaceFirstChar { it.uppercaseChar() }}NavKurdRoadGraph") {
        scriptFile.set(sourceRoot.resolve("tools/prepare-road-graph.py"))
        manifestFile.set(sourceRoot.resolve("contracts/offline-routing.json"))
    }
    variant.sources.assets?.addGeneratedSourceDirectory(prepare, PrepareNavKurdRoadGraph::assetsDirectory)
}

val keyProperties = Properties()
val keyPropertiesFile = rootProject.file("key.properties")
val hasReleaseKey = keyPropertiesFile.exists()
if (hasReleaseKey) {
    keyPropertiesFile.inputStream().use { keyProperties.load(it) }
}

val releaseRequested = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}
if (releaseRequested) {
    check(hasReleaseKey) { "Release signing configuration is required." }
    for (property in listOf("keyAlias", "keyPassword", "storeFile", "storePassword")) {
        check(!keyProperties.getProperty(property).isNullOrBlank()) {
            "Release signing property is missing: $property"
        }
    }
    check(file(keyProperties.getProperty("storeFile")).isFile) {
        "The established release keystore is unavailable."
    }
}

android {
    namespace = "com.navkurd.app"
    compileSdk = 37
    buildToolsVersion = "37.0.0"
    ndkVersion = flutter.ndkVersion

    androidResources {
        // PMTiles stays random-access inside the signed APK, including after
        // the user removes the installed offline-map copy.
        noCompress += listOf("pmtiles", "rd5")
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.navkurd.app"
        testInstrumentationRunner = "com.navkurd.app.WidgetLocationCheck"
        minSdk = 24
        targetSdk = 37
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        vectorDrawables.useSupportLibrary = true
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                enableV1Signing = true
                enableV2Signing = true
                enableV3Signing = true
                enableV4Signing = true
            }
        }
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
        }
        release {
            signingConfig = signingConfigs.findByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = false
        }
        resources {
            excludes += setOf(
                "META-INF/DEPENDENCIES",
                "META-INF/LICENSE*",
                "META-INF/NOTICE*",
            )
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
    implementation(files(sourceRoot.resolve("third_party/brouter/brouter-core-1.7.10.jar")))
    implementation(platform("com.google.firebase:firebase-bom:34.7.0"))
    implementation("com.google.firebase:firebase-crashlytics")
    implementation("androidx.work:work-runtime-ktx:2.10.5")
}
