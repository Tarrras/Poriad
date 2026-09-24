import java.util.Properties
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
}
val local = Properties().apply { rootProject.file("local.properties").takeIf { it.exists() }?.inputStream()?.use { load(it) } }
fun config(name: String, default: String = "") = (local.getProperty(name) ?: System.getenv(name) ?: default).replace("\\", "\\\\").replace("\"", "\\\"")
android {
    namespace = "app.poruch.android"
    compileSdk = 36
    defaultConfig {
        applicationId = "app.poriad.android"
        minSdk = 26
        targetSdk = 36
        // Номер збірки для магазину: `-Pporiad.versionCode=N` або gradle.properties. Без нього — 1.
        versionCode = providers.gradleProperty("poriad.versionCode").orNull?.toInt() ?: 1
        versionName = "1.0.0"
        // The style is the app's own; only where its geometry and letterforms come from is
        // configurable, and blank means the defaults in shared MapEndpoints.
        buildConfigField("String", "MAP_TILES_URL", "\"${config("MAP_TILES_URL")}\"")
        buildConfigField("String", "MAP_GLYPHS_URL", "\"${config("MAP_GLYPHS_URL")}\"")
    }
    // Ключ релізу з local.properties або оточення. Без нього assembleRelease збирає непідписаний APK:
    // так CI й чужі машини не падають, а магазинну збірку підписує лише той, у кого є сховище.
    signingConfigs.create("release") {
        val store = config("RELEASE_STORE_FILE")
        if (store.isNotEmpty()) {
            storeFile = file(store)
            storePassword = config("RELEASE_STORE_PASSWORD")
            keyAlias = config("RELEASE_KEY_ALIAS")
            keyPassword = config("RELEASE_KEY_PASSWORD")
        }
    }
    // Середовище — окремий вимір від debug/release: devDebug щодня, prodRelease у магазин,
    // prodDebug — відтворити баг на живих даних, devRelease — перевірити R8 без ризику для prod.
    // Адреса й ключ бекенду — лише свого середовища: prod-бінарник не несе dev.
    // Dev — окремий застосунок (.dev) у власному Firebase-проєкті: src/dev/google-services.json,
    // prod — src/prod/google-services.json. Схема auth-колбеку — з gradle.properties, як і в shared.
    flavorDimensions += "env"
    productFlavors {
        create("dev") {
            dimension = "env"
            applicationIdSuffix = ".dev"
            buildConfigField("String", "SUPABASE_URL", "\"${providers.gradleProperty("poriad.dev.supabaseUrl").get()}\"")
            buildConfigField("String", "SUPABASE_KEY", "\"${providers.gradleProperty("poriad.dev.supabaseKey").get()}\"")
            resValue("string", "app_name", "Поряд Dev")
            manifestPlaceholders["authScheme"] = providers.gradleProperty("poriad.dev.authScheme").get()
            buildConfigField("String", "AUTH_SCHEME", "\"${providers.gradleProperty("poriad.dev.authScheme").get()}\"")
        }
        create("prod") {
            dimension = "env"
            buildConfigField("String", "SUPABASE_URL", "\"${providers.gradleProperty("poriad.prod.supabaseUrl").get()}\"")
            buildConfigField("String", "SUPABASE_KEY", "\"${providers.gradleProperty("poriad.prod.supabaseKey").get()}\"")
            resValue("string", "app_name", "Поряд")
            manifestPlaceholders["authScheme"] = providers.gradleProperty("poriad.prod.authScheme").get()
            buildConfigField("String", "AUTH_SCHEME", "\"${providers.gradleProperty("poriad.prod.authScheme").get()}\"")
        }
    }
    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            if (config("RELEASE_STORE_FILE").isNotEmpty()) signingConfig = signingConfigs.getByName("release")
        }
        debug { }
    }
    buildFeatures { compose = true; buildConfig = true; resValues = true }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
}
dependencies {
    implementation("io.coil-kt.coil3:coil-compose:3.4.0")
    implementation("io.coil-kt.coil3:coil-network-okhttp:3.4.0")
    implementation(project(":shared"))
    implementation(project(":core:domain"))
    implementation(platform("androidx.compose:compose-bom:2026.02.01"))
    implementation("androidx.activity:activity-compose:1.12.4")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.10.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.10.0")
    implementation("androidx.navigation3:navigation3-runtime:1.0.1")
    implementation("androidx.navigation3:navigation3-ui:1.0.1")
    implementation("androidx.lifecycle:lifecycle-viewmodel-navigation3:2.10.0")
    // Koin: граф, моделі й записи стека навігації. Версія збігається з koin-core у :shared.
    implementation(platform("io.insert-koin:koin-bom:4.2.2"))
    implementation("io.insert-koin:koin-android")
    implementation("io.insert-koin:koin-androidx-compose")
    implementation("io.insert-koin:koin-compose-navigation3")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.10.0")
    implementation("org.maplibre.gl:android-sdk:11.11.0")
    implementation("com.airbnb.android:lottie-compose:6.7.1")
    // Орієнтація фото на API 26–27: системний ExifInterface там має відомі вразливості.
    implementation("androidx.exifinterface:exifinterface:1.4.2")
    // Firebase: пуші, аналітика, крашлітика. Версії з BOM.
    implementation(platform("com.google.firebase:firebase-bom:34.3.0"))
    implementation("com.google.firebase:firebase-messaging")
    implementation("com.google.firebase:firebase-analytics")
    implementation("com.google.firebase:firebase-crashlytics")
}
