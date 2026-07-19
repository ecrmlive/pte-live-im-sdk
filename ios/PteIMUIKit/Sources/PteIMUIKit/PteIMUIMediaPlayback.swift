import AVFoundation

/**
 A UIKit-wide exclusive media coordinator. Starting a voice or video playback
 stops the current one first, including playback owned by another chat screen.
 */
@MainActor
public final class PteIMUIMediaPlayback {
  public static let shared = PteIMUIMediaPlayback()
  private var activeIdentifier: String?
  private var voicePlayer: AVPlayer?
  private weak var videoPlayer: AVPlayer?

  private init() {}

  public func playVoice(identifier: String, url: URL) {
    if activeIdentifier == identifier, voicePlayer != nil { stop(); return }
    stop()
    let player = AVPlayer(url: url)
    activeIdentifier = identifier
    voicePlayer = player
    player.play()
  }

  public func activateVideo(identifier: String, player: AVPlayer) {
    if activeIdentifier != identifier { stop() }
    activeIdentifier = identifier
    videoPlayer = player
  }

  public func release(identifier: String) {
    guard activeIdentifier == identifier else { return }
    clear()
  }

  public func stop() {
    voicePlayer?.pause()
    videoPlayer?.pause()
    clear()
  }

  private func clear() {
    voicePlayer = nil
    videoPlayer = nil
    activeIdentifier = nil
  }
}
