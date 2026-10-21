// The shape vocabulary, as geometry — every variant produces faces,
// and a couple of constructions are checked against hand math.

package org.openworldformat.worldwalk

import org.openworldformat.Shape
import org.openworldformat.Vec3
import kotlin.math.abs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MeshesTest {
    @Test
    fun everyShapeProducesFaces() {
        val shapes = listOf(
            Shape.Cuboid(1.0, 2.0, 3.0),
            Shape.Sphere(0.75),
            Shape.Cylinder(0.6, 1.5),
            Shape.Cone(0.7, 1.5),
            Shape.Capsule(0.4, 0.45),
            Shape.Torus(0.6, 0.2),
            Shape.Plane(1.5, 1.5),
            Shape.Pyramid(1.5, 1.5, 1.5),
            Shape.Tetrahedron(0.9),
            Shape.Icosahedron(0.8),
            Shape.Wedge(1.5, 1.5, 1.5),
            Shape.Prism(6, 0.6, 1.5),
        )
        for (shape in shapes) {
            val tris = shapeMesh(shape)
            assertTrue("$shape produced no triangles", tris.isNotEmpty())
        }
    }

    @Test
    fun anIcosahedronHasTwentyFacesAndSitsOnItsCircumsphere() {
        val radius = 1.0
        val tris = shapeMesh(Shape.Icosahedron(radius))
        assertEquals(20, tris.size)
        for ((a, _, _) in tris) {
            assertTrue(abs(length(a) - radius) < 1e-9)
        }
    }

    @Test
    fun aPyramidIsCenteredOnItsOwnHeight() {
        val tris = shapeMesh(Shape.Pyramid(2.0, 2.0, 2.0))
        val ys = tris.flatMap { (a, b, c) -> listOf(a.y, b.y, c.y) }
        assertEquals(-1.0, ys.minOrNull())
        assertEquals(1.0, ys.maxOrNull())
    }

    @Test
    fun rotatingNinetyDegreesAboutYMovesXToMinusZ() {
        val rotated = rotate(Vec3(1.0, 0.0, 0.0), Vec3(0.0, 90.0, 0.0))
        assertTrue("got $rotated", abs(rotated.z + 1.0) < 1e-9)
        assertTrue(abs(rotated.x) < 1e-9)
        assertTrue(abs(rotated.y) < 1e-9)
    }
}
