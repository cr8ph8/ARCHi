import AppKit
import MetalKit
import SwiftUI
import simd

/// Art direction only. The preserved v008 samples and graph IDs remain exact.
/// Frame-based framing follows the displayed sample, including slow disk reads.
enum LiminalSeedStyle {
    static let revision = "garnet-seed/v5-retained-seed"
    static func weight(frame: Int) -> Float {
        let t = min(1, max(0, Float(frame - 90) / 18))
        return t * t * (3 - 2 * t)
    }
    static func framing(center: SIMD3<Float>, span: Float, frame: Int, refined: Bool = false) -> (center: SIMD3<Float>, span: Float) {
        if refined {
            let w = LiminalPointFinish.weights(frame: frame)
            return (SIMD3(center.x, 1.25 * w.x + 1.15 * (w.y + w.z), center.z),
                    3.5 * w.x + 2.5 * w.y + 1.9 * w.z)
        }
        let amount = weight(frame: frame)
        return (center + (SIMD3<Float>(0, 1.15, center.z) - center) * amount,
                span + (1.90 - span) * amount)
    }
    static func color(_ color: CompanionSeedColor) -> CompanionSeedColor { color == .original ? .garnet : color }
}

/// A transparent view of authenticated baked samples. It owns no companion,
/// graph, progression or simulation state. Progress is supplied by the owner.
@MainActor
struct LiminalMetalView: NSViewRepresentable, @MainActor Animatable {
    let asset: LiminalPointAsset
    let progress: Double
    let reduceMotion: Bool
    let isVisible: Bool
    var seedColor: CompanionSeedColor = .original
    var lightIntensity: Float = 1
    var lightExpression: KinLightExpression = .resting
    var inspection = false
    var structure: LiminalPointStructure? = nil
    var structureElapsed: Double? = nil
    var graphMorph: LiminalGraphMorph? = nil
    var graphMorphProgress: Double = 1
    var selectableIDs: [UInt32] = []
    var onSelectArtID: ((UInt32) -> Void)? = nil
    var onGraphMorphAvailability: ((Bool) -> Void)? = nil
    var onGraphMorphDisplayedProgress: ((Double) -> Void)? = nil
    var animatableData: Double {
        get { graphMorphProgress }
        set { graphMorphProgress = newValue }
    }

    func makeNSView(context: Context) -> LiminalMetalSurface {
        // Select our designated MTKView initializer explicitly. The inherited
        // init(frame:) bypasses the pipeline and delegate setup below.
        let surface = LiminalMetalSurface(frame: .zero, device: MTLCreateSystemDefaultDevice())
        surface.configure(self)
        return surface
    }
    func updateNSView(_ surface: LiminalMetalSurface, context: Context) { surface.configure(self) }
    static func dismantleNSView(_ surface: LiminalMetalSurface, coordinator: ()) { surface.stop() }

    /// An explicit, bounded offscreen snapshot using the exact live GPU pipeline.
    /// Call only for a qualified asset. Failure does not substitute another asset.
    static func snapshotPNGData(asset: LiminalPointAsset, progress: Double,
                                seedColor: CompanionSeedColor = .original,
                                lightIntensity: Float = 1, lightMode: KinLightMode = .rest,
                                unixTime: Double = 0, reduceMotion: Bool = true, inspection: Bool = false,
                                structure: LiminalPointStructure? = nil, structureElapsed: Double? = nil,
                                graphMorph: LiminalGraphMorph? = nil, graphMorphProgress: Double = 1,
                                detail: LiminalPointAsset.Detail = .medium) throws -> Data {
        guard let device = MTLCreateSystemDefaultDevice() else { throw LiminalMetalFailure.unavailable }
        let renderer = try LiminalMetalPipeline(device: device)
        guard graphMorph == nil || graphMorph?.manifestSHA256 == asset.manifestSHA256 else { throw LiminalMetalFailure.snapshotFailed }
        let seedTexture = graphMorph == nil ? renderer.seedTexture(color: seedColor) : nil
        let pair = try asset.framePair(progress: graphMorph == nil ? progress : LiminalGraphMorph.targetProgress,
                                       detail: graphMorph == nil ? detail : .low)
        let buffers = try renderer.buffers(pair, structure: graphMorph == nil ? structure : nil, asset: asset,
                                           elapsed: reduceMotion || inspection ? nil : structureElapsed)
        let mapBuffer = try graphMorph.map { try renderer.mapBuffer($0.mapTargets(count: pair.lower.pointCount)) }
        let seedMapBuffer = try graphMorph.map { try renderer.mapBuffer($0.seedTargets(count: pair.lower.pointCount)) }
        let description = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
            width: 512, height: 512, mipmapped: false)
        description.usage = [.renderTarget]
        description.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: description), let command = renderer.queue.makeCommandBuffer() else {
            throw LiminalMetalFailure.unavailable
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        try renderer.encode(command: command, pass: pass, buffers: buffers, count: pair.lower.pointCount,
            uniforms: .init(asset: asset, size: CGSize(width: 512, height: 512), fraction: pair.fraction,
                            seedColor: seedColor, lightIntensity: lightIntensity, frame: pair.lower.frame,
                            seedAvailable: seedTexture != nil, inspection: inspection,
                            light: .sample(mode: lightMode, unixTime: unixTime, reduced: reduceMotion || inspection),
                            phase: LiminalSurfaceLight.phase(unixTime: unixTime, moving: !reduceMotion && !inspection && lightMode != .rest),
                            count: pair.lower.pointCount, graphMorphProgress: graphMorph == nil ? nil : graphMorphProgress),
            seedTexture: seedTexture, mapBuffer: mapBuffer, seedMapBuffer: seedMapBuffer)
        let completed = DispatchSemaphore(value: 0)
        command.addCompletedHandler { _ in completed.signal() }
        command.commit()
        guard completed.wait(timeout: .now() + 3) == .success, command.status == .completed else {
            throw LiminalMetalFailure.snapshotFailed
        }
        var bytes = [UInt8](repeating: 0, count: 512 * 512 * 4)
        bytes.withUnsafeMutableBytes { raw in
            texture.getBytes(raw.baseAddress!, bytesPerRow: 512 * 4, from: MTLRegionMake2D(0, 0, 512, 512), mipmapLevel: 0)
        }
        // Metal readback is BGRA. ImageIO/AppKit receives ordinary RGBA bytes.
        for index in stride(from: 0, to: bytes.count, by: 4) { bytes.swapAt(index, index + 2) }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(width: 512, height: 512, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 512 * 4,
                space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw LiminalMetalFailure.snapshotFailed
        }
        return png
    }
}

private enum LiminalMetalFailure: Error { case unavailable, snapshotFailed }

/// No geometry shader is used: each authored point becomes six instanced quad
/// vertices. This path works on native Metal and has a direct Unity quad analogue.
private struct LiminalMetalPipeline {
    struct Buffers { let lower: MTLBuffer; let upper: MTLBuffer; let anchors: MTLBuffer; let finish: MTLBuffer; let curves: MTLBuffer?; let curveCount: Int; let structure: MTLBuffer?; let structureCount: Int }
    struct Uniforms {
        var centerAndScale: SIMD4<Float>
        var viewportAndFraction: SIMD4<Float>
        var tintAndAmount: SIMD4<Float>
        var intensityAndPadding: SIMD4<Float>
        var lightCue: SIMD4<Float>
        var finishWeights: SIMD4<Float>
        var finishSeed: SIMD4<Float>
        var displayStyle: SIMD4<Float>
        var graphMorph: SIMD4<Float>
        init(asset: LiminalPointAsset, size: CGSize, fraction: Float,
             seedColor: CompanionSeedColor, lightIntensity: Float, frame: Int,
             seedAvailable: Bool, inspection: Bool = false,
             light: LiminalLightFrame = .sample(mode: .rest, unixTime: 0), phase: Float = 0, count: Int = 100000,
             graphMorphProgress: Double? = nil) {
            let framing = LiminalSeedStyle.framing(center: asset.center, span: asset.span, frame: frame, refined: asset.finish != nil)
            centerAndScale = SIMD4(framing.center, 2 / framing.span)
            viewportAndFraction = SIMD4(Float(max(1, size.width)), Float(max(1, size.height)), fraction, 0)
            let palette: Float
            switch seedColor {
            case .original: palette = 0
            case .aqua: palette = 1
            case .garnet: palette = 2
            case .violet: palette = 3
            case .gold: palette = 4
            case .pearl: palette = 5
            }
            // Matches the Unity palette function, preserving neutral/gold points.
            tintAndAmount = SIMD4(asset.finish != nil && seedColor == .garnet ? 0 : palette, 0, 0, 0)
            // Body finish and light decorate the same retained Seed. Installing
            // either package must not withdraw its authenticated artwork.
            let seed = seedAvailable && !inspection ? LiminalSeedStyle.weight(frame: frame) : 0
            lightCue = SIMD4(light.accent, light.glow)
            finishWeights = SIMD4(LiminalPointFinish.weights(frame: frame), asset.finish == nil ? 0 : 1)
            finishSeed = LiminalPointFinish.seed(frame: frame)
            let flowing = asset.finish != nil && asset.surfaceLight != nil && !inspection
            displayStyle = SIMD4(flowing ? 1 : 0, 0, min(1.45, max(0.8, sqrt(100000 / Float(max(1,count))))), flowing ? phase : 0)
            if flowing { centerAndScale.w *= LiminalSurfaceLight.breath(phase: phase) }
            intensityAndPadding = SIMD4((lightIntensity.isFinite ? min(2, max(0, lightIntensity)) : 1) * light.intensity,
                                        inspection ? 1 : 0, 1 - 0.85 * seed, seed)
            graphMorph = .zero
            if let progress = graphMorphProgress {
                // Morph only the authenticated finish-treated points. Independent
                // light, breathing, artwork and motif passes have no map endpoint.
                centerAndScale = SIMD4(framing.center, 2 / framing.span)
                lightCue = .zero; displayStyle = .zero
                intensityAndPadding = SIMD4(1, 0, 1, 0)
                graphMorph = SIMD4(1, LiminalGraphMorph.signedSmoothstep(progress), 0, 0)
            }
        }
    }
    let device: MTLDevice
    let queue: MTLCommandQueue
    let state: MTLRenderPipelineState
    let seedState: MTLRenderPipelineState
    let curveState: MTLRenderPipelineState
    init(device: MTLDevice) throws {
        self.device = device
        guard let queue = device.makeCommandQueue() else { throw LiminalMetalFailure.unavailable }
        self.queue = queue
        let library = try device.makeLibrary(source: Self.shader, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "liminal_vertex")
        descriptor.fragmentFunction = library.makeFunction(name: "liminal_fragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        state = try device.makeRenderPipelineState(descriptor: descriptor)
        descriptor.vertexFunction = library.makeFunction(name: "liminal_seed_vertex")
        descriptor.fragmentFunction = library.makeFunction(name: "liminal_seed_fragment")
        seedState = try device.makeRenderPipelineState(descriptor: descriptor)
        descriptor.vertexFunction = library.makeFunction(name: "liminal_curve_vertex")
        descriptor.fragmentFunction = library.makeFunction(name: "liminal_curve_fragment")
        curveState = try device.makeRenderPipelineState(descriptor: descriptor)
    }
    @MainActor func seedTexture(color: CompanionSeedColor) -> MTLTexture? {
        guard let image = SeedColorRendering.image(for: .hamptonSeed, color: LiminalSeedStyle.color(color)),
              let bitmap = SeedColorRendering.rgba(image) else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
            width: bitmap.width, height: bitmap.height, mipmapped: false)
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        bitmap.bytes.withUnsafeBytes { raw in
            texture.replace(region: MTLRegionMake2D(0, 0, bitmap.width, bitmap.height), mipmapLevel: 0,
                            withBytes: raw.baseAddress!, bytesPerRow: bitmap.width * 4)
        }
        return texture
    }
    func buffers(_ pair: LiminalPointAsset.FramePair, anchorIndices: [Int] = [], structure: LiminalPointStructure? = nil,
                 asset: LiminalPointAsset? = nil, elapsed: Double? = nil) throws -> Buffers {
        func make(_ data: Data) throws -> MTLBuffer {
            guard let buffer = data.withUnsafeBytes({ bytes in
                bytes.baseAddress.flatMap { device.makeBuffer(bytes: $0, length: bytes.count, options: .storageModeShared) }
            }) else { throw LiminalMetalFailure.unavailable }
            return buffer
        }
        let first = try make(pair.lower.data)
        let second = pair.lower.data == pair.upper.data ? first : try make(pair.upper.data)
        let finish = try make(asset?.finish.map { Data($0.annotations.prefix(pair.lower.pointCount * 16)) } ?? Data(repeating: 0, count: 16))
        var anchors = [UInt32](repeating: 0, count: pair.lower.pointCount)
        for index in anchorIndices where anchors.indices.contains(index) { anchors[index] = 1 }
        guard let anchorBuffer = anchors.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }) else {
            throw LiminalMetalFailure.unavailable
        }
        let motif = asset.flatMap { asset in structure.map { $0.samples(frame: pair.lower, asset: asset, elapsed: elapsed) } } ?? []
        let curves = asset?.finish == nil ? [] : (asset?.surfaceLight?.segments(frame: pair.lower.frame) ?? [])
        return .init(lower: first, upper: second, anchors: anchorBuffer, finish: finish,
                     curves: curves.isEmpty ? nil : try make(LiminalSurfaceLight.packed(curves)), curveCount: curves.count,
                     structure: motif.isEmpty ? nil : try make(LiminalPointStructure.packed(motif)), structureCount: motif.count)
    }
    func mapBuffer(_ targets: [SIMD4<Float>]) throws -> MTLBuffer {
        guard !targets.isEmpty, let buffer = targets.withUnsafeBytes({ raw in
            device.makeBuffer(bytes: raw.baseAddress!, length: raw.count, options: .storageModeShared)
        }) else { throw LiminalMetalFailure.unavailable }
        return buffer
    }
    func encode(command: MTLCommandBuffer, pass: MTLRenderPassDescriptor, buffers: Buffers,
                count: Int, uniforms: Uniforms, seedTexture: MTLTexture?, mapBuffer: MTLBuffer? = nil,
                seedMapBuffer: MTLBuffer? = nil) throws {
        guard uniforms.graphMorph.x == 0 || ((mapBuffer?.length ?? 0) >= count * MemoryLayout<SIMD4<Float>>.stride
            && (seedMapBuffer?.length ?? 0) >= count * MemoryLayout<SIMD4<Float>>.stride) else {
            throw LiminalMetalFailure.unavailable
        }
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { throw LiminalMetalFailure.unavailable }
        encoder.setRenderPipelineState(state)
        encoder.setVertexBuffer(buffers.lower, offset: 0, index: 0)
        encoder.setVertexBuffer(buffers.upper, offset: 0, index: 1)
        encoder.setVertexBuffer(buffers.anchors, offset: 0, index: 3)
        encoder.setVertexBuffer(buffers.finish, offset: 0, index: 4)
        // A valid buffer is bound even on the unchanged path; the shader reads
        // it only when the explicit morph uniform is enabled.
        encoder.setVertexBuffer(mapBuffer ?? buffers.lower, offset: 0, index: 6)
        encoder.setVertexBuffer(seedMapBuffer ?? buffers.lower, offset: 0, index: 7)
        var copy = uniforms
        if copy.displayStyle.x > 0.5 {
            copy.displayStyle.y = 1
            encoder.setVertexBytes(&copy, length: MemoryLayout<Uniforms>.stride, index: 2)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: count)
            copy.displayStyle.y = 0
        }
        encoder.setVertexBytes(&copy, length: MemoryLayout<Uniforms>.stride, index: 2)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: count)
        if uniforms.intensityAndPadding.w > 0, let seedTexture {
            encoder.setRenderPipelineState(seedState)
            encoder.setFragmentTexture(seedTexture, index: 0)
            encoder.setFragmentBytes(&copy, length: MemoryLayout<Uniforms>.stride, index: 2)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        }
        if uniforms.displayStyle.x > 0.5, let curves = buffers.curves, buffers.curveCount > 0 {
            encoder.setRenderPipelineState(curveState)
            encoder.setVertexBuffer(curves, offset: 0, index: 5)
            for halo: Float in [1,0] {
                copy.displayStyle.y = halo
                encoder.setVertexBytes(&copy, length: MemoryLayout<Uniforms>.stride, index: 2)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: buffers.curveCount)
            }
        }
        // Same independent decoration pass as Unity: after the authored Seed,
        // with steady gold, full opacity, and no inherited activity amplification.
        if uniforms.graphMorph.x == 0, uniforms.intensityAndPadding.y == 0, let motif = buffers.structure, buffers.structureCount > 0 {
            var motifUniforms = uniforms
            motifUniforms.intensityAndPadding = SIMD4(1, 0, 1, 0)
            motifUniforms.lightCue = .zero
            motifUniforms.tintAndAmount = .zero
            motifUniforms.finishWeights = .zero
            motifUniforms.displayStyle = .zero
            encoder.setRenderPipelineState(state)
            encoder.setVertexBytes(&motifUniforms, length: MemoryLayout<Uniforms>.stride, index: 2)
            encoder.setVertexBuffer(motif, offset: 0, index: 0)
            encoder.setVertexBuffer(motif, offset: 0, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: buffers.structureCount)
        }
        encoder.endEncoding()
    }
    private static let shader = """
    #include <metal_stdlib>
    using namespace metal;
    struct Point { packed_float3 p; packed_float3 cd; float radius; float emission; };
    struct Uniforms { float4 centerScale; float4 viewportFraction; float4 tintAmount; float4 intensity; float4 lightCue; float4 finishWeights; float4 finishSeed; float4 displayStyle; float4 graphMorph; };
    struct Finish { packed_float3 direction; uint flags; };
    struct Raster { float4 position [[position]]; float2 local; float3 color; float opacity; float style; float glow; };
    float3 palette(float3 c, float choice) {
        if (choice < 0.5f) return c;
        float hi=max(c.r,max(c.g,c.b)),lo=min(c.r,min(c.g,c.b));
        if(hi<0.0001f || (hi-lo)/hi<0.12f || (c.r>c.b*1.2f && c.g>c.b*1.2f && c.g>c.r*0.18f)) return c;
        float3 tint=choice<1.5f?float3(0.05f,1,0.72f):choice<2.5f?float3(1,0.03f,0.20f):
            choice<3.5f?float3(0.52f,0.10f,1):choice<4.5f?float3(1,0.65f,0.06f):float3(1);
        return mix(float3(hi),tint*hi,saturate((hi-lo)/hi));
    }
    vertex Raster liminal_vertex(uint vertexID [[vertex_id]], uint pointID [[instance_id]],
        const device Point *a [[buffer(0)]], const device Point *b [[buffer(1)]], constant Uniforms &u [[buffer(2)]],
        const device uint *selected [[buffer(3)]], const device Finish *finish [[buffer(4)]],
        const device float4 *mapTargets [[buffer(6)]], const device float4 *seedTargets [[buffer(7)]]) {
        const float2 corners[6] = {float2(-1,-1),float2(1,-1),float2(-1,1),float2(-1,1),float2(1,-1),float2(1,1)};
        float t = u.viewportFraction.z;
        float3 p = mix(float3(a[pointID].p),float3(b[pointID].p),t);
        float3 cd = max(float3(0),mix(float3(a[pointID].cd),float3(b[pointID].cd),t));
        float anchor = u.intensity.y > 0.5f && selected[pointID] != 0 ? 1.0f : 0.0f;
        float radius = max(0.00001f,mix(a[pointID].radius,b[pointID].radius,t));
        float emission = clamp(mix(a[pointID].emission,b[pointID].emission,t),0.0f,8.0f);
        bool goldenSeed = false;
        if (u.finishWeights.w > 0.5f) {
            uint flags = finish[pointID].flags;
            if ((flags & 1u) != 0u) {
                goldenSeed = true;
                p = u.finishSeed.xyz + float3(finish[pointID].direction) * u.finishSeed.w;
                cd = float3(1,0.40f,0.028f); emission = 1.8f; radius = min(radius,0.0007f);
            } else {
                float residual = ((flags & 2u) != 0u ? u.finishWeights.x : 0.0f)
                    + ((flags & 4u) != 0u ? u.finishWeights.y : 0.0f);
                cd = mix(cd,float3(0.16f,0.004f,0.0015f),residual);
                emission = mix(emission,0.4f,residual);
                float tail = (flags & 8u) != 0u ? u.finishWeights.x : 0.0f;
                cd = mix(cd,float3(0.55f,0.055f,0.008f),tail);
                emission = mix(emission,0.5f,tail);
            }
            radius *= 2.0f; emission *= 0.5f;
        }
        float2 viewport = max(float2(1),u.viewportFraction.xy);
        float side = min(viewport.x,viewport.y);
        float2 aspect = side/viewport;
        float2 center = (p.xy-u.centerScale.xy)*u.centerScale.w*aspect;
        float morphOpacity = 1.0f;
        if (u.graphMorph.x > 0.5f) {
            float4 target = mapTargets[pointID];
            if (target.z > 0.5f) {
                if (u.graphMorph.y < 0.0f) center = mix(target.xy,seedTargets[pointID].xy,-u.graphMorph.y);
                else if (u.graphMorph.y == 0.0f) center = target.xy;
                else if (u.graphMorph.y < 1.0f) center = mix(target.xy,center,u.graphMorph.y);
            }
            else morphOpacity = target.z < -0.5f ? 0.0f : max(0.0f,u.graphMorph.y);
        }
        float floorRadius = u.displayStyle.x > 0.5f ? 1.25f*u.displayStyle.z : (u.finishWeights.w > 0.5f ? 0.8f : 0.5f);
        float radiusPixels = max(floorRadius,radius*u.centerScale.w*side*0.5f);
        radiusPixels = mix(radiusPixels,max(radiusPixels*2.5f,3.0f),anchor);
        if (u.displayStyle.y > 0.5f) radiusPixels *= 2.4f;
        if (u.displayStyle.x > 0.5f && !goldenSeed) cd *= 1.15f*pow(max(max(cd.r,max(cd.g,cd.b)),0.00001f),-0.28f);
        cd = palette(cd,u.tintAmount.x);
        cd = mix(cd,u.lightCue.rgb*max(cd.r,max(cd.g,cd.b)),u.lightCue.w*0.25f);
        cd = mix(cd,float3(0.9f,0.65f,0.16f),anchor*0.55f);
        float3 radiance = min(cd*emission*u.intensity.x,float3(8));
        Raster out;
        out.position = float4(center+corners[vertexID]*(2.0f*radiusPixels/viewport),0.5f,1);
        out.local = corners[vertexID]; out.color = radiance; out.opacity = u.intensity.z*morphOpacity;
        out.style = u.displayStyle.x; out.glow = u.displayStyle.y;
        return out;
    }
    fragment float4 liminal_fragment(Raster in [[stage_in]]) {
        float squared = dot(in.local,in.local);
        if (squared >= 1.0f) discard_fragment();
        float alpha = saturate(exp(-squared*4.0f)*(1.0f-squared)*in.opacity);
        if (in.style > 0.5f) alpha = 0.72f*exp(-2.2f*squared)*(1-smoothstep(0.6f,1.0f,squared))*in.opacity;
        if (in.glow > 0.5f) {
            if (max(in.color.r,max(in.color.g,in.color.b)) <= 0.12f) discard_fragment();
            alpha = 0.035f*exp(-3.0f*squared)*in.opacity;
        }
        float3 linear = 1.0f-exp(-in.color);
        float3 srgb = select(12.92f*linear, 1.055f*pow(linear,float3(1.0f/2.4f))-0.055f,
                             linear > 0.0031308f);
        // AppKit consumes premultiplied display-space RGBA. Encode BEFORE
        // premultiplication; the unorm target avoids a second RGB conversion.
        return float4(srgb*alpha,alpha);
    }
    struct Curve { packed_float3 a; float width; packed_float3 b; float intensity; packed_float3 color; float u0; float u1; float phase; float2 pad; };
    struct CurveRaster { float4 position [[position]]; float transverse; float3 color; float glow; float visibility; };
    vertex CurveRaster liminal_curve_vertex(uint vertexID [[vertex_id]], uint curveID [[instance_id]],
        const device Curve *segments [[buffer(5)]], constant Uniforms &u [[buffer(2)]]) {
        const float2 corners[6] = {float2(0,-1),float2(1,-1),float2(0,1),float2(0,1),float2(1,-1),float2(1,1)};
        Curve s=segments[curveID]; float2 corner=corners[vertexID];
        float2 viewport=max(float2(1),u.viewportFraction.xy); float side=min(viewport.x,viewport.y);
        float2 a=(float3(s.a).xy-u.centerScale.xy)*u.centerScale.w*side*0.5f;
        float2 b=(float3(s.b).xy-u.centerScale.xy)*u.centerScale.w*side*0.5f;
        float2 direction=(b-a)/max(length(b-a),0.00001f), normal=float2(-direction.y,direction.x);
        float width=max(0.65f,s.width*u.centerScale.w*side*0.25f);
        if(u.displayStyle.y>0.5f) width=width*3.8f+0.6f;
        float2 p=mix(a,b,corner.x)+normal*width*corner.y;
        float flow=1+0.14f*(0.5f+0.5f*cos(6.283185307f*mix(s.u0,s.u1,corner.x)-u.displayStyle.w+s.phase));
        CurveRaster out;out.position=float4(p*2.0f/viewport,0.5f,1);out.transverse=corner.y;
        out.color=min(palette(float3(s.color),u.tintAmount.x)*s.intensity*flow,float3(8));out.glow=u.displayStyle.y;
        // Endpoint surface anchors do not describe the intermediate source motion.
        // Withdraw strokes smoothly near the midpoint so they cannot cover the Seed.
        float held=max(u.finishWeights.x,max(u.finishWeights.y,u.finishWeights.z));
        out.visibility=smoothstep(0.0f,1.0f,clamp(2.0f*held-1.0f,0.0f,1.0f))*(1-u.intensity.w);return out;
    }
    fragment float4 liminal_curve_fragment(CurveRaster in [[stage_in]]) {
        float r2=in.transverse*in.transverse;
        float alpha=(in.glow>0.5f?0.08f*exp(-3*r2):0.86f*exp(-2*r2)*(1-smoothstep(0.6f,1.0f,r2)))*in.visibility;
        float3 linear=1-exp(-in.color);
        float3 srgb=select(12.92f*linear,1.055f*pow(linear,float3(1.0f/2.4f))-0.055f,linear>0.0031308f);
        return float4(srgb*alpha,alpha);
    }
    struct SeedRaster { float4 position [[position]]; float2 uv; };
    vertex SeedRaster liminal_seed_vertex(uint id [[vertex_id]], constant Uniforms &u [[buffer(2)]]) {
        const float2 corners[6] = {float2(-1,-1),float2(1,-1),float2(-1,1),float2(-1,1),float2(1,-1),float2(1,1)};
        float2 viewport = max(float2(1),u.viewportFraction.xy);
        SeedRaster out;
        float2 aspect = min(viewport.x,viewport.y)/viewport;
        float2 center = (float2(0,1.15f)-u.centerScale.xy)*u.centerScale.w;
        out.position = float4((center+corners[id]*0.95f*u.centerScale.w)*aspect,0.4f,1);
        out.uv = float2(corners[id].x*0.5f+0.5f,0.5f-corners[id].y*0.5f);
        return out;
    }
    fragment float4 liminal_seed_fragment(SeedRaster in [[stage_in]], texture2d<float> art [[texture(0)]],
                                        constant Uniforms &u [[buffer(2)]]) {
        constexpr sampler linearSampler(coord::normalized, address::clamp_to_edge, filter::linear);
        float4 color = art.sample(linearSampler,in.uv); // Already premultiplied sRGB.
        float radius = length(in.uv-float2(0.5f));
        float halo = exp(-radius*radius/0.025f)*u.lightCue.w;
        color.rgb = min(color.rgb+u.lightCue.rgb*halo*color.a,float3(color.a));
        color.rgb = min(color.rgb*u.intensity.x,float3(color.a));
        return color*u.intensity.w;
    }
    """
}

@MainActor
final class LiminalMetalSurface: MTKView, MTKViewDelegate {
    private var configuration: LiminalMetalView?
    private var pipeline: LiminalMetalPipeline?
    private var seedTexture: MTLTexture?
    private var seedTextureColor: CompanionSeedColor?
    private var buffers: LiminalMetalPipeline.Buffers?
    private struct Anchor { let id: UInt32; let rank: Int; let lower: LiminalPointAsset.Sample; let upper: LiminalPointAsset.Sample }
    private var anchors: [Anchor] = []
    private var mapBuffer: MTLBuffer?
    private var mapTargets: [SIMD4<Float>] = []
    private var seedMapBuffer: MTLBuffer?
    private var seedMapTargets: [SIMD4<Float>] = []
    private var mapBufferKey: String?
    private struct DisplayedSelection {
        let anchors: [Anchor]
        let fraction: Float
        let centerAndScale: SIMD4<Float>
        let morphDigest: String?
        let morphAmount: Float?
        let targets: [SIMD4<Float>]
        let seedTargets: [SIMD4<Float>]
    }
    private var displayedSelection: DisplayedSelection?
    private var reportedMorphAvailability: (key: String, ready: Bool)?
    private var reportedMorphProgress: (key: String, progress: Double)?
    private var frameNumbers: (lower: Int, upper: Int)?
    private var pointCount = 0
    private var loadedKey: String?
    private var loadingKey: String?
    private var failedKey: String?
    private var loading: Task<Void, Never>?
    private var detail = LiminalPointAsset.Detail.medium
    private var slowFrames = 0
    private var fastGPUFrames = 0
    private var lastFrameAt: Double?
    private var observers: [NSObjectProtocol] = []
    private let fallbackImage = NSImageView()
    private var fallbackKey: String?
    private var fallbackLoading: Task<Void, Never>?
    private var usesFallback: Bool { pipeline == nil || failedKey != nil }

    override init(frame frameRect: NSRect, device: MTLDevice? = nil) {
        let actualDevice = device ?? MTLCreateSystemDefaultDevice()
        super.init(frame: frameRect, device: actualDevice)
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColorMake(0, 0, 0, 0)
        framebufferOnly = true
        preferredFramesPerSecond = 30
        enableSetNeedsDisplay = false
        isPaused = true
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
        fallbackImage.frame = bounds
        fallbackImage.autoresizingMask = [.width, .height]
        fallbackImage.imageScaling = .scaleProportionallyUpOrDown
        fallbackImage.isHidden = true
        addSubview(fallbackImage)
        delegate = self
        if let actualDevice { pipeline = try? LiminalMetalPipeline(device: actualDevice) }
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
                     NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                     NSWindow.didDeminiaturizeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.updateVisibility() }
            })
        }
    }
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var isOpaque: Bool { false }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateVisibility() }
    override func viewDidHide() { super.viewDidHide(); updateVisibility() }
    override func viewDidUnhide() { super.viewDidUnhide(); updateVisibility() }

    func configure(_ next: LiminalMetalView) {
        if configuration?.asset.manifestSHA256 != next.asset.manifestSHA256 || configuration?.asset.finish?.digest != next.asset.finish?.digest || configuration?.asset.surfaceLight?.digest != next.asset.surfaceLight?.digest {
            loading?.cancel(); loading = nil; loadingKey = nil; loadedKey = nil
            failedKey = nil
            fallbackLoading?.cancel(); fallbackLoading = nil; fallbackKey = nil
            fallbackImage.image = nil; fallbackImage.isHidden = true
            frameNumbers = nil; anchors = []; buffers = nil; detail = .medium; slowFrames = 0
            mapBuffer = nil; mapTargets = []; seedMapBuffer = nil; seedMapTargets = []; mapBufferKey = nil; displayedSelection = nil
        }
        if configuration?.selectableIDs != next.selectableIDs || configuration?.structure != next.structure
            || configuration?.graphMorph?.digest != next.graphMorph?.digest {
            loading?.cancel(); loading = nil; loadingKey = nil; loadedKey = nil; anchors = []
            displayedSelection = nil
            if configuration?.graphMorph?.digest != next.graphMorph?.digest {
                reportedMorphProgress = nil
                mapBuffer = nil; mapTargets = []; seedMapBuffer = nil; seedMapTargets = []; mapBufferKey = nil
                buffers = nil; frameNumbers = nil
                clearSurface()
            }
            // Retire obsolete geometry immediately, even while the next frame loads.
            if let old = buffers { buffers = .init(lower: old.lower, upper: old.upper, anchors: old.anchors, finish: old.finish, curves: old.curves, curveCount: old.curveCount, structure: nil, structureCount: 0) }
        }
        // Morphs are externally animated rather than a continuous display loop.
        // Use the bounded 50k prefix explicitly; every mapped anchor and cluster
        // belongs to this prefix, so density cannot remove record correspondence.
        if next.graphMorph != nil { detail = .low }
        else if configuration?.graphMorph != nil { detail = .medium }
        if seedTextureColor != next.seedColor {
            seedTexture = pipeline?.seedTexture(color: next.seedColor)
            seedTextureColor = next.seedColor
        }
        configuration = next
        if next.graphMorph != nil, reportedMorphAvailability?.key != morphAvailabilityKey {
            reportGraphMorphAvailability(false)
        }
        updateVisibility()
        if isPaused, next.isVisible { setNeedsDisplay(bounds) }
    }
    func stop() {
        isPaused = true; loading?.cancel(); loading = nil; frameNumbers = nil; anchors = []; buffers = nil
        mapBuffer = nil; mapTargets = []; seedMapBuffer = nil; seedMapTargets = []; mapBufferKey = nil; displayedSelection = nil
        reportedMorphAvailability = nil
        reportedMorphProgress = nil
        fallbackLoading?.cancel(); fallbackLoading = nil; fallbackKey = nil; fallbackImage.image = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []; delegate = nil; configuration = nil; seedTexture = nil
    }
    private var canPresentPoints: Bool {
        configuration?.isVisible == true && !isHiddenOrHasHiddenAncestor
            && window?.isVisible == true && window?.occlusionState.contains(.visible) == true
    }
    private var morphAvailabilityKey: String? {
        guard let c = configuration, let morph = c.graphMorph else { return nil }
        return "\(c.asset.manifestSHA256):\(morph.digest)"
    }
    private func reportGraphMorphAvailability(_ ready: Bool) {
        guard let key = morphAvailabilityKey else { reportedMorphAvailability = nil; return }
        guard reportedMorphAvailability?.key != key || reportedMorphAvailability?.ready != ready else { return }
        reportedMorphAvailability = (key, ready)
        // SwiftUI state must not be published synchronously from updateNSView.
        Task { @MainActor [weak self] in
            guard let self, self.morphAvailabilityKey == key,
                  self.reportedMorphAvailability?.key == key,
                  self.reportedMorphAvailability?.ready == ready else { return }
            self.configuration?.onGraphMorphAvailability?(ready)
        }
    }
    private func reportGraphMorphDisplayedProgress(_ progress: Double) {
        guard let key = morphAvailabilityKey else { reportedMorphProgress = nil; return }
        guard reportedMorphProgress?.key != key || reportedMorphProgress?.progress != progress else { return }
        reportedMorphProgress = (key, progress)
        Task { @MainActor [weak self] in
            guard let self, self.morphAvailabilityKey == key,
                  self.reportedMorphProgress?.key == key,
                  self.reportedMorphProgress?.progress == progress else { return }
            self.configuration?.onGraphMorphDisplayedProgress?(progress)
        }
    }
    private func updateVisibility() {
        isPaused = !canPresentPoints || configuration?.reduceMotion == true || configuration?.inspection == true
            || configuration?.lightExpression.mode == .rest || configuration?.graphMorph != nil || usesFallback
        if isPaused { lastFrameAt = nil; slowFrames = 0; fastGPUFrames = 0 }
        fallbackImage.isHidden = !canPresentPoints || !usesFallback || fallbackImage.image == nil
        if !canPresentPoints {
            displayedSelection = nil
            lastFrameAt = nil; loading?.cancel(); loading = nil; loadingKey = nil
            if fallbackLoading != nil { fallbackLoading?.cancel(); fallbackLoading = nil; fallbackKey = nil }
        }
        if canPresentPoints && usesFallback { requestFallback(); return }
        if canPresentPoints && isPaused { draw() }
    }
    private func requestFallback() {
        guard canPresentPoints, usesFallback, let c = configuration else { return }
        if c.graphMorph != nil {
            reportGraphMorphAvailability(false)
            // A Beast endpoint image cannot truthfully stand in for a filtered
            // memory map or an intermediate graph morph.
            fallbackLoading?.cancel(); fallbackLoading = nil; fallbackKey = nil
            fallbackImage.image = nil; fallbackImage.isHidden = true
            setAccessibilityLabel("Memory-to-body particles unavailable. Return to the memory map to inspect records.")
            return
        }
        let progress = effectiveProgress
        let endpoint = [23.0 / 119, 65.0 / 119, 107.0 / 119].min { abs($0 - progress) < abs($1 - progress) }!
        let key = "\(c.asset.manifestSHA256):\(endpoint):\(c.seedColor.rawValue)"
        guard fallbackKey != key else { return }
        fallbackLoading?.cancel(); fallbackKey = key
        fallbackImage.image = nil; fallbackImage.isHidden = true
        if endpoint == 107.0 / 119, let seed = SeedColorRendering.image(for: .hamptonSeed, color: LiminalSeedStyle.color(c.seedColor)) {
            fallbackImage.image = seed
            fallbackImage.setAccessibilityLabel("Authored Liminal Seed artwork; particle rendering unavailable.")
            fallbackImage.isHidden = false
            return
        }
        let status = "Reference endpoint fallback; not an exact GPU capture."
        fallbackImage.setAccessibilityLabel(status)
        fallbackImage.toolTip = status
        setAccessibilityLabel("Liminal: \(status)")
        let asset = c.asset, color = c.seedColor
        fallbackLoading = Task { [weak self] in
            let task = Task.detached(priority: .utility) { try asset.endpointPNGData(progress: endpoint) }
            do {
                let data = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
                guard !Task.isCancelled, let self, self.fallbackKey == key, self.canPresentPoints, self.usesFallback else { return }
                self.fallbackLoading = nil
                guard let data, let original = NSImage(data: data),
                      let image = SeedColorRendering.recolor(original, color: color, preserveGold: true) else {
                    self.setAccessibilityLabel("Liminal reference endpoint fallback unavailable.")
                    return
                }
                self.fallbackImage.image = image
                self.fallbackImage.isHidden = false
            } catch {
                guard !Task.isCancelled, let self, self.fallbackKey == key else { return }
                self.fallbackLoading = nil
                self.setAccessibilityLabel("Liminal reference endpoint fallback unavailable: verification failed.")
            }
        }
    }
    private var effectiveProgress: Double {
        if configuration?.graphMorph != nil { return LiminalGraphMorph.targetProgress }
        guard let c = configuration, c.progress.isFinite else { return 0 }
        let value = min(1, max(0, c.progress))
        guard c.reduceMotion else { return value }
        // Reduced motion selects an authored endpoint, never a synthetic morph.
        return [23.0 / 119, 65.0 / 119, 107.0 / 119].min { abs($0 - value) < abs($1 - value) }!
    }
    private func requestFrames(_ c: LiminalMetalView, progress: Double) -> String {
        let index = (try? LiminalPointAsset.sourceFrameIndex(progress: progress)) ?? 0
        let key = "\(c.asset.manifestSHA256):\(c.asset.finish?.digest ?? "source"):\(c.asset.surfaceLight?.digest ?? "none"):\(c.asset.manifest.frames[index].file):\(detail.rawValue):\(c.structure?.digest ?? "none"):\(c.graphMorph?.digest ?? "none")"
        guard key != loadedKey, key != loadingKey, failedKey == nil, loading == nil else { return key }
        loadingKey = key
        // Only GPU buffers and bounded anchor samples survive a load. At most
        // two full CPU frame prefixes exist, with no whole-clip cache.
        let asset = c.asset, requestedDetail = detail
        loading = Task { [weak self] in
            let task = Task.detached(priority: .userInitiated) { try asset.framePair(progress: progress, detail: requestedDetail) }
            do {
                let frames = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
                guard !Task.isCancelled, let self, self.loadingKey == key, self.canPresentPoints,
                      self.configuration?.asset.manifestSHA256 == asset.manifestSHA256,
                      let pipeline = self.pipeline else { return }
                let indices = LiminalPointAsset.anchorIndices(for: self.configuration?.selectableIDs ?? [],
                    in: asset.artIDs, pointCount: frames.lower.pointCount)
                guard self.configuration?.structure?.digest == c.structure?.digest,
                      self.configuration?.graphMorph?.digest == c.graphMorph?.digest,
                      c.graphMorph == nil || c.graphMorph?.manifestSHA256 == asset.manifestSHA256 else { return }
                if let morph = c.graphMorph {
                    let mapKey = "\(morph.digest):\(frames.lower.pointCount)"
                    if self.mapBufferKey != mapKey {
                        let targets = morph.mapTargets(count: frames.lower.pointCount)
                        let seedTargets = morph.seedTargets(count: frames.lower.pointCount)
                        self.mapBuffer = try pipeline.mapBuffer(targets)
                        self.seedMapBuffer = try pipeline.mapBuffer(seedTargets)
                        self.seedMapTargets = seedTargets
                        self.mapTargets = targets; self.mapBufferKey = mapKey
                    }
                }
                let uploaded = try pipeline.buffers(frames, anchorIndices: indices,
                    structure: c.graphMorph == nil ? c.structure : nil, asset: asset)
                self.anchors = indices.compactMap { index in
                    guard let a = frames.lower.sample(at: index), let b = frames.upper.sample(at: index) else { return nil }
                    return Anchor(id: asset.artIDs[index], rank: index,
                        lower: asset.finish?.display(a, rank: index, frame: frames.lower.frame) ?? a,
                        upper: asset.finish?.display(b, rank: index, frame: frames.upper.frame) ?? b)
                }
                self.frameNumbers = (frames.lower.frame, frames.upper.frame)
                self.pointCount = frames.lower.pointCount
                self.buffers = uploaded; self.loadedKey = key
                self.loading = nil; self.loadingKey = nil
                if self.isPaused { self.draw() }
            } catch {
                guard !Task.isCancelled, let self, self.loadingKey == key else { return }
                self.loading = nil; self.loadingKey = nil; self.loadedKey = nil
                self.frameNumbers = nil; self.anchors = []; self.buffers = nil; self.failedKey = key
                self.reportGraphMorphAvailability(false)
                self.clearSurface()
                self.updateVisibility()
            }
        }
        return key
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { if isPaused && canPresentPoints { draw() } }
    func draw(in view: MTKView) {
        guard canPresentPoints, let c = configuration else { return }
        guard !usesFallback, let pipeline else { requestFallback(); return }
        let progress = effectiveProgress
        let key = requestFrames(c, progress: progress)
        guard frameNumbers != nil, let buffers,
              let pass = currentRenderPassDescriptor, let drawable = currentDrawable,
              let command = pipeline.queue.makeCommandBuffer() else { return }
        // A slow read may complete behind the owner's timeline. Display that
        // authenticated source sample while the next one loads. Both buffers
        // contain the same rounded v008 frame; never invent fractional motion.
        let fraction: Float = 0
        let uniforms = LiminalMetalPipeline.Uniforms(asset: c.asset, size: drawableSize, fraction: fraction,
            seedColor: c.seedColor, lightIntensity: c.lightIntensity, frame: frameNumbers!.lower,
            seedAvailable: seedTexture != nil, inspection: c.inspection,
            light: .sample(mode: c.lightExpression.mode, unixTime: Date().timeIntervalSince1970,
                           reduced: c.reduceMotion || c.inspection),
            phase: LiminalSurfaceLight.phase(unixTime: Date().timeIntervalSince1970,
                moving: !c.reduceMotion && !c.inspection && c.lightExpression.mode != .rest), count: pointCount,
            graphMorphProgress: c.graphMorph == nil ? nil : c.graphMorphProgress)
        do {
            try pipeline.encode(command: command, pass: pass, buffers: buffers, count: pointCount,
                uniforms: uniforms, seedTexture: seedTexture, mapBuffer: c.graphMorph == nil ? nil : mapBuffer,
                seedMapBuffer: c.graphMorph == nil ? nil : seedMapBuffer)
        } catch {
            failedKey = key; anchors = []; self.buffers = nil
            clearSurface(); updateVisibility(); return
        }
        let selection = DisplayedSelection(anchors: anchors, fraction: fraction, centerAndScale: uniforms.centerAndScale,
            morphDigest: c.graphMorph?.digest, morphAmount: c.graphMorph == nil ? nil : uniforms.graphMorph.y,
            targets: c.graphMorph == nil ? [] : mapTargets,
            seedTargets: c.graphMorph == nil ? [] : seedMapTargets)
        let renderedMorphProgress = LiminalGraphMorph.boundedProgress(c.graphMorphProgress)
        command.present(drawable)
        command.addCompletedHandler { [weak self] buffer in
            let duration = buffer.gpuEndTime - buffer.gpuStartTime
            let completed = buffer.status == .completed
            Task { @MainActor [weak self] in
                guard let self, self.loadedKey == key,
                      self.configuration?.graphMorph?.digest == selection.morphDigest else { return }
                if completed {
                    self.displayedSelection = selection
                    self.reportGraphMorphDisplayedProgress(renderedMorphProgress)
                    self.reportGraphMorphAvailability(true)
                } else {
                    self.displayedSelection = nil
                    self.reportGraphMorphAvailability(false)
                }
                self.observeGPUTime(duration)
            }
        }
        command.commit()
        let now = ProcessInfo.processInfo.systemUptime
        if let lastFrameAt, !isPaused {
            slowFrames = now - lastFrameAt > 1.0 / 27 ? slowFrames + 1 : max(0, slowFrames - 1)
            if slowFrames >= 8, detail != .low {
                detail = detail == .high ? .medium : .low
                loadedKey = nil; slowFrames = 0
            }
        }
        lastFrameAt = isPaused ? nil : now
    }

    private func observeGPUTime(_ duration: Double) {
        guard duration.isFinite, duration > 0, canPresentPoints, !isPaused else { return }
        fastGPUFrames = duration < 0.012 ? fastGPUFrames + 1 : 0
        if duration > 1.0 / 30, detail != .low {
            detail = detail == .high ? .medium : .low
            loadedKey = nil; fastGPUFrames = 0
        } else if fastGPUFrames >= 90, detail != .high {
            detail = detail == .low ? .medium : .high
            loadedKey = nil; fastGPUFrames = 0
        }
    }
    private func clearSurface() {
        displayedSelection = nil
        reportGraphMorphAvailability(false)
        guard let pass = currentRenderPassDescriptor, let drawable = currentDrawable,
              let command = pipeline?.queue.makeCommandBuffer(), let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.endEncoding(); command.present(drawable); command.commit()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !usesFallback, let c = configuration, c.inspection, c.onSelectArtID != nil,
              displayedSelection?.anchors.isEmpty == false, !c.selectableIDs.isEmpty else { return nil }
        return super.hitTest(point)
    }
    override func mouseDown(with event: NSEvent) {
        guard canPresentPoints, !usesFallback, let c = configuration, c.inspection, let callback = c.onSelectArtID,
              !c.selectableIDs.isEmpty, let displayed = displayedSelection,
              displayed.morphDigest == c.graphMorph?.digest else { return }
        let location = convert(event.locationInWindow, from: nil)
        let side = min(bounds.width, bounds.height), scale = CGFloat(displayed.centerAndScale.w)
        var closest: (id: UInt32, distance: CGFloat)?
        // Only the owner's explicit anchors are selectable; arbitrary art points
        // cannot masquerade as graph records. Bound selection work separately.
        for anchor in displayed.anchors where c.selectableIDs.contains(anchor.id) {
            let position = anchor.lower.position + (anchor.upper.position - anchor.lower.position) * displayed.fraction
            let radius = anchor.lower.radius + (anchor.upper.radius - anchor.lower.radius) * displayed.fraction
            var clip = SIMD2<Float>((position.x - displayed.centerAndScale.x) * Float(scale * side / bounds.width),
                                    (position.y - displayed.centerAndScale.y) * Float(scale * side / bounds.height))
            if let amount = displayed.morphAmount {
                guard displayed.targets.indices.contains(anchor.rank) else { continue }
                let target = displayed.targets[anchor.rank]
                guard target.z > 0.5 else { continue }
                if amount < 0 {
                    guard displayed.seedTargets.indices.contains(anchor.rank) else { continue }
                    let seed = displayed.seedTargets[anchor.rank]
                    clip = SIMD2(target.x, target.y) * (1 + amount) - SIMD2(seed.x, seed.y) * amount
                } else {
                    clip = SIMD2(target.x, target.y) + (clip - SIMD2(target.x, target.y)) * amount
                }
            }
            let x = bounds.midX + CGFloat(clip.x) * bounds.width / 2
            let y = bounds.midY + CGFloat(clip.y) * bounds.height / 2
            let distance = hypot(location.x - x, location.y - y)
            let hitRadius = max(8, CGFloat(radius) * 1.25 * side * scale)
            if distance <= hitRadius, closest == nil || distance < closest!.distance { closest = (anchor.id, distance) }
        }
        if let closest { callback(closest.id) }
    }
}
