plugins {
  id("com.android.library")
  kotlin("plugin.compose")
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

dependencies {
  implementation(project(":pte-im-sdk"))
  implementation("androidx.compose.runtime:runtime:1.11.4")
  implementation("androidx.compose.ui:ui:1.11.4")
  implementation("androidx.compose.foundation:foundation:1.11.4")
}
