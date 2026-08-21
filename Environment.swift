// Environment.swift — promptless macOS senses for the fly:
// window terrain + window-appearance looms (CGWindowList), circadian clock,
// user-idle detection (CGEventSource), and thermal-state "temperature".
// None of these trigger a TCC permission dialog.

import Cocoa
import ApplicationServices

func axTrusted() -> Bool { AXIsProcessTrusted() }

// The prompt is only shown once per binary by TCC, so also deep-link the pane.
func axRequestAccess() {
    let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security"
                   + "?Privacy_Accessibility") {
        NSWorkspace.shared.open(u)
    }
}

// A walkable window top edge, in scene coordinates (origin at screen center).
struct Ledge {
    let y: CGFloat
    let x0: CGFloat
    let x1: CGFloat
    let id: Int
}

struct VibeTarget {
    let center: CGPoint
    let topY: CGFloat
    let score: Double
    let token: String
    let owner: String
    let openness: Double
    let id: String
}

final class WindowSense {
    struct Snapshot {
        let ledges: [Ledge]
        let newWindows: [(center: CGPoint, size: CGFloat)]
        let vibe: [VibeTarget]
        let occluders: [CGRect]
    }

    private var knownIDs = Set<Int>()
    private var first = true
    private let myPID = NSRunningApplication.current.processIdentifier

    func poll(screen: NSRect, index: VibeIndex = VibeIndex(),
              settings: VibeSettings = VibeSettings()) -> Snapshot {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else {
            return Snapshot(ledges: [], newWindows: [], vibe: [], occluders: [])
        }
        // CG global coords are top-left-of-primary; Cocoa are bottom-left-of-primary.
        let primaryH = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? screen.height
        let W = screen.width, H = screen.height
        var ledges: [Ledge] = []
        var newWins: [(CGPoint, CGFloat)] = []
        var vibe: [VibeTarget] = []
        var occluders: [CGRect] = []
        var ids = Set<Int>()
        for w in info {
            guard (w["kCGWindowLayer"] as? Int) == 0,                     // normal windows only
                  (w["kCGWindowOwnerPID"] as? Int32) != myPID,
                  ((w["kCGWindowAlpha"] as? Double) ?? 1) > 0.05,
                  let b = w["kCGWindowBounds"] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: b as CFDictionary),
                  rect.width >= 160, rect.height >= 60,
                  let num = w["kCGWindowNumber"] as? Int else { continue }
            ids.insert(num)
            // only windows on the fly's current display
            let cocoaRect = NSRect(x: rect.minX, y: primaryH - rect.maxY,
                                   width: rect.width, height: rect.height)
            guard cocoaRect.intersects(screen) else { continue }
            // scene coords: centered on this display, y up
            let topY = (primaryH - rect.minY) - screen.midY
            let x0 = max(rect.minX - screen.midX, -W / 2 + 15)
            let x1 = min(rect.maxX - screen.midX, W / 2 - 15)
            if topY < H / 2 - 8, topY > -H / 2 + 8, x1 - x0 > 100, ledges.count < 12 {
                ledges.append(Ledge(y: topY, x0: x0, x1: x1, id: num))
            }
            let center = CGPoint(x: rect.midX - screen.midX,
                                 y: (primaryH - rect.midY) - screen.midY)
            let covered = occluders.contains { $0.contains(center) }
            occluders.append(CGRect(x: rect.minX - screen.midX,
                                    y: (primaryH - rect.maxY) - screen.midY,
                                    width: rect.width, height: rect.height))
            if !first && !knownIDs.contains(num) {
                newWins.append((center, max(rect.width, rect.height)))
            }
            if !index.isEmpty, let owner = w["kCGWindowOwnerName"] as? String {
                let title = (w["kCGWindowName"] as? String) ?? ""
                guard settings.windowOwners.contains(owner) else { continue }
                var best = 0.0
                var bestToken = ""
                for tok in vibeTitleTokens(title) where index.weight(for: tok) > best {
                    best = index.weight(for: tok)
                    bestToken = tok
                }
                if title.isEmpty && best == 0 {
                    best = settings.ownerFallbackScore
                    bestToken = "owner:" + owner
                }
                if best >= settings.minScore, !covered {
                    vibe.append(VibeTarget(center: center, topY: topY, score: best,
                                           token: bestToken, owner: owner,
                                           openness: settings.opennessEditor,
                                           id: "win:\(num)"))
                }
            }
        }
        knownIDs = ids
        first = false
        return Snapshot(ledges: ledges, newWindows: newWins, vibe: vibe, occluders: occluders)
    }
}

// Drosophila circadian activity: morning and evening peaks, midday siesta,
// night quiescence. Returns a multiplier for the sim's baseline drive.
func circadianActivity(hour: Double) -> Float {
    let pts: [(Double, Float)] = [(0, 0.25), (5, 0.25), (8, 1.0), (10, 1.0), (13, 0.55),
                                  (15, 0.55), (17, 1.0), (20, 1.0), (23, 0.3), (24, 0.25)]
    for i in 0..<(pts.count - 1) where hour >= pts[i].0 && hour <= pts[i + 1].0 {
        let t = Float((hour - pts[i].0) / max(0.001, pts[i + 1].0 - pts[i].0))
        return pts[i].1 + (pts[i + 1].1 - pts[i].1) * t
    }
    return 0.25
}

// Seconds since the user last touched mouse or keyboard. CGEventSource idle
// queries are permission-free (they reveal when, never what).
func userIdleSeconds() -> CGFloat {
    let types: [CGEventType] = [.mouseMoved, .leftMouseDown, .keyDown, .scrollWheel]
    let idles = types.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
    return CGFloat(idles.min() ?? 0)
}

// Flies are ectotherms: a hot Mac is a fast fly.
func thermalTempo() -> CGFloat {
    switch ProcessInfo.processInfo.thermalState {
    case .nominal: return 1.0
    case .fair: return 1.15
    case .serious: return 1.35
    case .critical: return 1.5
    @unknown default: return 1.0
    }
}
