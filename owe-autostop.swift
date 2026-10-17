// owe-autostop: frees Open Wallpaper Engine's memory while app windows hide its wallpapers.
// Every display hidden: `--control stop` unloads everything, and `play` loads it again.
// Some displays hidden: a hidden display's wallpaper closes when no visible display shows the
// same one (OWE shares one scene between displays, so closing a copy frees little).
// OWE's own "Stop (free memory)" playback rule only hides the window and keeps the scene loaded.
import AppKit

let oweBundleID = "app.openwallpaperengine"
let oweBinary = "/Applications/Open Wallpaper Engine.app/Contents/MacOS/Open Wallpaper Engine"
let stateFile = URL(fileURLWithPath: NSHomeDirectory() + "/.local/share/owe-autostop/closed.json")
let coverRatio = 0.85   // windows over this share of a display hide its desktop
let stopDelay = 5.0     // seconds a display stays hidden before its wallpaper unloads
let playDelay = 1.0     // seconds a display stays visible before its wallpaper loads

func log(_ message: String) {
    print("\(ISO8601DateFormatter().string(from: Date())) \(message)")
    fflush(stdout)
}

/// Awake displays by OWE's display id (the CGDirectDisplayID), in window coordinates.
func displayBounds() -> [String: CGRect] {
    var count: UInt32 = 0
    CGGetActiveDisplayList(0, nil, &count)
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    CGGetActiveDisplayList(count, &ids, &count)
    return Dictionary(uniqueKeysWithValues: ids.prefix(Int(count)).map { (String($0), CGDisplayBounds($0)) })
}

/// Bounds of visible app windows on screen, except those of `excluded` processes.
func appWindowBounds(excluding excluded: Set<pid_t>) -> [CGRect] {
    let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    return info.compactMap { window in
        guard window[kCGWindowLayer as String] as? Int == 0,
              (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
              let pid = window[kCGWindowOwnerPID as String] as? pid_t, !excluded.contains(pid),
              let bounds = window[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: bounds) else { return nil }
        return rect
    }
}

/// Samples `display` on a grid, so tiled or overlapping windows count together.
func isHidden(_ display: CGRect, by windows: [CGRect]) -> Bool {
    let steps = 40
    var covered = 0
    for i in 0..<steps {
        for j in 0..<steps {
            let point = CGPoint(x: display.minX + (CGFloat(i) + 0.5) * display.width / CGFloat(steps),
                                y: display.minY + (CGFloat(j) + 0.5) * display.height / CGFloat(steps))
            if windows.contains(where: { $0.contains(point) }) { covered += 1 }
        }
    }
    return Double(covered) >= Double(steps * steps) * coverRatio
}

func screenLocked() -> Bool {
    let session = CGSessionCopyCurrentDictionary() as? [String: Any]
    return session?["CGSSessionScreenIsLocked"] as? Bool ?? false
}

/// Runs `--control <arguments>` on the running OWE. Its answer when it succeeds, else nil.
@discardableResult
func control(_ arguments: [String], logsFailure: Bool = true) -> String? {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: oweBinary)
    process.arguments = ["--control"] + arguments
    process.standardOutput = output
    process.standardError = output
    do { try process.run() } catch { log("\(arguments.joined(separator: " ")) failed: \(error)"); return nil }
    let answer = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        if logsFailure { log("\(arguments.joined(separator: " ")) failed: \(answer)") }
        return nil
    }
    return answer
}

/// The project.json `display` shows, or nil when it shows none.
func wallpaper(on display: String) -> String? {
    control(["getWallpaper", "--location", display], logsFailure: false)
}

var stoppedByUs = false
var allSince: Date?
/// Displays this tool closed, with the wallpaper to reopen. Saved, as OWE keeps them closed.
var closedByUs = (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: stateFile))) ?? [:]
/// Hidden displays left open because a visible display shows the same wallpaper.
var keptOpen: Set<String> = []
var lastHidden: Set<String> = []
var displaySince: [String: Date] = [:]

func saveClosed() {
    do { try JSONEncoder().encode(closedByUs).write(to: stateFile, options: .atomic) } catch { log("saving \(stateFile.path) failed: \(error)") }
}

/// True once a change has waited `delay` seconds since `since` was first set.
func due(_ since: inout Date?, after delay: Double) -> Bool {
    let start = since ?? Date()
    since = start
    guard Date().timeIntervalSince(start) >= delay else { return false }
    since = nil  // a failed command waits a full delay before the next try
    return true
}

func close(_ display: String, visible: [String]) {
    guard let shown = wallpaper(on: display) else { keptOpen.insert(display); return }
    if visible.contains(where: { wallpaper(on: $0) == shown }) {
        log("\(display): a visible display shows the same wallpaper, kept")
        keptOpen.insert(display)
        return
    }
    guard control(["closeWallpaper", "--location", display]) != nil else { return }
    closedByUs[display] = shown
    saveClosed()
    log("\(display): closed")
}

func reopen(_ display: String) {
    guard let path = closedByUs.removeValue(forKey: display) else { return }
    saveClosed()
    // A wallpaper set there by hand stays.
    guard wallpaper(on: display) == nil else { return }
    if control(["openWallpaper", "--file", path, "--location", display]) != nil { log("\(display): reopened") }
}

func tick() {
    let owe = NSRunningApplication.runningApplications(withBundleIdentifier: oweBundleID)
    // A new OWE starts playing, so there is no stop to undo; closed displays stay closed in OWE.
    guard !owe.isEmpty else { stoppedByUs = false; allSince = nil; displaySince = [:]; keptOpen = []; return }
    let displays = displayBounds()
    guard !displays.isEmpty, !screenLocked() else { allSince = nil; displaySince = [:]; return }
    let windows = appWindowBounds(excluding: Set(owe.map(\.processIdentifier)))
    let hidden = Set(displays.filter { isHidden($0.value, by: windows) }.keys)
    if hidden != lastHidden { lastHidden = hidden; keptOpen = [] }

    let allHidden = hidden.count == displays.count
    if allHidden == stoppedByUs {
        allSince = nil
    } else if due(&allSince, after: allHidden ? stopDelay : playDelay), control([allHidden ? "stop" : "play"]) != nil {
        stoppedByUs = allHidden
        log(allHidden ? "every display hidden: stopped" : "resumed")
    }
    // Per display only while some display shows its wallpaper.
    guard !allHidden, !stoppedByUs else { displaySince = [:]; return }
    let visible = displays.keys.filter { !hidden.contains($0) }.sorted()
    for display in displays.keys.sorted() {
        let covered = hidden.contains(display)
        let closes = covered && closedByUs[display] == nil && !keptOpen.contains(display)
        let opens = !covered && closedByUs[display] != nil
        guard closes || opens else { displaySince[display] = nil; continue }
        guard due(&displaySince[display], after: closes ? stopDelay : playDelay) else { continue }
        if closes { close(display, visible: visible) } else { reopen(display) }
    }
}

log("started, closed displays: \(closedByUs.keys.sorted())")
Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in tick() }
RunLoop.main.run()
