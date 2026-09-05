plugins {
    kotlin("multiplatform")
    kotlin("plugin.serialization")
    id("com.android.kotlin.multiplatform.library")
}
kotlin {
    jvm()
    iosArm64()
    iosSimulatorArm64()
    androidLibrary { namespace = "app.poruch.feature.events"; compileSdk = 36; minSdk = 26 }
    sourceSets {
        commonMain.dependencies {
            implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2")
            implementation("org.jetbrains.kotlinx:kotlinx-datetime:0.7.1")
            api(project(":core:domain"))
        }
        commonTest.dependencies { implementation(kotlin("test")); implementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.10.2") }
    }
}
