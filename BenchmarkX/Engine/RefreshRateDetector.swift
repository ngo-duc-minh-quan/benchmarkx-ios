import QuartzCore
import UIKit

/// Measures the real display refresh rate with a CADisplayLink before the test starts.
final class RefreshRateDetector: NSObject {
    static let standardRates = [60, 90, 120, 144, 165, 240]
    private static let sampleCount = 60

    /// What iOS reports. For reference only: the measured value is the one to use.
    static var reportedMaximumFramesPerSecond: Int {
        UIScreen.main.maximumFramesPerSecond
    }

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var deltasMs: [Double] = []
    private var completion: ((Int) -> Void)?

    /// Calls `completion` once, on the main thread, with the snapped refresh rate.
    func detect(completion: @escaping (Int) -> Void) {
        guard displayLink == nil else { return }
        self.completion = completion
        lastTimestamp = nil
        deltasMs = []

        let link = CADisplayLink(target: self, selector: #selector(onFrame(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    /// Snaps a raw Hz value to the nearest standard rate.
    static func snap(_ rawHz: Double) -> Int {
        standardRates.min { abs(Double($0) - rawHz) < abs(Double($1) - rawHz) } ?? 60
    }

    /// Hz derived from the median frame delta. `deltasMs` must not be empty.
    static func rawHz(fromDeltasMs deltasMs: [Double]) -> Double {
        let sorted = deltasMs.sorted()
        return 1000 / sorted[sorted.count / 2]
    }

    @objc private func onFrame(_ link: CADisplayLink) {
        if let last = lastTimestamp {
            let deltaMs = (link.timestamp - last) * 1000
            if deltaMs > 0 { deltasMs.append(deltaMs) }
        }
        lastTimestamp = link.timestamp

        guard deltasMs.count >= Self.sampleCount else { return }

        // The display link retains its target: invalidate it or this object leaks.
        link.invalidate()
        displayLink = nil

        let hz = Self.snap(Self.rawHz(fromDeltasMs: deltasMs))
        let done = completion
        completion = nil
        done?(hz)
    }
}
