plugins {
    kotlin("multiplatform") version "2.4.0" apply false
    kotlin("plugin.serialization") version "2.4.0" apply false
    kotlin("plugin.compose") version "2.4.0" apply false
    id("com.android.application") version "9.0.1" apply false
    id("com.android.kotlin.multiplatform.library") version "9.0.1" apply false
    id("app.cash.sqldelight") version "2.1.0" apply false
}
