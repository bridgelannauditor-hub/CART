// Agora reads this root property when configuring its Android library.
// Without it, its own build script resets compileSdk to its fallback of 31.
extra["compileSdkVersion"] = 36

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// Configure legacy Android plugins (including Agora) as soon as their Android
// library plugin is applied, before AGP configures their native CMake build.
subprojects {
    if (name != "app") {
        plugins.withId("com.android.library") {
            extensions.configure<com.android.build.api.dsl.LibraryExtension>("android") {
                compileSdk = 36
                // Agora RTC 6.6.4's C++ renderer fails against NDK 28 libc++.
                ndkVersion = "27.2.12479018"
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
