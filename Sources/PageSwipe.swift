import Foundation

struct PageSwipe {
    private enum Axis { case undecided, horizontal, vertical }
    private var axis = Axis.undecided
    private var x: CGFloat = 0
    private var y: CGFloat = 0
    private var lastMotion: TimeInterval?
    private var velocity: CGFloat = 0

    mutating func track(dx: CGFloat, dy: CGFloat, at time: TimeInterval) -> CGFloat? {
        guard axis != .vertical, dx != 0 || dy != 0 else { return nil }
        x += dx
        y += dy
        if let lastMotion, time > lastMotion {
            let elapsed = time - lastMotion
            let sample = dx / CGFloat(elapsed)
            velocity = elapsed <= 0.08 ? velocity * 0.4 + sample * 0.6 : 0
        }
        lastMotion = time
        if axis == .undecided {
            if abs(x) >= 4 && abs(x) > abs(y) * 1.15 { axis = .horizontal }
            else if abs(y) >= 8 && abs(y) > abs(x) * 1.15 { axis = .vertical }
        }
        return axis == .horizontal ? x : nil
    }

    mutating func finish(at time: TimeInterval, cancelled: Bool = false) -> Int {
        defer { self = PageSwipe() }
        guard axis == .horizontal, !cancelled else { return 0 }
        // The gesture distance is in points, independent of the window width.
        let flick = lastMotion.map { time - $0 <= 0.08 } == true
            && abs(x) >= 10 && abs(velocity) >= 220 && velocity.sign == x.sign
        guard abs(x) >= 22 || flick else { return 0 }
        return x < 0 ? 1 : -1
    }
}
