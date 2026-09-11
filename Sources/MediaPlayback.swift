import AVFoundation
import SwiftUI

@MainActor
final class MediaPlayback: ObservableObject {
    enum State: Equatable { case idle, loading, playing, failed }
    @Published private(set) var player: AVPlayer?
    @Published private(set) var state: State = .idle
    @Published private(set) var elapsed: Double = 0
    private var task: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var observation: NSKeyValueObservation?
    private var timeObserver: Any?
    private var generation = 0
    private let diagnostics: DiagnosticsLog
    private var trace: [String: String] = [:]
    private var started = Date()
    init(diagnostics: DiagnosticsLog = .shared) { self.diagnostics = diagnostics }

    func start(_ url: URL, muted: Bool = false) {
        stop()
        state = .loading
        started = Date()
        trace = ["media_ref": diagnostics.reference(url.absoluteString), "muted": String(muted)]
        diagnostics.record(.mediaStart, trace)
        let epoch = generation
        task = Task { @MainActor [weak self] in
            do {
                let asset = AVURLAsset(url: url)
                guard try await asset.load(.isPlayable) else { throw URLError(.cannotDecodeContentData) }
                try Task.checkCancellation()
                guard let self, epoch == self.generation else { return }
                let item = AVPlayerItem(asset: asset)
                let player = AVPlayer(playerItem: item)
                player.isMuted = muted
                self.player = player
                self.observation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                    let failed = item.status == .failed
                    let ready = item.status == .readyToPlay
                    let error = item.error
                    Task { @MainActor in
                        guard let self, epoch == self.generation else { return }
                        if ready { self.diagnostics.record(.mediaReady, self.trace) }
                        if failed { self.fail(error, stage: "player") }
                    }
                }
                self.timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
                    Task { @MainActor in
                        guard let self, epoch == self.generation else { return }
                        let seconds = time.seconds
                        if seconds.isFinite && seconds > 0 {
                            if self.state != .playing {
                                self.diagnostics.record(.mediaPlaying, self.trace.merging(
                                    ["duration_ms": String(Date().timeIntervalSince(self.started) * 1_000)], uniquingKeysWith: { _, new in new }))
                            }
                            self.elapsed = seconds
                            self.state = .playing
                            self.watchdog?.cancel(); self.watchdog = nil
                        }
                    }
                }
                player.play()
            } catch is CancellationError { }
            catch { guard let self, epoch == self.generation else { return }; self.fail(error, stage: "asset") }
        }
        watchdog = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(25)) } catch { return }
            guard let self, self.generation == epoch, self.state == .loading else { return }
            self.fail(URLError(.timedOut), stage: "watchdog")
        }
    }
    private func fail(_ error: Error?, stage: String) {
        var fields = trace
        fields["stage"] = stage
        fields["duration_ms"] = String(Date().timeIntervalSince(started) * 1_000)
        if let error { fields.merge(DiagnosticsLog.errorFields(error), uniquingKeysWith: { _, new in new }) }
        diagnostics.record(.mediaFailed, fields)
        stop(); state = .failed
    }
    func stop() {
        if state != .idle {
            diagnostics.record(.mediaStopped, trace.merging(["duration_seconds": String(elapsed)], uniquingKeysWith: { _, new in new }))
        }
        trace = [:]
        generation += 1
        task?.cancel(); task = nil; watchdog?.cancel(); watchdog = nil
        observation?.invalidate(); observation = nil
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        player?.pause(); player = nil; elapsed = 0; state = .idle
    }
}
