// Original temperate materials and station models. GPL-2.0-only.
import AppKit
import SceneKit
import Metal
import simd

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "modern/assets/sprites")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
var manifest = ""
let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)

func png(_ bytes: [UInt8], width: Int, height: Int, file: String, anchor: (Int, Int)) throws -> (Int, Int) {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bitmapFormat: .alphaNonpremultiplied, bytesPerRow: width * 4, bitsPerPixel: 32) else { fatalError("Bitmap allocation") }
    _ = bytes.withUnsafeBytes { memcpy(bitmap.bitmapData!, $0.baseAddress!, bytes.count) }
    let source = bitmap.cgImage!
    var minX = width, minY = height, maxX = 0, maxY = 0
    for y in 0..<height { for x in 0..<width where bytes[(y*width+x)*4+3] > 0 {
        minX = min(minX,x); minY = min(minY,y); maxX = max(maxX,x+1); maxY = max(maxY,y+1)
    } }
    minX = minX/4*4; minY = minY/4*4
    maxX = min(width,(maxX+3)/4*4); maxY = min(height,(maxY+3)/4*4)
    guard let crop = source.cropping(to: CGRect(x:minX,y:minY,width:maxX-minX,height:maxY-minY)), let data = NSBitmapImageRep(cgImage:crop).representation(using:.png,properties:[:]) else { fatalError("PNG encoding") }
    try data.write(to:output.appendingPathComponent(file))
    return (anchor.0 + minX, anchor.1 + minY)
}

func hash(_ x: Int, _ y: Int, _ seed: Int = 0) -> Double {
    var value = UInt64(truncatingIfNeeded: x &* 374761393 &+ y &* 668265263 &+ seed &* 1442695041)
    value = (value ^ (value >> 13)) &* 1274126177
    return Double((value ^ (value >> 16)) & 0xffff) / 65535
}
func noise(_ u: Double, _ v: Double, frequency: Int, seed: Int) -> Double {
    let px = u * Double(frequency), py = v * Double(frequency)
    let x = Int(floor(px)), y = Int(floor(py))
    let fx = px - floor(px), fy = py - floor(py)
    let a = fx*fx*(3-2*fx), b = fy*fy*(3-2*fy)
    func h(_ x: Int, _ y: Int) -> Double { hash((x%frequency+frequency)%frequency,(y%frequency+frequency)%frequency,seed) }
    return (h(x,y)*(1-a)+h(x+1,y)*a)*(1-b)+(h(x,y+1)*(1-a)+h(x+1,y+1)*a)*b
}

// World x/y follow OpenTTD's 2:1 projection. Heights are engine pixel units.
func elevation(_ u: Double, _ v: Double, slope: Int) -> Double {
    switch slope {
    case 0: return 0
    case 1: return max(0,u-v)*8
    case 2: return max(0,u+v-1)*8
    case 4: return max(0,v-u)*8
    case 8: return max(0,1-u-v)*8
    case 3: return u*8
    case 6: return v*8
    case 9: return (1-v)*8
    case 12: return (1-u)*8
    case 7: return min(1,u+v)*8
    case 11: return (1-max(0,v-u))*8
    case 13: return (1-max(0,u+v-1))*8
    case 14: return (1-max(0,u-v))*8
    case 5: return abs(u-v)*8
    case 10: return abs(1-u-v)*8
    case 23: return (u+v)*8
    case 27: return (1+u-v)*8
    case 29: return (2-u-v)*8
    case 30: return (1+v-u)*8
    default: fatalError("Unsupported slope")
    }
}
struct Vertex { let x: Double; let y: Double; let u: Double; let v: Double; let z: Double }
func ground(slope: Int, density: Int, rough: Int = -1, railAxis: Int = 0, overlay: Bool = false, field: Int = -1, road: Int = 0, paved: Bool = false, courtyard: Bool = false) -> [UInt8] {
    let width = 256, height = 192
    var pixels = [UInt8](repeating:0,count:width*height*4)
    let uv: [(Double,Double)] = [(0,0),(1,0),(1,1),(0,1),(0.5,0.5)]
    let vertices = uv.map { u,v -> Vertex in
        let z = elevation(u,v,slope:slope)
        return Vertex(x:128+(v-u)*128,y:64+(u+v)*64-z*4,u:u,v:v,z:z)
    }
    for side in 0..<4 {
        let a = vertices[side], b = vertices[(side+1)%4], c = vertices[4]
        let denominator = (b.y-c.y)*(a.x-c.x)+(c.x-b.x)*(a.y-c.y)
        guard abs(denominator) > 0.001 else { continue }
        let minX = max(0,Int(floor(min(a.x,b.x,c.x)))), maxX = min(width-1,Int(ceil(max(a.x,b.x,c.x))))
        let minY = max(0,Int(floor(min(a.y,b.y,c.y)))), maxY = min(height-1,Int(ceil(max(a.y,b.y,c.y))))
        let pu = SIMD3<Double>(b.u-a.u,b.v-a.v,(b.z-a.z)/16)
        let pv = SIMD3<Double>(c.u-a.u,c.v-a.v,(c.z-a.z)/16)
        var normal = simd_normalize(simd_cross(pu,pv)); if normal.z < 0 { normal = -normal }
        let light = simd_normalize(SIMD3<Double>(-0.35,-0.55,0.85))
        let illumination = 0.72+0.28*max(0,simd_dot(normal,light))
        for y in minY...maxY { for x in minX...maxX {
            let px = Double(x)+0.5, py = Double(y)+0.5
            let wa = ((b.y-c.y)*(px-c.x)+(c.x-b.x)*(py-c.y))/denominator
            let wb = ((c.y-a.y)*(px-c.x)+(a.x-c.x)*(py-c.y))/denominator
            let wc = 1-wa-wb
            if min(wa,wb,wc) < -0.00001 { continue }
            let u = wa*a.u+wb*b.u+wc*c.u, v = wa*a.v+wb*b.v+wc*c.v
            let patch = noise(u,v,frequency:4,seed:71)
            let fine = noise(u,v,frequency:96,seed:29)-0.5
            let grain = noise(u,v,frequency:32,seed:3)-0.5
            var grass = Double(density)/3
            if density == 1 || density == 2 { grass = max(0,min(1,grass+(patch-0.5)*1.7)) }
            var colour = SIMD3<Double>(0.46,0.385,0.28)*(1-grass)+SIMD3<Double>(0.385,0.475,0.245)*grass
            colour += SIMD3<Double>(repeating:fine*0.065+grain*0.055+(patch-0.5)*0.035)
            if rough >= 0 {
                let tu = u*13, tv = v*13
                let cellX = Int(floor(tu)), cellY = Int(floor(tv))
                let cx = hash(cellX,cellY,rough+91), cy = hash(cellX,cellY,rough+47)
                let dx = tu-floor(tu)-cx, dy = tv-floor(tv)-cy
                if dx*dx+dy*dy < 0.015+hash(cellX,cellY,rough+17)*0.01 {
                    colour = SIMD3<Double>(0.55,0.52,0.43) + SIMD3<Double>(repeating:dx*0.20-dy*0.22)
                }
            }
            if railAxis != 0 {
                let across = railAxis == 1 ? v : u, along = railAxis == 1 ? u : v
                let distance = abs(across-0.5)
                if overlay && distance >= 0.23 { continue }
                if distance < 0.23 {
                    let gravel = noise(u,v,frequency:112,seed:51)-0.5
                    let bed = SIMD3<Double>(0.48,0.465,0.405)+SIMD3<Double>(repeating:gravel*0.19)
                    let blend = min(1,(0.23-distance)*50)
                    colour = colour*(1-blend)+bed*blend
                    let tiePhase = along*10-floor(along*10)
                    if distance < 0.17 && abs(tiePhase-0.5) < 0.14 {
                        colour = SIMD3<Double>(0.30,0.245,0.175)+SIMD3<Double>(repeating:fine*0.08)
                        if tiePhase < 0.40 { colour *= 0.72 }
                    }
                    let rail = abs(distance-0.11)
                    if rail < 0.014 { colour = SIMD3<Double>(0.235,0.25,0.235) }
                    if rail < 0.007 { colour = SIMD3<Double>(0.68,0.69,0.64)+SIMD3<Double>(repeating:fine*0.06) }
                }
            }
            if field >= 0 {
                let soil = SIMD3<Double>(0.42,0.325,0.225)
                let phases:[SIMD3<Double>] = [soil,soil,SIMD3(0.32,0.425,0.18),SIMD3(0.39,0.50,0.22),SIMD3(0.56,0.58,0.28),SIMD3(0.67,0.60,0.36),SIMD3(0.56,0.47,0.28),SIMD3(0.52,0.43,0.28),SIMD3(0.57,0.50,0.31)]
                let row = v*16-floor(v*16), crest = max(0,1-abs(row-0.5)*2)
                let cropCover = field == 2 ? pow(crest,3) : pow(crest,0.7)
                colour = soil*(1-cropCover)+phases[field]*cropCover
                colour *= 0.80+0.20*crest
                colour += SIMD3<Double>(repeating:fine*0.085+grain*0.045)
                if field == 8 {
                    let fu = u*3-floor(u*3)-0.5, fv = v*2-floor(v*2)-0.5
                    let ellipse = fu*fu/0.07+fv*fv/0.026
                    if ellipse < 1 {
                        colour = SIMD3<Double>(0.73,0.64,0.40)*(0.85+0.15*sqrt(1-ellipse))
                        colour += SIMD3<Double>(repeating:fine*0.055-fv*0.28)
                    }
                }
            }
            if road != 0 || courtyard {
                if paved || courtyard {
                    let joint = min(u*8-floor(u*8),v*8-floor(v*8)) < 0.024
                    colour = SIMD3<Double>(0.66,0.65,0.59)+SIMD3<Double>(repeating:fine*0.038+(joint ? -0.05 : 0))
                }
                if road != 0 {
                    let ends:[SIMD2<Double>] = [SIMD2(0.5,0),SIMD2(1,0.5),SIMD2(0.5,1),SIMD2(0,0.5)]
                    let active = (0..<4).filter { road & (1 << $0) != 0 }
                    var distance = Double.infinity, along = 0.0
                    // Centre lines join the engine's exact half-tile endpoints.
                    for arm in active {
                        let start = SIMD2<Double>(0.5,0.5), end = ends[arm], delta = end-start
                        let t = max(0,min(1,simd_dot(SIMD2(u,v)-start,delta)/simd_length_squared(delta)))
                        let d = simd_length(SIMD2(u,v)-(start+delta*t))
                        if d < distance { distance=d; along=t*0.5 }
                    }
                    if distance < 0.27 {
                        let edge = max(0,min(1,(0.27-distance)*100))
                        var asphalt = SIMD3<Double>(0.255,0.275,0.267)+SIMD3<Double>(repeating:fine*0.06)
                        if distance > 0.245 { asphalt = SIMD3(0.71,0.70,0.62) }
                        if distance > 0.237 && distance < 0.246 { asphalt = SIMD3(0.21,0.225,0.21) }
                        let straight = road == 5 || road == 10
                        if straight && distance < 0.007 && (along*10-floor(along*10)) < 0.38 { asphalt = SIMD3(0.81,0.81,0.73) }
                        if paved && active.count >= 3 && along > 0.30 && along < 0.36 && distance < 0.20 && (distance*32-floor(distance*32)) < 0.65 { asphalt = SIMD3(0.79,0.79,0.70) }
                        colour = colour*(1-edge)+asphalt*edge
                    }
                }
            }
            colour *= illumination
            let index = (y*width+x)*4
            for channel in 0..<3 { pixels[index+channel] = UInt8(max(0,min(255,Int(colour[channel]*255)))) }
            pixels[index+3] = 255
        } }
    }
    return pixels
}

func mat(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, metal: CGFloat = 0, rough: CGFloat = 0.7) -> SCNMaterial {
    let m = SCNMaterial(); m.lightingModel = .physicallyBased
    m.diffuse.contents = NSColor(srgbRed:r,green:g,blue:b,alpha:1)
    m.metalness.contents = metal; m.roughness.contents = rough
    return m
}
let stone = mat(0.68,0.66,0.57), edge = mat(0.82,0.79,0.67), brick = mat(0.49,0.25,0.15)
let mortar = mat(0.64,0.53,0.39), slate = mat(0.20,0.25,0.24), timber = mat(0.20,0.26,0.20)
let window = mat(0.17,0.23,0.23,metal:0.2,rough:0.2), cream = mat(0.85,0.80,0.66)
let company = mat(0.025,0.15,0.65), steel = mat(0.23,0.27,0.25,metal:0.65,rough:0.38)
let amber = mat(0.94,0.74,0.36); amber.emission.contents = NSColor(srgbRed:0.25,green:0.17,blue:0.035,alpha:1)

@discardableResult
func box(_ root: SCNNode, _ size:(CGFloat,CGFloat,CGFloat), _ pos:(CGFloat,CGFloat,CGFloat), _ material:SCNMaterial, bevel:CGFloat = 0) -> SCNNode {
    let geo = SCNBox(width:size.0,height:size.1,length:size.2,chamferRadius:bevel); geo.materials = [material]
    let node = SCNNode(geometry:geo); node.position = SCNVector3(pos.0,pos.1,pos.2); root.addChildNode(node); return node
}

func platform(front: Bool) -> SCNNode {
    let root = SCNNode()
    box(root,(0.3125,0.049,1),(0.15625,0.0245,0.5),stone)
    for i in 0..<16 {
        let z = CGFloat(i)/16+1.0/32
        box(root,(0.055,0.006,0.060),(front ? 0.0275 : 0.285,0.052,z),edge)
        box(root,(0.29,0.001,0.0015),(0.15,0.05,CGFloat(i)/16),mortar)
        // Tactile warning line stays clear of the track envelope.
        box(root,(0.014,0.004,0.056),(front ? 0.068 : 0.243,0.053,z),cream)
    }
    box(root,(0.002,0.001,1),(0.15,0.05,0.5),mortar)
    return root
}

func building() -> SCNNode {
    let root = platform(front:false)
    box(root,(0.27,0.265,0.86),(0.15,0.1825,0.5),brick)
    for row in 0..<9 {
        let y = 0.063+CGFloat(row)*0.028
        for side: CGFloat in [0.014,0.286] {
            box(root,(0.0018,0.002,0.86),(side,y,0.5),mortar)
            for column in 0..<12 {
                let z = 0.07+CGFloat(column)*0.07+(row%2==0 ? 0 : 0.035)
                if z < 0.93 { box(root,(0.0018,0.026,0.0015),(side,y+0.014,z),mortar) }
            }
        }
    }
    for z: CGFloat in [0.20,0.40,0.65,0.82] {
        box(root,(0.005,0.104,0.075),(0.289,0.198,z),cream)
        box(root,(0.007,0.082,0.057),(0.293,0.2,z),window)
        box(root,(0.010,0.004,0.058),(0.296,0.2,z),cream)
        box(root,(0.010,0.082,0.004),(0.296,0.2,z),cream)
        box(root,(0.02,0.011,0.085),(0.291,0.147,z),edge)
    }
    box(root,(0.008,0.17,0.075),(0.294,0.14,0.525),timber)
    box(root,(0.012,0.08,0.051),(0.298,0.178,0.525),window)
    box(root,(0.015,0.047,0.19),(0.297,0.278,0.52),company)
    // Two roof planes form a pitched roof, with individual slate seams.
    for sign: CGFloat in [-1,1] {
        let roof = box(root,(0.19,0.018,0.94),(0.15+sign*0.073,0.346,0.5),slate)
        roof.eulerAngles.z = sign * -0.44
        for course in 0..<6 {
            let seam = box(root,(0.0018,0.002,0.94),(0,0.011,0),steel)
            seam.removeFromParentNode(); seam.position = SCNVector3(CGFloat(course)*0.031-0.079,0.011,0); roof.addChildNode(seam)
        }
    }
    box(root,(0.065,0.10,0.065),(0.10,0.39,0.77),brick)
    box(root,(0.079,0.014,0.079),(0.10,0.448,0.77),edge)
    // Bench, station lantern and a planter give the building human scale.
    box(root,(0.047,0.014,0.14),(0.275,0.094,0.10),timber)
    box(root,(0.007,0.07,0.14),(0.253,0.103,0.10),timber)
    for z:CGFloat in [0.052,0.15] { box(root,(0.008,0.044,0.008),(0.272,0.072,z),steel) }
    box(root,(0.009,0.19,0.009),(0.27,0.147,0.95),steel)
    box(root,(0.023,0.033,0.023),(0.27,0.248,0.95),amber,bevel:0.003)
    return root
}

func pillars(front:Bool) -> SCNNode {
    let root = platform(front:front)
    for z:CGFloat in [0.06,0.5,0.94] {
        let x:CGFloat = front ? 0.20 : 0.11
        box(root,(0.025,0.018,0.025),(x,0.06,z),stone)
        box(root,(0.012,0.355,0.012),(x,0.235,z),timber)
        box(root,(0.16,0.010,0.016),(x,0.425,z),timber)
    }
    box(root,(0.03,0.036,0.18),(front ? 0.20 : 0.11,0.377,0.5),company)
    return root
}

func canopy(glazing: Bool, half: Int) -> SCNNode {
    let root = SCNNode()
    if glazing {
        let glass = mat(0.66,0.77,0.72,rough:0.15)
        glass.transparency = 0.28; glass.isDoubleSided = true
        for side:CGFloat in [-1,1] {
            let plane = box(root,(0.54,0.004,1),(0.5+side*0.23,0.08,0.5),glass)
            plane.eulerAngles.z = -side*0.20
        }
    } else {
        for z:CGFloat in [0,0.25,0.5,0.75,1] {
            for side:CGFloat in [-1,1] {
                let beam = box(root,(0.54,0.012,0.012),(0.5+side*0.23,0.08,z),timber)
                beam.eulerAngles.z = -side*0.20
            }
        }
        for x:CGFloat in [0.025,0.5,0.975] { box(root,(0.012,0.014,1),(x,x==0.5 ? 0.132 : 0.03,0.5),timber) }
        // Roof end trims provide a visible company accent.
        box(root,(0.05,0.018,1),(half==0 ? 0.027 : 0.973,0.038,0.5),company)
    }
    return root
}

struct TownAsset: Decodable {
    let id:Int, kind:String, stage:Int, width:Int, length:Int, height:Int, houses:[Int]
}
struct TownCoverage: Decodable {
    let houses:[Int], sprites:[TownAsset], grounds:[Int], ground_kinds:[String:String]
}

func pitchedRoof(_ root:SCNNode, width:CGFloat, length:CGFloat, y:CGFloat, x:CGFloat, z:CGFloat, rise:CGFloat, material:SCNMaterial) {
    let angle = atan2(rise,width/2)
    let span = hypot(width/2,rise)
    for sign:CGFloat in [-1,1] {
        let roof = box(root,(span+0.025,0.014,length+0.055),(x+sign*width/4,y+rise/2,z),material)
        roof.eulerAngles.z = -sign*angle
        for row in 0..<5 {
            box(roof,(0.002,0.002,length+0.05),(CGFloat(row)*span/5-span/2,0.008,0),steel)
        }
    }
    box(root,(0.024,0.018,length+0.06),(x,y+rise,z),material)
}

func cylinder(_ root:SCNNode, radius:CGFloat, height:CGFloat, x:CGFloat, y:CGFloat, z:CGFloat, material:SCNMaterial) {
    let geometry = SCNCylinder(radius:radius,height:height); geometry.radialSegmentCount = 32; geometry.materials = [material]
    let node = SCNNode(geometry:geometry); node.position = SCNVector3(x,y,z); root.addChildNode(node)
}

func shrubs(_ root:SCNNode, x:CGFloat, z:CGFloat, size:CGFloat) {
    cylinder(root,radius:0.009,height:size*0.75,x:x,y:size*0.375,z:z,material:timber)
    let geometry = SCNSphere(radius:size*0.30); geometry.segmentCount = 24
    geometry.materials = [mat(0.27,0.38,0.16)]
    let node = SCNNode(geometry:geometry); node.position = SCNVector3(x,size*0.72,z); node.scale = SCNVector3(1,1.2,0.85); root.addChildNode(node)
}

func townModel(_ asset:TownAsset) -> SCNNode {
    let root = SCNNode()
    let w = CGFloat(asset.width)/16, l = CGFloat(asset.length)/16
    let h = CGFloat(asset.height)*0.0255155182
    let colour = asset.id%4
    let wall = [brick,mat(0.73,0.66,0.51),mat(0.58,0.36,0.24),mat(0.64,0.66,0.57)][colour]
    let roof = colour%2==0 ? slate : mat(0.38,0.23,0.16)
    if asset.stage == 0 {
        box(root,(w*0.83,0.019,l*0.83),(w/2,0.0095,l/2),stone)
        for x:CGFloat in [w*0.1,w*0.9] { box(root,(0.023,0.045,l*0.8),(x,0.04,l/2),mortar) }
        for z:CGFloat in [l*0.1,l*0.9] { box(root,(w*0.8,0.045,0.023),(w/2,0.04,z),mortar) }
        for i in 0..<5 { box(root,(0.12,0.018,0.045),(w*0.35,0.036+CGFloat(i)*0.018,l*0.45),timber) }
        for i in 0..<4 { box(root,(0.01,0.07,0.01),(w*0.75,0.065,l*0.3+CGFloat(i)*0.08),steel) }
        return root
    }
    if asset.stage == 1 {
        let frameHeight = max(0.2,h*0.85), floors = max(1,Int(frameHeight/0.19))
        for level in 0...floors {
            box(root,(w*0.82,0.025,l*0.82),(w/2,0.035+CGFloat(level)*frameHeight/CGFloat(floors),l/2),stone)
        }
        for x:CGFloat in [w*0.1,w/2,w*0.9] { for z:CGFloat in [l*0.1,l/2,l*0.9] {
            box(root,(0.024,frameHeight,0.024),(x,frameHeight/2+0.04,z),steel)
        } }
        for level in 0..<floors {
            box(root,(w*0.85,0.009,0.01),(w/2,0.07+CGFloat(level)*0.19,l*0.95),timber)
        }
        return root
    }
    let kind = asset.kind
    if kind.contains("STADIUM") {
        let first = kind.contains("STADIUM_1") ? 20 : 32
        let part = (asset.houses.min() ?? first)-first
        let u = part>=2 ? 1 : 0, v = part%2
        let turf = mat(0.35,0.47,0.24)
        box(root,(1,0.005,1),(0.5,0.0025,0.5),turf)
        for axis in 0..<2 {
            let rim:CGFloat = (axis==0 ? v : u)==0 ? 0.07 : 0.93
            for row in 0..<4 {
                let direction:CGFloat = rim<0.5 ? 1 : -1
                let position = rim+direction*CGFloat(row)*0.043
                if axis==0 { box(root,(0.04,0.038+CGFloat(3-row)*0.034,1),(position,0.05+CGFloat(3-row)*0.017,0.5),stone) }
                else { box(root,(1,0.038+CGFloat(3-row)*0.034,0.04),(0.5,0.05+CGFloat(3-row)*0.017,position),stone) }
            }
        }
        if u==0 { box(root,(0.012,0.004,0.75),(v==0 ? 0.99 : 0.01,0.009,0.6),cream) }
        else { box(root,(0.012,0.004,0.75),(v==0 ? 0.99 : 0.01,0.009,0.4),cream) }
        let goalZ:CGFloat = u==0 ? 0.23 : 0.77
        let goalX:CGFloat = v==0 ? 0.86 : 0.14
        for dx:CGFloat in [-0.07,0.07] { box(root,(0.008,0.105,0.008),(goalX+dx,0.057,goalZ),cream) }
        box(root,(0.148,0.008,0.008),(goalX,0.11,goalZ),cream)
        return root
    }
    if kind.contains("FOUNTAIN") {
        cylinder(root,radius:0.28,height:0.032,x:w/2,y:0.016,z:l/2,material:stone)
        cylinder(root,radius:0.245,height:0.008,x:w/2,y:0.036,z:l/2,material:mat(0.24,0.42,0.43,rough:0.18))
        cylinder(root,radius:0.035,height:0.13,x:w/2,y:0.095,z:l/2,material:edge)
        cylinder(root,radius:0.12,height:0.025,x:w/2,y:0.155,z:l/2,material:edge)
        cylinder(root,radius:0.04,height:0.035,x:w/2,y:0.18,z:l/2,material:edge)
        return root
    }
    if kind.contains("STATUE") {
        box(root,(0.29,0.03,0.29),(w/2,0.015,l/2),edge)
        box(root,(0.14,0.12,0.14),(w/2,0.09,l/2),stone)
        let bronze = mat(0.23,0.29,0.21,metal:0.65)
        box(root,(0.07,0.06,0.045),(w/2,0.18,l/2),bronze,bevel:0.015)
        let head = SCNNode(geometry:SCNSphere(radius:0.023)); head.geometry!.materials=[bronze]; head.position=SCNVector3(w/2,0.226,l/2); root.addChildNode(head)
        return root
    }
    if kind.contains("PARK") {
        box(root,(w*0.9,0.005,l*0.9),(w/2,0.003,l/2),mat(0.36,0.46,0.23))
        box(root,(0.12,0.007,l*0.9),(w/2,0.008,l/2),stone)
        box(root,(w*0.9,0.007,0.10),(w/2,0.008,l/2),stone)
        shrubs(root,x:w*0.23,z:l*0.25,size:0.43)
        shrubs(root,x:w*0.75,z:l*0.74,size:0.40)
        box(root,(0.05,0.015,0.17),(w*0.7,0.055,l*0.3),timber)
        box(root,(0.012,0.07,0.17),(w*0.73,0.07,l*0.3),timber)
        return root
    }
    if kind.contains("CHURCH") {
        box(root,(w*0.48,0.51,l*0.82),(w*0.53,0.255,l*0.54),wall)
        pitchedRoof(root,width:w*0.51,length:l*0.85,y:0.51,x:w*0.53,z:l*0.54,rise:0.16,material:roof)
        box(root,(w*0.26,0.65,l*0.25),(w*0.53,0.325,l*0.18),wall)
        let spire = SCNPyramid(width:w*0.31,height:0.22,length:l*0.30); spire.materials=[slate]
        let node=SCNNode(geometry:spire); node.position=SCNVector3(w*0.53,0.76,l*0.18); root.addChildNode(node)
        box(root,(0.01,0.07,0.01),(w*0.53,0.9,l*0.18),steel)
        box(root,(0.047,0.01,0.01),(w*0.53,0.916,l*0.18),steel)
        for z:CGFloat in [l*0.37,l*0.60,l*0.83] {
            box(root,(0.004,0.20,0.064),(w*0.775,0.31,z),cream)
            box(root,(0.006,0.17,0.045),(w*0.78,0.32,z),window)
        }
        box(root,(0.11,0.23,0.008),(w*0.53,0.115,l*0.052),timber)
        return root
    }
    if kind.contains("WAREHOUSE") {
        let body=max(0.3,h-0.13)
        box(root,(w*0.82,body,l*0.82),(w/2,body/2,l/2),brick)
        pitchedRoof(root,width:w*0.85,length:l*0.85,y:body,x:w/2,z:l/2,rise:0.13,material:slate)
        for x:CGFloat in [w*0.32,w*0.69] {
            box(root,(0.235,0.35,0.010),(x,0.18,l*0.916),steel)
            for row in 0..<10 { box(root,(0.231,0.005,0.014),(x,0.023+CGFloat(row)*0.034,l*0.921),stone) }
            box(root,(0.26,0.024,0.17),(x,0.013,l*0.95),stone)
        }
        for z:CGFloat in [l*0.30,l*0.70] { box(root,(0.010,0.085,0.14),(w*0.918,body*0.78,z),window) }
        return root
    }
    let residential = kind.contains("HOUSES") || kind.contains("COTTAGES") || kind.contains("FLATS")
    let heritage = residential || (kind.contains("SHOPS") && h<1.5)
    let bw=w*0.80, bl=l*0.80
    let roofRise:CGFloat = heritage ? min(0.15,h*0.25) : 0.03
    let bodyH=max(0.22,h-roofRise-0.03)
    box(root,(bw,bodyH,bl),(w/2,bodyH/2+0.02,l/2),wall,bevel:0.003)
    let floors=max(1,Int(bodyH/0.18)), columns=max(2,Int(max(bw,bl)/0.17))
    for floor in 0..<floors {
        let y=0.035+(CGFloat(floor)+0.5)*bodyH/CGFloat(floors)
        let wh=min(0.115,bodyH/CGFloat(floors)*0.63)
        for column in 0..<columns {
            let x=w/2-bw/2+(CGFloat(column)+0.5)*bw/CGFloat(columns)
            let z=l/2-bl/2+(CGFloat(column)+0.5)*bl/CGFloat(columns)
            box(root,(0.008,wh+0.015,0.077),(w/2+bw/2+0.002,y,z),cream)
            box(root,(0.010,wh,0.059),(w/2+bw/2+0.007,y,z),window)
            box(root,(0.077,wh+0.015,0.008),(x,y,l/2+bl/2+0.002),cream)
            box(root,(0.059,wh,0.010),(x,y,l/2+bl/2+0.007),window)
            if heritage {
                box(root,(0.014,0.005,0.07),(w/2+bw/2+0.012,y,z),cream)
                box(root,(0.07,0.005,0.014),(x,y,l/2+bl/2+0.012),cream)
                box(root,(0.022,0.009,0.086),(w/2+bw/2,y-wh/2-0.012,z),edge)
            }
        }
        box(root,(bw+0.01,0.008,bl+0.01),(w/2,0.04+CGFloat(floor)*bodyH/CGFloat(floors),l/2),stone)
    }
    if heritage {
        pitchedRoof(root,width:bw+0.01,length:bl+0.02,y:bodyH+0.02,x:w/2,z:l/2,rise:roofRise,material:roof)
        box(root,(0.065,0.12,0.06),(w*0.34,bodyH+roofRise*0.7+0.06,l*0.37),brick)
        box(root,(0.079,0.012,0.075),(w*0.34,bodyH+roofRise*0.7+0.125,l*0.37),edge)
    } else {
        box(root,(bw+0.02,0.025,bl+0.02),(w/2,bodyH+0.033,l/2),edge)
        box(root,(bw*0.85,0.006,bl*0.85),(w/2,bodyH+0.049,l/2),slate)
        for i in 0..<2 { box(root,(0.13,0.041,0.11),(w*0.4+CGFloat(i)*0.16,bodyH+0.07,l*0.45),steel) }
    }
    box(root,(0.065,0.15,0.012),(w/2,0.095,l/2+bl/2+0.01),timber)
    box(root,(0.045,0.06,0.014),(w/2,0.128,l/2+bl/2+0.015),window)
    if kind.contains("SHOP") || kind.contains("CINEMA") || kind.contains("THEATER") || kind.contains("MALL") {
        box(root,(bw*0.79,0.10,0.012),(w/2,0.10,l/2+bl/2+0.009),window)
        box(root,(bw*0.90,0.029,0.13),(w/2,0.185,l/2+bl/2+0.052),timber)
        for stripe in 0..<12 {
            box(root,(bw/14,0.004,0.13),(w/2-bw*0.43+CGFloat(stripe)*bw/13,0.202,l/2+bl/2+0.052),stripe%2==0 ? cream : timber)
        }
        box(root,(bw*0.70,0.065,0.010),(w/2,0.27,l/2+bl/2+0.012),cream)
    }
    if residential {
        box(root,(0.10,0.025,0.10),(w/2,0.013,l*0.96),stone)
        box(root,(w*0.35,0.055,0.07),(w*0.30,0.029,l*0.95),mat(0.29,0.39,0.17))
        box(root,(0.054,0.075,0.054),(w*0.84,0.045,l*0.92),brick)
    }
    return root
}

func streetLamp(reverse:Bool) -> SCNNode {
    let root=SCNNode()
    box(root,(0.045,0.013,0.045),(0,0.0065,0),stone)
    box(root,(0.009,0.47,0.009),(0,0.242,0),steel)
    box(root,(0.09,0.010,0.012),(reverse ? -0.036 : 0.036,0.472,0),steel)
    box(root,(0.052,0.010,0.032),(reverse ? -0.063 : 0.063,0.464,0),amber,bevel:0.003)
    return root
}

func exportStation(_ model:SCNNode, id:Int, swap:Bool, name:String, paint:Bool = true, tall:Bool = false) throws {
    if swap {
        // Reflect across the tile diagonal to change rail axis without moving its origin.
        var transform = SCNMatrix4Identity; transform.m11 = 0; transform.m33 = 0; transform.m13 = 1; transform.m31 = 1
        model.transform = transform
    }
    let scene = SCNScene(); scene.background.contents = NSColor.clear; scene.rootNode.addChildNode(model)
    let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light!.type = .ambient; ambient.light!.intensity = 650
    ambient.light!.color = NSColor(srgbRed:0.83,green:0.87,blue:0.88,alpha:1); scene.rootNode.addChildNode(ambient)
    let sun = SCNNode(); sun.light = SCNLight(); sun.light!.type = .directional; sun.light!.intensity = 1100
    sun.light!.color = NSColor(srgbRed:1,green:0.92,blue:0.79,alpha:1); sun.eulerAngles = SCNVector3(-0.85,-0.7,0); scene.rootNode.addChildNode(sun)
    let camera = SCNNode(); camera.camera = SCNCamera(); camera.camera!.usesOrthographicProjection = true
    let height = tall ? 768 : 384, anchorY = tall ? 576 : 192
    let target:CGFloat = tall ? 1.2247448714 : 0
    camera.camera!.orthographicScale = tall ? 2.1213203436 : 1.0606601718; camera.camera!.zNear = 0.01; camera.camera!.zFar = 100
    camera.camera!.wantsHDR = false
    camera.position = SCNVector3(8,6.53197265+target,8); camera.look(at:SCNVector3(0,target,0)); scene.rootNode.addChildNode(camera)
    renderer.scene = scene; renderer.pointOfView = camera
    let image = renderer.snapshot(atTime:0,with:CGSize(width:384,height:height),antialiasingMode:.multisampling4X)
    guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data:tiff) else { fatalError("Station render") }
    var bytes = [UInt8](repeating:0,count:384*height*4)
    for y in 0..<height { for x in 0..<384 {
        let colour = bitmap.colorAt(x:x,y:y)!.usingColorSpace(.deviceRGB)!
        let i = (y*384+x)*4
        bytes[i] = UInt8(max(0,min(255,Int(colour.redComponent*255))))
        bytes[i+1] = UInt8(max(0,min(255,Int(colour.greenComponent*255))))
        bytes[i+2] = UInt8(max(0,min(255,Int(colour.blueComponent*255))))
        bytes[i+3] = UInt8(max(0,min(255,Int(colour.alphaComponent*255))))
    } }
    let offsets = try png(bytes,width:384,height:height,file:name,anchor:(-192,-anchorY))
    manifest += "\(id)\t\(offsets.0)\t\(offsets.1)\t\(paint ? 1 : 0)\t\(name)\n"
}

let slopes = Array(0..<15)+[29,23,27,30] // Inverse of OpenTTD's _slope_to_sprite_offset.
for density in 0..<4 {
    for (offset,slope) in slopes.enumerated() {
        let file = "terrain-\(density)-\(offset).png", id = 3924+density*19+offset
        let bytes = ground(slope:slope,density:density)
        let offsets = try png(bytes,width:256,height:192,file:file,anchor:(-128,-64))
        manifest += "\(id)\t\(offsets.0)\t\(offsets.1)\t0\t\(file)\n"
    }
}
for (offset,slope) in slopes.enumerated() {
    let file = "rough-\(offset).png", bytes = ground(slope:slope,density:3,rough:0)
    let offsets = try png(bytes,width:256,height:192,file:file,anchor:(-128,-64))
    manifest += "\(4000+offset)\t\(offsets.0)\t\(offsets.1)\t0\t\(file)\n"
}
for variant in 1...4 {
    let file = "rough-variant-\(variant).png"
    let offsets = try png(ground(slope:0,density:3,rough:variant),width:256,height:192,file:file,anchor:(-128,-64))
    manifest += "\(4018+variant)\t\(offsets.0)\t\(offsets.1)\t0\t\(file)\n"
}
for (id,axis,overlay) in [(1005,1,true),(1006,2,true),(1011,2,false),(1012,1,false)] {
    let file = "track-\(id).png"
    let offsets = try png(ground(slope:0,density:3,railAxis:axis,overlay:overlay),width:256,height:192,file:file,anchor:(-128,-64))
    manifest += "\(id)\t\(offsets.0)\t\(offsets.1)\t0\t\(file)\n"
}
for phase in 0..<9 { for (offset,slope) in slopes.enumerated() {
    let file = "field-\(phase)-\(offset).png"
    let offsets = try png(ground(slope:slope,density:0,field:phase),width:256,height:192,file:file,anchor:(-128,-64))
    manifest += "\(4126+phase*19+offset)\t\(offsets.0)\t\(offsets.1)\t0\t\(file)\n"
} }
try exportStation(platform(front:true),id:1069,swap:true,name:"platform-y-front.png",paint:false)
try exportStation(platform(front:false),id:1070,swap:false,name:"platform-x-rear.png",paint:false)
try exportStation(platform(front:false),id:1071,swap:true,name:"platform-y-rear.png",paint:false)
try exportStation(platform(front:true),id:1072,swap:false,name:"platform-x-front.png",paint:false)
try exportStation(building(),id:1073,swap:false,name:"station-building-x.png")
try exportStation(building(),id:1074,swap:true,name:"station-building-y.png")
for (id,front,swap) in [(1075,true,true),(1076,false,false),(1077,false,true),(1078,true,false)] {
    try exportStation(pillars(front:front),id:id,swap:swap,name:"platform-pillars-\(id).png")
}
for index in 0..<8 {
    try exportStation(canopy(glazing:index>=4,half:(index%4)/2),id:1079+index,swap:index%2==1,name:"station-canopy-\(index).png",paint:index<4)
}
let roadVariants:[(Int,Int)] = [(5,0),(10,0),(15,0),(13,0),(11,0),(7,0),(14,0),(3,0),(9,0),(12,0),(6,0),(10,12),(5,6),(10,3),(5,9),(8,0),(4,0),(2,0),(1,0)]
for paved in [false,true] { for (offset,variant) in roadVariants.enumerated() {
    let id=(paved ? 1313 : 1332)+offset, file="road-\(id).png"
    let offsets=try png(ground(slope:variant.1,density:3,road:variant.0,paved:paved),width:256,height:192,file:file,anchor:(-128,-64))
    manifest += "\(id)\t\(offsets.0)\t\(offsets.1)\t0\t\(file)\n"
} }
try exportStation(streetLamp(reverse:false),id:1406,swap:false,name:"street-lamp-1406.png",paint:false)
try exportStation(streetLamp(reverse:true),id:1407,swap:false,name:"street-lamp-1407.png",paint:false)
try manifest.write(to:output.appendingPathComponent("manifest-world.tsv"),atomically:true,encoding:.utf8)
manifest = ""
let coverage=try JSONDecoder().decode(TownCoverage.self,from:Data(contentsOf:output.deletingLastPathComponent().appendingPathComponent("town-coverage.json")))
for asset in coverage.sprites {
    try exportStation(townModel(asset),id:asset.id,swap:false,name:"town-\(asset.id).png",paint:false,tall:true)
}
for id in coverage.grounds {
    let file="courtyard-\(id).png", green=coverage.ground_kinds[String(id)]?.contains("PARK") == true
    let offsets=try png(ground(slope:0,density:3,courtyard:!green),width:256,height:192,file:file,anchor:(-128,-64))
    manifest += "\(id)\t\(offsets.0)\t\(offsets.1)\t0\t\(file)\n"
}
try manifest.write(to:output.appendingPathComponent("manifest-town.tsv"),atomically:true,encoding:.utf8)
print("Exported terrain/crops/rails/stations, 38 road layouts, two lamps and \(coverage.sprites.count) building plus \(coverage.grounds.count) courtyard sprites covering \(coverage.houses.count) temperate house tiles.")
