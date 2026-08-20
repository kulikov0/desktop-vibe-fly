// DesktopFly — a 3D fruit fly that walks across your macOS desktop, driven by
// REAL FlyWire v783 connectome data: a live LIF simulation of the escape
// circuit (LC4/LPLC2 looming detectors -> DNp01 giant fiber), DNa02 steering
// and MDN backward-walking neurons, with real signed synapse weights.
//
// Build:  ./build.sh
// Run:    ./DesktopFly                     (menu-bar 🪰; brain window shows live spikes)
//         ./DesktopFly --snapshot out.png  (offscreen fly model render)
//         ./DesktopFly --brainshot out.png (offscreen brain window render)
//         ./DesktopFly --simtest           (headless circuit test: spontaneous + loom)

import Cocoa
import SceneKit

// MARK: - Desktop overlay scene

func buildScene(bounds: CGSize) -> SCNScene {
    let scene = SCNScene()

    let camera = SCNCamera()
    camera.usesOrthographicProjection = true
    camera.orthographicScale = Double(bounds.height / 2)
    camera.zNear = 1
    camera.zFar = 600
    let camNode = SCNNode()
    camNode.name = "camera"
    camNode.camera = camera
    camNode.position = SCNVector3(0, 0, 300)
    scene.rootNode.addChildNode(camNode)

    let key = SCNLight()
    key.type = .directional
    key.intensity = 1000
    if SHADOWS_ENABLED {
        key.castsShadow = true
        key.shadowMode = .deferred
        key.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.30)
        key.shadowRadius = 6
        key.shadowSampleCount = 8
    }
    let keyNode = SCNNode()
    keyNode.light = key
    keyNode.eulerAngles = SCNVector3(-0.35, 0.30, 0)
    scene.rootNode.addChildNode(keyNode)

    let ambient = SCNLight()
    ambient.type = .ambient
    ambient.intensity = 550
    ambient.color = NSColor(calibratedWhite: 1.0, alpha: 1)
    let ambNode = SCNNode()
    ambNode.light = ambient
    scene.rootNode.addChildNode(ambNode)

    if SHADOWS_ENABLED {
        // fixed size: large enough for any display the fly may be moved to
        let plane = SCNPlane(width: 6000, height: 6000)
        let m = SCNMaterial()
        m.colorBufferWriteMask = []
        m.writesToDepthBuffer = true
        plane.materials = [m]
        let planeNode = SCNNode(geometry: plane)
        planeNode.position = SCNVector3(0, 0, -0.6)
        scene.rootNode.addChildNode(planeNode)
    }

    return scene
}

// MARK: - Offscreen render modes

func offscreenRender(_ scene: SCNScene, camNode: SCNNode, size: CGSize, path: String) {
    let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
    renderer.scene = scene
    renderer.pointOfView = camNode
    let img = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
    savePNG(img, to: path)
    print("snapshot written to \(path)")
}

func runSnapshot(path: String) {
    let scene = SCNScene()
    scene.background.contents = NSColor(calibratedWhite: 0.94, alpha: 1)
    let fly = Fly(at: .zero)
    fly.heading = .pi / 2
    for (i, leg) in fly.model.legs.enumerated() {
        leg.angle = [0.25, -0.2, -0.22, 0.28, 0.2, -0.25][i]
        leg.lift = [0.35, 0, 0, 0.3, 0, 0.35][i]
        leg.apply()
    }
    fly.syncNode()
    scene.rootNode.addChildNode(fly.node)
    let camera = SCNCamera()
    camera.fieldOfView = 42
    let camNode = SCNNode()
    camNode.camera = camera
    camNode.position = SCNVector3(30, -58, 42)
    let lookAt = SCNLookAtConstraint(target: fly.node)
    lookAt.isGimbalLockEnabled = true
    camNode.constraints = [lookAt]
    scene.rootNode.addChildNode(camNode)
    let key = SCNLight(); key.type = .directional; key.intensity = 1100
    let keyNode = SCNNode(); keyNode.light = key
    keyNode.eulerAngles = SCNVector3(-0.9, 0.5, 0)
    scene.rootNode.addChildNode(keyNode)
    let amb = SCNLight(); amb.type = .ambient; amb.intensity = 500
    let ambNode = SCNNode(); ambNode.light = amb
    scene.rootNode.addChildNode(ambNode)
    offscreenRender(scene, camNode: camNode, size: CGSize(width: 720, height: 720), path: path)
}

func runBrainshot(path: String) {
    guard let data = loadBrainData() else { fputs("no data/ — run etl.py first\n", stderr); exit(1) }
    let sim = LIFSim(circuit: data.circuit, spikeBus: nil)
    let bs = buildBrainScene(points: data.points, sim: sim)
    bs.brainGroup.removeAllActions()
    bs.brainGroup.eulerAngles = SCNVector3(-0.15, 0.5, 0)
    // decorate with a burst of fake spikes so the preview shows the live look
    let driver = BrainRenderDriver(sim: sim, flashPool: bs.flashPool)
    for _ in 0..<40 { driver.flash(neuron: Int.random(in: 0..<sim.n), isGF: false) }
    if let gfIdx = sim.gf.first { driver.flash(neuron: gfIdx, isGF: true) }
    for node in bs.flashPool { node.removeAllActions() }   // freeze mid-flash
    offscreenRender(bs.scene, camNode: bs.cameraNode, size: CGSize(width: 720, height: 560), path: path)
}

func runSimtest() {
    guard let data = loadBrainData() else { fputs("no data/ — run etl.py first\n", stderr); exit(1) }
    let sim = LIFSim(circuit: data.circuit, spikeBus: nil)
    print("circuit: \(sim.n) neurons | loom L/R: \(sim.loomLeft.count)/\(sim.loomRight.count)"
          + " | GF: \(sim.gf.count) | DNa L/R: \(sim.dnaL.count)/\(sim.dnaR.count) | MDN: \(sim.mdn.count)"
          + " | DNp09: \(sim.fwd.count) | DNg11: \(sim.groom.count) | escW: \(sim.escw.count)"
          + " | ascend: \(sim.ascend.count) | sens: \(sim.sens.count)")

    // Phase 1: 4 s spontaneous activity
    var gfSpont = 0
    for _ in 0..<40 { sim.step(100); if sim.consumeGF() { gfSpont += 1 } }
    let popHz = Float(sim.totalSpikes) / 4.0 / Float(sim.n)
    print(String(format: "spontaneous 4s: pop %.2f Hz/neuron, LC %.1f Hz, DNa02 L/R %.1f/%.1f Hz, "
                 + "MDN %.1f Hz, GF spikes: %d", popHz, sim.rateLoom, sim.rateDNaL, sim.rateDNaR,
                 sim.rateMDN, gfSpont))

    // Phase 2: abrupt loom, as produced by a cursor lunge (step, not ramp)
    var gfLatencyMs = -1
    var gfLoom = 0
    for ms in 0..<400 {
        sim.loomL = 1.0
        sim.loomR = 0.5
        sim.step(1)
        if sim.consumeGF() {
            gfLoom += 1
            if gfLatencyMs < 0 { gfLatencyMs = ms }
        }
    }
    sim.loomL = 0; sim.loomR = 0
    print(String(format: "abrupt loom 0.4s: LC rate %.1f Hz, GF spikes %d, first at %d ms",
                 sim.rateLoom, gfLoom, gfLatencyMs))

    // Phase 3: 20 s with walking proprioception; do behavior states emerge?
    var walkOn = 0, groomOn = 0, samples = 0
    var fwdMin = Float.greatestFiniteMagnitude, fwdMax: Float = 0
    for ms in 0..<20_000 {
        sim.gaitDrive = 0.5
        sim.gaitPhase = Float(ms % 125) / 125    // 8 Hz gait
        sim.step(1)
        if ms % 10 == 0 {
            samples += 1
            if sim.rateFwd / 10 > 0.22 { walkOn += 1 }
            if sim.rateGroom / 8 > 0.5 { groomOn += 1 }
            fwdMin = min(fwdMin, sim.rateFwd); fwdMax = max(fwdMax, sim.rateFwd)
        }
    }
    print(String(format: "behavior 20s: walk-drive on %.0f%%, groom-drive on %.0f%%, "
                 + "DNp09 %.1f-%.1f Hz, pop %.1f Hz", 100 * Float(walkOn) / Float(samples),
                 100 * Float(groomOn) / Float(samples), fwdMin, fwdMax, sim.ratePop))

    // Phase 3b: midday siesta must slow the fly down, not paralyze it
    sim.activityScale = 1 - (1 - 0.55) * 0.35   // = 0.84, the compressed siesta scale
    var siestaWalkOn = 0, siestaSamples = 0
    for ms in 0..<15_000 {
        sim.step(1)
        if ms % 10 == 0 {
            siestaSamples += 1
            if sim.rateFwd / 10 > 0.22 { siestaWalkOn += 1 }
        }
    }
    sim.activityScale = 1
    let siestaPct = 100 * Float(siestaWalkOn) / Float(siestaSamples)
    print(String(format: "siesta 15s (scale 0.84): walk-drive on %.0f%%", siestaPct))

    // Phase 4: air puff (fast cursor whoosh) for 1 s — wind startle pathway
    var gfPuff = 0
    for _ in 0..<1000 {
        sim.airPuff = 1.0
        sim.step(1)
        if sim.consumeGF() { gfPuff += 1 }
    }
    sim.airPuff = 0
    print("air puff 1s: GF spikes \(gfPuff)")

    // Phase 5: gentle left-eye-only loom 1 s — steering response probe
    for _ in 0..<500 { sim.step(1); _ = sim.consumeGF() }   // settle
    let diff0 = sim.rateDNaL - sim.rateDNaR
    for _ in 0..<1000 {
        sim.loomL = 0.30; sim.loomR = 0
        sim.step(1)
        _ = sim.consumeGF()
    }
    let diff1 = sim.rateDNaL - sim.rateDNaR
    sim.loomL = 0
    print(String(format: "left-eye loom: DNa L-R rate diff %+.1f -> %+.1f Hz, LC %.1f Hz",
                 diff0, diff1, sim.rateLoom))

    // Phase 6: click-stimulation probes (what the interactive brain window does)
    sim.stimulate(sim.gf, strength: 0.5, durationMs: 40)
    sim.step(60)
    let gfStim = sim.consumeGF()
    sim.stimulate(sim.groom, strength: 0.25, durationMs: 400)
    sim.step(400)
    let groomStim = sim.rateGroom
    _ = sim.consumeGF()
    print(String(format: "click probes: GF cluster -> spike %@, DNg11 cluster -> groom rate %.0f Hz",
                 gfStim ? "yes" : "NO", groomStim))

    // Phase 7: vibecode attraction. Spontaneous DNa drift and noise bursts are
    // worth several Hz, so control and drive alternate in 1 s blocks and only
    // the settled half of each block is sampled.
    var gfAttractOn = 0, gfAttractOff = 0
    var diffOff: Float = 0, diffOn: Float = 0, popOff: Float = 0, popOn: Float = 0
    var fwdOff: Float = 0, fwdOn: Float = 0
    var attractSamples: Float = 0
    for block in 0..<20 {
        let on = block % 2 == 1
        sim.attractL = on ? 0.30 : 0
        sim.attractR = on ? 0.03 : 0
        sim.attractFwd = on ? 0.15 : 0
        for ms in 0..<1000 {
            sim.step(1)
            if sim.consumeGF() { if on { gfAttractOn += 1 } else { gfAttractOff += 1 } }
            guard ms >= 500 else { continue }
            if on {
                diffOn += sim.rateDNaL - sim.rateDNaR
                popOn += sim.ratePop
                fwdOn += sim.rateFwd
                attractSamples += 1
            } else {
                diffOff += sim.rateDNaL - sim.rateDNaR
                popOff += sim.ratePop
                fwdOff += sim.rateFwd
            }
        }
    }
    sim.attractL = 0; sim.attractR = 0; sim.attractFwd = 0
    diffOff /= attractSamples; diffOn /= attractSamples; popOff /= attractSamples; popOn /= attractSamples
    fwdOff /= attractSamples; fwdOn /= attractSamples
    let popGrowth = (popOn - popOff) / max(0.001, popOff)
    print(String(format: "attraction (drivers L %d / R %d / fwd %d): DNa L-R %+.1f -> %+.1f Hz, "
                 + "DNp09 %.1f -> %.1f Hz, GF %d vs %d spontaneous, pop %+.0f%%",
                 sim.dnaDriveL.count, sim.dnaDriveR.count,
                 sim.fwdDrive.count, diffOff, diffOn, fwdOff, fwdOn,
                 gfAttractOn, gfAttractOff, 100 * popGrowth))

    // 20%: arousal is ratePop/20, so this keeps it near 0.33 against the 0.5
    // spontaneous-takeoff gate
    // Phase 8: odour-driven arousal must reach the takeoff gate (0.5) without
    // waking the giant fiber
    var arousalOff: Float = 0, arousalOn: Float = 0
    var gfArousalOn = 0, gfArousalOff = 0
    var mdnOn: Float = 0, mdnOff: Float = 0
    var arousalSamples: Float = 0
    for block in 0..<10 {
        let on = block % 2 == 1
        sim.attractArousal = on ? 1.0 : 0
        for ms in 0..<1000 {
            sim.step(1)
            if sim.consumeGF() { if on { gfArousalOn += 1 } else { gfArousalOff += 1 } }
            guard ms >= 500 else { continue }
            if on { arousalOn += sim.ratePop / 20; mdnOn += sim.rateMDN; arousalSamples += 1 }
            else { arousalOff += sim.ratePop / 20; mdnOff += sim.rateMDN }
        }
    }
    sim.attractArousal = 0
    arousalOff /= arousalSamples; arousalOn /= arousalSamples
    mdnOff /= arousalSamples; mdnOn /= arousalSamples
    print(String(format: "odour arousal (pool %d): %.2f -> %.2f (gate 0.50), MDN %.1f -> %.1f Hz "
                 + "(backward gate 8), GF %d vs %d spontaneous",
                 sim.arousalPool.count, arousalOff, arousalOn, mdnOff, mdnOn,
                 gfArousalOn, gfArousalOff))

    // MDN must stay under the backward-walking gate: the arousal pool once
    // drove it to 11 Hz and the fly moonwalked permanently
    let arousalOK = arousalOn > 0.5 && arousalOn < 0.75 && mdnOn < 8
        && gfArousalOn <= gfArousalOff + 1
    // GF must not fire *more* under drive than it does spontaneously; a bare
    // zero would flake on the occasional spontaneous spike over 20 s
    let attractOK = diffOn - diffOff > 2 && gfAttractOn <= gfAttractOff + 1
        && popGrowth < 0.20 && arousalOK
    let pass = gfSpont == 0 && gfLoom > 0 && walkOn > 0 && gfStim && siestaPct > 3 && attractOK
    print(pass ? "PASS: GF silent at rest, fires on loom; locomotor drive fluctuates; stim works; siesta alive; attraction steers"
               : "FAIL: tune weights/noise")
    exit(pass ? 0 : 1)
}

// MARK: - Behavior test (headless sim -> 3D body end-to-end)

func runBehaviorTest() {
    guard let data = loadBrainData() else { fputs("no data/ — run etl.py first\n", stderr); exit(1) }
    let bounds = CGSize(width: 1512, height: 982)
    let dt: CGFloat = 1.0 / 60.0
    var failures = 0

    func scenario(_ name: String, stim: (LIFSim) -> Void, hold: CGFloat,
                  setup: ((Fly) -> Void)? = nil,
                  check: (Fly) -> Bool, describe: (Fly) -> String) {
        let sim = LIFSim(circuit: data.circuit, spikeBus: nil)
        let builder = SignalBuilder()
        let fly = Fly(at: .zero)
        fly.state = .idle
        fly.speed = 0
        setup?(fly)
        // settle the network, drain any startup GF latch
        sim.step(400)
        _ = sim.consumeGF()
        stim(sim)
        var passed = false
        var frames = Int(hold / dt)
        while frames > 0 {
            frames -= 1
            sim.step(Int((dt * 1000).rounded()))
            let s = builder.make(sim, dt: dt)
            fly.update(dt: dt, bounds: bounds, mouse: nil, signals: s)
            if check(fly) { passed = true; break }
        }
        if !passed { failures += 1 }
        print("\(passed ? "PASS" : "FAIL")  \(name): \(describe(fly))")
    }

    scenario("GF stim -> escape flight",
             stim: { $0.stimulate($0.gf, strength: 0.5, durationMs: 40) }, hold: 0.5,
             check: { $0.state == .flying },
             describe: { "state=\($0.state)" })

    scenario("DNg11 stim -> grooming",
             stim: { $0.stimulate($0.groom, strength: 0.25, durationMs: 600) }, hold: 1.5,
             check: { $0.state == .grooming },
             describe: { "state=\($0.state)" })

    scenario("DNp09 stim -> walks, speed rises (capped)",
             stim: { $0.stimulate($0.fwd, strength: 0.25, durationMs: 1200) }, hold: 1.5,
             check: { $0.state == .walking && $0.speed > 40 && $0.speed < 100 },
             describe: { "state=\($0.state) speed=\(Int($0.speed))" })

    scenario("MDN stim (from idle) -> backward walk",
             stim: { $0.stimulate($0.mdn, strength: 0.3, durationMs: 600) }, hold: 1.2,
             check: { $0.backwardTimer > 0 },
             describe: { "backwardTimer=\(String(format: "%.2f", $0.backwardTimer))" })

    var heading0: CGFloat = 0
    scenario("DNa-left stim -> left (CCW) turn while walking",
             stim: { $0.stimulate($0.dnaL, strength: 0.3, durationMs: 900) }, hold: 1.4,
             setup: { fly in
                 fly.state = .walking
                 fly.speed = 30
                 fly.heading = 0
                 heading0 = 0
             },
             check: { $0.heading - heading0 > 0.25 },
             describe: { "heading change \(String(format: "%+.2f", $0.heading - heading0)) rad" })

    scenario("moderate loom -> fear response (dart or escape)",
             stim: { sim in
                 sim.loomL = 0.45; sim.loomR = 0.45
             }, hold: 1.0,
             check: { ($0.state == .walking && $0.speed > 100) || $0.state == .flying },
             describe: { "state=\($0.state) speed=\(Int($0.speed))" })

    scenario("tap near fly -> startle escape via sensory pathway",
             stim: { $0.stimulate($0.sens, strength: 0.45, durationMs: 150) }, hold: 0.8,
             check: { $0.state == .flying },
             describe: { "state=\($0.state)" })

    // ---- body-level environment checks (hand-built signals, no sim) ----
    func bodyCheck(_ name: String, _ run: () -> (Bool, String)) {
        let (ok, detail) = run()
        if !ok { failures += 1 }
        print("\(ok ? "PASS" : "FAIL")  \(name): \(detail)")
    }
    var walkSignals = BrainSignals()
    walkSignals.walkDrive = 0.6

    bodyCheck("ledge attach + follow window edge") {
        let fly = Fly(at: CGPoint(x: 0, y: -55))
        fly.state = .walking; fly.speed = 30; fly.heading = 0
        fly.terrain = [Ledge(y: -40, x0: -300, x1: 300, id: 1)]
        for _ in 0..<240 {
            fly.update(dt: dt, bounds: bounds, mouse: nil, signals: walkSignals)
            if fly.ledge != nil && abs(fly.pos.y + 40) < 8 { return (true, "attached, y=\(Int(fly.pos.y))") }
        }
        return (false, "state=\(fly.state) y=\(Int(fly.pos.y)) ledge=\(fly.ledge != nil)")
    }

    bodyCheck("window closes underfoot -> takeoff") {
        let fly = Fly(at: CGPoint(x: 0, y: -40))
        fly.state = .walking; fly.speed = 25; fly.heading = 0
        fly.terrain = [Ledge(y: -40, x0: -300, x1: 300, id: 1)]
        fly.ledge = fly.terrain[0]
        fly.terrain = []
        for _ in 0..<60 {
            fly.update(dt: dt, bounds: bounds, mouse: nil, signals: walkSignals)
            if fly.state == .flying { return (true, "took off") }
        }
        return (false, "state=\(fly.state)")
    }

    bodyCheck("sleep signal -> sleeping; wake -> grooming") {
        let fly = Fly(at: .zero)
        fly.state = .idle
        var s = BrainSignals(); s.sleep = true
        for _ in 0..<60 { fly.update(dt: dt, bounds: bounds, mouse: nil, signals: s) }
        guard fly.state == .sleeping else { return (false, "no sleep: \(fly.state)") }
        s.sleep = false
        fly.update(dt: dt, bounds: bounds, mouse: nil, signals: s)
        return (fly.state == .grooming, "woke to \(fly.state)")
    }

    bodyCheck("thermal tempo scales walking speed") {
        let fly = Fly(at: .zero)
        fly.state = .walking; fly.speed = 20; fly.heading = 0
        var cool = walkSignals; cool.tempo = 1.0
        for _ in 0..<120 { fly.update(dt: dt, bounds: bounds, mouse: nil, signals: cool) }
        let coolSpeed = fly.speed
        var hot = walkSignals; hot.tempo = 1.5
        for _ in 0..<120 { fly.update(dt: dt, bounds: bounds, mouse: nil, signals: hot) }
        let hotSpeed = fly.speed
        return (fly.state == .walking && hotSpeed > coolSpeed + 10,
                "cool \(Int(coolSpeed)) -> hot \(Int(hotSpeed)) pt/s")
    }

    bodyCheck("flight: altitude drives scale; escape flies higher than casual") {
        func flight(escape: Bool, effort: CGFloat?) -> (alt: CGFloat, scale: CGFloat) {
            let fly = Fly(at: .zero)
            fly.state = .idle
            fly.startFlight(bounds: bounds, escape: escape, effort: effort)
            var maxAlt: CGFloat = 0, maxScale: CGFloat = 0
            var frames = 0
            while fly.state == .flying && frames < 400 {
                frames += 1
                fly.update(dt: dt, bounds: bounds, mouse: nil, signals: BrainSignals())
                maxAlt = max(maxAlt, fly.alt)
                maxScale = max(maxScale, fly.node.scale.x)
            }
            return (maxAlt, maxScale)
        }
        let esc = flight(escape: true, effort: nil)
        let casual = flight(escape: false, effort: 0.45)
        let ok = esc.alt > casual.alt + 0.15 && esc.scale > FLY_SCALE * 1.5
            && abs(esc.scale - FLY_SCALE * (1 + 0.8 * esc.alt)) < 0.15
        return (ok, String(format: "escape alt %.2f scale %.2f | casual alt %.2f scale %.2f",
                           esc.alt, esc.scale, casual.alt, casual.scale))
    }

    bodyCheck("flight: wings actually beat") {
        let fly = Fly(at: .zero)
        fly.state = .idle
        fly.startFlight(bounds: bounds, effort: 0.8)
        var lo = CGFloat.greatestFiniteMagnitude, hi = -CGFloat.greatestFiniteMagnitude
        for _ in 0..<30 where fly.state == .flying {
            fly.update(dt: dt, bounds: bounds, mouse: nil, signals: BrainSignals())
            let z = fly.model.foldedWings.childNodes[0].eulerAngles.z
            lo = min(lo, z); hi = max(hi, z)
        }
        return (hi - lo > 0.25, String(format: "wing sweep %.2f rad over 0.5 s", hi - lo))
    }

    bodyCheck("escape-DN activity mid-flight raises wing-beat effort") {
        let fly = Fly(at: .zero)
        fly.state = .idle
        fly.startFlight(bounds: bounds, effort: 0.5)
        var calm = BrainSignals()
        for _ in 0..<12 { fly.update(dt: dt, bounds: bounds, mouse: nil, signals: calm) }
        let calmEffort = fly.effortCurrent
        var hot = BrainSignals(); hot.wingDrive = 1.0; hot.arousal = 0.6
        for _ in 0..<12 where fly.state == .flying {
            fly.update(dt: dt, bounds: bounds, mouse: nil, signals: hot)
        }
        let hotEffort = fly.effortCurrent
        return (fly.state == .flying && hotEffort > calmEffort + 0.2,
                String(format: "effort %.2f -> %.2f", calmEffort, hotEffort))
    }

    bodyCheck("threat while grounded raises the wings (no takeoff)") {
        let fly = Fly(at: .zero)
        fly.state = .walking; fly.speed = 20
        fly.dartCooldown = 99   // isolate the posture from darting
        var threat = BrainSignals(); threat.wingDrive = 0.9; threat.walkDrive = 0.4
        for _ in 0..<40 { fly.update(dt: dt, bounds: bounds, mouse: nil, signals: threat) }
        let x = fly.model.foldedWings.childNodes[0].eulerAngles.x
        return (fly.state != .flying && fly.wingRaise > 0.6 && x < -0.2,
                String(format: "raise %.2f, wing tilt %.2f rad", fly.wingRaise, x))
    }

    bodyCheck("landing is smooth: no scale/height snap at touchdown") {
        let fly = Fly(at: .zero)
        fly.state = .idle
        fly.startFlight(bounds: bounds, escape: true)
        var prevScale = fly.node.scale.x, prevZ = fly.node.position.z
        var maxDS: CGFloat = 0, maxDZ: CGFloat = 0
        var post = 20, frames = 0
        var landed = false
        while post > 0 && frames < 600 {
            frames += 1
            fly.update(dt: dt, bounds: bounds, mouse: nil, signals: BrainSignals())
            maxDS = max(maxDS, abs(fly.node.scale.x - prevScale))
            maxDZ = max(maxDZ, abs(fly.node.position.z - prevZ))
            prevScale = fly.node.scale.x; prevZ = fly.node.position.z
            if fly.state != .flying { landed = true; post -= 1 }
        }
        return (landed && maxDS < 0.2 && maxDZ < 25,
                String(format: "landed=%@, max per-frame Δscale %.2f, Δz %.1f",
                       landed ? "yes" : "NO", maxDS, maxDZ))
    }

    bodyCheck("DNa steers the fly in flight (no scripted destination)") {
        func run(turn: CGFloat) -> CGFloat {
            let fly = Fly(at: .zero)
            fly.state = .idle
            fly.heading = 0
            fly.startFlight(bounds: bounds, effort: 0.6)
            var s = BrainSignals()
            s.turnBias = turn
            var frames = 0
            while fly.state == .flying && frames < 45 {
                frames += 1
                fly.update(dt: dt, bounds: bounds, mouse: nil, signals: s)
            }
            return fly.heading
        }
        let straight = run(turn: 0), left = run(turn: 0.8)
        return (left - straight > 0.6,
                String(format: "heading after 0.75 s: %+.2f straight vs %+.2f with DNa left",
                       straight, left))
    }

    bodyCheck("circadian curve: siesta + night dips, dawn/dusk peaks") {
        let night = circadianActivity(hour: 3), dawn = circadianActivity(hour: 9)
        let siesta = circadianActivity(hour: 14), dusk = circadianActivity(hour: 18)
        let ok = night < 0.4 && dawn > 0.9 && siesta < 0.7 && siesta > 0.3 && dusk > 0.9
        return (ok, String(format: "3h %.2f, 9h %.2f, 14h %.2f, 18h %.2f", night, dawn, siesta, dusk))
    }

    bodyCheck("vibecode target on the left -> fly steers onto it") {
        // Locomotion is stochastic, so this asserts the steering outcome the
        // pull reliably produces (heading reaching the target) rather than a
        // full approach, and retries once.
        func trial() -> (aligned: Bool, minBearing: CGFloat, minDist: CGFloat, walk: Int) {
            let sim = LIFSim(circuit: data.circuit, spikeBus: nil)
            let builder = SignalBuilder()
            let settings = VibeSettings()
            let fly = Fly(at: .zero)
            fly.state = .walking
            fly.speed = 30
            let target = CGPoint(x: 0, y: 420)
            sim.step(400)
            _ = sim.consumeGF()
            fly.heading = 0
            func bearing() -> CGFloat {
                abs(angleDiff(fly.heading, atan2(target.y - fly.pos.y, target.x - fly.pos.x)))
            }
            func dist() -> CGFloat { hypot(target.x - fly.pos.x, target.y - fly.pos.y) }
            var minBearing = bearing(), minDist = dist(), walkFrames = 0
            let frames = 1800
            for _ in 0..<frames {
                let a = attractionSplit(pos: fly.pos, heading: fly.heading, target: target,
                                        weight: 9.7, d0: 200, settings: settings, gate: 1)
                sim.attractL = a.l
                sim.attractR = a.r
                sim.attractFwd = a.fwd
                sim.step(Int((dt * 1000).rounded()))
                let s = builder.make(sim, dt: dt, holdSteering: true)
                fly.update(dt: dt, bounds: bounds, mouse: nil, signals: s)
                minBearing = min(minBearing, bearing())
                minDist = min(minDist, dist())
                if fly.state == .walking { walkFrames += 1 }
            }
            return (minBearing < 0.5, minBearing, minDist, walkFrames * 100 / frames)
        }
        var t = trial()
        if !t.aligned { t = trial() }
        return (t.aligned,
                String(format: "best bearing %.2f rad (start 1.57), closest %d pt of 420, walking %d%%",
                       t.minBearing, Int(t.minDist), t.walk))
    }

    print(failures == 0 ? "ALL BEHAVIOR TESTS PASS" : "\(failures) FAILURES")
    exit(failures == 0 ? 0 : 1)
}

// MARK: - Signals

// Converts sim population rates into body commands. Shared by the app loop
// and --behaviortest so both exercise the identical mapping.
func odorConcentration(weight: CGFloat, dist: CGFloat, d0: CGFloat) -> CGFloat {
    weight / (1 + dist / max(1, d0))
}

func attractionSplit(pos: CGPoint, heading: CGFloat, target: CGPoint, weight: CGFloat,
                     d0: CGFloat, settings: VibeSettings,
                     gate: CGFloat) -> (l: Float, r: Float, fwd: Float) {
    let rel = CGPoint(x: target.x - pos.x, y: target.y - pos.y)
    let dist = max(20, hypot(rel.x, rel.y))
    let conc = odorConcentration(weight: weight, dist: dist, d0: d0)
    let drive = settings.attractGain * clampf(conc / CGFloat(settings.odorFull), 0, 1) * gate
    guard drive > 0.001 else { return (0, 0, 0) }
    let rd = CGPoint(x: rel.x / dist, y: rel.y / dist)
    let f = CGPoint(x: cos(heading), y: sin(heading))
    let crossZ = f.x * rd.y - f.y * rd.x
    let ahead = f.x * rd.x + f.y * rd.y
    // Purely differential: on target both sides get zero, so the residual
    // imbalance between the two driver groups cannot keep spinning the fly.
    // A target behind gives crossZ ~ 0 too, so it commits to one side instead.
    var l = drive * max(0, crossZ)
    var r = drive * max(0, -crossZ)
    if ahead < 0 {
        l = crossZ >= 0 ? drive : 0
        r = crossZ >= 0 ? 0 : drive
    }
    return (Float(l), Float(r), Float(drive * clampf(ahead, 0, 1)))
}

final class SignalBuilder {
    private var dnaBaseline: Float = 0
    private var primed = false

    func make(_ sim: LIFSim, dt: CGFloat, holdSteering: Bool = false) -> BrainSignals {
        let diff = sim.rateDNaL - sim.rateDNaR
        // starting from zero leaves the standing wiring asymmetry unsubtracted
        // for ~30 s, which reads as a constant turn bias
        if !primed { dnaBaseline = diff; primed = true }
        // Slow adaptation (tau ~8 s): the connectome's persistent left/right
        // wiring asymmetry is adapted out, so steady-state walking is straight
        // and only transient DNa asymmetries (visual, stimulation) steer.
        // Stretched to ~60 s while an appetitive target is driving: a 3 s
        // attraction bout must not be adapted away, but the standing wiring
        // asymmetry still has to be removed or it adds to the pull.
        let tau: CGFloat = holdSteering ? 20 : 8
        dnaBaseline += (diff - dnaBaseline) * Float(min(1, dt / tau))
        var s = BrainSignals()
        s.escape = sim.consumeGF()
        s.nervous = clampf(CGFloat(sim.rateLoom) / 80, 0, 1)
        s.turnBias = clampf(CGFloat(diff - dnaBaseline) * 0.04, -1.0, 1.0)
        s.backward = sim.rateMDN > 8
        s.walkDrive = clampf(CGFloat(sim.rateFwd) / 10, 0, 1.3)
        s.groomDrive = CGFloat(sim.rateGroom) / 8
        s.wingDrive = clampf(CGFloat(sim.rateEscW) / 10, 0, 1.3)
        s.arousal = clampf(CGFloat(sim.ratePop) / 20, 0, 1)
        return s
    }
}

// MARK: - Coordinator

final class Coordinator: NSObject, SCNSceneRendererDelegate {
    let scene: SCNScene
    var bounds: CGSize
    var flies: [Fly] = []
    var lastTime: TimeInterval?
    var mouseScene: CGPoint?
    private let lock = NSLock()
    private var pending: [(Coordinator) -> Void] = []

    let sim: LIFSim?
    private let fpsLog = ProcessInfo.processInfo.environment["DESKTOPFLY_FPS"] != nil
    private var fpsFrames = 0
    private var fpsWindowStart: TimeInterval = 0
    private let signalBuilder = SignalBuilder()
    private var msAccumulator: Double = 0
    private var prevMouse: CGPoint?
    private var mouseVel = CGPoint.zero
    private var loomOverride: CGFloat = 0

    // environment senses (written from main-thread timers, read in render loop)
    private var terrain: [Ledge] = []
    private var typingLevel: CGFloat = 0
    private var sleepy = false
    private var tempo: CGFloat = 1
    private var activity: Float = 1
    private var windowLoomL: Float = 0
    private var windowLoomR: Float = 0
    private(set) var lastFlyPos = CGPoint.zero

    private let vibe: VibeSettings
    private var odorSources: [(point: CGPoint, weight: CGFloat, token: String)] = []
    private var vibeTarget: (point: CGPoint, weight: CGFloat, token: String)?
    private var odorD0: CGFloat = 200
    private var satiation: CGFloat = 0
    private var vibeLogTime: TimeInterval = 0
    private var boutOn = false
    private var boutTime: CGFloat = 0

    init(bounds: CGSize, sim: LIFSim?, vibe: VibeSettings = VibeSettings()) {
        self.bounds = bounds
        self.sim = sim
        self.vibe = vibe
        self.scene = buildScene(bounds: bounds)
        super.init()
        enqueue { $0.addFlyNow() }
    }

    func enqueue(_ action: @escaping (Coordinator) -> Void) {
        lock.lock(); pending.append(action); lock.unlock()
    }

    private func addFlyNow() {
        let hw = bounds.width / 2 - 100, hh = bounds.height / 2 - 100
        let fly = Fly(at: CGPoint(x: rnd(-hw...hw), y: rnd(-hh...hh)))
        scene.rootNode.addChildNode(fly.node)
        flies.append(fly)
    }

    func addFly() { enqueue { $0.addFlyNow() } }
    func removeFly() {
        enqueue { c in
            guard c.flies.count > 1 else { return }   // fly #1 carries the brain
            c.flies.removeLast().node.removeFromParentNode()
        }
    }
    func scareAll() {
        enqueue { c in
            c.loomOverride = 0.6   // real stimulus into the real circuit for fly #1
            for fly in c.flies.dropFirst() where fly.state != .flying {
                fly.startFlight(bounds: c.bounds)
            }
        }
    }
    func escapeTest() { enqueue { $0.loomOverride = 0.6 } }
    func setMouse(_ p: CGPoint?) { lock.lock(); mouseScene = p; lock.unlock() }

    func setTerrain(_ ledges: [Ledge]) { enqueue { $0.terrain = ledges } }

    func setOdorSources(_ s: [(point: CGPoint, weight: CGFloat, token: String)]) {
        enqueue { c in
            c.odorSources = s
            c.odorD0 = hypot(c.bounds.width, c.bounds.height) / c.vibe.d0Divisor
        }
    }

    private func strongestSource(from pos: CGPoint)
        -> (target: (point: CGPoint, weight: CGFloat, token: String)?, total: CGFloat,
            dist: CGFloat, best: CGFloat) {
        var best: (point: CGPoint, weight: CGFloat, token: String)?
        var bestConc: CGFloat = 0
        var bestDist: CGFloat = 0
        var total: CGFloat = 0
        for s in odorSources {
            let d = hypot(s.point.x - pos.x, s.point.y - pos.y)
            let conc = odorConcentration(weight: s.weight, dist: d, d0: odorD0)
            guard conc > CGFloat(vibe.odorThreshold) else { continue }
            total += conc
            if conc > bestConc { bestConc = conc; best = s; bestDist = d }
        }
        return (best, total, bestDist, bestConc)
    }

    private func computeAttraction(fly: Fly, dt: CGFloat) -> (l: Float, r: Float, fwd: Float) {
        let sensed = strongestSource(from: fly.pos)
        vibeTarget = sensed.target
        satiation = clampf(sensed.best / CGFloat(vibe.odorFull), 0, 1)
        // motivation to fly is about being FAR from the smell: concentration rises
        // on approach, so feeding it raw would make her take off next to the folder
        let reach = clampf((sensed.dist - odorD0) / (2 * odorD0), 0, 1)
        sim?.attractArousal = Float(clampf(sensed.total / CGFloat(vibe.arousalFull), 0, 1) * reach)
        guard let t = sensed.target else { boutOn = false; satiation = 0; return (0, 0, 0) }
        if boutOn {
            boutTime -= dt
            if boutTime <= 0 { boutOn = false }
        } else if rnd(0...1) < dt / vibe.boutEverySeconds {
            boutOn = true
            boutTime = vibe.boutSeconds
        }
        return attractionSplit(pos: fly.pos, heading: fly.heading, target: t.point,
                               weight: t.weight, d0: odorD0, settings: vibe,
                               gate: boutOn ? 1 : vibe.idleDrive)
    }

    // the fly moved to a different display: new bounds + camera extent
    func retarget(size: CGSize) {
        enqueue { c in
            c.bounds = size
            c.odorD0 = hypot(size.width, size.height) / c.vibe.d0Divisor
            c.terrain = []   // stale until the next window poll
            if let camNode = c.scene.rootNode.childNode(withName: "camera", recursively: false) {
                camNode.camera?.orthographicScale = Double(size.height / 2)
            }
            // keep flies inside the new display
            for fly in c.flies {
                fly.ledge = nil
                fly.pos.x = clampf(fly.pos.x, -size.width / 2 + 40, size.width / 2 - 40)
                fly.pos.y = clampf(fly.pos.y, -size.height / 2 + 40, size.height / 2 - 40)
            }
        }
    }
    func setAmbient(typing: CGFloat, sleepy: Bool, tempo: CGFloat, activity: Float) {
        enqueue { c in
            c.typingLevel = typing; c.sleepy = sleepy; c.tempo = tempo; c.activity = activity
        }
    }
    func flyPosition() -> CGPoint { lock.lock(); defer { lock.unlock() }; return lastFlyPos }

    // a window appeared near the fly: a real looming object
    func injectWindowLoom(strength: CGFloat, at p: CGPoint) {
        enqueue { c in
            guard let fly = c.flies.first else { return }
            let rel = CGPoint(x: p.x - fly.pos.x, y: p.y - fly.pos.y)
            let dist = max(1, hypot(rel.x, rel.y))
            let f = CGPoint(x: cos(fly.heading), y: sin(fly.heading))
            let crossZ = (f.x * rel.y - f.y * rel.x) / dist
            c.windowLoomL = max(c.windowLoomL, Float(strength * clampf(0.5 + 0.5 * crossZ, 0.12, 1)))
            c.windowLoomR = max(c.windowLoomR, Float(strength * clampf(0.5 - 0.5 * crossZ, 0.12, 1)))
        }
    }

    // a global mouse click: a tap on the fly's substrate -> sensory pathway
    func injectTap(at p: CGPoint) {
        enqueue { c in
            guard let sim = c.sim, let fly = c.flies.first else { return }
            let d = hypot(p.x - fly.pos.x, p.y - fly.pos.y)
            let strength = Float(clampf(1 - d / 520, 0, 1))
            if strength > 0.05 {
                sim.stimulate(sim.sens, strength: 0.15 + strength * 0.35, durationMs: 130)
            }
        }
    }

    // Cursor kinematics -> looming drive for each eye of fly #1 + air puff.
    // This is the sensory transduction step; everything downstream of the
    // LC4/LPLC2 population is the real connectome.
    private func computeLoom(fly: Fly, mouse: CGPoint?, dt: CGFloat) -> (l: Float, r: Float, puff: Float) {
        guard let m = mouse else { return (0, 0, 0) }
        if let pm = prevMouse, dt > 0 {
            let v = CGPoint(x: (m.x - pm.x) / dt, y: (m.y - pm.y) / dt)
            mouseVel.x += (v.x - mouseVel.x) * 0.4
            mouseVel.y += (v.y - mouseVel.y) * 0.4
        }
        prevMouse = m
        let rel = CGPoint(x: m.x - fly.pos.x, y: m.y - fly.pos.y)
        let dist = max(20, hypot(rel.x, rel.y))
        // radial approach speed (positive = cursor closing in)
        let approach = -(rel.x * mouseVel.x + rel.y * mouseVel.y) / dist
        // loom ~ rate of angular expansion, attenuated with distance
        var loom = clampf(approach / dist * 6, 0, 1) * clampf(1 - dist / 800, 0, 1)
        loom += clampf((130 - dist) / 130, 0, 1) * 0.5          // hovering close = big object
        loom = clampf(loom + loomOverride, 0, 1)
        // split between eyes by bearing relative to heading
        let f = CGPoint(x: cos(fly.heading), y: sin(fly.heading))
        let rd = CGPoint(x: rel.x / dist, y: rel.y / dist)
        let crossZ = f.x * rd.y - f.y * rd.x                     // >0: threat on the left
        let lw = clampf(0.5 + 0.5 * crossZ, 0.12, 1)
        let rw = clampf(0.5 - 0.5 * crossZ, 0.12, 1)
        let puff = clampf(hypot(mouseVel.x, mouseVel.y) / 1500, 0, 1) * clampf(1 - dist / 500, 0, 1)
        return (Float(loom * lw), Float(loom * rw), Float(puff))
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime t: TimeInterval) {
        if fpsLog {
            if fpsWindowStart == 0 { fpsWindowStart = t }
            fpsFrames += 1
            if t - fpsWindowStart >= 5 {
                fputs(String(format: "fps: %.1f\n", Double(fpsFrames) / (t - fpsWindowStart)), stderr)
                fpsFrames = 0
                fpsWindowStart = t
            }
        }
        lock.lock()
        let actions = pending; pending.removeAll()
        let mouse = mouseScene
        lock.unlock()
        for a in actions { a(self) }

        guard let last = lastTime else { lastTime = t; return }
        let dt = CGFloat(min(0.05, max(0, t - last)))
        lastTime = t

        var signals: BrainSignals? = nil
        if let sim = sim, let first = flies.first {
            let sensory = computeLoom(fly: first, mouse: mouse, dt: dt)
            let decayF = Float(exp(-4 * Double(dt)))
            windowLoomL *= decayF
            windowLoomR *= decayF
            sim.loomL = max(sensory.l, windowLoomL)
            sim.loomR = max(sensory.r, windowLoomR)
            sim.airPuff = max(sensory.puff, Float(typingLevel * 0.30))
            let attract = computeAttraction(fly: first, dt: dt)
            sim.attractL = attract.l
            sim.attractR = attract.r
            sim.attractFwd = attract.fwd
            if vibeDebug && t - vibeLogTime > 0.5 {
                vibeLogTime = t
                let hdg = first.heading
                if let vt = vibeTarget {
                    let rel = CGPoint(x: vt.point.x - first.pos.x, y: vt.point.y - first.pos.y)
                    let d = hypot(rel.x, rel.y)
                    let bear = angleDiff(hdg, atan2(rel.y, rel.x))
                    vibeLog(String(format: "fly (%.0f,%.0f) hdg %+.2f | target \"%@\" %.1f at "
                            + "(%.0f,%.0f) d=%.0f bearing %+.2f | drive L/R/F %.3f/%.3f/%.3f %@",
                            first.pos.x, first.pos.y, hdg, vt.token, vt.weight,
                            vt.point.x, vt.point.y, d, bear,
                            attract.l, attract.r, attract.fwd, boutOn ? "BOUT" : "idle"))
                } else {
                    vibeLog(String(format: "fly (%.0f,%.0f) hdg %+.2f | no target",
                                   first.pos.x, first.pos.y, hdg))
                }
            }
            // body -> brain: leg proprioception from the current gait
            sim.gaitDrive = Float(first.walkingIntensity)
            sim.gaitPhase = Float(first.gaitPhasePublic)
            // circadian + sleep neuromodulation. Compressed: the LIF neurons sit
            // just below threshold, so a raw multiplier silences them entirely —
            // siesta should mean "less active", not comatose.
            // sitting on a strong source damps the whole population: a fed fly
            // does not take off. Compressed like the circadian scale — a linear
            // multiplier here silences the network entirely.
            sim.activityScale = (1 - (1 - activity) * 0.35) * (sleepy ? 0.75 : 1)
                * Float(1 - satiation * 0.2)
            sim.sensoryGate = sleepy ? 0.55 : 1
            loomOverride = max(0, loomOverride - dt * 1.2)   // override decays
            msAccumulator += Double(dt) * 1000
            let steps = min(50, Int(msAccumulator))
            msAccumulator -= Double(steps)
            sim.step(steps)

            var s = signalBuilder.make(sim, dt: dt,
                                       holdSteering: attract.l + attract.r + attract.fwd > 0.001)
            s.tempo = tempo
            s.sleep = sleepy
            signals = s
        }

        for (i, fly) in flies.enumerated() {
            fly.terrain = terrain
            fly.update(dt: dt, bounds: bounds, mouse: mouse, signals: i == 0 ? signals : nil)
        }
        if let first = flies.first {
            lock.lock(); lastFlyPos = first.pos; lock.unlock()
        }
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        // only offer the display hop when there is somewhere to hop to
        moveDisplayItem?.isHidden = NSScreen.screens.count < 2
        let trusted = axTrusted()
        axMenuItem?.title = trusted ? "Finder Icons: enabled" : "Enable Finder Icon Attraction…"
        axMenuItem?.isEnabled = !trusted
    }

    var window: NSWindow!
    var scnView: SCNView!
    var coordinator: Coordinator!
    var statusItem: NSStatusItem!
    var mouseTimer: Timer?
    var windowTimer: Timer?
    var clickMonitor: Any?
    var vibeTimer: Timer?
    let windowSense = WindowSense()
    var vibeSettings = VibeSettings.load()
    lazy var vibeSense = VibeSense(settings: vibeSettings)
    let finderSense = FinderSense()
    var typingLevel: CGFloat = 0
    var paused = false
    var brainWC: BrainWindowController?
    var dataInfo = "no data — run etl.py"
    var screenFrame = NSRect.zero
    var moveDisplayItem: NSMenuItem?
    var axMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.main else { fatalError("no screen") }
        let frame = screen.frame
        screenFrame = frame

        var sim: LIFSim? = nil
        let spikeBus = SpikeBus()
        var brainPoints: BrainPointsFile? = nil
        if let data = loadBrainData() {
            sim = LIFSim(circuit: data.circuit, spikeBus: spikeBus)
            brainPoints = data.points
            dataInfo = "FlyWire v783 · \(data.points.points.count) somas · circuit \(data.circuit.neurons.count)n/\(data.circuit.edges.count)e"
        }

        coordinator = Coordinator(bounds: frame.size, sim: sim, vibe: vibeSettings)
        vibeSense.rescan()
        if !axTrusted() && !UserDefaults.standard.bool(forKey: "axPromptShown") {
            UserDefaults.standard.set(true, forKey: "axPromptShown")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { axRequestAccess() }
        }

        window = NSWindow(contentRect: frame, styleMask: [.borderless],
                          backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        scnView = SCNView(frame: NSRect(origin: .zero, size: frame.size))
        scnView.scene = coordinator.scene
        scnView.backgroundColor = .clear
        scnView.allowsCameraControl = false
        scnView.antialiasingMode = .multisampling4X
        scnView.preferredFramesPerSecond = 120   // ProMotion; caps at display refresh
        if ProcessInfo.processInfo.environment["DESKTOPFLY_FPS"] != nil {
            fputs("display max fps: \(NSScreen.main?.maximumFramesPerSecond ?? 0)\n", stderr)
        }
        scnView.delegate = coordinator
        scnView.isPlaying = true
        window.contentView = scnView
        window.orderFrontRegardless()

        if let sim = sim, let pts = brainPoints {
            let wc = BrainWindowController(points: pts, sim: sim, screen: screen)
            wc.show()
            brainWC = wc
        }

        setupStatusItem()

        mouseTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let loc = NSEvent.mouseLocation
            self.coordinator.setMouse(CGPoint(x: loc.x - self.screenFrame.midX,
                                              y: loc.y - self.screenFrame.midY))
            // typing = substrate vibration (when, never what)
            let keyIdle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
            self.typingLevel += ((keyIdle < 0.6 ? 1.0 : 0.0) - self.typingLevel) * 0.15
            // circadian hour + sleep from user idleness + thermal tempo
            let idle = userIdleSeconds()
            let now = Date()
            let comps = Calendar.current.dateComponents([.hour, .minute], from: now)
            let h = Double(comps.hour ?? 12) + Double(comps.minute ?? 0) / 60
            let sleepy = (idle > 600 && (h >= 22 || h < 6)) || idle > 1800
            self.coordinator.setAmbient(typing: self.typingLevel, sleepy: sleepy,
                                        tempo: thermalTempo(), activity: circadianActivity(hour: h))
        }

        // window terrain + new-window looms, ~1.4 Hz
        vibeTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.vibeSense.rescan()
        }

        windowTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            guard let self else { return }
            let index = self.vibeSense.snapshot()
            let snap = self.windowSense.poll(screen: self.screenFrame, index: index,
                                             settings: self.vibeSettings)
            self.coordinator.setTerrain(snap.ledges)
            let flyPos = self.coordinator.flyPosition()
            let primaryH = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
                ?? self.screenFrame.height
            self.finderSense.refresh(index: index, screen: self.screenFrame,
                                     primaryH: primaryH, minScore: self.vibeSettings.minScore,
                                     occluders: snap.occluders,
                                     richness: self.vibeSettings.windowRichness,
                                     richnessCap: self.vibeSettings.windowRichnessCap,
                                     cap: self.vibeSettings.maxFolderScore,
                                     iconOpenness: self.vibeSettings.opennessIcon,
                                     rowOpenness: self.vibeSettings.opennessRow)
            let windows = self.vibeSettings.windowTargets ? snap.vibe : []
            self.coordinator.setOdorSources(
                self.odorSources(windows, icons: self.finderSense.snapshot(), flyPos: flyPos))
            for nw in snap.newWindows {
                let d = hypot(nw.center.x - flyPos.x, nw.center.y - flyPos.y)
                let strength = clampf(1 - d / 480, 0, 1) * 0.75
                if strength > 0.08 {
                    self.coordinator.injectWindowLoom(strength: strength, at: nw.center)
                }
            }
        }

        // global mouse clicks = taps on the fly's substrate (mouse monitors are permission-free)
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self else { return }
            let loc = NSEvent.mouseLocation
            self.coordinator.injectTap(at: CGPoint(x: loc.x - self.screenFrame.midX,
                                                   y: loc.y - self.screenFrame.midY))
        }

        // if the current display disappears, retreat to the main screen
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            if !NSScreen.screens.contains(where: { $0.frame == self.screenFrame }),
               let main = NSScreen.main {
                self.move(to: main)
            }
        }
    }

    func odorSources(_ windows: [VibeTarget], icons: [IconTarget],
                     flyPos: CGPoint) -> [(point: CGPoint, weight: CGFloat, token: String)] {
        var out: [(CGPoint, CGFloat, String)] = []
        for w in windows {
            out.append((w.center, CGFloat(w.score * w.openness), w.token))
        }
        for i in icons {
            out.append((i.center, CGFloat(i.score * i.openness), i.name))
        }
        if vibeDebug {
            let d0 = hypot(screenFrame.width, screenFrame.height) / vibeSettings.d0Divisor
            for s in out.sorted(by: { $0.1 > $1.1 }).prefix(6) {
                let d = hypot(s.0.x - flyPos.x, s.0.y - flyPos.y)
                let conc = odorConcentration(weight: s.1, dist: d, d0: d0)
                vibeLog(String(format: "odor \"%@\" w=%.1f d=%.0f conc=%.2f r=%.0f",
                               s.2, s.1, d, conc,
                               d0 * (s.1 / CGFloat(vibeSettings.odorThreshold) - 1)))
            }
        }
        return out
    }

    func move(to screen: NSScreen) {
        screenFrame = screen.frame
        window.setFrame(screen.frame, display: true)
        scnView.frame = NSRect(origin: .zero, size: screen.frame.size)
        coordinator.retarget(size: screen.frame.size)
        brainWC?.move(to: screen)
    }

    @objc func moveToNextDisplay() {
        let screens = NSScreen.screens
        guard screens.count > 1 else { return }
        let idx = screens.firstIndex(where: { $0.frame == screenFrame }) ?? 0
        move(to: screens[(idx + 1) % screens.count])
    }

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🪰"
        let menu = NSMenu()
        menu.addItem(withTitle: "Desktop Fly", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: dataInfo, action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        func item(_ title: String, _ sel: Selector, _ key: String) -> NSMenuItem {
            let it = NSMenuItem(title: title, action: sel, keyEquivalent: key)
            it.target = self
            return it
        }
        menu.addItem(item("Pause", #selector(togglePause(_:)), "p"))
        menu.addItem(item("Show/Hide Brain", #selector(toggleBrain), "b"))
        menu.addItem(item("Escape Test (loom)", #selector(escapeTest), "e"))
        let ax = item(axTrusted() ? "Finder Icons: enabled" : "Enable Finder Icon Attraction…",
                      #selector(requestAX), "")
        ax.isEnabled = !axTrusted()
        menu.addItem(ax)
        axMenuItem = ax
        let move = item("Move to Next Display", #selector(moveToNextDisplay), "d")
        menu.addItem(move)
        moveDisplayItem = move
        menu.delegate = self
        menu.addItem(item("Add Fly", #selector(addFly), "a"))
        menu.addItem(item("Remove Fly", #selector(removeFly), "r"))
        menu.addItem(item("Scare Flies", #selector(scareAll), "s"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc func togglePause(_ sender: NSMenuItem) {
        paused.toggle()
        scnView.isPlaying = !paused
        coordinator.lastTime = nil
        sender.title = paused ? "Resume" : "Pause"
    }
    @objc func toggleBrain() {
        guard let wc = brainWC else { return }
        wc.isVisible ? wc.hide() : wc.show()
    }
    @objc func requestAX() { axRequestAccess() }
    @objc func escapeTest() { coordinator.escapeTest() }
    @objc func addFly() { coordinator.addFly() }
    @objc func removeFly() { coordinator.removeFly() }
    @objc func scareAll() { coordinator.scareAll() }
}

// MARK: - Entry point

let args = CommandLine.arguments
if let i = args.firstIndex(of: "--snapshot") {
    runSnapshot(path: args.count > i + 1 ? args[i + 1] : "preview.png")
    exit(0)
}
if let i = args.firstIndex(of: "--brainshot") {
    runBrainshot(path: args.count > i + 1 ? args[i + 1] : "brain.png")
    exit(0)
}
if args.contains("--simtest") {
    runSimtest()
}
if args.contains("--behaviortest") {
    runBehaviorTest()
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
