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

    func start(_ url: URL, muted: Bool = false) {
        stop()
        state = .loading
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
                    Task { @MainActor in
                        guard let self, epoch == self.generation, failed else { return }
                        self.fail()
                    }
                }
                self.timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
                    Task { @MainActor in
                        guard let self, epoch == self.generation else { return }
                        let seconds = time.seconds
                        if seconds.isFinite && seconds > 0 {
                            self.elapsed = seconds
                            self.state = .playing
                            self.watchdog?.cancel(); self.watchdog = nil
                        }
                    }
                }
                player.play()
            } catch is CancellationError { }
            catch { guard let self, epoch == self.generation else { return }; self.fail() }
        }
        watchdog = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(25)) } catch { return }
            guard let self, self.generation == epoch, self.state == .loading else { return }
            self.fail()
        }
    }
    private func fail() { stop(); state = .failed }
    func stop() {
        generation += 1
        task?.cancel(); task = nil; watchdog?.cancel(); watchdog = nil
        observation?.invalidate(); observation = nil
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        player?.pause(); player = nil; elapsed = 0; state = .idle
    }
}
