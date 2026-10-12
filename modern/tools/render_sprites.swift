// Repeatable 3D-to-isometric asset export. Added 2026-10-12. GPL-2.0-only.
import AppKit
import SceneKit
import Metal

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "modern/assets/sprites")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
var manifest = ""

func material(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, metal: CGFloat = 0, rough: CGFloat = 0.7) -> SCNMaterial {
    let m = SCNMaterial()
    m.diffuse.contents = NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    m.lightingModel = .physicallyBased
    m.metalness.contents = metal
    m.roughness.contents = rough
    return m
}
let ivory = material(0.83, 0.78, 0.64, rough: 0.48)
let paint = material(0.025, 0.15, 0.65, metal: 0.15, rough: 0.32)
let graphite = material(0.10, 0.12, 0.12, metal: 0.35, rough: 0.42)
let glass = material(0.09, 0.13, 0.14, metal: 0.3, rough: 0.18)
let chrome = material(0.48, 0.48, 0.45, metal: 0.7, rough: 0.38)
let wood = material(0.21, 0.12, 0.055)

@discardableResult
func box(_ root: SCNNode, _ size: (CGFloat, CGFloat, CGFloat), _ pos: (CGFloat, CGFloat, CGFloat), _ mat: SCNMaterial, bevel: CGFloat = 0) -> SCNNode {
    let geo = SCNBox(width: size.0, height: size.1, length: size.2, chamferRadius: bevel)
    geo.materials = [mat]
    let n = SCNNode(geometry: geo)
    n.position = SCNVector3(pos.0, pos.1, pos.2)
    root.addChildNode(n)
    return n
}

func train(coach: Bool) -> SCNNode {
    let root = SCNNode()
    box(root, (0.27, 0.17, 1.06), (0, 0.145, 0), ivory, bevel: 0.025)
    box(root, (0.25, 0.045, 1.03), (0, 0.247, 0), graphite, bevel: 0.022)
    box(root, (0.28, 0.065, 1.055), (0, 0.097, 0), paint, bevel: 0.012)
    box(root, (0.25, 0.03, 0.91), (0, 0.055, 0), graphite)
    for bogie: CGFloat in [-0.32, 0.32] {
        box(root, (0.25, 0.045, 0.21), (0, 0.038, bogie), graphite, bevel: 0.01)
        for side: CGFloat in [-1, 1] {
            for axle: CGFloat in [-0.06, 0.06] {
                let geo = SCNCylinder(radius: 0.035, height: 0.023)
                geo.radialSegmentCount = 20; geo.materials = [chrome]
                let wheel = SCNNode(geometry: geo)
                wheel.position = SCNVector3(side * 0.145, 0.035, bogie + axle)
                wheel.eulerAngles.z = .pi / 2
                root.addChildNode(wheel)
            }
        }
    }
    for side: CGFloat in [-1, 1] {
        if coach {
            for i in 0..<9 {
                box(root, (0.006, 0.065, 0.069), (side * 0.137, 0.183, CGFloat(i) * 0.093 - 0.372), glass, bevel: 0.005)
            }
            for z: CGFloat in [-0.48, 0.48] {
                box(root, (0.007, 0.137, 0.05), (side * 0.14, 0.157, z), ivory)
                box(root, (0.009, 0.055, 0.03), (side * 0.145, 0.19, z), glass)
            }
        } else {
            box(root, (0.007, 0.066, 0.105), (side * 0.14, 0.188, -0.42), glass, bevel: 0.006)
            for i in 0..<12 {
                box(root, (0.006, 0.061, 0.011), (side * 0.139, 0.167, CGFloat(i)*0.037 - 0.1), graphite)
            }
            box(root, (0.005, 0.12, 0.003), (side*0.141, 0.156, -0.285), chrome)
        }
    }
    for z: CGFloat in [-0.548, 0.548] {
        box(root, (0.07, 0.029, 0.07), (0, 0.053, z), graphite)
    }
    if !coach {
        box(root, (0.20, 0.065, 0.009), (0, 0.183, -0.525), glass, bevel: 0.008)
        box(root, (0.009, 0.075, 0.012), (0, 0.183, -0.534), ivory)
        for x: CGFloat in [-0.087, 0.087] {
            let geo = SCNSphere(radius: 0.015)
            geo.segmentCount = 12
            geo.materials = [material(0.98, 0.91, 0.60, rough: 0.2)]
            let lamp = SCNNode(geometry: geo)
            lamp.position = SCNVector3(x, 0.106, -0.54)
            root.addChildNode(lamp)
        }
        for z: CGFloat in [-0.02, 0.20] {
            let geo = SCNCylinder(radius: 0.075, height: 0.015)
            geo.radialSegmentCount = 24; geo.materials = [graphite]
            let fan = SCNNode(geometry: geo)
            fan.position = SCNVector3(0, 0.278, z)
            root.addChildNode(fan)
        }
    }
    return root
}

struct Random {
    var state: UInt64
    mutating func next() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((state >> 32) & 0xffffff) / CGFloat(0xffffff)
    }
}

func branch(_ root: SCNNode, from: SCNVector3, to: SCNVector3, radius: CGFloat) {
    let delta = SIMD3<Float>(Float(to.x - from.x), Float(to.y - from.y), Float(to.z - from.z))
    let geo = SCNCylinder(radius: radius, height: CGFloat(simd_length(delta)))
    geo.radialSegmentCount = 8; geo.materials = [wood]
    let n = SCNNode(geometry: geo)
    n.position = SCNVector3((from.x+to.x)/2, (from.y+to.y)/2, (from.z+to.z)/2)
    n.simdOrientation = simd_quatf(from: SIMD3<Float>(0,1,0), to: simd_normalize(delta))
    root.addChildNode(n)
}

func tree(species: Int, stage: Int) -> SCNNode {
    let root = SCNNode()
    var rng = Random(state: UInt64(1707 + species * 97))
    let stages: [CGFloat] = [0.25, 0.45, 0.7, 1, 1, 1, 1]
    let size = stages[stage]
    let height: CGFloat = 0.93 + CGFloat(species % 3)*0.10
    branch(root, from: SCNVector3(0,0,0), to: SCNVector3(0,height * 0.9,0), radius: 0.016)
    let autumn = stage >= 4
    let bare = stage >= 5
    let conifer = species < 5
    let foliage = (0..<6).map { index -> SCNMaterial in
        let shift = CGFloat(index) * 0.025
        if autumn { return material(0.38+shift, 0.24+shift*0.7, 0.09) }
        return material(0.18+shift, 0.34+shift, 0.10+shift*0.35)
    }
    for i in 0..<16 {
        let angle = rng.next() * .pi * 2
        let level = CGFloat(i) / 16
        let y = height * (0.33 + level * 0.52)
        let radius: CGFloat = conifer ? 0.22 * (1-level*0.75) : 0.15 + rng.next()*0.15
        let tip = SCNVector3(cos(angle)*radius, y + 0.10, sin(angle)*radius)
        branch(root, from: SCNVector3(0,y,0), to: tip, radius: 0.006)
        if bare { continue }
    }
    if !bare {
        // Thousands of individual leaf surfaces make a continuous organic crown.
        // Combine each material into one mesh instead of instancing round blobs.
        for group in 0..<6 {
            var vertices: [SCNVector3] = []
            var normals: [SCNVector3] = []
            var indices: [Int32] = []
            for _ in 0..<450 {
                var x: CGFloat = 0, y: CGFloat = 0, z: CGFloat = 0
                repeat {
                    x = rng.next()*2-1; y = rng.next()*2-1; z = rng.next()*2-1
                } while x*x + y*y + z*z > 1
                let centreY = height * (conifer ? 0.60 : 0.70)
                let extentY = height * (conifer ? 0.42 : 0.33)
                let taper: CGFloat = conifer ? max(0.12, 0.55 - y*0.45) : 1
                let centre = SIMD3<Float>(Float(x * 0.30 * taper), Float(centreY + y * extentY), Float(z * 0.27 * taper))
                let theta = Float(rng.next()) * .pi * 2
                let tilt = Float(rng.next()) * 1.6 - 0.8
                let half: Float = conifer ? 0.014 : 0.021
                let u = SIMD3<Float>(cos(theta)*half, sin(tilt)*half, sin(theta)*half)
                let v = SIMD3<Float>(-sin(theta)*half*0.5, cos(tilt)*half*0.7, cos(theta)*half*0.5)
                let normal = simd_normalize(simd_cross(u,v))
                let base = Int32(vertices.count)
                for point in [centre-u-v, centre+u-v, centre+u+v, centre-u+v] {
                    vertices.append(SCNVector3(CGFloat(point.x),CGFloat(point.y),CGFloat(point.z)))
                    normals.append(SCNVector3(CGFloat(normal.x),CGFloat(normal.y),CGFloat(normal.z)))
                }
                indices += [base,base+1,base+2,base,base+2,base+3]
            }
            let geo = SCNGeometry(sources: [SCNGeometrySource(vertices:vertices),SCNGeometrySource(normals:normals)], elements:[SCNGeometryElement(indices:indices,primitiveType:.triangles)])
            foliage[group].isDoubleSided = true
            geo.materials = [foliage[group]]
            root.addChildNode(SCNNode(geometry:geo))
        }
    }

    root.scale = SCNVector3(size,size,size)
    return root
}

func scene(_ model: SCNNode, angle: CGFloat, isTree: Bool) -> SCNScene {
    let scene = SCNScene()
    scene.background.contents = NSColor.clear
    scene.rootNode.addChildNode(model)
    model.eulerAngles.y = angle
    let ambient = SCNNode()
    ambient.light = SCNLight(); ambient.light!.type = .ambient
    ambient.light!.color = NSColor(srgbRed: 0.81, green: 0.86, blue: 0.88, alpha: 1)
    ambient.light!.intensity = 650
    scene.rootNode.addChildNode(ambient)
    let sun = SCNNode()
    sun.light = SCNLight(); sun.light!.type = .directional
    sun.light!.color = NSColor(srgbRed: 1, green: 0.90, blue: 0.74, alpha: 1)
    sun.light!.intensity = 1350
    sun.eulerAngles = SCNVector3(-0.85, -0.7, 0)
    scene.rootNode.addChildNode(sun)
    let camera = SCNNode()
    camera.camera = SCNCamera()
    camera.camera!.usesOrthographicProjection = true
    camera.camera!.orthographicScale = isTree ? 1.5 : 0.75
    camera.camera!.zNear = 0.01; camera.camera!.zFar = 100
    camera.camera!.wantsHDR = false
    let target: CGFloat = isTree ? 0.613435 : 0
    camera.position = SCNVector3(8, 6.53197 + target, 8)
    camera.look(at: SCNVector3(0,target,0))
    scene.rootNode.addChildNode(camera)
    renderer.pointOfView = camera
    return scene
}

func export(_ model: SCNNode, file: String, angle: CGFloat = 0, isTree: Bool = false) throws -> (Int, Int) {
    renderer.scene = scene(model, angle: angle, isTree: isTree)
    let image = renderer.snapshot(atTime: 0, with: CGSize(width: 256, height: isTree ? 384 : 192), antialiasingMode: .multisampling4X)
    guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let source = bitmap.cgImage else { fatalError("PNG export failed") }
    var minX = bitmap.pixelsWide, minY = bitmap.pixelsHigh, maxX = 0, maxY = 0
    for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide where (bitmap.colorAt(x:x,y:y)?.alphaComponent ?? 0) > 0 {
            minX = min(minX,x); minY = min(minY,y); maxX = max(maxX,x+1); maxY = max(maxY,y+1)
        }
    }
    // Trim transparent space, retaining an exact ground anchor and 4x alignment.
    minX = minX/4*4; minY = minY/4*4
    maxX = min(bitmap.pixelsWide,(maxX+3)/4*4); maxY = min(bitmap.pixelsHigh,(maxY+3)/4*4)
    guard let cropped = source.cropping(to:CGRect(x:minX,y:minY,width:maxX-minX,height:maxY-minY)), let png = NSBitmapImageRep(cgImage:cropped).representation(using:.png,properties:[:]) else { fatalError("Crop export failed") }
    try png.write(to: output.appendingPathComponent(file))
    return (-128 + minX, (isTree ? -260 : -96) + minY)
}

for direction in 0..<8 {
    // Screen-facing N through NW with the fixed OpenTTD camera.
    let angle = .pi / 4 - CGFloat(direction) * .pi / 4
    let file = "express-\(direction).png"
    let offsets = try export(train(coach: false), file: file, angle: angle)
    manifest += "\(0xB7D + direction)\t\(offsets.0)\t\(offsets.1)\t1\t\(file)\n"
    if direction < 4 {
        let coachFile = "coach-\(direction).png"
        let offsets = try export(train(coach: true), file: coachFile, angle: angle)
        manifest += "\(0xAAD + direction)\t\(offsets.0)\t\(offsets.1)\t1\t\(coachFile)\n"
    }
}
for species in 0..<19 {
    for stage in 0..<7 {
        let file = "tree-\(species)-\(stage).png"
        let offsets = try export(tree(species: species, stage: stage), file: file, isTree: true)
        manifest += "\(0x628 + species * 7 + stage)\t\(offsets.0)\t\(offsets.1)\t0\t\(file)\n"
    }
}
try manifest.write(to: output.appendingPathComponent("manifest-models.tsv"), atomically: true, encoding: .utf8)
print("Exported 145 sprites: eight express directions, four carriage directions, nineteen tree variants with seven stages.")
