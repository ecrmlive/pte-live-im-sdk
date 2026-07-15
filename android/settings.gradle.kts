pluginManagement {
  repositories { google(); mavenCentral(); gradlePluginPortal() }
}
dependencyResolutionManagement {
  repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
  repositories { google(); mavenCentral() }
}
rootProject.name = "PteIMSDK-Android"
include(":pte-im-sdk")
include(":pte-im-uikit")
include(":pte-im-ui-demo")
