import Foundation
import MetalKit
import UIKit

/// Runs the whole benchmark: CPU phase, GPU phase, score. Port of the RN NativeStressTestEngine flow.
/// Use it from the main thread only: every callback is delivered on the main thread.
final class BenchmarkRunner {
    enum State {
        case idle, cpu, running, computing, done
    }

    private struct CPUOutcome {
        let singleCoreScore: Double
        let multiCoreScore: Double
        let singleCoreWorkUnitsPerSec: Double
        let multiCoreWorkUnitsPerSec: Double
        let cores: Int
    }

    private static let cpuTestDurationMs = 3000.0
    private static let progressInterval: TimeInterval = 0.1

    private(set) var state: State = .idle {
        didSet { onStateChange?(state) }
    }
    /// Measured by `RefreshRateDetector` when the runner is created. 60 until the measurement finishes.
    private(set) var detectedHz = 60
    /// False when iOS reports no battery level (for example in the simulator): battery drain is then 0.
    private(set) var batterySupported = true

    var onStateChange: ((State) -> Void)?
    /// 0...1
    var onProgress: ((Double) -> Void)?
    /// liveFPS, peakFPS, minFPS (nil before the first sample), isThrottling, throttleDropPercent
    var onLiveStats: ((Double, Double, Double?, Bool, Int) -> Void)?
    var onComplete: ((BenchmarkResult) -> Void)?
    var onError: ((String) -> Void)?
    /// Called once on the main thread when the refresh rate measurement finishes, even if it equals the
    /// default 60. Set it right after creating the runner: the measurement needs at least 60 display frames.
    var onDetectedHz: ((Int) -> Void)?

    private let view: MTKView
    private let renderer: MetalRenderer?
    private let setupError: String?
    private let refreshRateDetector = RefreshRateDetector()
    /// Serial, so a new run never overlaps the CPU phase of a cancelled one.
    private let cpuQueue = DispatchQueue(label: "BenchmarkRunner.cpu", qos: .userInitiated)

    /// Bumped by `start` and `stop`: results of a cancelled run are ignored.
    private var runToken = 0
    private var runDuration: TimeInterval = 0
    private var startBatteryPercent = 100.0
    private var cpuOutcome: CPUOutcome?
    private var progressTimer: Timer?
    private var publishedSampleCount = 0

    init(view: MTKView) {
        self.view = view
        do {
            renderer = try MetalRenderer(view: view)
            setupError = nil
        } catch {
            renderer = nil
            setupError = error.localizedDescription
        }
        renderer?.onFinished = { [weak self] _ in self?.finishTest() }

        // Enabled early: right after enabling, the first battery read can still be -1.
        UIDevice.current.isBatteryMonitoringEnabled = true

        // Like RN: detect in the background once the view exists, not when the test starts.
        refreshRateDetector.detect { [weak self] hz in
            self?.detectedHz = hz
            self?.onDetectedHz?(hz)
        }
    }

    deinit {
        refreshRateDetector.cancel()
        progressTimer?.invalidate()
    }

    func start(durationSeconds: TimeInterval) {
        guard state == .idle || state == .done else { return }
        guard renderer != nil else {
            onError?(setupError ?? "Metal is unavailable.")
            return
        }

        runToken += 1
        let token = runToken
        runDuration = durationSeconds
        cpuOutcome = nil
        publishedSampleCount = 0

        let battery = Self.initialBattery(level: UIDevice.current.batteryLevel)
        startBatteryPercent = battery.percent
        batterySupported = battery.supported

        onProgress?(0)
        onLiveStats?(0, 0, nil, false, 0)
        // Like RN, stop the preview: drawing 4000 cubes must not compete with the CPU benchmark.
        view.isPaused = true
        state = .cpu

        let cores = ProcessInfo.processInfo.activeProcessorCount
        cpuQueue.async { [weak self] in
            let single = CPUBenchmark.runSingleCore(durationMs: Self.cpuTestDurationMs)
            let multi = CPUBenchmark.runMultiCore(cores: cores, durationMs: Self.cpuTestDurationMs)
            DispatchQueue.main.async {
                self?.cpuPhaseDidFinish(single: single, multi: multi, cores: cores, token: token)
            }
        }
    }

    /// Cancels the current run without calling `onComplete`.
    func stop() {
        guard state == .cpu || state == .running else { return }
        runToken += 1
        progressTimer?.invalidate()
        progressTimer = nil
        renderer?.stopMeasuring()
        view.isPaused = false
        cpuOutcome = nil
        onProgress?(0)
        state = .idle
    }

    // MARK: - Phases

    private func cpuPhaseDidFinish(single: CPUBenchmarkResult, multi: CPUBenchmarkResult, cores: Int, token: Int) {
        guard token == runToken, state == .cpu, let renderer else { return }

        cpuOutcome = CPUOutcome(
            singleCoreScore: single.score,
            multiCoreScore: Self.multiCoreScore(multi: multi, singleCoreScore: single.score),
            singleCoreWorkUnitsPerSec: single.workUnitsPerSec,
            multiCoreWorkUnitsPerSec: multi.workUnitsPerSec,
            cores: cores
        )

        view.isPaused = false
        state = .running
        renderer.startMeasuring(duration: runDuration)

        let timer = Timer(timeInterval: Self.progressInterval, repeats: true) { [weak self] _ in
            self?.publishProgress()
        }
        RunLoop.main.add(timer, forMode: .common)
        progressTimer = timer
    }

    private func publishProgress() {
        guard state == .running, let renderer else { return }
        let sampler = renderer.sampler
        onProgress?(min(1, max(0, sampler.elapsed / runDuration)))

        // Live stats only change when a new FPS sample arrives (every 500ms).
        if sampler.fpsArray.count != publishedSampleCount {
            publishedSampleCount = sampler.fpsArray.count
            onLiveStats?(
                sampler.liveFPS, sampler.peakFPS, sampler.minFPS,
                sampler.isThrottling, sampler.throttleDropPercent
            )
        }
    }

    private func finishTest() {
        guard state == .running, let renderer, let cpu = cpuOutcome else { return }
        progressTimer?.invalidate()
        progressTimer = nil
        onProgress?(1)
        state = .computing

        let drain = Self.batteryDrain(
            startPercent: startBatteryPercent,
            endLevel: UIDevice.current.batteryLevel,
            supported: batterySupported
        )
        let sampler = renderer.sampler
        var result = ScoreCalculator.calculate(
            fpsArray: sampler.fpsArray,
            frameTimesMs: sampler.frameTimesMs,
            batteryDrain: drain,
            singleCoreScore: cpu.singleCoreScore,
            multiCoreScore: cpu.multiCoreScore,
            targetHz: detectedHz,
            singleCoreWups: cpu.singleCoreWorkUnitsPerSec,
            multiCoreWups: cpu.multiCoreWorkUnitsPerSec,
            cpuCoresUsed: cpu.cores
        )
        result.fpsTimeline = sampler.fpsTimeline
        result.duration = runDuration
        result.detectedHz = detectedHz
        result.gpuRenderer = renderer.gpuRendererName

        state = .done
        onComplete?(result)
    }

    // MARK: - Pure logic

    /// `level` is `UIDevice.batteryLevel`: 0...1, or -1 when unsupported. Unsupported starts at 100 like RN.
    static func initialBattery(level: Float) -> (percent: Double, supported: Bool) {
        level < 0 ? (100, false) : (Double(level) * 100, true)
    }

    /// Percentage points lost during the test, rounded to 2 decimals. Never negative; 0 when unsupported.
    /// Values under 1 are returned as they are: showing "<1%" is up to the UI.
    static func batteryDrain(startPercent: Double, endLevel: Float, supported: Bool) -> Double {
        guard supported, endLevel >= 0 else { return 0 }
        let drain = max(0, startPercent - Double(endLevel) * 100)
        return (drain * 100).rounded() / 100
    }

    /// Falls back to the single-core score when the multi-core run did no work (same as RN).
    static func multiCoreScore(multi: CPUBenchmarkResult, singleCoreScore: Double) -> Double {
        multi.workUnits > 0 ? multi.score : singleCoreScore
    }
}
