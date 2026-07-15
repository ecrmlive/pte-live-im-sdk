plugins {
  id("com.android.library")
  kotlin("android")
}

android {
  namespace = "com.ptelive.im.ui"
  compileSdk = 36
  defaultConfig { minSdk = 31 }
}

dependencies { implementation(project(":im-sdk")) }
kotlin { jvmToolchain(17) }
