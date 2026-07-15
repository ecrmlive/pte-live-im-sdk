plugins {
  id("com.android.application")
  kotlin("android")
}

android {
  namespace = "com.ptelive.im.uidemo"
  compileSdk = 36

  defaultConfig {
    applicationId = "com.ptelive.im.uidemo"
    minSdk = 31
    targetSdk = 36
    versionCode = 1
    versionName = "0.1.0-alpha"
  }
}

kotlin { jvmToolchain(17) }

dependencies {
  implementation(project(":pte-im-sdk"))
  implementation(project(":pte-im-uikit"))
}
