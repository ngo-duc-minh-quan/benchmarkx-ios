import Foundation

/// Collects FPS data while the GPU test runs. Feed it one monotonic timestamp (seconds) per frame.
final class FrameSampler {
    private static let sampleIntervalMs = 500.0
    private static let maxFrameTimeMs = 250.0
    private static let baselineSampleCount = 10
    private static let throttleDropThresholdPercent = 25.0

    private(set) var elapsed: TimeInterval = 0
    private(set) var fpsArray: [Double] = []
    private(set) var frameTimesMs: [Double] = []
    private(set) var fpsTimeline: [FPSSample] = []
    private(set) var liveFPS = 0.0
    private(set) var peakFPS = 0.0
    /// nil until the first FPS sample exists.
    private(set) var minFPS: Double?
    private(set) var isThrottling = false
    private(set) var throttleDropPercent = 0

    private var startTimestamp: TimeInterval?
    private var lastSampleTimestamp: TimeInterval = 0
    private var lastFrameTimestamp: TimeInterval = 0
    private var framesSinceLastSample = 0
    private var baselineFPS: Double?

    func tick(timestamp: TimeInterval) {
        guard let start = startTimestamp else {
            startTimestamp = timestamp
            lastSampleTimestamp = timestamp
            lastFrameTimestamp = timestamp
            return
        }

        // Frames of 250ms or more mean the app was interrupted: keep them out of the frame times.
        let frameTimeMs = (timestamp - lastFrameTimestamp) * 1000
        lastFrameTimestamp = timestamp
        if frameTimeMs > 0 && frameTimeMs < Self.maxFrameTimeMs {
            frameTimesMs.append(frameTimeMs)
        }

        elapsed = timestamp - start

        framesSinceLastSample += 1
        let sinceLastSampleMs = (timestamp - lastSampleTimestamp) * 1000
        guard sinceLastSampleMs >= Self.sampleIntervalMs else { return }

        let fps = (Double(framesSinceLastSample) / sinceLastSampleMs * 1000).rounded()
        framesSinceLastSample = 0
        lastSampleTimestamp = timestamp
        record(fps: fps)
    }

    private func record(fps: Double) {
        fpsArray.append(fps)
        fpsTimeline.append(FPSSample(t: Int(elapsed.rounded()), fps: fps))
        liveFPS = fps
        peakFPS = max(peakFPS, fps)
        minFPS = min(minFPS ?? fps, fps)

        if fpsArray.count == Self.baselineSampleCount {
            baselineFPS = fpsArray.reduce(0, +) / Double(Self.baselineSampleCount)
        }

        if let baseline = baselineFPS, baseline > 0 {
            let dropPercent = (baseline - fps) / baseline * 100
            if dropPercent >= Self.throttleDropThresholdPercent {
                isThrottling = true
                throttleDropPercent = Int(dropPercent.rounded())
            } else {
                isThrottling = false
            }
        }
    }
}
