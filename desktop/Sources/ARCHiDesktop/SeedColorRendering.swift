import AppKit
import CryptoKit

/// Palette work happens once per verified asset and palette, outside animation
/// frames. The cache is bounded by three bundled Seeds and five chosen colors.
@MainActor
enum SeedColorRendering {
    static let revision = "archi-seed-palette/v1"
    private static var images: [String: NSImage] = [:]

    static func applies(form: CompanionForm, family: EvolutionFamily? = nil) -> Bool {
        family == nil && [.corePearl, .particleSeed, .kinSeed, .hamptonSeed].contains(form)
    }

    static func image(for form: CompanionForm, color: CompanionSeedColor) -> NSImage? {
        guard applies(form: form) else { return nil }
        if form == .hamptonSeed, color == .garnet, let authored = CompanionVisualAsset.hamptonGarnetImage {
            return authored
        }
        let original: NSImage?, digest: String
        switch form {
        case .corePearl:
            original = CompanionVisualAsset.lightSeedImage; digest = CompanionVisualAsset.lightSeedDigest
        case .hamptonSeed:
            original = CompanionVisualAsset.hamptonSeedImage; digest = CompanionVisualAsset.hamptonSeedDigest
        default:
            original = CompanionVisualAsset.kinSeedImage; digest = CompanionVisualAsset.kinSeedDigest
        }
        guard let original else { return nil }
        guard color != .original else { return original }
        let key = "\(revision)\n\(digest)\n\(color.rawValue)"
        if let cached = images[key] { return cached }
        guard let result = recolor(original, color: color, preserveGold: form == .hamptonSeed) else { return nil }
        images[key] = result
        return result
    }

    static func identity(base: String, form: CompanionForm, family: EvolutionFamily?, color: CompanionSeedColor) -> String {
        guard color != .original, applies(form: form, family: family) else { return base }
        let authored = form == .hamptonSeed && color == .garnet && CompanionVisualAsset.hamptonGarnetImage != nil
            ? "\nblender=\(CompanionVisualAsset.hamptonGarnetDigest)" : ""
        let text = "\(revision)\nasset=\(base)\ncolor=\(color.rawValue)\(authored)"
        return "sc1-" + SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Canonical RGBA8, with alpha retained byte-for-byte during recoloring.
    /// Premultiplied pixels are unpremultiplied only for the selected chromatic
    /// material. White/gray light, the central pearl and Hampton's gold stay exact.
    static func rgba(_ image: NSImage) -> (width: Int, height: Int, bytes: [UInt8])? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              cgImage.width > 0, cgImage.height > 0 else { return nil }
        let width = cgImage.width, height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let success = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return success ? (width, height, bytes) : nil
    }

    static func recolor(_ image: NSImage, color: CompanionSeedColor, preserveGold: Bool) -> NSImage? {
        guard color != .original else { return image }
        guard var bitmap = rgba(image) else { return nil }
        for y in 0..<bitmap.height {
            for x in 0..<bitmap.width {
                let index = (y * bitmap.width + x) * 4
                let alpha = Double(bitmap.bytes[index + 3])
                guard alpha > 0 else { continue }
                let dx = Double(x) / Double(bitmap.width) - 0.5
                let dy = Double(y) / Double(bitmap.height) - 0.5
                guard dx * dx + dy * dy > 0.045 * 0.045 else { continue }
                let r = min(1, Double(bitmap.bytes[index]) / alpha)
                let g = min(1, Double(bitmap.bytes[index + 1]) / alpha)
                let b = min(1, Double(bitmap.bytes[index + 2]) / alpha)
                let hsv = components(r: r, g: g, b: b)
                guard hsv.s > 0.12 else { continue }
                if preserveGold && hsv.h >= 0.025 && hsv.h <= 0.19 { continue }
                let saturation = color == .pearl ? 0 : min(0.90, max(hsv.s, 0.25))
                let rgb = components(h: color.hue, s: saturation, v: hsv.v)
                bitmap.bytes[index] = UInt8(max(0, min(alpha, (rgb.0 * alpha).rounded())))
                bitmap.bytes[index + 1] = UInt8(max(0, min(alpha, (rgb.1 * alpha).rounded())))
                bitmap.bytes[index + 2] = UInt8(max(0, min(alpha, (rgb.2 * alpha).rounded())))
            }
        }
        let data = Data(bitmap.bytes)
        guard let provider = CGDataProvider(data: data as CFData),
              let result = CGImage(width: bitmap.width, height: bitmap.height, bitsPerComponent: 8,
                bitsPerPixel: 32, bytesPerRow: bitmap.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        return NSImage(cgImage: result, size: image.size)
    }

    private static func components(r: Double, g: Double, b: Double) -> (h: Double, s: Double, v: Double) {
        let maximum = max(r, g, b), minimum = min(r, g, b), delta = maximum - minimum
        guard delta > 0, maximum > 0 else { return (0, 0, maximum) }
        var hue: Double
        if maximum == r { hue = (g - b) / delta }
        else if maximum == g { hue = 2 + (b - r) / delta }
        else { hue = 4 + (r - g) / delta }
        hue /= 6
        if hue < 0 { hue += 1 }
        return (hue, delta / maximum, maximum)
    }

    private static func components(h: Double, s: Double, v: Double) -> (Double, Double, Double) {
        let sector = h * 6, index = Int(sector), f = sector - Double(index)
        let p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
        switch index % 6 {
        case 0: return (v, t, p)
        case 1: return (q, v, p)
        case 2: return (p, v, t)
        case 3: return (p, q, v)
        case 4: return (t, p, v)
        default: return (v, p, q)
        }
    }
}
