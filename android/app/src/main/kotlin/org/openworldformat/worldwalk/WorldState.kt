// One loaded .world package, folded — the state behind the app. The
// fold is the app's engine (the spec repo's Kotlin package); no
// format semantics live here.

package org.openworldformat.worldwalk

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import org.openworldformat.FoldState
import org.openworldformat.LogEntry
import org.openworldformat.StateFoldResult
import org.openworldformat.WorldPackage
import org.openworldformat.foldPath
import org.openworldformat.foldState

class WorldState {
    var pack: WorldPackage? by mutableStateOf(null)
    var folded: FoldState? by mutableStateOf(null)
    var selectedTip: String? by mutableStateOf(null)
    var tips: List<String> by mutableStateOf(emptyList())
    var stateValues: Map<String, kotlinx.serialization.json.JsonElement> by mutableStateOf(emptyMap())
    var undeclared: List<String> by mutableStateOf(emptyList())
    var errorText: String? by mutableStateOf(null)

    // Bumped on every successful fold — the canvas rebuilds when it changes.
    var foldGeneration: Int by mutableStateOf(0)

    // The orbit camera.
    var yaw: Float by mutableFloatStateOf(0.6f)
    var pitch: Float by mutableFloatStateOf(0.5f)
    var distance: Float by mutableFloatStateOf(26f)

    val worldName: String get() = folded?.name ?: ""

    /** First run: the bundled demo world, so the app opens into a
     *  world instead of an empty welcome. */
    fun loadDemo(context: android.content.Context) {
        val target = java.io.File(java.io.File(context.cacheDir, "worlds"), "hello-world")
        val manifest = java.io.File(target, "manifest.json")
        if (!manifest.exists()) {
            target.deleteRecursively()
            target.mkdirs()
            for (name in listOf("manifest.json", "ops.jsonl", "state.json", "package.json")) {
                context.assets.open("hello-world/$name").use { input ->
                    java.io.File(target, name).outputStream().use { input.copyTo(it) }
                }
            }
        }
        load(target)
    }

    fun load(packageDir: java.io.File) {
        try {
            val loaded = org.openworldformat.loadWorldPackage(packageDir)
            pack = loaded
            tips = loaded.history().tips
            selectedTip = null  // default tip: last in file order
            refold()
            errorText = null
        } catch (e: Exception) {
            errorText = e.message
        }
    }

    fun refold() {
        val p = pack ?: return
        try {
            val state = foldPath(p.manifest, p.entries, tip = selectedTip)
            folded = state
            val byId = p.entries.filter { it.id != null }.associateBy { it.id!! }
            val chain: List<LogEntry> = state.path?.mapNotNull { byId[it] } ?: p.entries
            val result: StateFoldResult = foldState(p.stateDocument, chain)
            stateValues = result.values
            undeclared = result.undeclared
            foldGeneration += 1
            errorText = null
        } catch (e: Exception) {
            errorText = e.message
        }
    }

    /** Fold receipts for the sidebar, one line each. */
    fun summary(): List<Pair<String, String>> {
        val p = pack ?: return emptyList()
        val f = folded ?: return emptyList()
        return listOf(
            "name" to f.name,
            "entities" to f.entities.size.toString(),
            "edits applied" to f.appliedEdits.toString(),
            "log entries" to p.entries.size.toString(),
        )
    }
}

/** State values as compact literals, for the receipts panel. */
fun renderValue(value: kotlinx.serialization.json.JsonElement): String =
    when (value) {
        is kotlinx.serialization.json.JsonNull -> "null"
        is kotlinx.serialization.json.JsonPrimitive -> value.content
        is kotlinx.serialization.json.JsonArray ->
            "[" + value.joinToString(", ") { renderValue(it) } + "]"
        is kotlinx.serialization.json.JsonObject ->
            "{" + value.entries.sortedBy { it.key }.joinToString(", ") {
                "${it.key}: ${renderValue(it.value)}"
            } + "}"
    }

/** Glyph per entity, for the entity list — mirrors the Apple sidebar. */
fun entityIcon(hasLight: Boolean, isInstance: Boolean, hasParent: Boolean): String =
    when {
        hasLight -> "☀"
        isInstance -> "▣"
        hasParent -> "↳"
        else -> "■"
    }
