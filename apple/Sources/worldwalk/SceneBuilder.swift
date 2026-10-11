// The fold, made walkable: a FoldState becomes a RealityKit scene.
//
// Adds no format semantics of its own — shapes, materials, lights and
// transforms are read exactly as the document declares them, and
// everything the viewer profile doesn't carry (behaviors, triggers,
// audio, tours, `ext-*`) is must-ignored. Units are meters in both
// worlds; Y is up in both.

import RealityKit
import OpenWorldFormat

#if os(macOS)
import AppKit
typealias PlatformColor = NSColor
#else
import UIKit
typealias PlatformColor = UIColor
#endif

/// A built scene: the root entity the app adds to its RealityView.
struct BuiltScene {
    let root: Entity
}

@MainActor
enum SceneBuilder {

    static func makeRoot(from state: FoldState, manifest: WorldManifest) throws -> BuiltScene {
        let root = Entity()
        root.name = "world"

        // Instances resolve against the manifest's creations.
        let creations = Self.creations(manifest)

        // One RealityKit entity per folded world entity, parents linked.
        var byId: [Int: Entity] = [:]
        for entity in state.entities {
            guard let node = Self.node(for: entity, creations: creations) else { continue }
            byId[entity.id] = node
        }
        for entity in state.entities {
            guard let node = byId[entity.id] else { continue }
            if let parentId = entity.parent, let parent = byId[parentId] {
                parent.addChild(node)
            } else {
                root.addChild(node)
            }
        }

        // The environment's ambient light, if declared. RealityKit has
        // no ambient light — approximate with two soft fills (from
        // above and from the default camera), capped so neither
        // competes with a sun.
        if let env = state.environment,
           let ambient = env.ambientColor ?? env.backgroundColor {
            let tint = Self.color(ambient, alpha: 1)
            let intensity = Float(min(env.ambientIntensity ?? 100, 450))
            root.addChild(Self.fillLight(
                name: "ambient-fill-overhead", tint: tint, intensity: intensity,
                toward: SIMD3(0, -1, 0)))
            root.addChild(Self.fillLight(
                name: "ambient-fill-camera", tint: tint, intensity: intensity * 0.4,
                toward: simd_normalize(SIMD3(0.3, -0.5, -1))))
        }

        return BuiltScene(root: root)
    }

    // MARK: - Shots (ext-cinematography)

    /// The RealityKit camera that looks through a shot: placed at the
    /// camera entity's view as the package derives it — through parents,
    /// `aim_entity` resolved in the fold — with the frame's vertical
    /// field of view. Letterboxing the frame's aspect into the window is
    /// the view's job (`Letterbox`); nothing here invents camera math.
    static func shotCamera(
        _ entity: WorldEntity, _ camera: OpenWorldFormat.CameraComponent, in state: FoldState
    ) -> (camera: PerspectiveCamera, frame: CameraFrame) {
        let view = viewOf(entity, camera, in: state.entities)
        let frame = frameOf(camera)
        let node = PerspectiveCamera()
        node.name = "shot-camera"
        node.camera.fieldOfViewInDegrees = Float(frame.vfovDegrees)
        let position = SIMD3<Float>(Float(view.position.x), Float(view.position.y), Float(view.position.z))
        let forward = SIMD3<Float>(Float(view.forward.x), Float(view.forward.y), Float(view.forward.z))
        let up = SIMD3<Float>(Float(view.up.x), Float(view.up.y), Float(view.up.z))
        node.look(at: position + forward, from: position, upVector: up, relativeTo: nil)
        return (node, frame)
    }

    /// A soft directional fill pointing `toward` the scene.
    private static func fillLight(
        name: String, tint: PlatformColor, intensity: Float, toward: SIMD3<Float>
    ) -> DirectionalLight {
        let light = DirectionalLight()
        light.name = name
        light.light.color = tint
        light.light.intensity = intensity
        light.orientation = simd_quatf(from: SIMD3(0, 0, -1), to: simd_normalize(toward))
        return light
    }

    // MARK: - One entity

    private static func node(
        for entity: WorldEntity, creations: [Int: JSONValue]
    ) -> Entity? {
        var node: Entity?

        if let shape = entity.shape {
            let model = ModelEntity(
                mesh: Self.mesh(shape, name: entity.name),
                materials: [Self.material(entity.material)])
            node = model
        } else if let lightDef = entity.light {
            node = Self.lightNode(lightDef, name: entity.name)
        } else if let instanceOf = entity.fields["instance_of"],
                  let creationId = instanceOf["creation"]?.int,
                  let creation = creations[creationId] {
            node = Self.instanceNode(creation, instanceOf: instanceOf, name: entity.name)
        }

        guard var concrete = node else { return nil }
        concrete.name = entity.name
        Self.apply(entity.transform, to: &concrete)
        return concrete
    }

    private static func apply(_ transform: WorldTransform?, to entity: inout Entity) {
        guard let transform else { return }
        if let p = transform.position { entity.position = SIMD3(Float(p.x), Float(p.y), Float(p.z)) }
        if let r = transform.rotationDegrees {
            entity.orientation = Self.rotation(r)
        }
        if let s = transform.scale {
            entity.scale = SIMD3(Float(s.x), Float(s.y), Float(s.z))
        }
        if transform.visible == false { entity.isEnabled = false }
    }

    /// Euler XYZ in degrees — the format's convention.
    private static func rotation(_ r: SIMD3<Double>) -> simd_quatf {
        let d = Float.pi / 180
        let qx = simd_quatf(angle: Float(r.x) * d, axis: SIMD3(1, 0, 0))
        let qy = simd_quatf(angle: Float(r.y) * d, axis: SIMD3(0, 1, 0))
        let qz = simd_quatf(angle: Float(r.z) * d, axis: SIMD3(0, 0, 1))
        return qz * qy * qx
    }

    // MARK: - Lights

    private static func lightNode(_ def: LightDef, name: String) -> Entity {
        let tint = Self.color(def.color, alpha: 1)
        switch def.lightType {
        case "point":
            let light = PointLight()
            light.name = name
            light.light.color = tint
            light.light.intensity = Float(def.intensity ?? 1000)  // lumens
            if let range = def.range { light.light.attenuationRadius = Float(range) }
            return light
        case "spot":
            let light = SpotLight()
            light.name = name
            light.light.color = tint
            light.light.intensity = Float(def.intensity ?? 1000)
            if let range = def.range { light.light.attenuationRadius = Float(range) }
            if let angle = def.angleDegrees {
                light.light.innerAngleInDegrees = Float(angle / 2)
                light.light.outerAngleInDegrees = Float(angle)
            }
            return light
        default:  // directional — the sun and the moon
            let light = DirectionalLight()
            light.name = name
            light.light.color = tint
            // Lux, capped a little under the conformance suns so pale
            // surfaces keep some range after RealityKit's exposure.
            light.light.intensity = Float(min(def.intensity ?? 1000, 9000))
            if let d = def.direction, d.count >= 3,
               simd_length(SIMD3<Float>(Float(d[0]), Float(d[1]), Float(d[2]))) > 0 {
                // DirectionalLight shines along its local -Z; aim it.
                let dir = simd_normalize(SIMD3<Float>(Float(d[0]), Float(d[1]), Float(d[2])))
                light.orientation = simd_quatf(from: SIMD3(0, 0, -1), to: dir)
            }
            return light
        }
    }

    // MARK: - Instances (creations)

    /// `creations` from the manifest, indexed by id: prototypes whose
    /// `parts` are entity-shaped dictionaries.
    private static func creations(_ manifest: WorldManifest) -> [Int: JSONValue] {
        var byId: [Int: JSONValue] = [:]
        for creation in manifest.fields["creations"]?.array ?? [] {
            if let id = creation["id"]?.int {
                byId[id] = creation
            }
        }
        return byId
    }

    /// An instance renders its creation's parts (with per-part
    /// overrides), parented under one node at the instance's transform.
    private static func instanceNode(
        _ creation: JSONValue, instanceOf: JSONValue, name: String
    ) -> Entity {
        let root = Entity()
        root.name = name
        // part id → node, for parenting parts that name a part parent.
        var parts: [Int: Entity] = [:]
        for partJSON in creation["parts"]?.array ?? [] {
            guard let partId = partJSON["id"]?.int else { continue }
            let partName = partJSON["name"]?.string ?? "part-\(partId)"
            guard let shapeJSON = partJSON["shape"],
                  let shape = Shape(json: shapeJSON) else { continue }
            let mesh = Self.mesh(shape, name: partName)
            var model = ModelEntity(
                mesh: mesh,
                materials: [Self.material(MaterialDef(json: partJSON["material"] ?? .null))])
            model.name = partName
            var transform = WorldTransform(json: partJSON["transform"] ?? .null)
            // Overrides patch the part: same patch semantics as the fold.
            for overrideJSON in instanceOf["overrides"]?.array ?? [] {
                guard overrideJSON["part"]?.int == partId,
                      let patch = overrideJSON["patch"]?.object else { continue }
                Self.applyPatch(patch, toPart: partJSON, transform: &transform, model: &model, mesh: mesh)
            }
            var node: Entity = model
            Self.apply(transform, to: &node)
            parts[partId] = node
        }
        for partJSON in creation["parts"]?.array ?? [] {
            guard let partId = partJSON["id"]?.int, let node = parts[partId] else { continue }
            if let parentId = partJSON["parent"]?.int, let parent = parts[parentId] {
                parent.addChild(node)
            } else {
                root.addChild(node)
            }
        }
        return root
    }

    /// A part override: absent = unchanged, null = clear, value = set —
    /// the same rule entity patches follow. Only the fields the viewer
    /// carries (material, transform) are patched.
    private static func applyPatch(
        _ patch: [String: JSONValue], toPart partJSON: JSONValue,
        transform: inout WorldTransform, model: inout ModelEntity, mesh: MeshResource
    ) {
        if let materialJSON = patch["material"], materialJSON != .null {
            model.components.set(ModelComponent(
                mesh: mesh,
                materials: [Self.material(MaterialDef(json: materialJSON))]))
        }
        if let t = patch["transform"], t != .null {
            let merged = Self.mergeTransform(partJSON["transform"] ?? .null, t)
            transform = merged
        }
    }

    /// Field-wise transform merge: the override's present fields win.
    private static func mergeTransform(_ base: JSONValue, _ override: JSONValue) -> WorldTransform {
        var o = base.object ?? [:]
        for (key, value) in override.object ?? [:] {
            if value == .null { o.removeValue(forKey: key) } else { o[key] = value }
        }
        return WorldTransform(json: .object(o))
    }

    // MARK: - Meshes

    private static func mesh(_ shape: Shape, name: String) -> MeshResource {
        switch shape {
        case .cuboid(let x, let y, let z):
            return MeshResource.generateBox(size: SIMD3(Float(x), Float(y), Float(z)))
        case .sphere(let radius):
            return MeshResource.generateSphere(radius: Float(radius))
        case .cylinder(let radius, let height):
            return MeshResource.generateCylinder(height: Float(height), radius: Float(radius))
        case .cone(let radius, let height):
            return MeshResource.generateCone(height: Float(height), radius: Float(radius))
        case .capsule(let radius, let halfLength):
            return Self.capsule(radius: radius, halfLength: halfLength)
        case .torus(let majorRadius, let minorRadius):
            // RealityKit's torus lies flat (axis Y); the format's stands
            // upright (axis Z) and the conformance world rotates it 90°
            // about X to lay it flat — so the flat default is where the
            // document is heading anyway.
            return Self.torus(majorRadius: majorRadius, minorRadius: minorRadius)
        case .plane(let x, let z):
            return MeshResource.generatePlane(width: Float(x), depth: Float(z))
        case .pyramid(let baseX, let baseZ, let height):
            return flatMesh(name: name, triangles: Self.pyramid(baseX: baseX, baseZ: baseZ, height: height))
        case .tetrahedron(let radius):
            return flatMesh(name: name, triangles: Self.tetrahedron(radius: radius))
        case .icosahedron(let radius):
            return flatMesh(name: name, triangles: Self.icosahedron(radius: radius))
        case .wedge(let x, let y, let z):
            return flatMesh(name: name, triangles: Self.wedge(x: x, y: y, z: z))
        }
    }

    // MARK: - Hand-built meshes

    /// A lathe/grid mesh: rings of points around Y, quads split into
    /// triangles, flat normals, winding auto-fixed against each face's
    /// local center (the closest point on the shape's axis works for
    /// capsules and tori alike).
    private static func lathedMesh(
        name: String, rings: Int, profile: [SIMD3<Float>], localCenter: (SIMD3<Float>) -> SIMD3<Float>
    ) -> MeshResource {
        var grid: [[SIMD3<Float>]] = []
        for i in 0..<rings {
            let angle = Float(i) / Float(rings) * 2 * .pi
            let c = cos(angle), s = sin(angle)
            // The profile is given in (radius, y); revolve it around Y.
            grid.append(profile.map { SIMD3($0.x * c, $0.y, $0.x * s) })
        }
        var triangles: [[SIMD3<Float>]] = []
        for i in 0..<rings {
            let j = (i + 1) % rings
            for k in 0..<(profile.count - 1) {
                let a = grid[i][k], b = grid[j][k]
                let c = grid[j][k + 1], d = grid[i][k + 1]
                triangles.append([a, b, c])
                triangles.append([a, c, d])
            }
        }
        return flatMesh(name: name, triangles: triangles, localCenter: localCenter)
    }

    /// A capsule: cylinder of ±halfLength, hemispherical caps.
    private static func capsule(radius: Double, halfLength: Double) -> MeshResource {
        let r = Float(radius), hl = Float(halfLength)
        var profile: [SIMD3<Float>] = []
        // Bottom cap, cylinder, top cap — 40 samples, pole to pole.
        for step in 0...40 {
            let y = -hl - r + Float(step) / 40 * (2 * (hl + r))
            let rho: Float
            if y < -hl { rho = sqrt(max(0, r * r - (y + hl) * (y + hl))) }
            else if y > hl { rho = sqrt(max(0, r * r - (y - hl) * (y - hl))) }
            else { rho = r }
            profile.append(SIMD3(rho, y, 0))
        }
        return lathedMesh(name: "capsule", rings: 24, profile: profile) { centroid in
            // The closest point on the axis segment — the local "center"
            // each face should point away from.
            SIMD3(0, min(max(centroid.y, -hl), hl), 0)
        }
    }

    /// A torus: major radius around Y (lying flat, RealityKit-style).
    private static func torus(majorRadius: Double, minorRadius: Double) -> MeshResource {
        let R = Float(majorRadius), r = Float(minorRadius)
        // Profile around the tube: (radius, y) pairs, v from 0 to 2π.
        var profile: [SIMD3<Float>] = []
        for step in 0..<32 {
            let v = Float(step) / 32 * 2 * .pi
            profile.append(SIMD3(R + r * cos(v), r * sin(v), 0))
        }
        return lathedMesh(name: "torus", rings: 32, profile: profile) { centroid in
            // The tube's ring center at this face's angle.
            let length = simd_length(SIMD2(centroid.x, centroid.z))
            if length < 1e-6 { return .zero }
            return SIMD3(centroid.x / length * R, 0, centroid.z / length * R)
        }
    }

    /// Triangles with flat normals, winding auto-fixed against `center`.
    private static func flatMesh(
        name: String, center: SIMD3<Float> = .zero, triangles: [[SIMD3<Float>]]
    ) -> MeshResource {
        flatMesh(name: name, triangles: triangles) { _ in center }
    }

    private static func flatMesh(
        name: String, triangles: [[SIMD3<Float>]], localCenter: (SIMD3<Float>) -> SIMD3<Float>
    ) -> MeshResource {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        for triangle in triangles {
            var a = triangle[0], b = triangle[1], c = triangle[2]
            var n = simd_normalize(simd_cross(b - a, c - a))
            let centroid = (a + b + c) / 3
            if simd_dot(n, centroid - localCenter(centroid)) < 0 {  // pointing inward: flip
                swap(&b, &c)
                n = -n
            }
            let base = UInt32(positions.count)
            positions.append(contentsOf: [a, b, c])
            normals.append(contentsOf: [n, n, n])
            indices.append(contentsOf: [base, base + 1, base + 2])
        }
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffer(positions)
        descriptor.normals = MeshBuffer(normals)
        descriptor.primitives = .triangles(indices)
        return (try? MeshResource.generate(from: [descriptor]))
            ?? MeshResource.generateBox(size: .one)
    }

    /// A square pyramid, centered: base at -h/2, apex at +h/2.
    private static func pyramid(baseX: Double, baseZ: Double, height: Double) -> [[SIMD3<Float>]] {
        let hx = Float(baseX / 2), hz = Float(baseZ / 2), h = Float(height / 2)
        let a = SIMD3(-hx, -h, -hz), b = SIMD3(hx, -h, -hz)
        let c = SIMD3(hx, -h, hz), d = SIMD3(-hx, -h, hz)
        let apex = SIMD3(0, h, 0)
        return [
            [a, b, apex], [b, c, apex], [c, d, apex], [d, a, apex],  // sides
            [a, d, c], [a, c, b],                                     // base
        ]
    }

    /// A regular tetrahedron, vertices on the circumsphere.
    private static func tetrahedron(radius: Double) -> [[SIMD3<Float>]] {
        let r = Float(radius)
        let v = [
            SIMD3(1, 1, 1), SIMD3(1, -1, -1), SIMD3(-1, 1, -1), SIMD3(-1, -1, 1),
        ].map { simd_normalize($0) * r }
        return [
            [v[0], v[1], v[2]], [v[0], v[3], v[1]],
            [v[0], v[2], v[3]], [v[1], v[3], v[2]],
        ]
    }

    /// A regular icosahedron: the golden-ratio construction.
    private static func icosahedron(radius: Double) -> [[SIMD3<Float>]] {
        let r = Float(radius)
        let t = (1 + sqrt(5)) / 2
        let raw: [(Double, Double, Double)] = [
            (-1, t, 0), (1, t, 0), (-1, -t, 0), (1, -t, 0),
            (0, -1, t), (0, 1, t), (0, -1, -t), (0, 1, -t),
            (t, 0, -1), (t, 0, 1), (-t, 0, -1), (-t, 0, 1),
        ]
        let v = raw.map { simd_normalize(SIMD3(Float($0.0), Float($0.1), Float($0.2))) * r }
        let faces = [
            [0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
            [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 9],
            [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
            [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1],
        ]
        return faces.map { [v[$0[0]], v[$0[1]], v[$0[2]]] }
    }

    /// A ramp: full height at the back, zero at the front, centered.
    private static func wedge(x: Double, y: Double, z: Double) -> [[SIMD3<Float>]] {
        let hx = Float(x / 2), hy = Float(y / 2), hz = Float(z / 2)
        // Bottom rectangle, then the top back edge; recentred on Y.
        let a = SIMD3(-hx, -hy, -hz), b = SIMD3(hx, -hy, -hz)
        let c = SIMD3(hx, -hy, hz), d = SIMD3(-hx, -hy, hz)
        let e = SIMD3(-hx, hy, -hz), f = SIMD3(hx, hy, -hz)
        return [
            [a, d, c], [a, c, b],          // bottom
            [a, b, f], [a, f, e],          // back, full height
            [a, e, d], [b, c, f],          // left and right sides
            [d, e, f], [d, f, c],          // the ramp
        ]
    }

    // MARK: - Materials and colors

    private static func material(_ def: MaterialDef?) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        if let def {
            if let c = def.color { material.baseColor = .init(tint: Self.color(c, alpha: nil)) }
            if let e = def.emissive {
                material.emissiveColor = .init(color: Self.color(e, alpha: nil))
            }
            // The scalar material types are float-literal-initializable;
            // this SDK exposes that init directly.
            material.roughness = .init(floatLiteral: Float(def.roughness ?? 0.8))
            material.metallic = .init(floatLiteral: Float(def.metallic ?? 0))
        }
        return material
    }

    /// Linear rgb(a), 0–1, to a platform color (white when absent).
    /// RealityKit expects extended-linear; NSColor/UIColor inputs here
    /// are already that in RealityKit's color space handling.
    private static func color(_ components: [Double]?, alpha: Double?) -> PlatformColor {
        let c = components ?? [1, 1, 1, 1]
        let r = c.count > 0 ? c[0] : 1
        let g = c.count > 1 ? c[1] : 1
        let b = c.count > 2 ? c[2] : 1
        let a = c.count > 3 ? c[3] : (alpha ?? 1)
        return PlatformColor(
            red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a))
    }
}
