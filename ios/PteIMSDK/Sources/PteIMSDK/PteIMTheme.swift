import Foundation

/**
 A platform-neutral appearance value. UIKit trait handling belongs to
 PteIMUIKit so the transport/storage SDK remains usable without a UI runtime.
 */
public enum PteIMTheme: Sendable, Equatable { case light, dark }
