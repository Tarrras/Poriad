import java.util.Properties
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}
val local = Properties().apply { rootProject.file("local.properties").takeIf { it.exists() }?.inputStream()?.use { load(it) } }
fun config(name: String, default: String = "") = (local.getProperty(name) ?: System.getenv(name) ?: default).replace("\\", "\\\\").replace("\"", "\\\"")
android {
    namespace = "app.poruch.android"
    compileSdk = 36
    defaultConfig {
        applicationId = "app.poruch.android"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"
        buildConfigField("String", "SUPABASE_URL", "\"${config("SUPABASE_URL", "https://tzdogzdvctlumsqlqskr.supabase.co")}\"")
        buildConfigField("String", "SUPABASE_KEY", "\"${config("SUPABASE_KEY", "sb_publishable_RoY0wFzTOcXlmOIYC0UE-w_fOt5rXPq")}\"")
        buildConfigField("String", "MAP_STYLE_URL", "\"${config("MAP_STYLE_URL", "https://tiles.openfreemap.org/styles/positron")}\"")
    }
    buildFeatures { compose = true; buildConfig = true }
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
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.10.0")
    implementation("org.maplibre.gl:android-sdk:11.11.0")
}
