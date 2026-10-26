import MetalKit
import SwiftUI

/// The live water behind the menu: the block page's silt, small. The cursor stirs it, a quick
/// move near the bottom kicks up sand, holding "Hold to lock" lifts the floor, and an attempt
/// on a blocked site clouds it while the menu is open. Falls back to the still water without Metal.
struct WaterSurface: View {
    var body: some View {
        if let renderer = FluidRenderer.shared {
            WaterMetalView(renderer: renderer)
        } else {
            WaterBackground()
        }
    }
}

/// What happens to the water, as splats: a push of velocity, maybe with silt in it.
/// Positions are in the view's unit square with y up, like the block page's simulation.
@MainActor
final class Water {
    static let shared = Water()

    struct Splat {
        var point: SIMD2<Float>
        var force: SIMD2<Float>
        var silt: Float
        var radius: Float
    }

    /// The view's size in points, kept current by the renderer.
    var size = CGSize(width: 320, height: 400)
    private var pending: [Splat] = []
    private var last: SIMD2<Float>?
    private var pointer: SIMD2<Float>?
    private var pressedAt: CFTimeInterval?

    /// Height of the sand's top edge at `u` (0…1 across), in unit-square y.
    func floor(at u: Float) -> Float {
        Float(Deep.sandTop(at: CGFloat(u)) / max(size.height, 1))
    }

    func hover(_ location: CGPoint) {
        let p = SIMD2(Float(location.x / size.width), Float(1 - location.y / size.height))
        if let last {
            // Measured in 2x pixels, the scale the block page's numbers were tuned at.
            let d = (p - last) * SIMD2(Float(size.width), Float(size.height)) * 2
            let speed = (d * d).sum().squareRoot()
            if speed > 0.5 {
                // Slow hands leave a clear wake; fast ones lift silt.
                add(p, force: d * 2.4, silt: min(0.25, max(0, speed - 9) * 0.004), radius: 0.3)
                if p.y < floor(at: p.x) + 0.06, speed > 6 {
                    kick(p.x, up: 200 + speed * 4, silt: min(0.35, speed * 0.005), radius: 0.5)
                }
            }
        }
        last = p
        pointer = p
    }

    func endHover() {
        last = nil
    }

    /// While "Hold to lock" is held, the floor starts to lift.
    func pressing(_ on: Bool) {
        // Only the original stirs the floor while it's held; the others keep the water calm.
        pressedAt = on && Preferences.shared.holdAnimation == .classic ? CACurrentMediaTime() : nil
    }

    /// A block just started: a cloud from where the button was, and sand from the whole floor.
    func lock() {
        pressedAt = nil
        let at = pointer ?? SIMD2(0.5, 0.35)
        guard Preferences.shared.holdAnimation == .classic else {
            // A slow swell from the button and a little sand, not a storm.
            for _ in 0..<3 {
                add(at + SIMD2(.random(in: -0.12...0.12), .random(in: -0.02...0.02)),
                    force: SIMD2(.random(in: -40...40), .random(in: 60...140)), silt: 0.1, radius: 0.7)
            }
            for i in 0..<4 { kick((Float(i) + 0.5) / 4, up: 160, silt: 0.1, radius: 0.8) }
            return
        }
        for _ in 0..<8 {
            add(at + SIMD2(.random(in: -0.25...0.25), .random(in: -0.025...0.025)),
                force: SIMD2(.random(in: -150...150), .random(in: 260...460)), silt: 0.35, radius: 0.9)
        }
        for i in 0..<8 { kick((Float(i) + 0.5) / 8, up: 500, silt: 0.45, radius: 1) }
    }

    /// Someone just tried a blocked site.
    func attempt() {
        stir(0.6, from: 0.05, to: 0.5)
        for _ in 0..<6 { kick(.random(in: 0...1), up: 520, silt: 0.5, radius: 1) }
    }

    /// Opening the menu disturbs the water a little.
    func opened() {
        last = nil
        stir(0.3, from: 0.05, to: 0.6)
    }

    /// Everything queued since the last frame, plus the floor lifting under a held button.
    func drain() -> [Splat] {
        if let pressedAt {
            let p = Float(min(1, (CACurrentMediaTime() - pressedAt) / HoldButton.holdTime))
            if Float.random(in: 0...1) < p * 0.7 {
                kick(.random(in: 0...1), up: 100 + 240 * p, silt: 0.12 * p, radius: 0.4 + 0.6 * p)
            }
        }
        defer { pending.removeAll(keepingCapacity: true) }
        return pending
    }

    private func add(_ point: SIMD2<Float>, force: SIMD2<Float>, silt: Float, radius: Float) {
        guard pending.count < 200 else { return }
        pending.append(Splat(point: point, force: force, silt: silt, radius: radius))
    }

    private func kick(_ x: Float, up: Float, silt: Float, radius: Float) {
        add(SIMD2(x, floor(at: x) + 0.004), force: SIMD2(.random(in: -60...60), up), silt: silt, radius: radius)
    }

    private func stir(_ k: Float, from y0: Float, to y1: Float) {
        for _ in 0..<26 {
            add(SIMD2(.random(in: 0.05...0.95), .random(in: y0...y1)),
                force: SIMD2(.random(in: -190...190) * k, .random(in: -66...154) * k),
                silt: .random(in: 0.3...0.6) * k, radius: .random(in: 0.8...2.2))
        }
    }
}

// MARK: - Rendering

private struct WaterMetalView: NSViewRepresentable {
    let renderer: FluidRenderer

    func makeNSView(context: Context) -> WaterMTKView {
        let view = WaterMTKView(frame: .zero, device: renderer.device)
        view.colorPixelFormat = FluidRenderer.pixelFormat
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.delegate = renderer
        return view
    }

    func updateNSView(_ view: WaterMTKView, context: Context) {}
}

/// Stops drawing whenever the menu isn't on screen.
final class WaterMTKView: MTKView {
    private var observer: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        guard let window else { isPaused = true; return }
        isPaused = !window.occlusionState.contains(.visible)
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let window = self.window else { return }
                self.isPaused = !window.occlusionState.contains(.visible)
            }
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// A stable-fluids simulation (advect, curl, pressure) drawn as murky water over sand,
/// the same one as the block page, in Metal. One instance; the silt survives between openings.
@MainActor
final class FluidRenderer: NSObject, MTKViewDelegate {
    /// Nil where Metal isn't available or the shaders don't compile; the menu then shows still water.
    static let shared: FluidRenderer? = MTLCreateSystemDefaultDevice().flatMap(FluidRenderer.init(device:))
    static let pixelFormat = MTLPixelFormat.bgra8Unorm

    let device: MTLDevice
    let queue: MTLCommandQueue
    private var pipelines: [String: MTLRenderPipelineState] = [:]

    private struct PingPong {
        var read: MTLTexture
        var write: MTLTexture
        mutating func swap() { (read, write) = (write, read) }
    }

    private var velocity: PingPong?
    private var dye: PingPong?
    private var pressure: PingPong?
    private var divergence: MTLTexture?
    private var curl: MTLTexture?
    private var simSize = SIMD2<Int>(0, 0)
    private var dyeSize = SIMD2<Int>(0, 0)
    private var time: Float = 0
    private var lastFrame = CACurrentMediaTime()

    private init?(device: MTLDevice) {
        guard let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.queue = queue
        super.init()
        do {
            let library = try device.makeLibrary(source: Self.shaders, options: nil)
            let vertex = library.makeFunction(name: "fullscreen")
            for name in ["splat", "advect", "curlOf", "vorticity", "divergenceOf", "scale", "jacobi", "subtractGradient", "display"] {
                let descriptor = MTLRenderPipelineDescriptor()
                descriptor.vertexFunction = vertex
                descriptor.fragmentFunction = library.makeFunction(name: name)
                descriptor.colorAttachments[0].pixelFormat = name == "display" ? Self.pixelFormat : .rgba16Float
                pipelines[name] = try device.makeRenderPipelineState(descriptor: descriptor)
            }
        } catch {
            log.error("Water shaders: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let target = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let buffer = queue.makeCommandBuffer() else { return }
        render(into: target, pixels: view.drawableSize, points: view.bounds.size, buffer)
        buffer.present(drawable)
        buffer.commit()
    }

    /// One frame: take what happened to the water, step it, and draw it into `target`.
    func render(into target: MTLRenderPassDescriptor, pixels: CGSize, points: CGSize, _ buffer: MTLCommandBuffer) {
        let now = CACurrentMediaTime()
        let dt = Float(min(1.0 / 30, max(0, now - lastFrame)))
        lastFrame = now
        time += dt

        let water = Water.shared
        water.size = points
        guard pixels.width > 0, pixels.height > 0, points.height > 0 else { return }
        allocate(for: pixels, buffer)
        guard var velocity, var dye, var pressure, let divergence, let curl else { return }

        let aspect = Float(pixels.width / pixels.height)
        for splat in water.drain() {
            let at = SIMD4(splat.point.x, splat.point.y, splat.radius / 100, aspect)
            pass("splat", into: velocity.write, buffer, [velocity.read], [at, SIMD4(splat.force.x, splat.force.y, 0, 0)])
            velocity.swap()
            if splat.silt > 0 {
                pass("splat", into: dye.write, buffer, [dye.read], [at, SIMD4(splat.silt, splat.silt, splat.silt, 0)])
                dye.swap()
            }
        }

        // One step of the simulation, as on the block page.
        let texel = SIMD2(1 / Float(simSize.x), 1 / Float(simSize.y))
        pass("curlOf", into: curl, buffer, [velocity.read], [SIMD4(texel.x, texel.y, 0, 0)])
        pass("vorticity", into: velocity.write, buffer, [velocity.read, curl], [SIMD4(texel.x, texel.y, 5, dt)])
        velocity.swap()
        pass("divergenceOf", into: divergence, buffer, [velocity.read], [SIMD4(texel.x, texel.y, 0, 0)])
        pass("scale", into: pressure.write, buffer, [pressure.read], [SIMD4(0.8, 0, 0, 0)])
        pressure.swap()
        for _ in 0..<16 {
            pass("jacobi", into: pressure.write, buffer, [pressure.read, divergence], [SIMD4(texel.x, texel.y, 0, 0)])
            pressure.swap()
        }
        pass("subtractGradient", into: velocity.write, buffer, [pressure.read, velocity.read], [SIMD4(texel.x, texel.y, 0, 0)])
        velocity.swap()
        pass("advect", into: velocity.write, buffer, [velocity.read, velocity.read],
             [SIMD4(texel.x, texel.y, dt, pow(0.985, dt * 60)), .zero])
        velocity.swap()
        // Silt fades slowly and sinks.
        pass("advect", into: dye.write, buffer, [velocity.read, dye.read],
             [SIMD4(texel.x, texel.y, dt, pow(0.9945, dt * 60)), SIMD4(0, -0.03, 0, 0)])
        dye.swap()

        self.velocity = velocity
        self.dye = dye
        self.pressure = pressure

        let height = Float(points.height)
        pass("display", target: target, buffer, [dye.read, velocity.read], [
            SIMD4(time, Float(pixels.width), Float(pixels.height), Float(Deep.floor) / height),
            SIMD4(1 / Float(dyeSize.x), 1 / Float(dyeSize.y), 1 / height, 0),
        ])
    }

    /// Fields sized to the view's shape; a new shape starts clear water.
    private func allocate(for drawable: CGSize, _ buffer: MTLCommandBuffer) {
        let aspect = drawable.width / drawable.height
        let sim = SIMD2(Int((96 * aspect).rounded()), 96)
        guard sim != simSize else { return }
        simSize = sim
        dyeSize = SIMD2(Int((256 * aspect).rounded()), 256)
        func texture(_ size: SIMD2<Int>) -> MTLTexture? {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: size.x, height: size.y, mipmapped: false)
            descriptor.usage = [.renderTarget, .shaderRead]
            descriptor.storageMode = .private
            return device.makeTexture(descriptor: descriptor)
        }
        func pair(_ size: SIMD2<Int>) -> PingPong? {
            guard let a = texture(size), let b = texture(size) else { return nil }
            return PingPong(read: a, write: b)
        }
        velocity = pair(sim)
        pressure = pair(sim)
        dye = pair(dyeSize)
        divergence = texture(sim)
        curl = texture(sim)
        let all = [velocity?.read, velocity?.write, pressure?.read, pressure?.write, dye?.read, dye?.write, divergence, curl]
        for case let texture? in all {
            let clear = MTLRenderPassDescriptor()
            clear.colorAttachments[0].texture = texture
            clear.colorAttachments[0].loadAction = .clear
            clear.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            clear.colorAttachments[0].storeAction = .store
            buffer.makeRenderCommandEncoder(descriptor: clear)?.endEncoding()
        }
    }

    private func pass(_ name: String, into texture: MTLTexture, _ buffer: MTLCommandBuffer, _ inputs: [MTLTexture], _ params: [SIMD4<Float>]) {
        let target = MTLRenderPassDescriptor()
        target.colorAttachments[0].texture = texture
        target.colorAttachments[0].loadAction = .dontCare
        target.colorAttachments[0].storeAction = .store
        pass(name, target: target, buffer, inputs, params)
    }

    private func pass(_ name: String, target: MTLRenderPassDescriptor, _ buffer: MTLCommandBuffer, _ inputs: [MTLTexture], _ params: [SIMD4<Float>]) {
        guard let pipeline = pipelines[name], let encoder = buffer.makeRenderCommandEncoder(descriptor: target) else { return }
        encoder.setRenderPipelineState(pipeline)
        for (index, texture) in inputs.enumerated() { encoder.setFragmentTexture(texture, index: index) }
        var params = params
        encoder.setFragmentBytes(&params, length: MemoryLayout<SIMD4<Float>>.stride * params.count, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    // uv runs 0…1 with y up, as in the block page's WebGL; textures are sampled with y flipped.
    private static let shaders = """
    #include <metal_stdlib>
    using namespace metal;

    struct VOut { float4 position [[position]]; float2 uv; };

    vertex VOut fullscreen(uint id [[vertex_id]]) {
        float2 p = float2((id << 1) & 2, id & 2);
        VOut out; out.position = float4(p * 2.0 - 1.0, 0.0, 1.0); out.uv = p; return out;
    }

    constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);
    static float4 at(texture2d<float> t, float2 uv) { return t.sample(linearClamp, float2(uv.x, 1.0 - uv.y)); }

    fragment float4 splat(VOut in [[stage_in]], texture2d<float> target [[texture(0)]], constant float4 *P [[buffer(0)]]) {
        float2 p = in.uv - P[0].xy; p.x *= P[0].w;
        return float4(at(target, in.uv).xyz + exp(-dot(p, p) / P[0].z) * P[1].xyz, 1.0);
    }

    fragment float4 advect(VOut in [[stage_in]], texture2d<float> vel [[texture(0)]], texture2d<float> src [[texture(1)]], constant float4 *P [[buffer(0)]]) {
        float2 coord = in.uv - P[0].z * at(vel, in.uv).xy * P[0].xy - P[0].z * P[1].xy;
        return P[0].w * at(src, coord);
    }

    fragment float4 curlOf(VOut in [[stage_in]], texture2d<float> vel [[texture(0)]], constant float4 *P [[buffer(0)]]) {
        float2 t = P[0].xy;
        float L = at(vel, in.uv - float2(t.x, 0)).y, R = at(vel, in.uv + float2(t.x, 0)).y;
        float T = at(vel, in.uv + float2(0, t.y)).x, B = at(vel, in.uv - float2(0, t.y)).x;
        return float4(0.5 * (R - L - T + B), 0.0, 0.0, 1.0);
    }

    fragment float4 vorticity(VOut in [[stage_in]], texture2d<float> vel [[texture(0)]], texture2d<float> curl [[texture(1)]], constant float4 *P [[buffer(0)]]) {
        float2 t = P[0].xy;
        float L = at(curl, in.uv - float2(t.x, 0)).x, R = at(curl, in.uv + float2(t.x, 0)).x;
        float T = at(curl, in.uv + float2(0, t.y)).x, B = at(curl, in.uv - float2(0, t.y)).x, C = at(curl, in.uv).x;
        float2 f = 0.5 * float2(abs(T) - abs(B), abs(R) - abs(L));
        f /= length(f) + 0.0001; f *= P[0].z * C; f.y *= -1.0;
        return float4(at(vel, in.uv).xy + f * P[0].w, 0.0, 1.0);
    }

    fragment float4 divergenceOf(VOut in [[stage_in]], texture2d<float> vel [[texture(0)]], constant float4 *P [[buffer(0)]]) {
        float2 t = P[0].xy; float2 C = at(vel, in.uv).xy;
        float L = at(vel, in.uv - float2(t.x, 0)).x, R = at(vel, in.uv + float2(t.x, 0)).x;
        float T = at(vel, in.uv + float2(0, t.y)).y, B = at(vel, in.uv - float2(0, t.y)).y;
        if (in.uv.x - t.x < 0.0) L = -C.x;
        if (in.uv.x + t.x > 1.0) R = -C.x;
        if (in.uv.y + t.y > 1.0) T = -C.y;
        if (in.uv.y - t.y < 0.0) B = -C.y;
        return float4(0.5 * (R - L + T - B), 0.0, 0.0, 1.0);
    }

    fragment float4 scale(VOut in [[stage_in]], texture2d<float> tex [[texture(0)]], constant float4 *P [[buffer(0)]]) {
        return P[0].x * at(tex, in.uv);
    }

    fragment float4 jacobi(VOut in [[stage_in]], texture2d<float> p [[texture(0)]], texture2d<float> div [[texture(1)]], constant float4 *P [[buffer(0)]]) {
        float2 t = P[0].xy;
        float L = at(p, in.uv - float2(t.x, 0)).x, R = at(p, in.uv + float2(t.x, 0)).x;
        float T = at(p, in.uv + float2(0, t.y)).x, B = at(p, in.uv - float2(0, t.y)).x;
        return float4((L + R + B + T - at(div, in.uv).x) * 0.25, 0.0, 0.0, 1.0);
    }

    fragment float4 subtractGradient(VOut in [[stage_in]], texture2d<float> p [[texture(0)]], texture2d<float> vel [[texture(1)]], constant float4 *P [[buffer(0)]]) {
        float2 t = P[0].xy;
        float L = at(p, in.uv - float2(t.x, 0)).x, R = at(p, in.uv + float2(t.x, 0)).x;
        float T = at(p, in.uv + float2(0, t.y)).x, B = at(p, in.uv - float2(0, t.y)).x;
        return float4(at(vel, in.uv).xy - float2(R - L, T - B), 0.0, 1.0);
    }

    static float caustic(float2 p, float t) {
        float2 i = p; float c = 1.0;
        for (int n = 0; n < 4; n++) {
            float tt = t * (1.0 - (3.5 / float(n + 1)));
            i = p + float2(cos(tt - i.x) + sin(tt + i.y), sin(tt - i.y) + cos(tt + i.x));
            c += 1.0 / length(float2(p.x / (sin(i.x + tt) / 0.005), p.y / (cos(i.y + tt) / 0.005)));
        }
        c /= 4.0; c = 1.17 - pow(c, 1.4);
        return clamp(pow(abs(c), 8.0), 0.0, 1.0);
    }

    // P[0]: time, drawable width, drawable height, sand height / view height. P[1]: dye texel, 1 / view height.
    fragment float4 display(VOut in [[stage_in]], texture2d<float> dye [[texture(0)]], texture2d<float> vel [[texture(1)]], constant float4 *P [[buffer(0)]]) {
        float2 uv = in.uv; float time = P[0].x, asp = P[0].y / P[0].z;
        float2 v = at(vel, uv).xy, wob = clamp(v * 0.00005, -0.012, 0.012);
        float3 col = mix(float3(0.05, 0.22, 0.27), float3(0.18, 0.52, 0.58), pow(uv.y, 1.2));
        col += float3(0.9, 1.0, 1.0) * exp(-length((uv - float2(0.65, 1.08)) * float2(asp * 0.6, 1.0)) * 3.0) * 0.2;
        float rays = 0.0;
        for (int k = 0; k < 4; k++) {
            float x = 0.14 + float(k) * 0.24 + sin(time * 0.15 + float(k)) * 0.04;
            rays += smoothstep(0.06, 0.0, abs(uv.x + wob.x - x - (1.0 - uv.y) * 0.22 * asp)) * (0.5 + 0.5 * sin(time * 0.6 + float(k) * 2.0));
        }
        col += float3(0.75, 0.95, 0.95) * rays * 0.06 * uv.y;
        float fl = P[0].w + (sin(uv.x * 7.0) * 2.2 + sin(uv.x * 19.0 + 1.0) * 1.1) * P[1].z;
        if (uv.y < fl) {
            float2 sp = float2((uv.x + wob.x) * asp, uv.y) * 9.0;
            float3 s = mix(float3(0.36, 0.40, 0.34), float3(0.50, 0.52, 0.42), sin(sp.x * 2.2 + sin(sp.y * 3.0)) * 0.5 + 0.5);
            s += float3(0.6, 0.85, 0.8) * caustic(sp * 0.9, time * 0.35) * 0.25;
            s *= 0.75 + 0.25 * (uv.y / fl);
            col = mix(col, s, smoothstep(fl, fl - 1.5 * P[1].z, uv.y));
        }
        col += float3(0.8, 1.0, 1.0) * min(length(v) * 0.00012, 0.03);
        float2 e = P[1].xy * 3.0; float d = 0.0;
        for (int j = -2; j <= 2; j++) for (int k = -2; k <= 2; k++) d += at(dye, uv + float2(float(j), float(k)) * e).r;
        d /= 25.0;
        float dUp = at(dye, uv + float2(0.0, P[1].y * 10.0)).r, shade = clamp(1.0 + (d - dUp) * 0.6, 0.88, 1.12);
        float3 silt = mix(float3(0.27, 0.32, 0.30), float3(0.58, 0.62, 0.55), clamp(uv.y * 1.05, 0.0, 1.0)) * shade;
        col = mix(col, silt, clamp(1.0 - exp(-max(d, 0.0) * 1.6), 0.0, 0.88));
        float2 q = uv - 0.5; col *= 1.0 - 0.45 * dot(q, q);
        return float4(col, 1.0);
    }
    """
}
