import SwiftUI

/// KIN's selected beginning: an open particle field around one stationary core.
/// Geometry and motion are presentation only; neither advances the Journey.
struct KinCoreSeedArt: View {
    let size: CGFloat
    let reduceMotion: Bool
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    var body: some View {
        let still = reduceMotion || systemReduceMotion
        TimelineView(.animation(minimumInterval: 1 / 20, paused: still)) { time in
            KinCoreSeedFrame(phase: KinCoreSeedGeometry.phase(
                at: time.date.timeIntervalSinceReferenceDate, reduceMotion: reduceMotion,
                systemReduceMotion: systemReduceMotion))
        }
        .frame(width: size, height: size)
        .accessibilityLabel("KIN, Core Seed form")
    }
}

struct KinCoreSeedFrame: View {
    let phase: Double

    var body: some View {
        Canvas { context, size in
            let unit = min(size.width, size.height)
            // Match the authored portrait's center so fallback motion, light,
            // and the carried pearl use the same protected inset.
            let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
            let radius = unit * 0.335
            let gold = Color(red: 1, green: 0.69, blue: 0.26)
            let ivory = Color(red: 1, green: 0.97, blue: 0.83)
            func circle(_ point: CGPoint, _ r: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2))
            }
            func screen(_ point: KinCoreSeedGeometry.Point) -> CGPoint {
                CGPoint(x: center.x + point.x * radius, y: center.y + point.y * radius)
            }
            func glow(_ point: CGPoint, _ r: CGFloat, _ color: Color, _ opacity: Double) {
                context.fill(circle(point, r), with: .radialGradient(
                    Gradient(stops: [.init(color: color.opacity(opacity), location: 0),
                                     .init(color: color.opacity(opacity * 0.22), location: 0.35),
                                     .init(color: .clear, location: 1)]),
                    center: point, startRadius: 0, endRadius: r))
            }
            let palette: [Color] = [gold, Color(red: 0.72, green: 0.13, blue: 0.22),
                Color(red: 1, green: 0.84, blue: 0.51), Color(red: 0.63, green: 0.37, blue: 0.71),
                Color(red: 0.79, green: 0.80, blue: 0.85)]

            // Small grounding pool; the body itself remains unfilled and open.
            let ground = CGPoint(x: center.x, y: unit * 0.855)
            var pool = context
            pool.translateBy(x: ground.x, y: ground.y)
            pool.scaleBy(x: 1, y: 0.16)
            pool.fill(circle(.zero, unit * 0.19), with: .radialGradient(
                Gradient(colors: [gold.opacity(0.19), gold.opacity(0.05), .clear]),
                center: .zero, startRadius: 0, endRadius: unit * 0.19))

            // Interrupted threads sit among the motes, never a solid shell rim.
            for ring in 0..<4 {
                let points = KinCoreSeedGeometry.thread(ring: ring, phase: phase)
                for index in 1..<points.count where index % 23 < 17 {
                    let a = points[index - 1], b = points[index]
                    var path = Path()
                    path.move(to: screen(a)); path.addLine(to: screen(b))
                    let depth = (a.z + b.z + 2) / 4
                    context.stroke(path, with: .color(palette[ring == 2 ? 1 : 0].opacity(0.12 + depth * 0.43)),
                        style: StrokeStyle(lineWidth: max(0.22, unit * 0.0019), lineCap: .round))
                }
            }

            let points = KinCoreSeedGeometry.project(phase: phase)
            for index in points.indices.sorted(by: { points[$0].z < points[$1].z }) {
                let point = points[index], p = screen(point)
                let depth = (point.z + 1) / 2
                let bright = index % 11 == 0
                let colorIndex = index % 17 == 0 ? 4 : index % 13 == 0 ? 3 : index % 3 == 0 ? 1 : index % 5 == 0 ? 2 : 0
                let color = palette[colorIndex]
                let r = max(0.22, unit * (bright ? 0.0054 : 0.0015 + Double(index % 4) * 0.00045)) * (0.7 + depth * 0.5)
                let opacity = 0.35 + depth * 0.65
                if bright {
                    glow(p, r * 6, color, opacity * 0.18)
                    glow(p, r * 2.8, color, opacity * 0.58)
                }
                // A warm dark edge keeps individual flecks readable on pale desktops.
                if bright {
                    context.fill(circle(p, r * 1.18), with: .color(Color(red: 0.34, green: 0.12, blue: 0.05).opacity(0.5)))
                }
                context.fill(circle(p, r), with: .color(color.opacity(opacity)))
                if bright {
                    context.fill(circle(p, r * 0.45), with: .color(ivory.opacity(0.95)))
                }
            }

            // The same quiet center survives every frame and every presentation.
            glow(center, unit * 0.15, gold, 0.32)
            let coreRadius = unit * 0.034
            context.stroke(circle(center, coreRadius * 1.38), with: .color(gold.opacity(0.62)), lineWidth: unit * 0.002)
            context.fill(circle(center, coreRadius), with: .radialGradient(
                Gradient(colors: [.white, ivory, Color(red: 1, green: 0.81, blue: 0.43)]),
                center: CGPoint(x: center.x - coreRadius * 0.18, y: center.y - coreRadius * 0.2),
                startRadius: 0, endRadius: coreRadius * 1.4))
            context.stroke(circle(center, coreRadius), with: .color(Color(red: 0.64, green: 0.37, blue: 0.12).opacity(0.72)),
                lineWidth: max(0.4, unit * 0.0025))
        }
    }
}

enum KinCoreSeedGeometry {
    struct Point: Equatable, Sendable { let x: Double; let y: Double; let z: Double }
    static let points: [Point] = (0..<288).map { index in
        let y = 1 - 2 * (Double(index) + 0.5) / 288
        let theta = Double(index) * .pi * (3 - sqrt(5))
        let r = index % 7 == 0 ? 0.48 + Double(index % 5) * 0.065 : 0.88 + Double(index % 9) * 0.012
        let span = sqrt(1 - y * y) * r
        return Point(x: cos(theta) * span, y: y * r, z: sin(theta) * span)
    }

    static func phase(at time: Double, reduceMotion: Bool, systemReduceMotion: Bool = false) -> Double {
        guard !reduceMotion, !systemReduceMotion, time.isFinite else { return 0 }
        return normalized(time * 0.13)
    }

    static func project(phase: Double) -> [Point] {
        let angle = normalized(phase)
        return points.map { rotate($0, yaw: angle, tilt: 0.23) }
    }

    static func thread(ring: Int, phase: Double) -> [Point] {
        let angle = normalized(phase)
        return (0...120).map { index in
            let theta = Double(index) / 120 * .pi * 2
            let r = 0.91 + Double(ring % 2) * 0.06
            let point = Point(x: cos(theta) * r, y: sin(theta) * r, z: 0)
            let tilted = rotate(point, yaw: 0.65 + Double(ring) * 0.58, tilt: Double(ring) * 0.63)
            return rotate(tilted, yaw: angle, tilt: 0.23)
        }
    }

    private static func normalized(_ phase: Double) -> Double {
        phase.isFinite ? phase.truncatingRemainder(dividingBy: .pi * 2) : 0
    }

    private static func rotate(_ p: Point, yaw: Double, tilt: Double) -> Point {
        let x = p.x * cos(yaw) + p.z * sin(yaw)
        let z = p.z * cos(yaw) - p.x * sin(yaw)
        return Point(x: x, y: p.y * cos(tilt) - z * sin(tilt), z: p.y * sin(tilt) + z * cos(tilt))
    }
}
