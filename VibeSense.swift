import Cocoa
import ApplicationServices

struct VibeProject {
    let path: String
    let name: String
    let score: Double
}

struct VibeIndex {
    var weights: [String: Double] = [:]
    var pathWeights: [String: Double] = [:]
    var projects: [VibeProject] = []
    var isEmpty: Bool { weights.isEmpty }
    func weight(for token: String) -> Double { weights[token] ?? 0 }
}

struct VibeSettings {
    var roots = ["~/Desktop", "~/Documents", "~/Projects", "~/code", "~/dev", "~/src", "~/work"]
    var maxDepth = 4
    var maxDirs = 20_000
    var ancestorDecay = 0.7
    var ancestorLevels = 3
    var countBonus = 0.25
    var maxFolderScore = 10.0
    var windowRichness = 0.15
    var windowRichnessCap = 2.0
    var minScore = 1.0
    var ownerFallbackScore = 1.0
    var attractGain: CGFloat = 0.6
    var d0Divisor: CGFloat = 10
    var odorThreshold = 0.5
    var odorFull = 4.0
    var arousalFull = 8.0
    var opennessEditor = 1.4
    var opennessRow = 1.0
    var opennessIcon = 0.45
    var boutSeconds: CGFloat = 5
    var boutEverySeconds: CGFloat = 4
    var idleDrive: CGFloat = 0.6
    var windowTargets = true

    var markers: [String: Double] = [
        "AGENTS.md": 3, "AGENT.md": 3, "CLAUDE.md": 3, "CLAUDE.local.md": 3,
        "GEMINI.md": 3, "QWEN.md": 3, "WARP.md": 3, "CRUSH.md": 3,
        ".cursorrules": 3, ".cursor/rules": 3, ".windsurfrules": 3, ".windsurf": 3,
        ".clinerules": 3, ".claude": 3, ".github/copilot-instructions.md": 3,
        ".junie/guidelines.md": 2, ".kiro/steering": 2, ".amazonq/rules": 2,
        ".augment/rules": 2, ".trae/rules": 2, ".agent/rules": 2,
        ".aiassistant/rules": 2, ".idx/airules.md": 2, ".openhands/microagents": 2,
        ".goosehints": 2, ".aider.conf.yml": 2, ".roo": 2, ".kilocode": 2,
        "opencode.json": 2, ".codex": 2, ".gemini": 2, ".qwen": 2, ".zed": 2,
        "firebender.json": 2, ".factory": 2, ".vibe": 2,
        ".mcp.json": 1, "mcp.json": 1, ".cursorignore": 1, ".aiderignore": 1,
        ".specstory": 1, ".taskmaster": 1, ".serena": 1, ".memory-bank": 1,
    ]

    var prune: Set<String> = [
        "node_modules", ".git", "Library", "vendor", "Pods", ".build", "build",
        "dist", "target", ".venv", "venv", "DerivedData", ".next", ".cache",
        "Applications", "Public", "Movies", "Music", "Pictures",
    ]

    var genericTokens: Set<String> = [
        "src", "code", "dev", "work", "projects", "project", "documents",
        "desktop", "downloads", "repos", "repo", "git", "home", "users",
        "tmp", "temp", "app", "apps", "lib", "test", "tests",
    ]

    var windowOwners: Set<String> = [
        "Finder", "Code", "Code - Insiders", "Cursor", "Visual Studio Code",
        "Terminal", "iTerm2", "Ghostty", "Alacritty", "kitty", "WezTerm",
        "Warp", "Zed", "Xcode", "Windsurf", "Sublime Text", "Nova", "Emacs",
        "Android Studio", "IntelliJ IDEA", "PyCharm", "WebStorm", "GoLand",
        "RustRover", "CLion", "Positron", "Trae",
    ]

    static func load() -> VibeSettings {
        var s = VibeSettings()
        let path = ("~/.desktopfly.json" as NSString).expandingTildeInPath
        guard let data = FileManager.default.contents(atPath: path),
              let raw = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return s }
        if let v = raw["roots"] as? [String] { s.roots = v }
        if let v = raw["maxDepth"] as? Int { s.maxDepth = v }
        if let v = raw["ancestorDecay"] as? Double { s.ancestorDecay = v }
        if let v = raw["ancestorLevels"] as? Int { s.ancestorLevels = v }
        if let v = raw["minScore"] as? Double { s.minScore = v }
        if let v = raw["ownerFallbackScore"] as? Double { s.ownerFallbackScore = v }
        if let v = raw["attractGain"] as? Double { s.attractGain = CGFloat(v) }
        if let v = raw["d0Divisor"] as? Double { s.d0Divisor = CGFloat(v) }
        if let v = raw["odorThreshold"] as? Double { s.odorThreshold = v }
        if let v = raw["odorFull"] as? Double { s.odorFull = v }
        if let v = raw["arousalFull"] as? Double { s.arousalFull = v }
        if let v = raw["opennessEditor"] as? Double { s.opennessEditor = v }
        if let v = raw["opennessRow"] as? Double { s.opennessRow = v }
        if let v = raw["opennessIcon"] as? Double { s.opennessIcon = v }
        if let v = raw["boutSeconds"] as? Double { s.boutSeconds = CGFloat(v) }
        if let v = raw["boutEverySeconds"] as? Double { s.boutEverySeconds = CGFloat(v) }
        if let v = raw["idleDrive"] as? Double { s.idleDrive = CGFloat(v) }
        if let v = raw["windowTargets"] as? Bool { s.windowTargets = v }
        if let v = raw["countBonus"] as? Double { s.countBonus = v }
        if let v = raw["maxFolderScore"] as? Double { s.maxFolderScore = v }
        if let v = raw["windowRichness"] as? Double { s.windowRichness = v }
        if let v = raw["windowRichnessCap"] as? Double { s.windowRichnessCap = v }
        if let v = raw["markers"] as? [String: Double] { s.markers = v }
        if let v = raw["prune"] as? [String] { s.prune = Set(v) }
        if let v = raw["genericTokens"] as? [String] { s.genericTokens = Set(v.map { $0.lowercased() }) }
        if let v = raw["windowOwners"] as? [String] { s.windowOwners = Set(v) }
        return s
    }
}

let vibeDebug = ProcessInfo.processInfo.environment["DESKTOPFLY_VIBE"] != "0"

func vibeLog(_ s: String) {
    guard vibeDebug else { return }
    fputs("[vibe] \(s)\n", stderr)
}

func vibeNormalize(_ s: String) -> String {
    s.trimmingCharacters(in: CharacterSet(charactersIn: " \t●*◂▸•·")).lowercased()
}

func vibeTitleTokens(_ title: String) -> [String] {
    var s = title.replacingOccurrences(of: " - ", with: "|")
    for sep in ["—", "–", "·", "•", ":", "/", "\\", ",", "(", ")", "[", "]", "@"] {
        s = s.replacingOccurrences(of: sep, with: "|")
    }
    return s.split(separator: "|").map { vibeNormalize(String($0)) }.filter { !$0.isEmpty }
}

final class VibeSense {
    private let settings: VibeSettings
    private let lock = NSLock()
    private var current = VibeIndex()
    private let queue = DispatchQueue(label: "desktopfly.vibesense", qos: .utility)

    init(settings: VibeSettings) { self.settings = settings }

    func snapshot() -> VibeIndex { lock.lock(); defer { lock.unlock() }; return current }

    func rescan() {
        queue.async { [weak self] in
            guard let self else { return }
            let idx = self.build()
            self.lock.lock(); self.current = idx; self.lock.unlock()
            if vibeDebug {
                let top = idx.weights.sorted { $0.value > $1.value }.prefix(12)
                vibeLog("index (\(idx.projects.count) projects): "
                        + top.map { "\($0.key)=\(String(format: "%.1f", $0.value))" }.joined(separator: " "))
            }
        }
    }

    private func markerScore(dir: URL, children: Set<String>) -> Double {
        var score = 0.0
        let fm = FileManager.default
        for (marker, weight) in settings.markers {
            if marker.contains("/") {
                guard let head = marker.split(separator: "/").first,
                      children.contains(String(head)) else { continue }
                if fm.fileExists(atPath: dir.appendingPathComponent(marker).path) { score += weight }
            } else if children.contains(marker) {
                score += weight
            }
        }
        return score
    }

    private func build() -> VibeIndex {
        let fm = FileManager.default
        var projects: [VibeProject] = []
        var visited = Set<String>()
        var rootPaths = Set<String>()
        var budget = settings.maxDirs

        for rootSpec in settings.roots {
            let root = URL(fileURLWithPath: (rootSpec as NSString).expandingTildeInPath)
                .standardizedFileURL
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else { continue }
            rootPaths.insert(root.path)

            var stack: [(URL, Int)] = [(root, 0)]
            while let (dir, depth) = stack.popLast() {
                if budget <= 0 { break }
                budget -= 1
                guard visited.insert(dir.resolvingSymlinksInPath().path).inserted else { continue }
                guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
                let score = markerScore(dir: dir, children: Set(names))
                if score > 0 {
                    projects.append(VibeProject(path: dir.path, name: dir.lastPathComponent,
                                                score: score))
                }
                guard depth < settings.maxDepth else { continue }
                for n in names where !n.hasPrefix(".") && !settings.prune.contains(n) {
                    let child = dir.appendingPathComponent(n)
                    var d: ObjCBool = false
                    if fm.fileExists(atPath: child.path, isDirectory: &d), d.boolValue {
                        stack.append((child, depth + 1))
                    }
                }
            }
        }

        var best: [String: Double] = [:]
        var count: [String: Int] = [:]
        for p in projects {
            var url = URL(fileURLWithPath: p.path).standardizedFileURL
            var level = 0
            while level <= settings.ancestorLevels {
                let w = p.score * pow(settings.ancestorDecay, Double(level))
                best[url.path] = max(best[url.path] ?? 0, w)
                count[url.path, default: 0] += 1
                let parent = url.deletingLastPathComponent().standardizedFileURL
                if parent.path == url.path || rootPaths.contains(parent.path) { break }
                url = parent
                level += 1
            }
        }

        var index = VibeIndex(weights: [:], projects: projects)
        for (path, b) in best {
            let n = count[path] ?? 1
            let w = min(settings.maxFolderScore, b + settings.countBonus * Double(n - 1))
            index.pathWeights[path] = w
            let token = vibeNormalize(URL(fileURLWithPath: path).lastPathComponent)
            if !token.isEmpty, !settings.genericTokens.contains(token) {
                index.weights[token] = max(index.weights[token] ?? 0, w)
            }
        }
        return index
    }
}

struct IconTarget {
    let name: String
    let path: String
    let center: CGPoint
    let score: Double
    let openness: Double
}

final class FinderSense {
    private let lock = NSLock()
    private var icons: [IconTarget] = []
    private let queue = DispatchQueue(label: "desktopfly.findersense", qos: .utility)
    private var busy = false

    func snapshot() -> [IconTarget] { lock.lock(); defer { lock.unlock() }; return icons }

    func refresh(index: VibeIndex, screen: NSRect, primaryH: CGFloat, minScore: Double,
                 occluders: [CGRect], richness: Double, richnessCap: Double, cap: Double,
                 iconOpenness: Double, rowOpenness: Double) {
        lock.lock(); let running = busy; busy = true; lock.unlock()
        guard !running else { return }
        queue.async { [weak self] in
            guard let self else { return }
            let found = self.scan(index: index, screen: screen, primaryH: primaryH,
                                  minScore: minScore, occluders: occluders,
                                  richness: richness, richnessCap: richnessCap, cap: cap,
                                  iconOpenness: iconOpenness, rowOpenness: rowOpenness)
            self.lock.lock(); self.icons = found; self.busy = false; self.lock.unlock()
        }
    }

    private func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
    }

    private func children(_ el: AXUIElement) -> [AXUIElement] {
        (attr(el, kAXChildrenAttribute as String) as? [AXUIElement]) ?? []
    }

    private func rect(_ el: AXUIElement) -> CGRect? {
        guard let p = attr(el, kAXPositionAttribute as String),
              let s = attr(el, kAXSizeAttribute as String) else { return nil }
        var pt = CGPoint.zero, sz = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &pt),
              AXValueGetValue(s as! AXValue, .cgSize, &sz) else { return nil }
        return CGRect(origin: pt, size: sz)
    }

    private func scan(index: VibeIndex, screen: NSRect, primaryH: CGFloat,
                      minScore: Double, occluders: [CGRect],
                      richness: Double, richnessCap: Double, cap: Double,
                      iconOpenness: Double, rowOpenness: Double) -> [IconTarget] {
        guard axTrusted(), !index.pathWeights.isEmpty,
              let finder = NSRunningApplication
                .runningApplications(withBundleIdentifier: "com.apple.finder").first
        else { return [] }
        let app = AXUIElementCreateApplication(finder.processIdentifier)
        let desktop = (("~/Desktop") as NSString).expandingTildeInPath
        var out: [IconTarget] = []

        func walk(_ el: AXUIElement, _ depth: Int) {
            guard depth < 4, out.count < 60 else { return }
            for c in children(el) {
                let role = (attr(c, kAXRoleAttribute as String) as? String) ?? ""
                if role == "AXImage" {
                    let name = (attr(c, kAXTitleAttribute as String) as? String) ?? ""
                    guard !name.isEmpty, let r = rect(c) else { continue }
                    let path = desktop + "/" + name
                    let score = index.pathWeights[path] ?? 0
                    guard score >= minScore else { continue }
                    let center = CGPoint(x: r.midX - screen.midX,
                                         y: (primaryH - r.midY) - screen.midY)
                    guard !occluders.contains(where: { $0.contains(center) }) else { continue }
                    out.append(IconTarget(name: name, path: path, center: center, score: score,
                                          openness: iconOpenness))
                } else {
                    walk(c, depth + 1)
                }
            }
        }
        for w in children(app) {
            let role = (attr(w, kAXRoleAttribute as String) as? String) ?? ""
            if role == "AXScrollArea" { walk(w, 0) }
        }

        if let focused = attr(app, kAXFocusedWindowAttribute as String) {
            let win = focused as! AXUIElement
            var rows: [(String, CGRect)] = []
            collectRows(win, 0, &rows)
            var marked: [(String, CGRect, Double)] = []
            for (name, r) in rows {
                let w = index.weight(for: vibeNormalize(name))
                if w >= minScore { marked.append((name, r, w)) }
            }
            let mult = min(richnessCap, 1 + richness * Double(max(0, marked.count - 1)))
            for (name, r, w) in marked {
                let center = CGPoint(x: r.midX - screen.midX,
                                     y: (primaryH - r.midY) - screen.midY)
                out.append(IconTarget(name: name, path: "window:" + name, center: center,
                                      score: min(cap, w * mult), openness: rowOpenness))
            }
        }
        return out
    }

    private func collectRows(_ el: AXUIElement, _ depth: Int, _ out: inout [(String, CGRect)]) {
        guard depth < 12, out.count < 200 else { return }
        for c in children(el) {
            let role = (attr(c, kAXRoleAttribute as String) as? String) ?? ""
            let sub = children(c)
            if role == "AXGroup", sub.count == 2 {
                var name = ""
                var iconRect: CGRect?
                for s in sub {
                    let r = (attr(s, kAXRoleAttribute as String) as? String) ?? ""
                    if r == "AXImage" { iconRect = rect(s) }
                    if r == "AXTextField" { name = (attr(s, kAXValueAttribute as String) as? String) ?? "" }
                }
                if !name.isEmpty, let ir = iconRect {
                    out.append((name, ir))
                    continue
                }
            }
            collectRows(c, depth + 1, &out)
        }
    }
}
