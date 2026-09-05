pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement { repositories { google(); mavenCentral() } }
rootProject.name = "Poruch"
include(":core:domain", ":core:data", ":feature:events", ":feature:account", ":shared")
if (file("androidApp/build.gradle.kts").exists()) include(":androidApp")
