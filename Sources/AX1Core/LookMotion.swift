import Foundation

/// Movement across the fixtures that show a look. The look's fixtures (enabled, following looks, without a fixed
/// warmth), in patch order, take turns being the lit one.
///
/// Motion only scales each fixture's level (its held note or level CC), so CC fades, group maximums and the
/// master still work: with the stage at 100% the lit tube is at full; with it at 50%, at half.
/// Steps follow MIDI clock when it arrives (24 pulses per beat, Song Position resets the phase). Without clock
/// they run at `bpm`, starting from the first step when the look is chosen.
public struct LookMotion: Codable, Equatable, Sendable {
    public enum Style: String, Codable, CaseIterable, Sendable {
        /// Only the lit fixture shows; the others are dark.
        case chase
        /// Every fixture shows; the others are at `dim` percent of their level.
        case highlight

        public var name: String { self == .chase ? "One at a time" : "One brighter" }
    }

    public enum Order: String, Codable, CaseIterable, Sendable {
        case forward, backward, bounce, outsideIn, insideOut, random

        public var name: String {
            switch self {
            case .forward: "1 → 4"
            case .backward: "4 → 1"
            case .bounce: "Bounce"
            case .outsideIn: "Outside in"
            case .insideOut: "Inside out"
            case .random: "Random"
            }
        }
    }

    public var style: Style
    public var order: Order
    /// Steps per beat: 0.5, 1, 2, 4…
    public var stepsPerBeat: Double
    /// For `highlight`: the other fixtures' brightness, 0–100 percent of their level.
    public var dim: UInt8
    /// Each step fades out over this fraction of a step (0 = hard steps, 1 = a smooth tail into the next step).
    public var tail: Double
    /// Tempo used when no MIDI clock is arriving.
    public var bpm: Double

    public init(style: Style = .chase, order: Order = .forward, stepsPerBeat: Double = 4, dim: UInt8 = 20,
                tail: Double = 0, bpm: Double = 120) {
        self.style = style
        self.order = order
        self.stepsPerBeat = stepsPerBeat
        self.dim = min(dim, 100)
        self.tail = tail
        self.bpm = bpm
    }

    private enum CodingKeys: String, CodingKey { case style, order, stepsPerBeat, dim, tail, bpm }

    public init(from decoder: Decoder) throws {
        let v = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            style: try v.decodeIfPresent(Style.self, forKey: .style) ?? .chase,
            order: try v.decodeIfPresent(Order.self, forKey: .order) ?? .forward,
            stepsPerBeat: try v.decodeIfPresent(Double.self, forKey: .stepsPerBeat) ?? 4,
            dim: try v.decodeIfPresent(UInt8.self, forKey: .dim) ?? 20,
            tail: try v.decodeIfPresent(Double.self, forKey: .tail) ?? 0,
            bpm: try v.decodeIfPresent(Double.self, forKey: .bpm) ?? 120
        )
    }

    public static let stepChoices: [(name: String, value: Double)] = [
        ("Every 2 beats", 0.5), ("Every beat", 1), ("8ths", 2), ("8th triplets", 3), ("16ths", 4), ("32nds", 8),
    ]

    /// The fixtures lit at each step, as indices into the fixtures taking part. One cycle of the pattern.
    public func steps(count n: Int) -> [[Int]] {
        guard n > 0 else { return [] }
        let all = Array(0..<n)
        switch order {
        case .forward: return all.map { [$0] }
        case .backward: return all.reversed().map { [$0] }
        case .bounce: return n < 3 ? all.map { [$0] } : (all + all.dropFirst().dropLast().reversed()).map { [$0] }
        case .outsideIn, .insideOut:
            var pairs = (0..<((n + 1) / 2)).map { i in Array(Set([i, n - 1 - i])).sorted() }
            if order == .insideOut { pairs.reverse() }
            return pairs.count < 3 ? pairs : pairs + pairs.dropFirst().dropLast().reversed()
        case .random:
            // A fixed shuffle so every bar of clock lines up the same way; never the same fixture twice in a row.
            var out: [[Int]] = []
            var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
            for _ in 0..<(n * 4) {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                var pick = Int((seed >> 33) % UInt64(n))
                if n > 1, pick == out.last?.first { pick = (pick + 1) % n }
                out.append([pick])
            }
            if n > 1, out.first == out.last { out[out.count - 1] = [(out.last![0] + 1) % n] }
            return out
        }
    }

    /// Brightness factor (0–1) for fixture `index` of `count` at `beats` into the motion.
    public func factor(index: Int, count: Int, beats: Double) -> Double {
        let pattern = steps(count: count)
        guard !pattern.isEmpty, stepsPerBeat > 0 else { return 1 }
        let position = max(0, beats) * stepsPerBeat
        let step = Int(position.rounded(.down))
        let within = position - Double(step)
        let floor = style == .chase ? 0 : Double(dim) / 100
        let current = pattern[step % pattern.count].contains(index)
        if current { return 1 }
        let t = min(1, max(0, tail))
        if t > 0 {
            let previous = pattern[((step - 1) % pattern.count + pattern.count) % pattern.count].contains(index)
            if previous, within < t { return floor + (1 - floor) * (1 - within / t) }
        }
        return floor
    }
}
