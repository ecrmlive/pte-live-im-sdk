plugins {
  id("com.android.library")
  kotlin("plugin.compose")
}

// AGP 9+ ships built-in Kotlin and rejects org.jetbrains.kotlin.android.
// Host apps still on AGP 8 (e.g. qixi-live-sports) must apply it explicitly.
val agpMajor = com.android.Version.ANDROID_GRADLE_PLUGIN_VERSION
  .substringBefore('.')
  .toIntOrNull() ?: 0
if (agpMajor < 9) {
  apply(plugin = "org.jetbrains.kotlin.android")
}

android {
  namespace = "com.ptelive.im.ui"
  compileSdk = 36
  defaultConfig { minSdk = 31 }
  buildFeatures { compose = true }
  compileOptions {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
  }
}

if (agpMajor < 9) {
  extensions.configure<org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension>("kotlin") {
    compilerOptions {
      jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
  }
}

dependencies {
  implementation(project(":pte-im-sdk"))
  implementation("androidx.compose.runtime:runtime:1.11.4")
  implementation("androidx.compose.ui:ui:1.11.4")
  implementation("androidx.compose.foundation:foundation:1.11.4")
}
