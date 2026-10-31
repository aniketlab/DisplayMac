pluginManagement {
    repositories {
        maven { url = uri("https://maven.google.com") }
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
    repositories {
        maven { url = uri("https://maven.google.com") }
        mavenCentral()
    }
}

rootProject.name = "DisplayMacClient"
include(":app")
