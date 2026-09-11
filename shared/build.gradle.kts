plugins {
    kotlin("multiplatform")
    kotlin("plugin.serialization")
    id("com.android.kotlin.multiplatform.library")
}
kotlin {
    jvm()
    listOf(iosArm64(), iosSimulatorArm64()).forEach { target ->
        target.binaries.framework {
            baseName = "Shared"
            isStatic = true
            export(project(":core:domain"))
        }
    }
    androidLibrary { namespace = "app.poruch.shared"; compileSdk = 36; minSdk = 26 }
    sourceSets {
        commonMain.dependencies {
            implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2")
            implementation("org.jetbrains.kotlinx:kotlinx-datetime:0.7.1")
            api(project(":core:domain"))
            implementation(project(":core:data"))
            implementation(project(":feature:events"))
            implementation(project(":feature:account"))
            api("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2")
            implementation("io.insert-koin:koin-core:4.2.2")
            implementation("io.ktor:ktor-client-core:3.2.3")
            implementation("app.cash.sqldelight:runtime:2.1.0")
        }
        commonTest.dependencies {
            implementation(kotlin("test"))
            implementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.10.2")
            implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.10.0")
        }
    }
}
