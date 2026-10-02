// The fold, projected: a dependency-free 3D renderer on Compose
// Canvas — perspective projection, painter's algorithm, one-lambert
// lighting from the fold's own directional light. The same role
// RealityKit plays on the Apple side; Filament/SceneView is the
// upgrade path when the viewer needs real PBR.

package org.openworldformat.worldwalk

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.input.pointer.pointerInput
import org.openworldformat.FoldState
import org.openworldformat.MaterialDef
import org.openworldformat.Shape
import org.openworldformat.Vec3
import org.openworldformat.WorldEntity
import org.openworldformat.light
import org.openworldformat.material
import org.openworldformat.shape
import org.openworldformat.transform
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.tan

/** A face prepared for painting: screen polygon, depth, fill color. */
private class Face(val points: List<Offset>, val depth: Float, val color: Color)

/** One entity's draw record: world-space triangles plus presentation. */
private class Drawable(
    val tris: List<Tri>,
    val color: Color,
    val emissive: Boolean,
    val isLight: Boolean,
)

/** Euler XYZ in degrees, the format's convention. */
fun rotate(v: Vec3, degrees: Vec3): Vec3 {
    val rx = Math.toRadians(degrees.x)
    val ry = Math.toRadians(degrees.y)
    val rz = Math.toRadians(degrees.z)
    var p = v
    // X
    p = Vec3(p.x, p.y * cos(rx) - p.z * sin(rx), p.y * sin(rx) + p.z * cos(rx))
    // Y
    p = Vec3(p.x * cos(ry) + p.z * sin(ry), p.y, -p.x * sin(ry) + p.z * cos(ry))
    // Z
    p = Vec3(p.x * cos(rz) - p.y * sin(rz), p.x * sin(rz) + p.y * cos(rz), p.z)
    return p
}

private fun rgb(components: List<Double>?, fallback: Long): Color {
    if (components == null || components.size < 3) return Color(fallback)
    val a = if (components.size > 3) components[3].toFloat() else 1f
    return Color(
        red = components[0].toFloat(),
        green = components[1].toFloat(),
        blue = components[2].toFloat(),
        alpha = a.coerceIn(0f, 1f),
    )
}

private fun materialColor(material: MaterialDef?): Color =
    rgb(material?.color, 0xFF9E9E9E)

/** Build the draw list: entities flattened to world space. Parent
 *  rotations are not composed (v0 — the conformance trees stand
 *  upright, so position chaining is exact for them). */
private fun buildDrawables(state: FoldState): List<Drawable> {
    val byId = state.entities.associateBy { it.id }
    val out = mutableListOf<Drawable>()
    for (entity in state.entities) {
        val shape = entity.shape
        val lightDef = entity.light
        if (shape == null && lightDef == null) continue
        // World position: own transform plus the parent chain's.
        var position = Vec3(0.0, 0.0, 0.0)
        var rotation = Vec3(0.0, 0.0, 0.0)
        var scale = Vec3(1.0, 1.0, 1.0)
        var cursor: WorldEntity? = entity
        val guard = HashSet<Int>()
        while (cursor != null && cursor.id !in guard) {
            guard.add(cursor.id)
            val t = cursor.transform
            if (t != null) {
                t.position?.let { position = position + it }
                t.rotationDegrees?.let { rotation = it + rotation }
                t.scale?.let { scale = Vec3(scale.x * it.x, scale.y * it.y, scale.z * it.z) }
            }
            cursor = cursor.parent?.let { byId[it] }
        }
        val material = entity.material
        val drawable = if (shape != null) {
            val tris = shapeMesh(shape).map { (a, b, c) ->
                Tri(
                    rotate(a * scale, rotation) + position,
                    rotate(b * scale, rotation) + position,
                    rotate(c * scale, rotation) + position,
                )
            }
            Drawable(
                tris = tris,
                color = materialColor(material),
                emissive = material?.emissive != null,
                isLight = false,
            )
        } else {
            // A light draws as a small bright octahedron at its position.
            Drawable(
                tris = shapeMesh(Shape.Tetrahedron(0.5)).map { (a, b, c) ->
                    Tri(
                        rotate(a * scale, rotation) + position,
                        rotate(b * scale, rotation) + position,
                        rotate(c * scale, rotation) + position,
                    )
                },
                color = rgb(lightDef?.color, 0xFFFFE082),
                emissive = true,
                isLight = true,
            )
        }
        out.add(drawable)
    }
    return out
}

/** The first directional light in the fold, for lambert shading;
 *  a mild default from above when a world declares none. */
private fun sunOf(state: FoldState): Pair<Vec3, Color> {
    for (entity in state.entities) {
        val light = entity.light ?: continue
        if (light.lightType == null || light.lightType == "directional") {
            val d = light.direction
            if (d != null && d.size >= 3) {
                val dir = normalize(Vec3(-d[0], -d[1], -d[2]))  // shading direction
                return dir to rgb(light.color, 0xFFFFFFFF)
            }
        }
    }
    return normalize(Vec3(0.3, -1.0, -0.4)) to Color.White
}

@Composable
fun Worldport(state: WorldState, modifier: Modifier = Modifier) {
    val folded = state.folded ?: return

    Canvas(
        modifier = modifier.pointerInput(Unit) {
            detectTransformGestures { _, pan, zoom, _ ->
                state.yaw -= pan.x * 0.01f
                state.pitch = (state.pitch + pan.y * 0.01f).coerceIn(-1.4f, 1.4f)
                state.distance = (state.distance / zoom).coerceIn(2f, 120f)
            }
        }
    ) {
        val drawables = buildDrawables(folded)
        val (sunDir, sunTint) = sunOf(folded)
        val ambient = ((folded.environment?.ambientIntensity ?: 100.0) / 400.0).toFloat()
        val background = folded.environment?.backgroundColor
        if (background != null && background.size >= 3) {
            drawRect(rgb(background, 0xFF101018))
        }

        // Camera: orbit the scene, looking at its heart.
        val center = Vec3(0.0, 1.0, 0.0)
        val yawR = state.yaw.toDouble()
        val pitchR = state.pitch.toDouble()
        val dist = state.distance.toDouble()
        val eye = center + Vec3(
            dist * cos(pitchR) * sin(yawR),
            dist * sin(pitchR),
            dist * cos(pitchR) * cos(yawR),
        )
        val forward = normalize(center - eye)
        val upWorld = Vec3(0.0, 1.0, 0.0)
        val right = normalize(cross(forward, upWorld))
        val up = cross(right, forward)
        val focal = size.height * 1.1

        fun project(p: Vec3): Pair<Offset, Float>? {
            val d = p - eye
            val z = dot(d, forward)
            if (z < 0.05) return null  // behind the camera
            val x = dot(d, right)
            val y = dot(d, up)
            val sx = size.width / 2 + (x / z * focal).toFloat()
            val sy = size.height / 2 - (y / z * focal).toFloat()
            return Offset(sx, sy) to z.toFloat()
        }

        val faces = mutableListOf<Face>()
        for (drawable in drawables) {
            for ((a, b, c) in drawable.tris) {
                val pa = project(a) ?: continue
                val pb = project(b) ?: continue
                val pc = project(c) ?: continue
                val depth = (pa.second + pb.second + pc.second) / 3f
                val shade = if (drawable.emissive) {
                    1.0f
                } else {
                    val n = normalize(cross(b - a, c - a))
                    val lambert = kotlin.math.abs(dot(n, sunDir)).toFloat() * 0.8f
                    (ambient.coerceIn(0.05f, 0.6f) + lambert).coerceAtMost(1f)
                }
                val color = Color(
                    red = drawable.color.red * shade * sunTint.red,
                    green = drawable.color.green * shade * sunTint.green,
                    blue = drawable.color.blue * shade * sunTint.blue,
                    alpha = drawable.color.alpha,
                )
                faces.add(Face(listOf(pa.first, pb.first, pc.first), depth, color))
            }
        }
        faces.sortByDescending { it.depth }
        for (face in faces) {
            val path = Path().apply {
                moveTo(face.points[0].x, face.points[0].y)
                lineTo(face.points[1].x, face.points[1].y)
                lineTo(face.points[2].x, face.points[2].y)
                close()
            }
            drawPath(path, face.color)
        }
        // A horizon line so orientation survives flat worlds.
        drawLine(
            color = Color.White.copy(alpha = 0.08f),
            start = Offset(0f, size.height * 0.5f),
            end = Offset(size.width, size.height * 0.5f),
            strokeWidth = 1f,
        )
    }
}
