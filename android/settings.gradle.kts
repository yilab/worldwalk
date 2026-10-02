pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
    }
}

// The fold, from the spec repo's Kotlin package: a composite build
// substitutes the org.openworldformat:openworldformat dependency with
// the local sources until the package publishes to Maven Central —
// the same "path dep until it publishes" note worldprobe carries.
includeBuild("../../openworldformat/kotlin")

include(":app")
rootProject.name = "worldwalk"
