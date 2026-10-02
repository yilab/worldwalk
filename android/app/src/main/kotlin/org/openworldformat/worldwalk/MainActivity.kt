// Worldwalk on Android — walk a .world. The fold (the spec repo's
// Kotlin package) is the engine; this UI shows what it says: the
// viewport, the branch picker, the receipts.

package org.openworldformat.worldwalk

import android.content.ContentResolver
import android.net.Uri
import android.os.Bundle
import android.provider.DocumentsContract
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.FolderOpen
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import org.openworldformat.light
import java.io.File

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            MaterialTheme {
                WorldwalkApp(resolver = contentResolver, cacheDir = cacheDir, context = this)
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WorldwalkApp(resolver: ContentResolver, cacheDir: File, context: android.content.Context? = null) {
    val state = remember { WorldState() }
    // First run opens straight into the bundled demo world.
    androidx.compose.runtime.LaunchedEffect(Unit) {
        if (state.folded == null) state.loadDemo(context ?: return@LaunchedEffect)
    }
    val openTree = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocumentTree()
    ) { uri ->
        if (uri != null) {
            val target = File(File(cacheDir, "worlds"), uri.lastPathSegment?.substringAfterLast('/') ?: "world")
            target.deleteRecursively()
            target.mkdirs()
            try {
                copyDocumentTree(resolver, uri, DocumentsContract.getTreeDocumentId(uri), target)
                state.load(target)
            } catch (e: Exception) {
                state.errorText = e.message
            }
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(state.worldName.ifEmpty { "Worldwalk" }) },
                actions = {
                    if (state.tips.size > 1) {
                        state.tips.forEach { tip ->
                            androidx.compose.material3.AssistChip(
                                onClick = {
                                    state.selectedTip = tip
                                    state.refold()
                                },
                                label = { Text("tip ${tip.take(8)}") },
                                modifier = Modifier.padding(horizontal = 2.dp),
                            )
                        }
                    }
                    Button(onClick = { openTree.launch(null) }) {
                        Icon(Icons.Filled.FolderOpen, contentDescription = null)
                        Spacer(Modifier.width(4.dp))
                        Text("Open")
                    }
                },
            )
        },
    ) { padding ->
        val folded = state.folded
        if (folded == null) {
            Welcome(state) { openTree.launch(null) }
        } else {
            Row(modifier = Modifier.padding(padding).fillMaxSize()) {
                Worldport(state, modifier = Modifier.weight(1f).fillMaxHeight())
                Receipts(state, modifier = Modifier.width(280.dp).fillMaxHeight())
            }
        }
    }
}

@Composable
private fun Welcome(state: WorldState, onOpen: () -> Unit) {
    Column(
        modifier = Modifier.fillMaxSize().padding(32.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text("🌍", style = MaterialTheme.typography.displayLarge)
        Spacer(Modifier.height(16.dp))
        Text("Worldwalk", style = MaterialTheme.typography.headlineLarge)
        Text(
            "Walk a .world.",
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(24.dp))
        Button(onClick = onOpen) { Text("Open a World…") }
        state.errorText?.let {
            Spacer(Modifier.height(16.dp))
            Text(
                it,
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodySmall,
            )
        }
        Spacer(Modifier.height(24.dp))
        Text(
            "A .world is a folder: manifest.json, an optional ops.jsonl " +
                "session log, an optional state.json. The conformance " +
                "worlds and examples live in the format's repository.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

/** The fold, itemized — the world, its branches, its state, entities. */
@Composable
private fun Receipts(state: WorldState, modifier: Modifier = Modifier) {
    LazyColumn(modifier = modifier.padding(12.dp)) {
        item {
            Section("World")
            state.summary().forEach { (label, value) -> RowLine(label, value) }
        }
        if (state.tips.size > 1) {
            item {
                Section("Branches")
                Text(
                    "tip ${state.folded?.path?.lastOrNull() ?: "—"} folded",
                    style = MaterialTheme.typography.bodySmall,
                    fontFamily = FontFamily.Monospace,
                )
            }
        }
        val values = state.stateValues
        if (values.isNotEmpty()) {
            item { Section("State") }
            items(values.keys.sorted()) { key ->
                RowLine(key, renderValue(values.getValue(key)), mono = true)
            }
        }
        val folded = state.folded
        if (folded != null) {
            item { Section("Entities (${folded.entities.size})") }
            items(folded.entities, key = { it.id }) { entity ->
                Text(
                    "${entityIcon(
                        entity.light != null,
                        entity.fields.containsKey("instance_of"),
                        entity.parent != null,
                    )} ${entity.name}",
                    style = MaterialTheme.typography.bodySmall,
                )
            }
        }
    }
}

@Composable
private fun Section(title: String) {
    Spacer(Modifier.height(12.dp))
    Text(
        title,
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.primary,
    )
}

@Composable
private fun RowLine(label: String, value: String, mono: Boolean = false) {
    Row(modifier = Modifier.fillMaxWidth()) {
        Text(label, style = MaterialTheme.typography.bodySmall)
        Spacer(Modifier.weight(1f))
        Text(
            value,
            style = MaterialTheme.typography.bodySmall,
            fontFamily = if (mono) FontFamily.Monospace else null,
        )
    }
}

// ---------------------------------------------------------------------------
// SAF folder copy — no dependency: walk the document tree by hand
// ---------------------------------------------------------------------------

private fun copyDocumentTree(resolver: ContentResolver, treeUri: Uri, docId: String, target: File) {
    val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, docId)
    val projection = arrayOf(
        DocumentsContract.Document.COLUMN_DOCUMENT_ID,
        DocumentsContract.Document.COLUMN_DISPLAY_NAME,
        DocumentsContract.Document.COLUMN_MIME_TYPE,
    )
    resolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
        while (cursor.moveToNext()) {
            val id = cursor.getString(0)
            val name = cursor.getString(1) ?: continue
            val mime = cursor.getString(2)
            val child = File(target, name)
            if (mime == DocumentsContract.Document.MIME_TYPE_DIR) {
                child.mkdirs()
                copyDocumentTree(resolver, treeUri, id, child)
            } else {
                val docUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, id)
                resolver.openInputStream(docUri)?.use { input ->
                    child.outputStream().use { input.copyTo(it) }
                }
            }
        }
    }
}
