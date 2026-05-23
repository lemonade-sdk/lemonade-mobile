allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

// Compatibility shims for abandoned / outdated Android plugins still in the
// dep graph (looking at you, isar_flutter_libs 3.1.0+1). Registered BEFORE
// the evaluationDependsOn block below — that block triggers eager
// evaluation, and Gradle won't accept an `afterEvaluate` hook on a project
// that's already finished evaluating.
//
// Two fixes baked in:
//   1. Inject a `namespace` (required by AGP 8.0+) when the module forgot
//      one, by reading the package attribute from its AndroidManifest.
//   2. Bump `compileSdk` to at least 34 so resources like
//      `android:attr/lStar` (API 31) resolve when Material / AppCompat
//      transitively pulls in newer styles.
val pluginCompileSdkFloor = 34

fun applyAndroidShims(project: Project) {
    val androidExt = project.extensions.findByName("android") ?: return

    // ── 1. Namespace ─────────────────────────────────────────────────
    try {
        val current = androidExt.javaClass
            .getMethod("getNamespace")
            .invoke(androidExt) as String?
        if (current.isNullOrBlank()) {
            val manifest = project.file("src/main/AndroidManifest.xml")
            if (manifest.exists()) {
                val match = Regex("""package="([^"]+)"""")
                    .find(manifest.readText())
                if (match != null) {
                    val pkg = match.groupValues[1]
                    androidExt.javaClass
                        .getMethod("setNamespace", String::class.java)
                        .invoke(androidExt, pkg)
                    println("[plugin-shim] Injected namespace '$pkg' for ${project.path}")
                }
            }
        }
    } catch (_: Throwable) {
        return // Not an Android module — nothing else to do.
    }

    // ── 2. compileSdk floor ──────────────────────────────────────────
    try {
        val getter = androidExt.javaClass.getMethod("getCompileSdk")
        val current = (getter.invoke(androidExt) as Int?) ?: 0
        if (current < pluginCompileSdkFloor) {
            androidExt.javaClass
                .getMethod("setCompileSdk", Int::class.javaPrimitiveType)
                .invoke(androidExt, pluginCompileSdkFloor)
            println(
                "[plugin-shim] Bumped compileSdk $current → $pluginCompileSdkFloor for ${project.path}",
            )
        }
    } catch (_: Throwable) {
        // Some plugins use compileSdkVersion (string) instead — try that.
        try {
            val getter = androidExt.javaClass.getMethod("getCompileSdkVersion")
            val current = getter.invoke(androidExt) as String?
            val parsed =
                current?.removePrefix("android-")?.toIntOrNull() ?: 0
            if (parsed < pluginCompileSdkFloor) {
                androidExt.javaClass
                    .getMethod("setCompileSdkVersion", String::class.java)
                    .invoke(androidExt, "android-$pluginCompileSdkFloor")
                println(
                    "[plugin-shim] Bumped compileSdkVersion $current → android-$pluginCompileSdkFloor for ${project.path}",
                )
            }
        } catch (_: Throwable) {
            // Older AGP — skip.
        }
    }
}

subprojects {
    if (state.executed) {
        applyAndroidShims(this)
    } else {
        afterEvaluate { applyAndroidShims(this) }
    }
}

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
