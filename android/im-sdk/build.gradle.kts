plugins {
  id("com.android.library")
  kotlin("android")
}

android {
  namespace = "com.ptelive.im"
  compileSdk = 36

  defaultConfig {
    minSdk = 31
  }
}

kotlin { jvmToolchain(17) }
