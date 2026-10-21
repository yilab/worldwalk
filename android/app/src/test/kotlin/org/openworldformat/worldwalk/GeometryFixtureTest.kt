// The spec repo's geometry parity fixture (conformance/geometry/shapes.json,
// spec/world.md "The geometry of the shapes") against this renderer's
// meshes: for one instance of every shape, the exact bounds, and landmark
// points that must be vertices — which way the wedge faces, where the apex
// is, the plane the torus lies in, the prism's first vertex, a polyhedron's
// orientation. Plus the spec's winding rule: every face counter-clockwise
// seen from outside. The fixture is read from the sibling checkout the
// composite build already needs (settings.gradle.kts), found by walking up.

package org.openworldformat.worldwalk

import java.io.File
import kotlin.math.abs
import kotlin.math.sqrt
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.double
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.openworldformat.Shape
import org.openworldformat.Vec3

class GeometryFixtureTest {
    private fun fixture(): JsonObject {
        var dir: File? = File(System.getProperty("user.dir")).absoluteFile
        while (dir != null) {
            val f = File(dir, "openworldformat/conformance/geometry/shapes.json")
            if (f.isFile) return Json.parseToJsonElement(f.readText()).jsonObject
            dir = dir.parentFile
        }
        error("no openworldformat checkout beside this one (the composite build needs it too)")
    }

    private fun Vec3.axis(i: Int): Double = when (i) { 0 -> x; 1 -> y; else -> z }

    @Test
    fun everyShapeHasTheNormativeBoundsLandmarksAndWinding() {
        val doc = fixture()
        val tolerance = doc["tolerance"]?.jsonPrimitive?.double ?: 0.001
        val kinds = mutableSetOf<String>()
        for (entry in doc["shapes"]!!.jsonArray) {
            val e = entry.jsonObject
            val name = e["name"]!!.jsonPrimitive.content
            kinds.add(e["shape"]!!.jsonObject.keys.first())
            val shape = Shape(e["shape"]) ?: error("$name: the package can't read the shape")
            val tris = shapeMesh(shape)
            val points = tris.flatMap { (a, b, c) -> listOf(a, b, c) }
            assertTrue("$name: no triangles", points.isNotEmpty())

            val min = e["bounds"]!!.jsonObject["min"]!!.jsonArray.map { it.jsonPrimitive.double }
            val max = e["bounds"]!!.jsonObject["max"]!!.jsonArray.map { it.jsonPrimitive.double }
            for (axis in 0..2) {
                val lo = points.minOf { it.axis(axis) }
                val hi = points.maxOf { it.axis(axis) }
                assertTrue("$name: min on axis $axis is $lo, not ${min[axis]}", abs(lo - min[axis]) <= tolerance)
                assertTrue("$name: max on axis $axis is $hi, not ${max[axis]}", abs(hi - max[axis]) <= tolerance)
            }
            for (mark in e["landmarks"]?.jsonArray ?: emptyList()) {
                val m = mark.jsonArray.map { it.jsonPrimitive.double }
                val nearest = points.minOf { p ->
                    sqrt((p.x - m[0]) * (p.x - m[0]) + (p.y - m[1]) * (p.y - m[1]) + (p.z - m[2]) * (p.z - m[2]))
                }
                assertTrue("$name: no vertex within $tolerance of landmark $m (nearest $nearest)", nearest <= tolerance)
            }
            // Outward: a face's normal points away from the shape's local
            // centre — the vertex centroid for the convex shapes (strictly
            // inside, unlike the origin, which the wedge's slope passes
            // through), the tube's centre circle for the torus; the plane,
            // with no inside, faces +Y.
            val centre = points.reduce { acc, p -> acc + p } * (1.0 / points.size)
            for ((a, b, c) in tris) {
                val n = cross(b - a, c - a)
                val centroid = (a + b + c) * (1.0 / 3.0)
                val outward = when (shape) {
                    is Shape.Plane -> n.y
                    is Shape.Torus -> {
                        val ring = length(Vec3(centroid.x, 0.0, centroid.z)).takeIf { it > 1e-9 } ?: 1.0
                        val onRing = Vec3(centroid.x, 0.0, centroid.z) * (shape.majorRadius / ring)
                        dot(n, centroid - onRing)
                    }
                    else -> dot(n, centroid - centre)
                }
                assertTrue("$name: a face winds inward: $a $b $c", outward > 1e-12)
            }
        }
        assertEquals(12, kinds.size)
    }
}
