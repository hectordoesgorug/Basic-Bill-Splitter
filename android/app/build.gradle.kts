import java.nio.file.Files
import java.nio.file.Paths
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseSigningPropertiesFile = rootProject.file("key.properties")
val releaseSigningProperties = Properties().apply {
    if (releaseSigningPropertiesFile.isFile) {
        releaseSigningPropertiesFile.inputStream().use(::load)
    }
}
val releaseStorePath = releaseSigningProperties.getProperty("storeFile")?.trim()
val releaseStorePassword = releaseSigningProperties.getProperty("storePassword")?.trim()
val releaseKeyAlias = releaseSigningProperties.getProperty("keyAlias")?.trim()
val releaseKeyPassword = releaseSigningProperties.getProperty("keyPassword")?.trim()

gradle.taskGraph.whenReady {
    val releaseTasks = allTasks.filter { task ->
        task.name in setOf("assembleRelease", "bundleRelease", "packageRelease") ||
            task.name.startsWith("validateSigningRelease")
    }
    if (releaseTasks.isNotEmpty()) {
        if (listOf(releaseStorePath, releaseStorePassword, releaseKeyAlias, releaseKeyPassword)
                .any { it.isNullOrBlank() }
        ) {
            throw GradleException(
                "Release signing is not configured. Set storeFile, storePassword, keyAlias, and keyPassword in android/key.properties."
            )
        }

        val keystore = try {
            Paths.get(requireNotNull(releaseStorePath)).also {
                if (!it.isAbsolute) throw IllegalArgumentException()
            }.normalize()
        } catch (_: Exception) {
            throw GradleException("Release signing storeFile must be a valid absolute path outside the repository.")
        }
        val repository = rootProject.projectDir.toPath().toRealPath()
        val realKeystore = try {
            keystore.toRealPath()
        } catch (_: Exception) {
            throw GradleException(
                "Release signing keystore must be an existing readable file outside the repository."
            )
        }
        if (realKeystore.startsWith(repository) ||
            !Files.isRegularFile(realKeystore) ||
            !Files.isReadable(realKeystore)
        ) {
            throw GradleException(
                "Release signing keystore must be an existing readable file outside the repository."
            )
        }
    }
}

android {
    namespace = "com.hectordoesgorug.basic_bill_splitter"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.hectordoesgorug.basic_bill_splitter"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            storeFile = releaseStorePath?.let { file(it) }
            storePassword = releaseStorePassword
            keyAlias = releaseKeyAlias
            keyPassword = releaseKeyPassword
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
