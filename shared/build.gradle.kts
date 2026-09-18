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

// BuildConfig для commonMain: у KMP-модуля свого немає. Значення — з gradle.properties (poriad.*).
val buildConfigFields = mapOf(
    "DEV_SUPABASE_URL" to "poriad.dev.supabaseUrl",
    "DEV_SUPABASE_KEY" to "poriad.dev.supabaseKey",
    "DEV_AUTH_SCHEME" to "poriad.dev.authScheme",
    "PROD_SUPABASE_URL" to "poriad.prod.supabaseUrl",
    "PROD_SUPABASE_KEY" to "poriad.prod.supabaseKey",
    "PROD_AUTH_SCHEME" to "poriad.prod.authScheme",
).mapValues { (_, property) -> providers.gradleProperty(property).orElse(providers.provider { error("Немає $property у gradle.properties") }) }
val generateBuildConfig by tasks.registering {
    val fields = buildConfigFields
    val outputDir = layout.buildDirectory.dir("generated/buildConfig/commonMain")
    fields.forEach { (name, value) -> inputs.property(name, value) }
    outputs.dir(outputDir)
    doLast {
        val body = fields.entries.joinToString("\n") { (name, value) -> "    const val $name = \"${value.get()}\"" }
        outputDir.get().file("app/poruch/shared/BuildConfig.kt").asFile.apply { parentFile.mkdirs() }
            .writeText("package app.poruch.shared\n\ninternal object BuildConfig {\n$body\n}\n")
    }
}
kotlin.sourceSets.commonMain { kotlin.srcDir(generateBuildConfig) }
