import Foundation
import Metal
import MetalKit
import QuartzCore
import simd
import UIKit

enum MetalRendererError: LocalizedError {
    case noMetalDevice
    case setupFailed(String)

    var errorDescription: String? {
        switch self {
        case .noMetalDevice:
            return "This device does not support Metal."
        case .setupFailed(let reason):
            return "Metal setup failed: \(reason)"
        }
    }
}

/// Draws `cubeCount` animated cubes with one instanced draw call and feeds `sampler` while measuring.
final class MetalRenderer: NSObject, MTKViewDelegate {
    // 4000 is the RN (expo-gl) value. Metal native is much lighter than expo-gl,
    // so this will have to grow once the scores are calibrated across devices.
    static let cubeCount = 4000

    /// Read from `MTLDevice.name` at runtime.
    let gpuRendererName: String
    /// Replaced by a fresh sampler on every `startMeasuring`.
    private(set) var sampler = FrameSampler()
    /// Called on the main thread when the measured test reaches its duration (passes that duration in seconds).
    var onFinished: ((TimeInterval) -> Void)?

    private struct CubeVertex {
        var position: SIMD3<Float>
        var normal: SIMD3<Float>
    }

    private struct InstanceData {
        var model: simd_float4x4
        var color: SIMD4<Float>
    }

    private struct Uniforms {
        var viewProjection: simd_float4x4
        var lightDirection: SIMD4<Float>
    }

    private struct Cube {
        let x: Float
        let y: Float
        let z: Float
        var rx: Float
        var ry: Float
        var rz: Float
        let spinX: Float
        let spinY: Float
        let spinZ: Float
        let floatOffset: Float
        let floatSpeed: Float
        let baseY: Float
    }

    private static let cubeColors: [SIMD4<Float>] = ([
        0x00d4ff, 0x7c3aed, 0xff3b3b, 0xffb800, 0x00e676, 0xff6b35,
    ] as [Int]).map { hex in
        SIMD4<Float>(
            Float((hex >> 16) & 0xff) / 255,
            Float((hex >> 8) & 0xff) / 255,
            Float(hex & 0xff) / 255,
            1
        )
    }

    private static let maxFramesInFlight = 3

    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let vertexBuffer: MTLBuffer
    private let indexBuffer: MTLBuffer
    private let indexCount: Int
    private let instanceBuffers: [MTLBuffer]
    private let inFlight = DispatchSemaphore(value: MetalRenderer.maxFramesInFlight)
    private var frameIndex = 0
    private var cubes: [Cube]
    private var isMeasuring = false
    private var measureDuration: TimeInterval = 0

    init(view: MTKView) throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw MetalRendererError.noMetalDevice
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw MetalRendererError.setupFailed("could not create a command queue")
        }
        guard let library = device.makeDefaultLibrary(),
              let vertexFunction = library.makeFunction(name: "cube_vertex"),
              let fragmentFunction = library.makeFunction(name: "cube_fragment") else {
            throw MetalRendererError.setupFailed("shader functions not found (is Shaders.metal in the app target?)")
        }

        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        // RN scene background 0x080b12.
        view.clearColor = MTLClearColor(red: 8.0 / 255, green: 11.0 / 255, blue: 18.0 / 255, alpha: 1)
        view.preferredFramesPerSecond = UIScreen.main.maximumFramesPerSecond

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.vertexDescriptor = Self.makeVertexDescriptor()
        pipelineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat

        let pipelineState: MTLRenderPipelineState
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            throw MetalRendererError.setupFailed(error.localizedDescription)
        }

        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .less
        depthDescriptor.isDepthWriteEnabled = true
        guard let depthState = device.makeDepthStencilState(descriptor: depthDescriptor) else {
            throw MetalRendererError.setupFailed("could not create the depth state")
        }

        let mesh = Self.makeCubeMesh()
        guard let vertexBuffer = device.makeBuffer(
                bytes: mesh.vertices,
                length: MemoryLayout<CubeVertex>.stride * mesh.vertices.count,
                options: []),
              let indexBuffer = device.makeBuffer(
                bytes: mesh.indices,
                length: MemoryLayout<UInt16>.stride * mesh.indices.count,
                options: []) else {
            throw MetalRendererError.setupFailed("could not create the cube mesh buffers")
        }

        // One instance buffer per frame in flight, so the CPU never writes data the GPU is still reading.
        var instanceBuffers: [MTLBuffer] = []
        for _ in 0..<Self.maxFramesInFlight {
            guard let buffer = device.makeBuffer(
                length: MemoryLayout<InstanceData>.stride * Self.cubeCount,
                options: .storageModeShared
            ) else {
                throw MetalRendererError.setupFailed("could not create an instance buffer")
            }
            let instances = buffer.contents().bindMemory(to: InstanceData.self, capacity: Self.cubeCount)
            for i in 0..<Self.cubeCount {
                instances[i] = InstanceData(
                    model: matrix_identity_float4x4,
                    color: Self.cubeColors[i % Self.cubeColors.count]
                )
            }
            instanceBuffers.append(buffer)
        }

        self.gpuRendererName = device.name
        self.commandQueue = commandQueue
        self.pipelineState = pipelineState
        self.depthState = depthState
        self.vertexBuffer = vertexBuffer
        self.indexBuffer = indexBuffer
        self.indexCount = mesh.indices.count
        self.instanceBuffers = instanceBuffers
        self.cubes = Self.makeCubes()
        super.init()

        view.delegate = self
    }

    func startMeasuring(duration: TimeInterval) {
        sampler = FrameSampler()
        measureDuration = duration
        isMeasuring = true
    }

    func stopMeasuring() {
        isMeasuring = false
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let passDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else {
            return
        }

        // Count the frame only once it can be drawn, and before the semaphore wait,
        // so the wait time falls into the next frame's interval.
        let now = CACurrentMediaTime()
        let measuring = isMeasuring
        var t = now
        if measuring {
            sampler.tick(timestamp: now)
            if sampler.elapsed >= measureDuration {
                encoder.endEncoding()   // the encoder already exists: end it before dropping the frame
                isMeasuring = false
                onFinished?(measureDuration)
                return
            }
            t = sampler.elapsed
        }

        inFlight.wait()
        let semaphore = inFlight
        commandBuffer.addCompletedHandler { _ in semaphore.signal() }

        let instanceBuffer = instanceBuffers[frameIndex]
        frameIndex = (frameIndex + 1) % Self.maxFramesInFlight
        updateCubes(into: instanceBuffer, t: t, measuring: measuring)

        let size = view.drawableSize
        let aspect = size.height > 0 ? Float(size.width / size.height) : 1
        var uniforms = Uniforms(
            viewProjection: Self.perspective(fovyDegrees: 60, aspect: aspect, near: 0.1, far: 200)
                * Self.viewMatrix(t: t, measuring: measuring),
            // Same direction as the RN directional light position (10, 20, 10).
            lightDirection: SIMD4<Float>(normalize(SIMD3<Float>(10, 20, 10)), 0)
        )

        encoder.setRenderPipelineState(pipelineState)
        encoder.setDepthStencilState(depthState)
        encoder.setCullMode(.back)
        encoder.setFrontFacing(.counterClockwise)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.setVertexBuffer(instanceBuffer, offset: 0, index: 2)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: indexCount,
            indexType: .uint16,
            indexBuffer: indexBuffer,
            indexBufferOffset: 0,
            instanceCount: Self.cubeCount
        )
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Per-frame CPU update (same as the RN idleLoop / startLoop)

    private func updateCubes(into buffer: MTLBuffer, t: Double, measuring: Bool) {
        let instances = buffer.contents().bindMemory(to: InstanceData.self, capacity: Self.cubeCount)
        for i in 0..<cubes.count {
            let y: Float
            if measuring {
                cubes[i].rx += cubes[i].spinX
                cubes[i].ry += cubes[i].spinY
                cubes[i].rz += cubes[i].spinZ
                y = cubes[i].baseY + Float(sin(t * Double(cubes[i].floatSpeed) + Double(cubes[i].floatOffset))) * 0.5
            } else {
                cubes[i].rx += 0.003
                cubes[i].ry += 0.004
                y = cubes[i].baseY + Float(sin(t * 0.5 + Double(i) * 0.01)) * 0.3
            }
            instances[i].model = Self.modelMatrix(
                position: SIMD3<Float>(cubes[i].x, y, cubes[i].z),
                rotation: SIMD3<Float>(cubes[i].rx, cubes[i].ry, cubes[i].rz)
            )
        }
    }

    private static func viewMatrix(t: Double, measuring: Bool) -> simd_float4x4 {
        let eye: SIMD3<Float>
        if measuring {
            eye = SIMD3<Float>(
                Float(sin(t * 0.1) * 35),
                Float(8 + sin(t * 0.05) * 5),
                Float(cos(t * 0.1) * 35)
            )
        } else {
            eye = SIMD3<Float>(Float(sin(t * 0.05) * 35), 8, Float(cos(t * 0.05) * 35))
        }
        return lookAt(eye: eye, target: SIMD3<Float>(0, 0, 0), up: SIMD3<Float>(0, 1, 0))
    }

    // MARK: - Scene data (distribution copied from RN buildScene)

    private static func makeCubes() -> [Cube] {
        (0..<cubeCount).map { _ -> Cube in
            let y = Float.random(in: -15..<15)
            return Cube(
                x: Float.random(in: -30..<30),
                y: y,
                z: Float.random(in: -30..<30),
                rx: Float.random(in: 0..<Float.pi),
                ry: Float.random(in: 0..<Float.pi),
                rz: Float.random(in: 0..<Float.pi),
                spinX: Float.random(in: -0.01..<0.01),
                spinY: Float.random(in: -0.01..<0.01),
                spinZ: Float.random(in: -0.005..<0.005),
                floatOffset: Float.random(in: 0..<(2 * Float.pi)),
                floatSpeed: Float.random(in: 0.3..<1.0),
                baseY: y
            )
        }
    }

    private static func makeVertexDescriptor() -> MTLVertexDescriptor {
        let descriptor = MTLVertexDescriptor()
        descriptor.attributes[0].format = .float3
        descriptor.attributes[0].offset = MemoryLayout<CubeVertex>.offset(of: \.position)!
        descriptor.attributes[0].bufferIndex = 0
        descriptor.attributes[1].format = .float3
        descriptor.attributes[1].offset = MemoryLayout<CubeVertex>.offset(of: \.normal)!
        descriptor.attributes[1].bufferIndex = 0
        descriptor.layouts[0].stride = MemoryLayout<CubeVertex>.stride
        return descriptor
    }

    /// 0.6 x 0.6 x 0.6 cube (RN BoxGeometry) as 24 vertices, 36 indices.
    private static func makeCubeMesh() -> (vertices: [CubeVertex], indices: [UInt16]) {
        let half: Float = 0.3
        let x = SIMD3<Float>(1, 0, 0)
        let y = SIMD3<Float>(0, 1, 0)
        let z = SIMD3<Float>(0, 0, 1)
        // (normal, u, v) with u x v = normal, so every quad is counter-clockwise seen from outside.
        let faces: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = [
            (x, y, z), (-x, z, y), (y, z, x), (-y, x, z), (z, x, y), (-z, y, x),
        ]
        let corners: [(Float, Float)] = [(-1, -1), (1, -1), (1, 1), (-1, 1)]

        var vertices: [CubeVertex] = []
        var indices: [UInt16] = []
        for (normal, u, v) in faces {
            let base = UInt16(vertices.count)
            for (su, sv) in corners {
                vertices.append(CubeVertex(position: (normal + su * u + sv * v) * half, normal: normal))
            }
            indices += [base, base + 1, base + 2, base, base + 2, base + 3]
        }
        return (vertices, indices)
    }

    // MARK: - Math

    /// Translation * Rx * Ry * Rz, i.e. a three.js Euler 'XYZ' rotation.
    private static func modelMatrix(position p: SIMD3<Float>, rotation r: SIMD3<Float>) -> simd_float4x4 {
        let a = cos(r.x), b = sin(r.x)
        let c = cos(r.y), d = sin(r.y)
        let e = cos(r.z), f = sin(r.z)
        let ae = a * e, af = a * f, be = b * e, bf = b * f
        return simd_float4x4(columns: (
            SIMD4<Float>(c * e, af + be * d, bf - ae * d, 0),
            SIMD4<Float>(-c * f, ae - bf * d, be + af * d, 0),
            SIMD4<Float>(d, -b * c, a * c, 0),
            SIMD4<Float>(p.x, p.y, p.z, 1)
        ))
    }

    /// Right-handed look-at.
    private static func lookAt(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
        let z = normalize(eye - target)
        let x = normalize(cross(up, z))
        let y = cross(z, x)
        return simd_float4x4(columns: (
            SIMD4<Float>(x.x, y.x, z.x, 0),
            SIMD4<Float>(x.y, y.y, z.y, 0),
            SIMD4<Float>(x.z, y.z, z.z, 0),
            SIMD4<Float>(-dot(x, eye), -dot(y, eye), -dot(z, eye), 1)
        ))
    }

    /// Right-handed perspective with Metal's 0...1 depth range.
    private static func perspective(fovyDegrees: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        let ys = 1 / tan(fovyDegrees * .pi / 180 / 2)
        let xs = ys / aspect
        let zs = far / (near - far)
        return simd_float4x4(columns: (
            SIMD4<Float>(xs, 0, 0, 0),
            SIMD4<Float>(0, ys, 0, 0),
            SIMD4<Float>(0, 0, zs, -1),
            SIMD4<Float>(0, 0, zs * near, 0)
        ))
    }
}
