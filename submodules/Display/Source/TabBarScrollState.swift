import Foundation

public enum TabBarScrollMode: Int32 {
    case alwaysVisible = 0
    case hideOnScroll = 1
    case hideWhileScrolling = 2
    case hideOnAnyScroll = 3
}

// Desired visibility, independent of UIKit animation and content insets. Using
// finger translation avoids feedback when hiding the bar changes list layout.
public struct TabBarScrollState {
    public private(set) var mode: TabBarScrollMode = .alwaysVisible
    public private(set) var isHidden = false
    private var previousTranslation: Double?
    private var accumulated: Double = 0.0

    public init() {}

    public mutating func configure(mode: TabBarScrollMode) {
        self.mode = mode
        self.reset()
    }

    public mutating func reset() {
        self.isHidden = false
        self.previousTranslation = nil
        self.accumulated = 0.0
    }

    public mutating func beginGesture() {
        self.previousTranslation = 0.0
        self.accumulated = 0.0
    }

    public mutating func updateGesture(translation: Double, atTop: Bool = false) {
        // Keep the existing top-edge reveal in directional modes. In the
        // bidirectional mode, even a top-edge bounce stays hidden until stop.
        if atTop && self.mode != .hideOnAnyScroll {
            self.reset()
            return
        }
        guard self.mode != .alwaysVisible, translation.isFinite else { return }
        guard let previous = self.previousTranslation else {
            // A reset (e.g. overscroll at the top) can happen mid-gesture.
            // Resume from this translation without treating layout as movement.
            self.previousTranslation = translation
            return
        }
        self.previousTranslation = translation
        // Finger moving upward means scrolling down through the chat list.
        let delta = previous - translation
        guard delta != 0.0 else { return }
        if self.mode == .hideOnAnyScroll {
            self.isHidden = true
            return
        }
        if (delta > 0.0) != (self.accumulated > 0.0) { self.accumulated = 0.0 }
        self.accumulated += delta
        if !self.isHidden && self.accumulated >= 20.0 {
            self.isHidden = true
            self.accumulated = 0.0
        } else if self.isHidden && self.accumulated <= -8.0 {
            self.isHidden = false
            self.accumulated = 0.0
        }
    }

    public mutating func endScrolling() {
        self.previousTranslation = nil
        self.accumulated = 0.0
        if self.mode == .hideWhileScrolling || self.mode == .hideOnAnyScroll { self.isHidden = false }
    }
}
