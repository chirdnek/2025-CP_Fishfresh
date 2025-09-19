
buildscript {
    repositories {
        google()
        mavenCentral()
     maven { url = uri("https://storage.googleapis.com/download.flutter.io") }
    }
      dependencies {
        classpath("com.android.tools.build:gradle:8.2.1") // Match Flutter version
        classpath("com.google.gms:google-services:4.4.2") 
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
