plugins {
  id("com.android.application")
}

android {
  namespace = "com.ptelive.im.uidemo"
  compileSdk = 36

  buildFeatures {
    buildConfig = true
  }

  defaultConfig {
    applicationId = "com.ptelive.app.im.sdk.demo"
    minSdk = 31
    targetSdk = 36
    versionCode = 1
    versionName = "0.1.0-alpha"
  }
  compileOptions {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
  }
}

dependencies {
  implementation(project(":pte-im-sdk"))
  implementation(project(":pte-im-uikit"))
}
