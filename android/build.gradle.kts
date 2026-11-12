allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// Some older plugins (e.g. cloud_functions 5.6.x) don't declare compileSdk,
// which AGP 9 rejects. Give library plugins a default; plugins that set their
// own value afterwards still override it.
subprojects {
    plugins.withId("com.android.library") {
        extensions.findByName("android")?.withGroovyBuilder {
            setProperty("compileSdk", 36)
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
