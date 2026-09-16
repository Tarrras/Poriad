plugins {
    kotlin("multiplatform")
    kotlin("plugin.serialization")
    id("com.android.kotlin.multiplatform.library")
    id("app.cash.sqldelight")
}
kotlin {
    jvm()
    iosArm64()
    iosSimulatorArm64()
    androidLibrary { namespace = "app.poruch.core.data"; compileSdk = 36; minSdk = 26 }
    sourceSets {
        commonMain.dependencies {
            implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2")
            implementation("org.jetbrains.kotlinx:kotlinx-datetime:0.7.1")
            api(project(":core:domain"))
            implementation("io.ktor:ktor-client-core:3.2.3")
            implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.10.0")
            implementation("app.cash.sqldelight:runtime:2.1.0")
        }
        commonTest.dependencies { implementation(kotlin("test")); implementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.10.2") }
        androidMain.dependencies { implementation("io.ktor:ktor-client-okhttp:3.2.3"); implementation("app.cash.sqldelight:android-driver:2.1.0") }
        iosMain.dependencies { implementation("io.ktor:ktor-client-darwin:3.2.3"); implementation("app.cash.sqldelight:native-driver:2.1.0") }
        jvmMain.dependencies { implementation("io.ktor:ktor-client-cio:3.2.3"); implementation("app.cash.sqldelight:sqlite-driver:2.1.0") }
        commonTest.dependencies { implementation("io.ktor:ktor-client-mock:3.2.3") }
    }
}
sqldelight { databases { create("PoruchDatabase") { packageName.set("app.poruch.data.cache") } } }
