plugins {
  id("com.android.library")
  id("com.google.devtools.ksp")
}

dependencies {
  implementation("androidx.room:room-runtime:2.8.4")
  ksp("androidx.room:room-compiler:2.8.4")
  testImplementation("junit:junit:4.13.2")
  // Android's platform JSON jar is a host-JVM stub. Use the real implementation for SDK unit tests.
  testImplementation("org.json:json:20250517")
  androidTestImplementation("androidx.test:runner:1.7.0")
  androidTestImplementation("androidx.test.ext:junit:1.2.1")
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
