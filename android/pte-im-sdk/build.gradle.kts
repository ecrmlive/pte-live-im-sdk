plugins {
  id("com.android.library")
  id("com.google.devtools.ksp")
}

dependencies {
  implementation("androidx.room:room-runtime:2.8.4")
  ksp("androidx.room:room-compiler:2.8.4")
}

android {
  namespace = "com.ptelive.im"
  compileSdk = 36

  defaultConfig {
    minSdk = 31
  }
  compileOptions {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
  }
}
