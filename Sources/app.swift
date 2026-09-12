// Convertify — entries, engine, window, preferences, menus.
// The conversion commands themselves live in main.swift (presets and helpers).

import AppKit
import UserNotifications
import CryptoKit

// MARK: - Preferences

enum Prefs {
    static let d = UserDefaults.standard
    static func register() {
        d.register(defaults: [
            "keepWindowOpen": false, "quitDelay": 6, "bringToFront": true,
            "notifyOnFinish": true, "soundOnFinish": true,
            "historyLimit": 50, "historyDays": 0, "confirmClear": true, "clearOnQuit": false,
        ])
    }
    static var keepWindowOpen: Bool { get { d.bool(forKey: "keepWindowOpen") } set { d.set(newValue, forKey: "keepWindowOpen") } }
    static var quitDelay: Int { get { max(0, d.integer(forKey: "quitDelay")) } set { d.set(newValue, forKey: "quitDelay") } }
    static var bringToFront: Bool { get { d.bool(forKey: "bringToFront") } set { d.set(newValue, forKey: "bringToFront") } }
    static var notifyOnFinish: Bool { get { d.bool(forKey: "notifyOnFinish") } set { d.set(newValue, forKey: "notifyOnFinish") } }
    static var soundOnFinish: Bool { get { d.bool(forKey: "soundOnFinish") } set { d.set(newValue, forKey: "soundOnFinish") } }
    static var historyLimit: Int { get { max(0, d.integer(forKey: "historyLimit")) } set { d.set(newValue, forKey: "historyLimit") } }
    static var historyDays: Int { get { max(0, d.integer(forKey: "historyDays")) } set { d.set(newValue, forKey: "historyDays") } }
    static var confirmClear: Bool { get { d.bool(forKey: "confirmClear") } set { d.set(newValue, forKey: "confirmClear") } }
    static var clearOnQuit: Bool { get { d.bool(forKey: "clearOnQuit") } set { d.set(newValue, forKey: "clearOnQuit") } }
    static var welcomed: Bool { get { d.bool(forKey: "welcomed") } set { d.set(newValue, forKey: "welcomed") } }
    static var oldServicesChecked: Bool { get { d.bool(forKey: "oldServicesChecked") } set { d.set(newValue, forKey: "oldServicesChecked") } }
}

// MARK: - First launch: welcome, and leftovers from the script-based SendTo encoders

enum FirstLaunch {
    /// Menu titles used by the old Automator workflows (the script-based version) and by Convertify itself.
    static let oldTitles: Set<String> = [
        "MP3 Encode", "MP3 Encode (Low Quality)", "AAC Encode", "Opus Encode", "OGG Encode", "File to Wav",
        "Flac to Wav and Delete", "Wav to Flac and Delete", "File to MP4", "File to MOV", "Image + Audio to Video",
        "FFmpeg to M4A", "Opus Decode to Wav", "VGMStream to Wav", "Encoder Progress",
    ]
    static let servicesDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Services")

    /// Automator workflows in ~/Library/Services whose menu title matches one of the old SendTo encoder names.
    static func findOldWorkflows() -> [(title: String, url: URL)] {
        guard let items = try? FileManager.default.contentsOfDirectory(at: servicesDir, includingPropertiesForKeys: nil) else { return [] }
        var found: [(String, URL)] = []
        for u in items where u.pathExtension == "workflow" {
            let plist = u.appendingPathComponent("Contents/Info.plist")
            guard let d = try? Data(contentsOf: plist) else { continue }
            var titles: [String] = []
            if let dict = try? PropertyListSerialization.propertyList(from: d, format: nil) as? [String: Any],
               let services = dict["NSServices"] as? [[String: Any]] {
                titles = services.compactMap { ($0["NSMenuItem"] as? [String: Any])?["default"] as? String }
            }
            if titles.isEmpty, let text = String(data: d, encoding: .utf8) {
                // Some hand-written Info.plists do not parse as property lists; fall back to reading the title text.
                for t in oldTitles where text.contains("<string>\(t)</string>") { titles.append(t) }
            }
            if let title = titles.first(where: { oldTitles.contains($0) }) { found.append((title, u)); continue }
            // Broken or missing Info.plist: recognise the script-era workflows by the command they run.
            for wf in ["Contents/Resources/document.wflow", "Contents/document.wflow"] {
                if let text = try? String(contentsOf: u.appendingPathComponent(wf), encoding: .utf8),
                   text.contains(".encoders/_run") {
                    let name = u.deletingPathExtension().lastPathComponent
                    found.append((name, u)); break
                }
            }
        }
        return found.sorted { $0.0 < $1.0 }
    }

    /// Shows the "old services found" sheet on the main window. Calls `then` when done (with or without removal).
    static func offerToRemoveOldWorkflows(on window: NSWindow, then: @escaping () -> Void) {
        let old = findOldWorkflows()
        guard !old.isEmpty else { then(); return }
        let a = NSAlert()
        a.messageText = "Older SendTo encoder services found"
        a.informativeText = "These \(old.count) Automator services from the script-based version are still installed and would appear in the Services menu next to Convertify's own entries:\n\n" +
            old.map { "• " + $0.title }.joined(separator: "\n") +
            "\n\nMove them to the Trash? Convertify replaces all of them. Nothing else is touched."
        a.addButton(withTitle: "Move to Trash"); a.addButton(withTitle: "Keep Them")
        a.beginSheetModal(for: window) { r in
            if r == .alertFirstButtonReturn {
                for item in old {
                    do { try FileManager.default.trashItem(at: item.url, resultingItemURL: nil); Log.write("moved old service to Trash: \(item.url.lastPathComponent)") }
                    catch { Log.write("could not trash \(item.url.lastPathComponent): \(error.localizedDescription)") }
                }
                refreshServices()
            }
            then()
        }
    }

    static func refreshServices() {
        NSUpdateDynamicServices()
        let pbs = "/System/Library/CoreServices/pbs"
        for flag in ["-flush", "-update"] {
            let p = Process(); p.executableURL = URL(fileURLWithPath: pbs); p.arguments = [flag]
            p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
            try? p.run(); p.waitUntilExit()
        }
    }

    static func relaunchFinder() {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/killall"); p.arguments = ["Finder"]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try? p.run()
    }

    static func welcome(on window: NSWindow, then: @escaping () -> Void) {
        let a = NSAlert()
        a.messageText = "Welcome to Convertify"
        a.informativeText = "The conversions are now set up in the Finder. Select an audio or video file, open its context menu (VoiceOver: VO Shift M), open the Services submenu and pick a conversion such as MP3 Encode.\n\nIf the entries do not show up yet, the Finder needs a nudge: relaunch it now, or log out and back in later. Relaunching the Finder only closes its windows; nothing else is affected.\n\nThe full manual is in the Help menu."
        a.addButton(withTitle: "Relaunch Finder Now"); a.addButton(withTitle: "Later")
        a.beginSheetModal(for: window) { r in
            if r == .alertFirstButtonReturn { relaunchFinder() }
            then()
        }
    }

    static func runIfNeeded(on window: NSWindow) {
        Maintenance.afterUpgradeIfNeeded()
        Maintenance.tidyCopies(on: window) { runAfterTidy(on: window) }
    }
    static func runAfterTidy(on window: NSWindow) {
        let showWelcome = {
            guard !Prefs.welcomed else { return }
            refreshServices()
            welcome(on: window) { Prefs.welcomed = true }
        }
        if !Prefs.oldServicesChecked {
            offerToRemoveOldWorkflows(on: window) { Prefs.oldServicesChecked = true; showWelcome() }
        } else {
            showWelcome()
        }
    }
}

// MARK: - Entries (one per file, shown as table rows, persisted as history)

enum EntryStatus: String, Codable { case waiting, converting, done, failed, skipped, cancelled }

final class Entry: Codable {
    var id = UUID()
    var fileName: String
    var filePath: String
    var status: EntryStatus = .waiting
    var action: String
    var presetId: String?
    var started: Date?
    var finished: Date?
    var percent: Double?
    var remaining: Double?
    var output: String?      // output file name
    var outputPath: String?
    var message: String?     // error or note
    init(file: URL, preset: Preset) { fileName = file.lastPathComponent; filePath = file.path; action = preset.title; presetId = preset.id }

    static let timeFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "H:mm"; return f }()      // "8:35": VoiceOver reads H:MM as a time
    static let dayFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "d MMM"; return f }()

    var isFinished: Bool { status != .waiting && status != .converting }
    var statusText: String { status.rawValue }
    var progressText: String {
        switch status {
        case .converting:
            guard let p = percent else { return "running for \(spokenDuration(Date().timeIntervalSince(started ?? Date())))" }
            var t = "\(Int(p)) percent"
            if let r = remaining { t += r < 3 ? ", almost done" : ", about \(spokenDuration(r)) left" }
            return t
        case .done:
            if let s = started, let f = finished { return "took \(spokenDuration(f.timeIntervalSince(s)))" }
            return ""
        default: return ""
        }
    }
    var startedText: String {
        guard let d = started else { return "" }
        if Calendar.current.isDateInToday(d) { return Entry.timeFmt.string(from: d) }
        return Entry.dayFmt.string(from: d) + " " + Entry.timeFmt.string(from: d)
    }
    var resultText: String {
        switch status {
        case .done: return output ?? ""
        case .failed, .skipped, .cancelled: return message ?? ""
        default: return ""
        }
    }
    /// Full sentence for speech, in the order: file, status, progress, started, action, result.
    var spoken: String {
        [fileName, statusText, progressText, startedText.isEmpty ? "" : "started \(startedText)", action, resultText].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

enum History {
    static let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Convertify")
    static let url = dir.appendingPathComponent("history.json")
    static func load() -> [Entry] {
        guard let d = try? Data(contentsOf: url), let e = try? JSONDecoder().decode([Entry].self, from: d) else { return [] }
        return prune(e)
    }
    static func prune(_ entries: [Entry]) -> [Entry] {
        var out = entries
        if Prefs.historyDays > 0 {
            let cutoff = Date().addingTimeInterval(-Double(Prefs.historyDays) * 86400)
            out = out.filter { !$0.isFinished || ($0.finished ?? $0.started ?? Date()) >= cutoff }
        }
        if Prefs.historyLimit > 0 {
            var kept = 0
            out = out.filter { e in
                if !e.isFinished { return true }
                kept += 1; return kept <= Prefs.historyLimit
            }
        }
        return out
    }
    static func save(_ entries: [Entry]) {
        let finished = entries.filter { $0.isFinished }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(finished) { try? d.write(to: url) }
    }
}

// MARK: - Jobs

final class Job {
    let preset: Preset
    let files: [URL]
    let entries: [Entry]
    var finished = false
    var cancelled = false
    var skipCurrent = false
    var progressPath: String?
    var currentEntry: Entry?
    var currentDuration: Double?
    init(preset: Preset, files: [URL]) {
        self.preset = preset; self.files = files
        entries = files.map { Entry(file: $0, preset: preset) }
    }
    var okCount: Int { entries.filter { $0.status == .done }.count }
    var failures: [String] { entries.filter { $0.status == .failed }.map { "\($0.fileName): \($0.message ?? "")" } }
    var skips: [String] { entries.filter { $0.status == .skipped }.map { "\($0.fileName) \($0.message ?? "")" } }
}

// MARK: - Engine

final class Engine {
    static let shared = Engine()
    private let queue = DispatchQueue(label: "convertify.engine")
    private(set) var jobs: [Job] = []                       // main-thread access
    private(set) var entries: [Entry] = History.load()      // newest first; main-thread access
    private var current: Process?
    private var currentAux: Process?
    private let lock = NSLock()
    var onChange: (() -> Void)?
    var isBusy: Bool { jobs.contains { !$0.finished } }
    var activeJob: Job? { jobs.first { !$0.finished } }
    var activeEntry: Entry? { activeJob?.currentEntry }

    func enqueue(_ job: Job) {
        jobs.append(job)
        entries.insert(contentsOf: job.entries.reversed(), at: 0)
        Log.write("=== \(job.preset.title): \(job.files.count) file(s)")
        onChange?()
        queue.async { self.run(job) }
    }

    func cancelAll() {
        for j in jobs where !j.finished { j.cancelled = true }
        lock.lock(); current?.terminate(); currentAux?.terminate(); lock.unlock()
    }
    func cancelCurrentFile() {
        guard let j = activeJob else { return }
        j.skipCurrent = true
        lock.lock(); current?.terminate(); currentAux?.terminate(); lock.unlock()
    }

    // History editing (main thread)
    func clearHistory() {
        entries.removeAll { $0.isFinished }
        History.save(entries); onChange?()
    }
    func remove(_ e: Entry) { remove([e]) }
    func remove(_ list: [Entry]) {
        let ids = Set(list.filter { $0.isFinished }.map { ObjectIdentifier($0) })
        guard !ids.isEmpty else { return }
        entries.removeAll { ids.contains(ObjectIdentifier($0)) }
        History.save(entries); onChange?()
    }
    func pruneNow() { entries = History.prune(entries); History.save(entries); onChange?() }

    private func main(_ block: @escaping () -> Void) { DispatchQueue.main.sync(execute: block) }

    private func finish(_ e: Entry, _ status: EntryStatus, output: URL? = nil, message: String? = nil) {
        main {
            e.status = status; e.finished = Date(); e.percent = status == .done ? 100 : e.percent; e.remaining = nil
            e.output = output?.lastPathComponent; e.outputPath = output?.path; e.message = message
            History.save(self.entries); self.onChange?()
        }
    }

    private func begin(_ job: Job, _ e: Entry, duration dur: Double?, progress: String) {
        main {
            e.status = .converting; e.started = Date(); e.percent = nil; e.remaining = nil
            job.currentEntry = e; job.currentDuration = dur; job.progressPath = progress
            self.onChange?()
        }
    }

    private func run(_ job: Job) {
        defer {
            main {
                for e in job.entries where !e.isFinished {
                    e.status = job.cancelled ? .cancelled : .failed; e.finished = Date(); e.message = e.message ?? (job.cancelled ? "cancelled" : "not processed")
                }
                job.finished = true; job.currentEntry = nil
                self.entries = History.prune(self.entries); History.save(self.entries); self.onChange?()
            }
            Log.write(job.failures.isEmpty ? "done: all ok" : "done: \(job.okCount) ok, \(job.failures.count) failed")
            main { AppDelegate.shared.jobFinished(job) }
        }
        let missing = job.preset.tools.filter { findTool($0) == nil }
        if !missing.isEmpty {
            let msg = "missing tool: \(missing.joined(separator: ", ")). Install it with Homebrew."
            for e in job.entries { finish(e, .failed, message: msg) }
            Log.write("missing tools: \(missing)")
            return
        }
        if job.preset.kind == .imageAudio { runImageAudio(job); return }

        for (i, file) in job.files.enumerated() {
            let e = job.entries[i]
            if job.cancelled { finish(e, .cancelled, message: "cancelled"); continue }
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: file.path, isDirectory: &isDir)
            if isDir.boolValue { finish(e, .skipped, message: "is a folder"); Log.write("skip folder: \(file.path)"); continue }
            if !FileManager.default.isReadableFile(atPath: file.path) { finish(e, .failed, message: "cannot read the file"); Log.write("cannot read: \(file.path)"); continue }

            var ext = job.preset.ext
            if job.preset.kind == .extractAudio {
                let codec = audioCodec(file)
                if codec.isEmpty { finish(e, .failed, message: "no audio stream in file"); Log.write("FAIL: \(file.path) no audio"); continue }
                ext = extractExtension(forCodec: codec)
            }
            let out = outputPath(for: file, ext: ext)
            let progress = NSTemporaryDirectory() + "convertify-progress-\(ProcessInfo.processInfo.processIdentifier).txt"
            try? FileManager.default.removeItem(atPath: progress)
            job.skipCurrent = false
            begin(job, e, duration: duration(file), progress: progress)
            let result = convert(job, file, out, progress)
            switch result {
            case .success:
                if outputLooksValid(out) {
                    Log.write("ok:   \(file.path) -> \(out.path)")
                    if job.preset.kind == .flacDecodeDelete || job.preset.kind == .flacEncodeDelete {
                        try? FileManager.default.removeItem(at: file)
                    }
                    finish(e, .done, output: out)
                } else {
                    try? FileManager.default.removeItem(at: out)
                    Log.write("FAIL: \(file.path) output failed verification")
                    finish(e, .failed, message: "the result could not be read back, so it was deleted")
                }
            case .failure(let msg):
                try? FileManager.default.removeItem(at: out)
                let cancelled = job.cancelled || job.skipCurrent
                Log.write(cancelled ? "cancelled: \(file.path)" : "FAIL: \(file.path) \(msg)")
                finish(e, cancelled ? .cancelled : .failed, message: cancelled ? "cancelled" : msg)
            }
            try? FileManager.default.removeItem(atPath: progress)
        }
    }

    // MARK: per-file conversion

    private func convert(_ job: Job, _ input: URL, _ out: URL, _ progress: String) -> Result<Void, String> {
        let ff = findTool("ffmpeg")!
        func ffmpeg(_ middle: [String], inputArgs: [String] = []) -> Result<Void, String> {
            var args = ["-nostdin", "-hide_banner", "-loglevel", "error", "-y", "-nostats", "-progress", progress]
            args += inputArgs + ["-i", input.path] + middle + [out.path]
            return exec(ff, args)
        }
        let threads = ["-j", String(max(1, min(8, ProcessInfo.processInfo.activeProcessorCount)))]
        switch job.preset.kind {
        case .ffmpeg:
            return ffmpeg(job.preset.ffmpegArgs(input))
        case .videoMP4, .videoMOV:
            guard hasVideo(input) else { return .failure("no video stream in file") }
            let isMP4 = job.preset.kind == .videoMP4
            let vcodec = ffprobe(input, entries: "stream=codec_name").components(separatedBy: "\n").first ?? ""   // first stream; refine below
            let vcodecReal = runTool(findTool("ffprobe")!, ["-v", "error", "-select_streams", "v:0", "-show_entries", "stream=codec_name", "-of", "csv=p=0", input.path]).out.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = vcodec
            let acodec = audioCodec(input)
            let videoOK = isMP4 ? ["h264", "hevc", "mpeg4", "av1", "vp9"].contains(vcodecReal)
                                : ["h264", "hevc", "mpeg4", "prores", "mjpeg", "dnxhd", "av1"].contains(vcodecReal)
            let audioOK = acodec.isEmpty || (isMP4 ? ["aac", "mp3", "ac3", "eac3", "alac", "opus"].contains(acodec)
                                                   : ["aac", "mp3", "ac3", "alac"].contains(acodec) || acodec.hasPrefix("pcm_"))
            let audioArgs: [String] = acodec.isEmpty ? ["-an"] : (audioOK ? ["-map", "0:a?", "-c:a", "copy"] : ["-map", "0:a?", "-c:a", "aac_at", "-b:a", "192k"])
            let common = ["-sn", "-dn", "-map_metadata", "0", "-map_chapters", "0", "-movflags", "+faststart"]
            if videoOK {
                // 1. Keep the video as it is; copy or re-encode only the audio. Seconds, and the picture is untouched.
                let r = ffmpeg(["-map", "0:v:0", "-c:v", "copy"] + audioArgs + common)
                if case .success = r, outputLooksValid(out) { return .success(()) }
                try? FileManager.default.removeItem(at: out)
            }
            let encAudio: [String] = acodec.isEmpty ? ["-an"] : ["-map", "0:a?", "-c:a", "aac_at", "-b:a", "192k"]
            // 2. Apple's hardware H.264 encoder.
            let hw = ffmpeg(["-map", "0:v:0", "-c:v", "h264_videotoolbox", "-q:v", "65", "-pix_fmt", "yuv420p"] + encAudio + common)
            if case .success = hw, outputLooksValid(out) { return .success(()) }
            try? FileManager.default.removeItem(at: out)
            // 3. Software x264.
            return ffmpeg(["-map", "0:v:0", "-c:v", "libx264", "-crf", "18", "-preset", "medium", "-pix_fmt", "yuv420p"] + encAudio + common)
        case .remuxMKV:
            let full = ffmpeg(["-map", "0", "-map_metadata", "0", "-map_chapters", "0", "-c", "copy"])
            if case .success = full, outputLooksValid(out) { return .success(()) }
            try? FileManager.default.removeItem(at: out)
            // Retry without container-specific data streams; keep video, audio, subtitles and attachments.
            return ffmpeg(["-map", "0:v?", "-map", "0:a?", "-map", "0:s?", "-map", "0:t?", "-map_metadata", "0", "-map_chapters", "0", "-c", "copy"])
        case .extractAudio:
            let codec = audioCodec(input)
            var args = ["-map", "0:a:0"]
            if !rawAudioCodecs.contains(codec) { args += ["-map_metadata", "0", "-map_chapters", "0"] }
            args += ["-vn", "-sn", "-dn", "-c:a", "copy"]
            let r = ffmpeg(args)
            if case .failure = r { return r }
            guard audioCodec(out) == codec else { return .failure("the extracted file did not contain the expected \(codec) audio") }
            return .success(())
        case .imageJPEG, .imagePNG:
            // sips is part of macOS and keeps the photo metadata the destination can hold.
            let fmt = job.preset.kind == .imageJPEG ? "jpeg" : "png"
            var args = ["-s", "format", fmt]
            if fmt == "jpeg" { args += ["-s", "formatOptions", "90"] }
            args += [input.path, "--out", out.path]
            let r = exec("/usr/bin/sips", args)
            if case .failure = r { return r }
            guard let size = try? FileManager.default.attributesOfItem(atPath: out.path)[.size] as? Int, size > 0 else { return .failure("no image was written") }
            return .success(())
        case .oggPipe:
            return oggPipe(input, out, progress)
        case .flacDecodeDelete:
            return exec(findTool("flac")!, ["-d", "-f", "-s"] + threads + ["--keep-foreign-metadata-if-present", "-o", out.path, input.path])
        case .flacEncodeDelete:
            let flac = findTool("flac")!
            if case .success = exec(flac, ["-8", "-V", "-f", "-s"] + threads + ["--keep-foreign-metadata-if-present", "-o", out.path, input.path]) { return .success(()) }
            let tmp = NSTemporaryDirectory() + "convertify-pcm24-\(UUID().uuidString).wav"
            defer { try? FileManager.default.removeItem(atPath: tmp) }
            let r = exec(ff, ["-nostdin", "-hide_banner", "-loglevel", "error", "-y", "-nostats", "-progress", progress, "-i", input.path, "-map", "0:a:0", "-c:a", "pcm_s24le", tmp])
            if case .failure(let m) = r { return .failure(m) }
            return exec(flac, ["-8", "-V", "-f", "-s"] + threads + ["-o", out.path, tmp])
        case .imageAudio:
            return .failure("internal")
        }
    }

    private func oggPipe(_ input: URL, _ out: URL, _ progress: String) -> Result<Void, String> {
        let ff = Process(), ogg = Process()
        ff.executableURL = URL(fileURLWithPath: findTool("ffmpeg")!)
        ff.arguments = ["-nostdin", "-hide_banner", "-loglevel", "error", "-nostats", "-progress", progress, "-i", input.path, "-map", "0:a:0", "-f", "wav", "-"]
        var oargs = ["-Q", "-q", "4"]
        let title = mediaTag(input, "title"), artist = mediaTag(input, "artist"), album = mediaTag(input, "album")
        if !title.isEmpty { oargs += ["-t", title] }
        if !artist.isEmpty { oargs += ["-a", artist] }
        if !album.isEmpty { oargs += ["-l", album] }
        oargs += ["-o", out.path, "-"]
        ogg.executableURL = URL(fileURLWithPath: findTool("oggenc")!)
        ogg.arguments = oargs
        let pipe = Pipe(), ffErr = Pipe(), oggErr = Pipe()
        ff.standardOutput = pipe; ogg.standardInput = pipe
        ff.standardError = ffErr; ogg.standardError = oggErr
        ff.standardInput = FileHandle.nullDevice; ogg.standardOutput = FileHandle.nullDevice
        lock.lock(); current = ff; currentAux = ogg; lock.unlock()
        defer { lock.lock(); current = nil; currentAux = nil; lock.unlock() }
        do { try ff.run(); try ogg.run() } catch { return .failure("\(error)") }
        let e1 = ffErr.fileHandleForReading.readDataToEndOfFile()
        let e2 = oggErr.fileHandleForReading.readDataToEndOfFile()
        ff.waitUntilExit(); ogg.waitUntilExit()
        if ff.terminationStatus != 0 || ogg.terminationStatus != 0 {
            let msg = lastLine(String(decoding: e1 + e2, as: UTF8.self))
            return .failure(msg.isEmpty ? "exit \(ff.terminationStatus)/\(ogg.terminationStatus)" : msg)
        }
        return .success(())
    }

    private func runImageAudio(_ job: Job) {
        func kind(_ u: URL) -> String {
            switch u.pathExtension.lowercased() {
            case "jpg", "jpeg", "png", "bmp", "gif", "webp", "heic", "tif", "tiff": return "image"
            case "mp3", "wav", "m4a", "aac", "flac", "ogg", "opus", "wma", "aif", "aiff", "alac", "caf": return "audio"
            default: return "unknown"
            }
        }
        guard job.files.count == 2 else {
            for e in job.entries { finish(e, .failed, message: "select exactly one image and one audio file") }; Log.write("wrong file count"); return
        }
        let k = job.files.map(kind)
        let image: URL, audio: URL, audioEntry: Entry, imageEntry: Entry
        if k == ["image", "audio"] { image = job.files[0]; audio = job.files[1]; imageEntry = job.entries[0]; audioEntry = job.entries[1] }
        else if k == ["audio", "image"] { audio = job.files[0]; image = job.files[1]; audioEntry = job.entries[0]; imageEntry = job.entries[1] }
        else { for e in job.entries { finish(e, .failed, message: "need one image and one audio file, got \(k[0]) and \(k[1])") }; Log.write("bad pair"); return }

        finish(imageEntry, .skipped, message: "used as the picture")
        let out = outputPath(for: audio, ext: "mp4")
        let progress = NSTemporaryDirectory() + "convertify-progress-\(ProcessInfo.processInfo.processIdentifier).txt"
        begin(job, audioEntry, duration: duration(audio), progress: progress)
        let codec = audioCodec(audio)
        let acodec = ["aac", "mp3"].contains(codec) ? ["-c:a", "copy"] : ["-c:a", "aac_at", "-b:a", "192k"]
        let args = ["-nostdin", "-hide_banner", "-loglevel", "error", "-y", "-nostats", "-progress", progress,
                    "-loop", "1", "-framerate", "1", "-i", image.path, "-i", audio.path,
                    "-map", "0:v:0", "-map", "1:a:0", "-map_metadata", "1", "-map_chapters", "1",
                    "-vf", "scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2,format=yuv420p",
                    "-r", "1"] + acodec + ["-shortest", "-movflags", "+faststart"]
        var r = exec(findTool("ffmpeg")!, args + ["-c:v", "h264_videotoolbox", "-q:v", "65", out.path])
        if case .failure = r { r = exec(findTool("ffmpeg")!, args + ["-c:v", "libx264", "-preset", "veryfast", "-tune", "stillimage", out.path]) }
        else if !(hasVideo(out) && !audioCodec(out).isEmpty) {
            try? FileManager.default.removeItem(at: out)
            r = exec(findTool("ffmpeg")!, args + ["-c:v", "libx264", "-preset", "veryfast", "-tune", "stillimage", out.path])
        }
        try? FileManager.default.removeItem(atPath: progress)
        switch r {
        case .success where hasVideo(out) && !audioCodec(out).isEmpty:
            Log.write("ok:   \(image.path) + \(audio.path) -> \(out.path)")
            finish(audioEntry, .done, output: out)
        case .success:
            try? FileManager.default.removeItem(at: out)
            Log.write("FAIL: \(audio.path) video missing a stream")
            finish(audioEntry, .failed, message: "the result was missing the picture or the sound, so it was deleted")
        case .failure(let m):
            try? FileManager.default.removeItem(at: out)
            let cancelled = job.cancelled || job.skipCurrent
            Log.write(cancelled ? "cancelled: \(audio.path)" : "FAIL: \(audio.path) \(m)")
            finish(audioEntry, cancelled ? .cancelled : .failed, message: cancelled ? "cancelled" : m)
        }
    }

    private func exec(_ path: String, _ args: [String]) -> Result<Void, String> {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        let err = Pipe(); p.standardError = err
        lock.lock(); current = p; lock.unlock()
        defer { lock.lock(); current = nil; lock.unlock() }
        do { try p.run() } catch { return .failure("\(error)") }
        let e = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        if p.terminationStatus == 0 { return .success(()) }
        let msg = lastLine(String(decoding: e, as: UTF8.self))
        return .failure(msg.isEmpty ? "exit code \(p.terminationStatus)" : msg)
    }

    private func lastLine(_ s: String) -> String {
        s.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.last.map { String($0.prefix(160)) } ?? ""
    }

    /// Called by the UI timer: read ffmpeg's progress file for the running job.
    func pollProgress() {
        for job in jobs where !job.finished {
            guard let e = job.currentEntry, let path = job.progressPath, let dur = job.currentDuration, dur > 0,
                  let text = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            var outUs: Double?; var speed: Double?
            for line in text.components(separatedBy: "\n") {
                if line.hasPrefix("out_time_us=") { outUs = Double(line.dropFirst(12)) }
                else if line.hasPrefix("speed=") { speed = Double(line.dropFirst(6).trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "x", with: "")) }
            }
            guard let o = outUs else { continue }
            let done = o / 1_000_000
            e.percent = min(100, done / dur * 100)
            if let sp = speed, sp > 0 { e.remaining = max(0, (dur - done) / sp) }
        }
    }
}

extension String: @retroactive Error {}

// MARK: - Table with Home/End/Page keys, Delete, Copy

final class FilesTable: NSTableView {
    override func keyDown(with event: NSEvent) {
        let n = numberOfRows
        func select(_ row: Int) {
            guard n > 0 else { return }
            let r = max(0, min(n - 1, row))
            selectRowIndexes(IndexSet(integer: r), byExtendingSelection: false)
            scrollRowToVisible(r)
        }
        let visible = max(1, Int(visibleRect.height / (rowHeight + intercellSpacing.height)) - 1)
        switch event.keyCode {
        case 115: select(0)                                  // Home
        case 119: select(n - 1)                              // End
        case 116: select(selectedRow - visible)              // Page Up
        case 121: select(selectedRow + visible)              // Page Down
        case 51, 117: AppDelegate.shared.removeSelected(nil) // Delete, Forward Delete
        case 36: AppDelegate.shared.openOutput(nil)          // Return opens the output
        case 53: AppDelegate.shared.hideWindow(nil)          // Escape hides the window, the app keeps running
        default: super.keyDown(with: event)
        }
    }
    @objc func copy(_ sender: Any?) { AppDelegate.shared.copyRow(sender) }
    override func selectAll(_ sender: Any?) { selectRowIndexes(IndexSet(integersIn: 0..<numberOfRows), byExtendingSelection: false) }
    override func menu(for event: NSEvent) -> NSMenu? {
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        if row >= 0 { selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        return AppDelegate.shared.rowMenu()
    }
}

// MARK: - Main window

final class ProgressWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    let header = NSTextField(labelWithString: "No encode running.")
    let bar = NSProgressIndicator()
    let table = FilesTable()
    let scroll = NSScrollView()
    let cancelButton = NSButton(title: "Cancel All", target: nil, action: nil)
    let clearButton = NSButton(title: "Clear History", target: nil, action: nil)
    let closeButton = NSButton(title: "Close", target: nil, action: nil)
    var timer: Timer?
    let columns: [(id: String, title: String, width: CGFloat, text: (Entry) -> String)] = [
        ("file", "File", 220, { $0.fileName }),
        ("status", "Status", 80, { $0.statusText }),
        ("progress", "Progress", 200, { $0.progressText }),
        ("started", "Started", 90, { $0.startedText }),
        ("action", "Action", 170, { $0.action }),
        ("result", "Result", 240, { $0.resultText }),
    ]

    init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 440), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.title = "Convertify"
        w.center()
        w.setFrameAutosaveName("MainWindow")
        super.init(window: w)
        w.delegate = self
        let root = NSStackView(); root.orientation = .vertical; root.alignment = .leading; root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        header.font = .boldSystemFont(ofSize: 14); header.lineBreakMode = .byWordWrapping; header.maximumNumberOfLines = 3; header.preferredMaxLayoutWidth = 920
        header.setAccessibilityLabel("Current status")
        bar.style = .bar; bar.minValue = 0; bar.maxValue = 100; bar.isIndeterminate = false
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.setAccessibilityLabel("Current file progress")

        for c in columns {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(c.id))
            col.title = c.title; col.width = c.width; col.minWidth = 50
            table.addTableColumn(col)
        }
        table.dataSource = self; table.delegate = self
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = true
        table.setAccessibilityLabel("Files")
        table.rowHeight = 22
        table.doubleAction = #selector(AppDelegate.openOutput(_:)); table.target = AppDelegate.shared
        scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let buttons = NSStackView(views: [cancelButton, clearButton, closeButton]); buttons.orientation = .horizontal; buttons.spacing = 8
        cancelButton.target = AppDelegate.shared; cancelButton.action = #selector(AppDelegate.cancelAll(_:))
        clearButton.target = AppDelegate.shared; clearButton.action = #selector(AppDelegate.clearHistory(_:))
        closeButton.target = self; closeButton.action = #selector(closeTapped)
        cancelButton.setAccessibilityLabel("Cancel all running encodes")
        for v in [header, bar, scroll, buttons] { root.addArrangedSubview(v) }
        w.contentView = root
        NSLayoutConstraint.activate([
            bar.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -32),
            scroll.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -32),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 200),
        ])
        w.initialFirstResponder = table
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in Engine.shared.pollProgress(); self?.refresh() }
    }
    required init?(coder: NSCoder) { nil }

    var selectedEntry: Entry? {
        let r = table.selectedRow
        return r >= 0 && r < Engine.shared.entries.count ? Engine.shared.entries[r] : nil
    }
    var selectedEntries: [Entry] {
        let all = Engine.shared.entries
        return table.selectedRowIndexes.compactMap { $0 < all.count ? all[$0] : nil }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { Engine.shared.entries.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let col = tableColumn, let spec = columns.first(where: { $0.id == col.identifier.rawValue }) else { return nil }
        let e = Engine.shared.entries[row]
        let id = NSUserInterfaceItemIdentifier("cell-" + spec.id)
        let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView) ?? {
            let c = NSTableCellView(); c.identifier = id
            let t = NSTextField(labelWithString: ""); t.lineBreakMode = .byTruncatingTail; t.translatesAutoresizingMaskIntoConstraints = false
            c.addSubview(t); c.textField = t
            NSLayoutConstraint.activate([t.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 2), t.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -2), t.centerYAnchor.constraint(equalTo: c.centerYAnchor)])
            return c
        }()
        cell.textField?.stringValue = spec.text(e)
        return cell
    }

    var lastCount = -1
    func refresh() {
        let jobs = Engine.shared.jobs
        let active = jobs.filter { !$0.finished }
        if let e = Engine.shared.activeEntry {
            header.stringValue = "Converting \(e.fileName), \(e.progressText)"
            window?.title = "Convertify, \(e.fileName), \(e.percent.map { "\(Int($0)) percent" } ?? "converting")"
            if let p = e.percent { bar.isIndeterminate = false; bar.stopAnimation(nil); bar.doubleValue = p }
            else if !bar.isIndeterminate { bar.isIndeterminate = true; bar.startAnimation(nil) }
        } else {
            header.stringValue = active.isEmpty ? (jobs.isEmpty ? "No encode running." : "All jobs finished.") : "Starting..."
            window?.title = "Convertify"
            bar.isIndeterminate = false; bar.doubleValue = 0
        }
        let selected = table.selectedRow
        let selectedSet = table.selectedRowIndexes
        let count = Engine.shared.entries.count
        if count != lastCount { table.reloadData(); lastCount = count } else {
            let rows = table.rows(in: table.visibleRect)
            if rows.length > 0 { table.reloadData(forRowIndexes: IndexSet(integersIn: rows.location..<(rows.location + rows.length)), columnIndexes: IndexSet(integersIn: 0..<columns.count)) }
        }
        let keep = IndexSet(selectedSet.filter { $0 < count })
        if !keep.isEmpty { table.selectRowIndexes(keep, byExtendingSelection: false) }
        else if count > 0 && selected < 0 { table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
        cancelButton.isEnabled = !active.isEmpty
        clearButton.isEnabled = Engine.shared.entries.contains { $0.isFinished }
    }

    @objc func closeTapped() { AppDelegate.shared.closeWindow() }
    func windowShouldClose(_ sender: NSWindow) -> Bool { AppDelegate.shared.closeWindow(); return false }
}

// MARK: - Media Info window

final class MediaInfoWindowController: NSWindowController {
    let text = NSTextView()
    init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 420), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        w.title = "Media Info"; w.center(); w.setFrameAutosaveName("MediaInfoWindow")
        super.init(window: w)
        let sc = NSScrollView(); sc.hasVerticalScroller = true; sc.borderType = .noBorder
        text.isEditable = false; text.isSelectable = true; text.font = .systemFont(ofSize: 14)
        text.textContainerInset = NSSize(width: 12, height: 12)
        text.setAccessibilityLabel("Media information")
        text.isVerticallyResizable = true; text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        sc.documentView = text
        w.contentView = sc
        w.initialFirstResponder = text
    }
    required init?(coder: NSCoder) { nil }
    func show(_ urls: [URL]) {
        let reports = urls.map { MediaInfo.report(for: $0) }
        text.string = reports.joined(separator: "\n\n")
        window?.title = urls.count == 1 ? "Media Info, \(urls[0].lastPathComponent)" : "Media Info, \(urls.count) files"
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil); window?.makeKeyAndOrderFront(nil); window?.makeFirstResponder(text)
    }
}

// MARK: - Upgrades, duplicates, and Check for Updates

enum Maintenance {
    static let bundleID = "com.jakobrosin.convertify"
    static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    /// After the app was replaced by a newer version: refresh registrations, drop temp files, remember the version.
    static func afterUpgradeIfNeeded() {
        let last = Prefs.d.string(forKey: "lastVersion") ?? ""
        guard last != version else { return }
        Log.write(last.isEmpty ? "first run of version \(version)" : "upgraded from \(last) to \(version)")
        let lsr = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        let p = Process(); p.executableURL = URL(fileURLWithPath: lsr); p.arguments = ["-f", Bundle.main.bundlePath]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice; try? p.run(); p.waitUntilExit()
        FirstLaunch.refreshServices()
        // stale temp files from older versions
        let tmp = NSTemporaryDirectory()
        if let items = try? FileManager.default.contentsOfDirectory(atPath: tmp) {
            for f in items where f.hasPrefix("convertify-") { try? FileManager.default.removeItem(atPath: tmp + f) }
        }
        Prefs.d.set(version, forKey: "lastVersion")
    }

    /// Other copies of Convertify on this Mac (not counting mounted disk images).
    static func duplicateCopies() -> [URL] {
        let me = Bundle.main.bundleURL.standardizedFileURL
        let all = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleID)
        return all.map { $0.standardizedFileURL }.filter { $0 != me && !$0.path.hasPrefix("/Volumes/") && FileManager.default.fileExists(atPath: $0.path) }
    }
    static var runningFromApplications: Bool { Bundle.main.bundlePath.hasPrefix("/Applications/") }
    static var runningFromDiskImageOrDownloads: Bool {
        let p = Bundle.main.bundlePath
        return p.hasPrefix("/Volumes/") || p.contains("/Downloads/") || p.contains("/Desktop/")
    }

    /// Offer to move to /Applications when run from a disk image or Downloads; offer to trash duplicates otherwise.
    static func tidyCopies(on window: NSWindow, then: @escaping () -> Void) {
        if !runningFromApplications && runningFromDiskImageOrDownloads {
            let a = NSAlert()
            a.messageText = "Install Convertify into Applications?"
            a.informativeText = "Convertify is running from \(Bundle.main.bundlePath.hasPrefix("/Volumes/") ? "the disk image" : "the Downloads folder"). Copying it to the Applications folder and running it from there keeps the Finder services in one place and avoids leftover copies."
            a.addButton(withTitle: "Install and Relaunch"); a.addButton(withTitle: "Not Now")
            a.beginSheetModal(for: window) { r in
                if r == .alertFirstButtonReturn { installIntoApplicationsAndRelaunch() } else { then() }
            }
            return
        }
        let dups = duplicateCopies()
        guard runningFromApplications, !dups.isEmpty else { then(); return }
        let a = NSAlert()
        a.messageText = "Other copies of Convertify found"
        a.informativeText = "Only the copy in the Applications folder should stay, otherwise macOS may register the Finder services from the wrong one. Move these to the Trash?\n\n" + dups.map { "• " + $0.path }.joined(separator: "\n")
        a.addButton(withTitle: "Move to Trash"); a.addButton(withTitle: "Keep Them")
        a.beginSheetModal(for: window) { r in
            if r == .alertFirstButtonReturn {
                for d in dups {
                    do { try FileManager.default.trashItem(at: d, resultingItemURL: nil); Log.write("trashed duplicate copy: \(d.path)") }
                    catch { Log.write("could not trash \(d.path): \(error.localizedDescription)") }
                }
                let lsr = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
                let p = Process(); p.executableURL = URL(fileURLWithPath: lsr); p.arguments = ["-f", Bundle.main.bundlePath]
                p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice; try? p.run(); p.waitUntilExit()
                FirstLaunch.refreshServices()
            }
            then()
        }
    }

    static func installIntoApplicationsAndRelaunch() {
        replaceInstalledApp(with: Bundle.main.bundleURL)
    }

    /// Replaces /Applications/Convertify.app with `source` and relaunches. Done by a detached shell so the running app can quit first.
    static func replaceInstalledApp(with source: URL) {
        let target = "/Applications/Convertify.app"
        let script = """
        sleep 1
        rm -rf "\(target)"
        ditto "\(source.path)" "\(target)"
        xattr -dr com.apple.quarantine "\(target)" 2>/dev/null
        case "\(source.path)" in "\(NSTemporaryDirectory())"*) rm -rf "\(source.path)";; esac
        /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "\(target)"
        /System/Library/CoreServices/pbs -flush; /System/Library/CoreServices/pbs -update
        open "\(target)"
        """
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/zsh"); p.arguments = ["-c", script]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try? p.run()
        Log.write("installing \(source.path) into \(target) and relaunching")
        NSApp.terminate(nil)
    }

    // MARK: Check for Updates
    // Manifest: {"version":"1.4","url":"https://.../Convertify.dmg","sha256":"...","size":123,"notes":["..."]}
    static let defaultManifestURL = "https://github.com/jakobrosin/convertify/releases/latest/download/convertify-update.json"
    static var manifestURL: String { Prefs.d.string(forKey: "updateManifestURL") ?? defaultManifestURL }

    static func checkForUpdates(on window: NSWindow, quiet: Bool = false) {
        guard let url = URL(string: manifestURL), !manifestURL.isEmpty else {
            if !quiet {
                let a = NSAlert(); a.messageText = "No update location set"
                a.informativeText = "Convertify does not know where to look for updates. The person who gave you Convertify can provide a manifest address; set it with:\ndefaults write com.jakobrosin.convertify updateManifestURL \"https://...\""
                a.beginSheetModal(for: window) { _ in }
            }
            return
        }
        var req = URLRequest(url: url); req.cachePolicy = .reloadIgnoringLocalCacheData; req.timeoutInterval = 20
        URLSession.shared.dataTask(with: req) { data, _, err in
            DispatchQueue.main.async {
                guard let data = data, let m = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let newVersion = m["version"] as? String, let dl = m["url"] as? String, let dlURL = URL(string: dl) else {
                    if !quiet { let a = NSAlert(); a.messageText = "Could not check for updates"; a.informativeText = err?.localizedDescription ?? "The update manifest could not be read."; a.beginSheetModal(for: window) { _ in } }
                    return
                }
                if !isNewer(newVersion, than: version) {
                    if !quiet { let a = NSAlert(); a.messageText = "Convertify is up to date"; a.informativeText = "Version \(version) is the newest."; a.beginSheetModal(for: window) { _ in } }
                    return
                }
                let notes = (m["notes"] as? [String] ?? []).map { "• " + $0 }.joined(separator: "\n")
                let a = NSAlert()
                a.messageText = "Convertify \(newVersion) is available"
                a.informativeText = "You have \(version).\n\n" + (notes.isEmpty ? "" : notes + "\n\n") + "Download and Install replaces the copy in Applications and relaunches. Nothing is left behind."
                a.addButton(withTitle: "Download and Install"); a.addButton(withTitle: "Later")
                a.beginSheetModal(for: window) { r in
                    guard r == .alertFirstButtonReturn else { return }
                    downloadAndInstall(dlURL, sha256: m["sha256"] as? String, size: m["size"] as? Int, on: window)
                }
            }
        }.resume()
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    static func downloadAndInstall(_ url: URL, sha256: String?, size: Int?, on window: NSWindow) {
        Log.write("downloading update from \(url)")
        URLSession.shared.downloadTask(with: url) { tmp, _, err in
            // The temporary download is deleted when this handler returns, so keep it now.
            let dmg = URL(fileURLWithPath: NSTemporaryDirectory() + "convertify-update-\(UUID().uuidString).dmg")
            var kept = false
            if let tmp = tmp, (try? FileManager.default.moveItem(at: tmp, to: dmg)) != nil { kept = true }
            DispatchQueue.main.async {
                guard kept else { fail("The download failed. \(err?.localizedDescription ?? "")", window); return }
                if let size = size, let real = try? FileManager.default.attributesOfItem(atPath: dmg.path)[.size] as? Int, real != size {
                    try? FileManager.default.removeItem(at: dmg); fail("The downloaded file has the wrong size, so it was discarded.", window); return
                }
                if let sha = sha256?.lowercased(), !sha.isEmpty {
                    let got = sha256Hex(of: dmg)
                    if got != sha {
                        Log.write("checksum mismatch: expected \(sha) got \(got)")
                        try? FileManager.default.removeItem(at: dmg); fail("The downloaded file failed its checksum, so it was discarded.", window); return
                    }
                }
                let mount = NSTemporaryDirectory() + "convertify-update-mount-\(UUID().uuidString)"
                let att = runTool("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-mountpoint", mount, dmg.path])
                guard att.status == 0 else { try? FileManager.default.removeItem(at: dmg); fail("The disk image could not be opened.", window); return }
                let newApp = URL(fileURLWithPath: mount + "/Convertify.app")
                guard FileManager.default.fileExists(atPath: newApp.path) else {
                    _ = runTool("/usr/bin/hdiutil", ["detach", mount, "-force"]); try? FileManager.default.removeItem(at: dmg)
                    fail("The disk image does not contain Convertify.", window); return
                }
                // Copy out of the image first so it can be detached, then replace and relaunch.
                let staged = URL(fileURLWithPath: NSTemporaryDirectory() + "convertify-update-\(UUID().uuidString).app")
                let copy = runTool("/usr/bin/ditto", [newApp.path, staged.path])
                _ = runTool("/usr/bin/hdiutil", ["detach", mount, "-force"])
                try? FileManager.default.removeItem(at: dmg)
                guard copy.status == 0 else { fail("The new version could not be copied.", window); return }
                replaceInstalledApp(with: staged)
            }
        }.resume()
    }
    static func sha256Hex(of url: URL) -> String {
        guard let h = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? h.close() }
        var hasher = SHA256()
        while let chunk = try? h.read(upToCount: 4 * 1024 * 1024), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
    static func fail(_ msg: String, _ window: NSWindow) {
        Log.write("update failed: \(msg)")
        let a = NSAlert(); a.messageText = "Update not installed"; a.informativeText = msg; a.beginSheetModal(for: window) { _ in }
    }
}

// MARK: - Preferences window

final class PreferencesWindowController: NSWindowController {
    let keepOpen = NSButton(checkboxWithTitle: "Keep the window open after jobs finish", target: nil, action: nil)
    let quitDelay = NSPopUpButton(frame: .zero, pullsDown: false)
    let bringFront = NSButton(checkboxWithTitle: "Bring the window to the front when a job starts", target: nil, action: nil)
    let notify = NSButton(checkboxWithTitle: "Show a notification when a job finishes", target: nil, action: nil)
    let sound = NSButton(checkboxWithTitle: "Play a sound when a job finishes", target: nil, action: nil)
    let limit = NSPopUpButton(frame: .zero, pullsDown: false)
    let days = NSPopUpButton(frame: .zero, pullsDown: false)
    let confirm = NSButton(checkboxWithTitle: "Ask before clearing the history", target: nil, action: nil)
    let clearQuit = NSButton(checkboxWithTitle: "Clear the history when Convertify quits", target: nil, action: nil)
    let tabs = NSTabView()

    static let delayChoices: [(String, Int)] = [("3 seconds", 3), ("6 seconds", 6), ("10 seconds", 10), ("15 seconds", 15), ("30 seconds", 30)]
    static let limitChoices: [(String, Int)] = [("25 files", 25), ("50 files", 50), ("100 files", 100), ("200 files", 200), ("No limit", 0)]
    static let daysChoices: [(String, Int)] = [("Never", 0), ("After 7 days", 7), ("After 30 days", 30), ("After 90 days", 90)]

    init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 300), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Convertify Preferences"
        w.center()
        super.init(window: w)

        func popup(_ p: NSPopUpButton, _ choices: [(String, Int)], label: String) {
            for c in choices { p.addItem(withTitle: c.0) }
            p.setAccessibilityLabel(label)
            p.target = self; p.action = #selector(changed)
        }
        popup(quitDelay, Self.delayChoices, label: "Quit this long after a successful job")
        popup(limit, Self.limitChoices, label: "Keep at most this many finished files")
        popup(days, Self.daysChoices, label: "Drop finished files from the history")
        for b in [keepOpen, bringFront, notify, sound, confirm, clearQuit] { b.target = self; b.action = #selector(changed) }

        func labeled(_ text: String, _ control: NSView) -> NSView {
            let l = NSTextField(labelWithString: text)
            let row = NSStackView(views: [l, control]); row.orientation = .horizontal; row.spacing = 8; row.alignment = .firstBaseline
            return row
        }
        func page(_ title: String, _ views: [NSView]) {
            let stack = NSStackView(views: views); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
            stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
            let item = NSTabViewItem(identifier: title); item.label = title; item.view = stack
            tabs.addTabViewItem(item)
        }
        page("General", [keepOpen, labeled("After a successful job, quit after:", quitDelay), bringFront, notify, sound])
        page("History", [labeled("Keep at most:", limit), labeled("Drop old entries:", days), confirm, clearQuit])
        tabs.setAccessibilityLabel("Preference sections")
        let root = NSStackView(views: [tabs]); root.orientation = .vertical; root.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        tabs.translatesAutoresizingMaskIntoConstraints = false
        w.contentView = root
        NSLayoutConstraint.activate([tabs.widthAnchor.constraint(equalToConstant: 490), tabs.heightAnchor.constraint(greaterThanOrEqualToConstant: 240)])
        load()
    }
    required init?(coder: NSCoder) { nil }

    private func select(_ p: NSPopUpButton, _ choices: [(String, Int)], value: Int) {
        p.selectItem(at: choices.firstIndex { $0.1 == value } ?? choices.firstIndex { $0.1 >= value } ?? 0)
    }
    func load() {
        keepOpen.state = Prefs.keepWindowOpen ? .on : .off
        select(quitDelay, Self.delayChoices, value: Prefs.quitDelay)
        bringFront.state = Prefs.bringToFront ? .on : .off
        notify.state = Prefs.notifyOnFinish ? .on : .off
        sound.state = Prefs.soundOnFinish ? .on : .off
        select(limit, Self.limitChoices, value: Prefs.historyLimit)
        select(days, Self.daysChoices, value: Prefs.historyDays)
        confirm.state = Prefs.confirmClear ? .on : .off
        clearQuit.state = Prefs.clearOnQuit ? .on : .off
    }
    @objc func changed() { save() }
    func save() {
        Prefs.keepWindowOpen = keepOpen.state == .on
        Prefs.quitDelay = Self.delayChoices[max(0, quitDelay.indexOfSelectedItem)].1
        Prefs.bringToFront = bringFront.state == .on
        Prefs.notifyOnFinish = notify.state == .on
        Prefs.soundOnFinish = sound.state == .on
        Prefs.historyLimit = Self.limitChoices[max(0, limit.indexOfSelectedItem)].1
        Prefs.historyDays = Self.daysChoices[max(0, days.indexOfSelectedItem)].1
        Prefs.confirmClear = confirm.state == .on
        Prefs.clearOnQuit = clearQuit.state == .on
        Engine.shared.pruneNow()
    }
    override func showWindow(_ sender: Any?) { load(); super.showWindow(sender); window?.makeKeyAndOrderFront(nil) }
}

// MARK: - App delegate, menus, services

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, NSMenuItemValidation {
    static var shared: AppDelegate!
    var windowController: ProgressWindowController!
    var prefsController: PreferencesWindowController?
    var infoController: MediaInfoWindowController?
    var quitTimer: Timer?
    var notificationsAllowed = false

    override init() { super.init(); AppDelegate.shared = self }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.register()
        windowController = ProgressWindowController()
        Engine.shared.onChange = { [weak self] in self?.windowController.refresh() }
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { ok, _ in self.notificationsAllowed = ok }
        buildMenus()
        // First-launch dialogs a moment later, once the app is fully up (so they are proper, accessible windows).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            if let w = self.windowController.window, w.isVisible { FirstLaunch.runIfNeeded(on: w) }
        }

        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--preset"), i + 1 < args.count, let preset = Preset.byId(args[i + 1]) {
            start(preset, args[(i + 2)...].map { URL(fileURLWithPath: $0) })
        } else {
            showWindow(nil)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(nil); return true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if Engine.shared.isBusy {
            let a = NSAlert(); a.messageText = "A conversion is still running."; a.informativeText = "Quit anyway? The current file will be cancelled and its partial output deleted."
            a.addButton(withTitle: "Quit"); a.addButton(withTitle: "Keep Running")
            if a.runModal() != .alertFirstButtonReturn { return .terminateCancel }
            Engine.shared.cancelAll()
        }
        return .terminateNow
    }
    func applicationWillTerminate(_ notification: Notification) {
        if Prefs.clearOnQuit { Engine.shared.clearHistory() }
    }
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let m = NSMenu()
        m.addItem(withTitle: "Show Convertify Window", action: #selector(showWindow(_:)), keyEquivalent: "")
        m.addItem(withTitle: "Open Files…", action: #selector(openFiles(_:)), keyEquivalent: "")
        return m
    }

    // Files dropped on the icon, or Open With: ask which conversion.
    func application(_ application: NSApplication, open urls: [URL]) { askPreset(for: urls) }

    func askPreset(for urls: [URL]) {
        let alert = NSAlert()
        alert.messageText = "Convert \(urls.count) file\(urls.count == 1 ? "" : "s")"
        alert.informativeText = "Choose the conversion."
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 280, height: 26), pullsDown: false)
        for p in Preset.all { popup.addItem(withTitle: p.title) }
        popup.setAccessibilityLabel("Conversion")
        alert.accessoryView = popup
        alert.window.initialFirstResponder = popup
        alert.addButton(withTitle: "Convert"); alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { start(Preset.all[popup.indexOfSelectedItem], urls) }
    }

    // MARK: window handling

    @objc func showWindow(_ sender: Any?) {
        quitTimer?.invalidate(); quitTimer = nil
        windowController.refresh()
        windowController.showWindow(nil)
        windowController.window?.makeFirstResponder(windowController.table)
        windowController.window?.orderFrontRegardless()
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)
        windowController.window?.makeKeyAndOrderFront(nil)
    }
    func showWindowForJob() {
        quitTimer?.invalidate(); quitTimer = nil
        windowController.refresh()
        if Prefs.bringToFront { showWindow(nil) }
        else { windowController.showWindow(nil); windowController.window?.orderFrontRegardless() }
    }
    func closeWindow() {
        if Engine.shared.isBusy || Prefs.keepWindowOpen { windowController.window?.orderOut(nil) } else { NSApp.terminate(nil) }
    }

    func start(_ preset: Preset, _ files: [URL]) {
        guard !files.isEmpty else { return }
        Engine.shared.enqueue(Job(preset: preset, files: files))
        showWindowForJob()
    }

    func jobFinished(_ job: Job) {
        let ok = job.failures.isEmpty && !job.cancelled
        if Prefs.soundOnFinish { NSSound(named: ok ? "Glass" : "Sosumi")?.play() }
        var body: String
        if job.cancelled { body = "Cancelled." }
        else if ok { body = job.files.count == 1 ? "Done: \(job.entries.first?.output ?? "")" : "Done: \(job.okCount) of \(job.files.count) files" }
        else { body = "\(job.failures.count) of \(job.files.count) failed. \(job.failures.first ?? "")" }
        if !job.skips.isEmpty { body += " Skipped: " + job.skips.joined(separator: "; ") }
        if Prefs.notifyOnFinish { sendNotification(title: job.preset.title, body: body) }
        windowController.refresh()
        if !Engine.shared.isBusy && !Prefs.keepWindowOpen && Engine.shared.jobs.allSatisfy({ $0.failures.isEmpty && !$0.cancelled }) {
            quitTimer?.invalidate()
            quitTimer = Timer.scheduledTimer(withTimeInterval: Double(Prefs.quitDelay), repeats: false) { _ in
                if !Engine.shared.isBusy && !Prefs.keepWindowOpen { NSApp.terminate(nil) }
            }
        }
    }

    func sendNotification(title: String, body: String) {
        if notificationsAllowed {
            let c = UNMutableNotificationContent(); c.title = title; c.body = body
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
        } else {
            // macOS refuses notification permission for locally signed apps; AppleScript notifications still work and VoiceOver reads them.
            let esc = { (t: String) in t.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", "display notification \"\(esc(body))\" with title \"\(esc(title))\""]
            p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
            try? p.run()
        }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler handler: @escaping (UNNotificationPresentationOptions) -> Void) { handler([.banner]) }

    // MARK: menus

    func buildMenus() {
        let main = NSMenu()
        func menu(_ title: String, _ build: (NSMenu) -> Void) { let i = NSMenuItem(); let m = NSMenu(title: title); build(m); i.submenu = m; main.addItem(i) }
        func item(_ m: NSMenu, _ title: String, _ sel: Selector?, _ key: String = "", _ mods: NSEvent.ModifierFlags = [.command]) {
            let it = NSMenuItem(title: title, action: sel, keyEquivalent: key); it.keyEquivalentModifierMask = mods; m.addItem(it)
        }
        menu("Convertify") { m in
            item(m, "About Convertify", #selector(showAbout(_:)))
            item(m, "Check for Updates…", #selector(checkForUpdates(_:)))
            m.addItem(.separator())
            item(m, "Preferences…", #selector(showPreferences(_:)), ",")
            m.addItem(.separator())
            item(m, "Hide Convertify", #selector(NSApplication.hide(_:)), "h")
            item(m, "Quit Convertify", #selector(NSApplication.terminate(_:)), "q")
        }
        menu("File") { m in
            item(m, "Open Files…", #selector(openFiles(_:)), "o")
            m.addItem(.separator())
            item(m, "Reveal Output in Finder", #selector(revealOutput(_:)), "r")
            item(m, "Open Output", #selector(openOutput(_:)), String(UnicodeScalar(NSDownArrowFunctionKey)!))
            item(m, "Reveal Source in Finder", #selector(revealSource(_:)), "r", [.command, .shift])
            item(m, "Retry This File", #selector(retry(_:)), "t")
            item(m, "Show Details", #selector(showDetails(_:)), "d")
            item(m, "Media Info", #selector(mediaInfoForSelection(_:)), "i", [.command, .shift])
            m.addItem(.separator())
            item(m, "Close Window", #selector(closeWindowItem(_:)), "w")
        }
        menu("Edit") { m in
            item(m, "Cut", #selector(NSText.cut(_:)), "x")
            item(m, "Copy", #selector(NSText.copy(_:)), "c")
            item(m, "Paste", #selector(NSText.paste(_:)), "v")
            item(m, "Select All", #selector(NSText.selectAll(_:)), "a")
            m.addItem(.separator())
            item(m, "Remove from History", #selector(removeSelected(_:)), String(UnicodeScalar(NSBackspaceCharacter)!))
            item(m, "Clear History…", #selector(clearHistory(_:)), String(UnicodeScalar(NSBackspaceCharacter)!), [.command, .shift])
        }
        menu("Convert") { m in
            let groups: [[String]] = [["mp3", "mp3low", "aac", "opus", "ogg"], ["wav", "extractaudio"], ["mp4", "mov", "mkv", "imagevideo"], ["jpeg", "png"], ["flac2wav", "wav2flac"]]
            for (gi, g) in groups.enumerated() {
                if gi > 0 { m.addItem(.separator()) }
                for id in g { guard let p = Preset.byId(id) else { continue }
                    let it = NSMenuItem(title: p.title + "…", action: #selector(convertMenu(_:)), keyEquivalent: ""); it.representedObject = p.id; m.addItem(it) }
            }
            m.addItem(.separator())
            item(m, "Media Info…", #selector(mediaInfoChoose(_:)))
        }
        menu("Job") { m in
            item(m, "Cancel This File", #selector(cancelCurrent(_:)), ".")
            item(m, "Cancel All", #selector(cancelAll(_:)), ".", [.command, .shift])
        }
        menu("Window") { m in
            item(m, "Show Convertify Window", #selector(showWindow(_:)), "0")
            item(m, "Speak Status", #selector(speakStatus(_:)), "i")
            item(m, "Minimize", #selector(NSWindow.miniaturize(_:)), "m")
            item(m, "Zoom", #selector(NSWindow.zoom(_:)))
            NSApp.windowsMenu = m
        }
        menu("Help") { m in
            item(m, "Convertify Help", #selector(showHelp(_:)), "?")
            item(m, "Convertify Manual", #selector(showManual(_:)))
            item(m, "Convertify on GitHub", #selector(openGitHub(_:)))
            item(m, "Open Log File", #selector(openLog(_:)))
            m.addItem(.separator())
            item(m, "Remove Old SendTo Encoder Services…", #selector(removeOldServices(_:)))
            item(m, "Refresh Services Menu (Relaunch Finder)", #selector(relaunchFinder(_:)))
            item(m, "Show History File in Finder", #selector(revealHistory(_:)))
            NSApp.helpMenu = m
        }
        NSApp.mainMenu = main
    }

    func rowMenu() -> NSMenu {
        let m = NSMenu()
        m.addItem(withTitle: "Open Output", action: #selector(openOutput(_:)), keyEquivalent: "")
        m.addItem(withTitle: "Reveal Output in Finder", action: #selector(revealOutput(_:)), keyEquivalent: "")
        m.addItem(withTitle: "Reveal Source in Finder", action: #selector(revealSource(_:)), keyEquivalent: "")
        m.addItem(withTitle: "Retry This File", action: #selector(retry(_:)), keyEquivalent: "")
        m.addItem(withTitle: "Show Details", action: #selector(showDetails(_:)), keyEquivalent: "")
        m.addItem(withTitle: "Media Info", action: #selector(mediaInfoForSelection(_:)), keyEquivalent: "")
        m.addItem(withTitle: "Copy Row", action: #selector(copyRow(_:)), keyEquivalent: "")
        m.addItem(.separator())
        m.addItem(withTitle: "Remove from History", action: #selector(removeSelected(_:)), keyEquivalent: "")
        return m
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let e = windowController?.selectedEntry
        switch item.action {
        case #selector(openOutput(_:)), #selector(revealOutput(_:)): return e?.outputPath.map { FileManager.default.fileExists(atPath: $0) } ?? false
        case #selector(revealSource(_:)): return e.map { FileManager.default.fileExists(atPath: $0.filePath) } ?? false
        case #selector(retry(_:)): return e.map { $0.isFinished && $0.presetId != nil && FileManager.default.fileExists(atPath: $0.filePath) } ?? false
        case #selector(removeSelected(_:)): return windowController?.selectedEntries.contains { $0.isFinished } ?? false
        case #selector(clearHistory(_:)): return Engine.shared.entries.contains { $0.isFinished }
        case #selector(cancelCurrent(_:)), #selector(cancelAll(_:)): return Engine.shared.isBusy
        case #selector(copyRow(_:)), #selector(showDetails(_:)), #selector(mediaInfoForSelection(_:)): return e != nil
        default: return true
        }
    }

    // MARK: actions

    @objc func openFiles(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        panel.message = "Choose files to convert"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, !panel.urls.isEmpty { askPreset(for: panel.urls) }
    }
    @objc func convertMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let preset = Preset.byId(id) else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        panel.message = "Choose files for \(preset.title)"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, !panel.urls.isEmpty { start(preset, panel.urls) }
    }
    @objc func openOutput(_ sender: Any?) {
        guard let p = windowController.selectedEntry?.outputPath, FileManager.default.fileExists(atPath: p) else { NSSound.beep(); return }
        NSWorkspace.shared.open(URL(fileURLWithPath: p))
    }
    @objc func revealOutput(_ sender: Any?) {
        guard let p = windowController.selectedEntry?.outputPath, FileManager.default.fileExists(atPath: p) else { NSSound.beep(); return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)])
    }
    @objc func revealSource(_ sender: Any?) {
        guard let e = windowController.selectedEntry, FileManager.default.fileExists(atPath: e.filePath) else { NSSound.beep(); return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: e.filePath)])
    }
    @objc func retry(_ sender: Any?) {
        guard let e = windowController.selectedEntry, let id = e.presetId, let preset = Preset.byId(id) else { NSSound.beep(); return }
        start(preset, [URL(fileURLWithPath: e.filePath)])
    }
    @objc func copyRow(_ sender: Any?) {
        let list = windowController.selectedEntries
        guard !list.isEmpty else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(list.map { $0.spoken }.joined(separator: "\n"), forType: .string)
    }
    @objc func removeSelected(_ sender: Any?) {
        let finished = windowController.selectedEntries.filter { $0.isFinished }
        guard !finished.isEmpty else { NSSound.beep(); return }
        let row = windowController.table.selectedRowIndexes.first ?? 0
        Engine.shared.remove(finished)
        let n = Engine.shared.entries.count
        if n > 0 { windowController.table.selectRowIndexes(IndexSet(integer: min(row, n - 1)), byExtendingSelection: false) }
    }
    @objc func clearHistory(_ sender: Any?) {
        let count = Engine.shared.entries.filter { $0.isFinished }.count
        guard count > 0 else { return }
        if Prefs.confirmClear {
            let a = NSAlert(); a.messageText = "Clear the history?"; a.informativeText = "Removes \(count) finished file\(count == 1 ? "" : "s") from the list. Converted files on disk are not touched."
            a.addButton(withTitle: "Clear"); a.addButton(withTitle: "Cancel")
            guard a.runModal() == .alertFirstButtonReturn else { return }
        }
        Engine.shared.clearHistory()
    }
    @objc func cancelCurrent(_ sender: Any?) { Engine.shared.cancelCurrentFile() }
    @objc func cancelAll(_ sender: Any?) { Engine.shared.cancelAll() }
    @objc func closeWindowItem(_ sender: Any?) {
        guard let key = NSApp.keyWindow else { closeWindow(); return }
        if key == windowController.window { closeWindow() } else { key.orderOut(nil) }   // preferences, media info: just close that window
    }
    @objc func showPreferences(_ sender: Any?) {
        if prefsController == nil { prefsController = PreferencesWindowController() }
        NSApp.activate(ignoringOtherApps: true)
        prefsController?.showWindow(nil)
    }
    @objc func showAbout(_ sender: Any?) {
        let ff = findTool("ffmpeg") ?? "not found"
        let credits = NSAttributedString(string: "Converts audio and video from the Finder Services menu.\n\nDescended from the Windows SendTo encoders by Andre Louis (github.com/OnjLouis) and arfy.\nSource and updates: github.com/jakobrosin/convertify\nMIT licence for Convertify; bundled tools keep their own licences, see the manual.\n\nffmpeg: \(ff)\noggenc: \(findTool("oggenc") ?? "not found")\nflac: \(findTool("flac") ?? "not found")\n\nLog: \(Log.url.path)\nHistory: \(History.url.path)")
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits, .applicationName: "Convertify", .applicationVersion: "1.3"])
    }
    @objc func showHelp(_ sender: Any?) {
        let a = NSAlert()
        a.messageText = "Convertify Help"
        a.informativeText = """
        Start a conversion: right-click audio or video files in Finder and pick an action from the Services menu, or use the Convert menu here, or drop files on the app icon.

        The Files table lists every file, newest first: file name, status, progress, started time, action, result. Arrow keys, Home, End, Page Up and Page Down move through it. Return opens the output. Delete removes the selected finished rows; Command A selects all rows first. Command R reveals the output in Finder, Command Shift R the source. Command T retries the selected file. Command C copies the row as text.

        Cancel This File is Command Period, Cancel All is Command Shift Period. Clear History is Command Shift Delete. Command I makes VoiceOver speak the current status. Command D shows the full details of the selected row. Escape hides the window without quitting.

        Nothing is ever overwritten: a name clash gets a number, converting to the same format adds "converted". The two "and Delete" actions remove the source only after the result was verified.

        Preferences (Command comma): keep the window open, quit delay, bring to front, notification, sound, history limits, clear history on quit.

        The full manual is in the Help menu under Convertify Manual.
        """
        a.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
    @objc func openLog(_ sender: Any?) { NSWorkspace.shared.open(Log.url) }
    @objc func openGitHub(_ sender: Any?) { NSWorkspace.shared.open(URL(string: "https://github.com/jakobrosin/convertify")!) }
    @objc func hideWindow(_ sender: Any?) { windowController.window?.orderOut(nil) }

    /// Have VoiceOver announce the current status without moving focus.
    @objc func speakStatus(_ sender: Any?) {
        let text: String
        if let e = Engine.shared.activeEntry { text = "Converting \(e.fileName), \(e.progressText)" }
        else if let last = Engine.shared.entries.first { text = "No encode running. Last: \(last.spoken)" }
        else { text = "No encode running." }
        let target: Any = windowController.window ?? NSApp!
        NSAccessibility.post(element: target, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    /// Full details of the selected row in a sheet, selectable and copyable.
    @objc func showDetails(_ sender: Any?) {
        guard let e = windowController.selectedEntry, let w = windowController.window else { NSSound.beep(); return }
        var lines: [String] = []
        lines.append("File: \(e.fileName)")
        lines.append("Location: \(e.filePath)")
        lines.append("Conversion: \(e.action)")
        lines.append("Status: \(e.statusText)")
        if !e.progressText.isEmpty { lines.append("Progress: \(e.progressText)") }
        if let d = e.started { lines.append("Started: \(DateFormatter.localizedString(from: d, dateStyle: .medium, timeStyle: .short))") }
        if let d = e.finished { lines.append("Finished: \(DateFormatter.localizedString(from: d, dateStyle: .medium, timeStyle: .short))") }
        if let o = e.outputPath { lines.append("Output: \(o)") }
        if let m = e.message, !m.isEmpty { lines.append("Message: \(m)") }
        let a = NSAlert()
        a.messageText = e.fileName
        a.informativeText = ""
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 460, height: 160))
        tv.string = lines.joined(separator: "\n"); tv.isEditable = false; tv.isSelectable = true; tv.font = .systemFont(ofSize: 13)
        tv.setAccessibilityLabel("Details")
        let sc = NSScrollView(frame: NSRect(x: 0, y: 0, width: 460, height: 160)); sc.documentView = tv; sc.hasVerticalScroller = true; sc.borderType = .bezelBorder
        a.accessoryView = sc
        a.window.initialFirstResponder = tv
        a.addButton(withTitle: "OK"); a.addButton(withTitle: "Copy")
        a.beginSheetModal(for: w) { r in
            if r == .alertSecondButtonReturn { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string) }
        }
    }
    @objc func removeOldServices(_ sender: Any?) {
        showWindow(nil)
        guard let w = windowController.window else { return }
        if FirstLaunch.findOldWorkflows().isEmpty {
            let a = NSAlert(); a.messageText = "No old SendTo encoder services found."; a.informativeText = "Nothing from the script-based version is installed in your Library Services folder."
            a.beginSheetModal(for: w) { _ in }
        } else { FirstLaunch.offerToRemoveOldWorkflows(on: w) {} }
    }
    @objc func relaunchFinder(_ sender: Any?) { FirstLaunch.refreshServices(); FirstLaunch.relaunchFinder() }
    @objc func showManual(_ sender: Any?) {
        if let u = Bundle.main.url(forResource: "Manual", withExtension: "html") { NSWorkspace.shared.open(u) } else { NSSound.beep() }
    }
    @objc func revealHistory(_ sender: Any?) { NSWorkspace.shared.activateFileViewerSelecting([History.url]) }

    // MARK: Services (NSMessage in Info.plist = method name)
    private func files(from pboard: NSPasteboard) -> [URL] {
        if let urls = pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty { return urls }
        if let names = pboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] { return names.map { URL(fileURLWithPath: $0) } }
        return []
    }
    private func service(_ id: String, _ pboard: NSPasteboard) {
        guard let preset = Preset.byId(id) else { return }
        let urls = files(from: pboard)
        Log.write("service \(preset.title): \(urls.count) file(s)")
        start(preset, urls)
    }
    @objc func svc_mp3(_ p: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) { service("mp3", p) }
    @objc func svc_mp3low(_ p: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) { service("mp3low", p) }
    @objc func svc_aac(_ p: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) { service("aac", p) }
    @objc func svc_opus(_ p: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) { service("opus", p) }
    @objc func svc_ogg(_ p: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) { service("ogg", p) }
    @objc func svc_wav(_ p: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) { service("wav", p) }
    @objc func svc_flac2wav(_ p: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) { service("flac2wav", p) }
    @objc func svc_wav2flac(_ p: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) { service("wav2flac", p) }
    @objc func svc_mp4(_ p: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) { service("mp4", p) }
    @objc func svc_mov(_ p: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) { service("mov", p) }
    @objc func svc_imagevideo(_ p: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) { service("imagevideo", p) }
    @objc func svc_mkv(_ p: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) { service("mkv", p) }
    @objc func svc_extractaudio(_ p: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) { service("extractaudio", p) }
    @objc func svc_jpeg(_ p: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) { service("jpeg", p) }
    @objc func svc_png(_ p: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) { service("png", p) }
    @objc func svc_mediainfo(_ p: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let urls = files(from: p); Log.write("service Media Info: \(urls.count) file(s)"); showMediaInfo(urls)
    }
    func showMediaInfo(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        if infoController == nil { infoController = MediaInfoWindowController() }
        infoController?.show(urls)
    }
    @objc func mediaInfoForSelection(_ sender: Any?) {
        guard let e = windowController.selectedEntry else { NSSound.beep(); return }
        let src = URL(fileURLWithPath: e.filePath)
        let out = e.outputPath.map { URL(fileURLWithPath: $0) }
        var list: [URL] = []
        if FileManager.default.fileExists(atPath: src.path) { list.append(src) }
        if let o = out, FileManager.default.fileExists(atPath: o.path) { list.append(o) }
        if list.isEmpty { NSSound.beep(); return }
        showMediaInfo(list)
    }
    @objc func mediaInfoChoose(_ sender: Any?) {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        panel.message = "Choose files to inspect"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, !panel.urls.isEmpty { showMediaInfo(panel.urls) }
    }
    @objc func checkForUpdates(_ sender: Any?) {
        showWindow(nil)
        if let w = windowController.window { Maintenance.checkForUpdates(on: w) }
    }
}
