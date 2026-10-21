// Shape → triangles: the parametric vocabulary as pure geometry, the
// same constructions the Apple renderer builds (boxes and lathe
// surfaces, hand-built polyhedra with winding auto-corrected). No
// engine, no dependency — the renderer projects these itself.

package org.openworldformat.worldwalk

import org.openworldformat.Shape
import org.openworldformat.Vec3
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

typealias Tri = Triple<Vec3, Vec3, Vec3>

fun shapeMesh(shape: Shape): List<Tri> = when (shape) {
    is Shape.Cuboid -> box(shape.x, shape.y, shape.z)
    is Shape.Sphere -> latheSphere(shape.radius)
    is Shape.Cylinder -> latheCylinder(shape.radius, shape.height)
    is Shape.Cone -> latheCone(shape.radius, shape.height)
    is Shape.Capsule -> latheCapsule(shape.radius, shape.halfLength)
    is Shape.Torus -> torus(shape.majorRadius, shape.minorRadius)
    is Shape.Plane -> planeQuad(shape.x, shape.z)
    is Shape.Pyramid -> pyramid(shape.baseX, shape.baseZ, shape.height)
    is Shape.Tetrahedron -> tetrahedron(shape.radius)
    is Shape.Icosahedron -> icosahedron(shape.radius)
    is Shape.Wedge -> wedge(shape.x, shape.y, shape.z)
    is Shape.Prism -> prism(shape.sides, shape.radius, shape.height)
}

// ---------------------------------------------------------------------------
// Boxes, planes, polyhedra — flat triangles, winding fixed outward
// ---------------------------------------------------------------------------

private fun box(x: Double, y: Double, z: Double): List<Tri> {
    val hx = x / 2
    val hy = y / 2
    val hz = z / 2
    val c = listOf(
        Vec3(-hx, -hy, -hz), Vec3(hx, -hy, -hz), Vec3(hx, -hy, hz), Vec3(-hx, -hy, hz),
        Vec3(-hx, hy, -hz), Vec3(hx, hy, -hz), Vec3(hx, hy, hz), Vec3(-hx, hy, hz),
    )
    // Each quad counter-clockwise seen from outside (the spec's winding rule).
    val quads = listOf(
        listOf(c[0], c[1], c[2], c[3]), listOf(c[4], c[7], c[6], c[5]),  // bottom (-Y), top (+Y)
        listOf(c[0], c[4], c[5], c[1]), listOf(c[3], c[2], c[6], c[7]),  // back (-Z), front (+Z)
        listOf(c[0], c[3], c[7], c[4]), listOf(c[1], c[5], c[6], c[2]),  // left (-X), right (+X)
    )
    return quads.flatMap { q -> listOf(Tri(q[0], q[1], q[2]), Tri(q[0], q[2], q[3])) }
}

private fun planeQuad(x: Double, z: Double): List<Tri> {
    val hx = x / 2
    val hz = z / 2
    val a = Vec3(-hx, 0.0, -hz)
    val b = Vec3(hx, 0.0, -hz)
    val c = Vec3(hx, 0.0, hz)
    val d = Vec3(-hx, 0.0, hz)
    return listOf(Tri(a, d, c), Tri(a, c, b))  // facing +Y, like the ground
}

private fun pyramid(baseX: Double, baseZ: Double, height: Double): List<Tri> {
    val hx = baseX / 2
    val hz = baseZ / 2
    val h = height / 2
    val a = Vec3(-hx, -h, -hz)
    val b = Vec3(hx, -h, -hz)
    val c = Vec3(hx, -h, hz)
    val d = Vec3(-hx, -h, hz)
    val apex = Vec3(0.0, h, 0.0)
    // Counter-clockwise seen from outside: the spec's winding rule.
    return listOf(
        Tri(b, a, apex), Tri(c, b, apex), Tri(d, c, apex), Tri(a, d, apex),
        Tri(a, b, d), Tri(b, c, d),
    )
}

private fun tetrahedron(radius: Double): List<Tri> {
    val v = listOf(
        Vec3(1.0, 1.0, 1.0), Vec3(1.0, -1.0, -1.0),
        Vec3(-1.0, 1.0, -1.0), Vec3(-1.0, -1.0, 1.0),
    ).map { normalize(it) * radius }
    return listOf(
        Tri(v[0], v[1], v[2]), Tri(v[0], v[3], v[1]),
        Tri(v[0], v[2], v[3]), Tri(v[1], v[3], v[2]),
    )
}

private fun icosahedron(radius: Double): List<Tri> {
    val t = (1 + sqrt(5.0)) / 2
    val raw = listOf(
        Vec3(-1.0, t, 0.0), Vec3(1.0, t, 0.0), Vec3(-1.0, -t, 0.0), Vec3(1.0, -t, 0.0),
        Vec3(0.0, -1.0, t), Vec3(0.0, 1.0, t), Vec3(0.0, -1.0, -t), Vec3(0.0, 1.0, -t),
        Vec3(t, 0.0, -1.0), Vec3(t, 0.0, 1.0), Vec3(-t, 0.0, -1.0), Vec3(-t, 0.0, 1.0),
    ).map { normalize(it) * radius }
    val faces = listOf(
        listOf(0, 11, 5), listOf(0, 5, 1), listOf(0, 1, 7), listOf(0, 7, 10), listOf(0, 10, 11),
        listOf(1, 5, 9), listOf(5, 11, 4), listOf(11, 10, 2), listOf(10, 7, 6), listOf(7, 1, 8),
        listOf(3, 9, 4), listOf(3, 4, 2), listOf(3, 2, 6), listOf(3, 6, 8), listOf(3, 8, 9),
        listOf(4, 9, 5), listOf(2, 4, 11), listOf(6, 2, 10), listOf(8, 6, 7), listOf(9, 8, 1),
    )
    return faces.map { Tri(raw[it[0]], raw[it[1]], raw[it[2]]) }
}

/** A ramp, as spec/world.md "The geometry of the shapes" states it: the
 *  right-triangle profile in XY — the vertical face at -x (full height),
 *  the base at -y, the slope down toward +x — extruded along Z. Its six
 *  vertices are (-x/2, ±y/2, ±z/2) and (+x/2, -y/2, ±z/2). */
private fun wedge(x: Double, y: Double, z: Double): List<Tri> {
    val hx = x / 2
    val hy = y / 2
    val hz = z / 2
    val af = Vec3(-hx, -hy, hz)
    val bf = Vec3(hx, -hy, hz)
    val cf = Vec3(-hx, hy, hz)
    val ab = Vec3(-hx, -hy, -hz)
    val bb = Vec3(hx, -hy, -hz)
    val cb = Vec3(-hx, hy, -hz)
    return listOf(
        Tri(af, bf, cf),                    // front cap, z = +hz
        Tri(bb, ab, cb),                    // back cap, z = -hz
        Tri(ab, bb, bf), Tri(ab, bf, af),   // bottom
        Tri(ab, af, cf), Tri(ab, cf, cb),   // the vertical face at -x
        Tri(bf, bb, cb), Tri(bf, cb, cf),   // the slope
    )
}

/** The experimental prism, as the spec states it: `sides` 3..8, `radius`
 *  the circumradius, axis +Y, cap vertex i at (r cos θ, ±h/2, -r sin θ)
 *  with θ = 2πi/sides — the first vertex on +X, the ring counter-clockwise
 *  seen from above — sides as quads, caps as fans from vertex 0, outward. */
private fun prism(sides: Int, radius: Double, height: Double): List<Tri> {
    val n = sides.coerceIn(3, 8)
    val hy = height / 2
    fun ring(y: Double): List<Vec3> = (0 until n).map { i ->
        val theta = 2 * PI * i / n
        Vec3(radius * cos(theta), y, -radius * sin(theta))
    }
    val top = ring(hy)
    val bottom = ring(-hy)
    val tris = mutableListOf<Tri>()
    for (i in 0 until n) {
        val j = (i + 1) % n
        tris.add(Tri(bottom[i], bottom[j], top[j]))
        tris.add(Tri(bottom[i], top[j], top[i]))
    }
    for (i in 1 until n - 1) {
        tris.add(Tri(top[0], top[i], top[i + 1]))
        tris.add(Tri(bottom[0], bottom[i + 1], bottom[i]))
    }
    return tris
}

// ---------------------------------------------------------------------------
// Lathe surfaces — rings around Y, auto-corrected winding
// ---------------------------------------------------------------------------

private fun lathe(rings: Int, profile: List<Vec3>): List<Tri> {
    // The profile is given as (x = radius, y = height); revolve it.
    val grid = (0 until rings).map { i ->
        val angle = i.toDouble() / rings * 2 * PI
        profile.map { p -> Vec3(p.x * cos(angle), p.y, p.x * sin(angle)) }
    }
    val tris = mutableListOf<Tri>()
    for (i in 0 until rings) {
        val j = (i + 1) % rings
        for (k in 0 until profile.size - 1) {
            val a = grid[i][k]
            val b = grid[j][k]
            val c = grid[j][k + 1]
            val d = grid[i][k + 1]
            // Counter-clockwise seen from outside (the spec's winding rule):
            // the ring runs +X toward +Z, clockwise from above, so the quad
            // is split against it. The renderer shades both sides anyway.
            // A ring collapsed to a pole makes zero-area triangles: drop them.
            if (length(cross(c - a, b - a)) > 1e-12) tris.add(Tri(a, c, b))
            if (length(cross(d - a, c - a)) > 1e-12) tris.add(Tri(a, d, c))
        }
    }
    return tris
}

private fun latheSphere(radius: Double): List<Tri> =
    lathe(24, profile(0..40) { step ->  // inclusive: the last point is the north pole
        val theta = step.toDouble() / 40 * PI  // pole to pole
        Vec3(radius * sin(theta), -radius * cos(theta), 0.0)
    })

private fun latheCylinder(radius: Double, height: Double): List<Tri> =
    lathe(24, profile(listOf(-height / 2, height / 2)) { y ->
        Vec3(radius, y, 0.0)
    }) + cap(24, radius, -height / 2, facingUp = false) + cap(24, radius, height / 2, facingUp = true)

private fun latheCone(radius: Double, height: Double): List<Tri> =
    lathe(24, profile(listOf(-height / 2, height / 2)) { y ->
        Vec3(radius * (1 - (y + height / 2) / height), y, 0.0)
    }) + cap(24, radius, -height / 2, facingUp = false)

/** A flat cap closing a lathe surface: a fan from the axis point at
 *  height [y], wound to face up (+Y) or down (-Y). The spec's cylinder
 *  and cone have flat caps; an open tube is a different shape. */
private fun cap(rings: Int, radius: Double, y: Double, facingUp: Boolean): List<Tri> {
    val centre = Vec3(0.0, y, 0.0)
    return (0 until rings).map { i ->
        val a = i.toDouble() / rings * 2 * PI
        val b = (i + 1).toDouble() / rings * 2 * PI
        val p = Vec3(radius * cos(a), y, radius * sin(a))
        val q = Vec3(radius * cos(b), y, radius * sin(b))
        if (facingUp) Tri(centre, q, p) else Tri(centre, p, q)
    }
}

private fun latheCapsule(radius: Double, halfLength: Double): List<Tri> =
    lathe(24, profile(0..40) { step ->  // inclusive: the last point is the top pole
        val y = -halfLength - radius + step.toDouble() / 40 * (2 * (halfLength + radius))
        val rho = when {
            y < -halfLength -> sqrt((radius * radius - (y + halfLength) * (y + halfLength)).coerceAtLeast(0.0))
            y > halfLength -> sqrt((radius * radius - (y - halfLength) * (y - halfLength)).coerceAtLeast(0.0))
            else -> radius
        }
        Vec3(rho, y, 0.0)
    })

private fun torus(majorRadius: Double, minorRadius: Double): List<Tri> =
    lathe(32, profile(0..32) { step ->  // inclusive: the tube closes on its first point
        val v = step.toDouble() / 32 * 2 * PI
        Vec3(majorRadius + minorRadius * cos(v), minorRadius * sin(v), 0.0)
    })

/** Numeric range → profile points (empty ranges get start/end guards). */
private fun profile(steps: IntRange, f: (Int) -> Vec3): List<Vec3> =
    steps.map(f).ifEmpty { listOf(Vec3(0.0, 0.0, 0.0)) }

private fun profile(heights: List<Double>, f: (Double) -> Vec3): List<Vec3> =
    heights.map(f)

// ---------------------------------------------------------------------------
// Vector helpers (Vec3 from the package has no math operators)
// ---------------------------------------------------------------------------

operator fun Vec3.plus(o: Vec3) = Vec3(x + o.x, y + o.y, z + o.z)
operator fun Vec3.minus(o: Vec3) = Vec3(x - o.x, y - o.y, z - o.z)
operator fun Vec3.times(s: Double) = Vec3(x * s, y * s, z * s)
operator fun Vec3.times(o: Vec3) = Vec3(x * o.x, y * o.y, z * o.z)  // component-wise scale
operator fun Double.times(v: Vec3) = v * this

fun dot(a: Vec3, b: Vec3): Double = a.x * b.x + a.y * b.y + a.z * b.z
fun cross(a: Vec3, b: Vec3): Vec3 =
    Vec3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
fun length(v: Vec3): Double = sqrt(dot(v, v))
fun normalize(v: Vec3): Vec3 = v * (1.0 / (length(v).takeIf { it > 1e-9 } ?: 1.0))
