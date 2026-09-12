// Convertify — Finder services that convert audio and video with ffmpeg.
// Single-file AppKit app. Build with build.sh.

import AppKit
import UserNotifications

// MARK: - Tools

func findTool(_ name: String) -> String? {
    // Bundled copies first (Contents/MacOS), then Homebrew, then the system.
    let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/" + name).path
    if FileManager.default.isExecutableFile(atPath: bundled) { return bundled }
    for dir in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"] {
        let p = dir + "/" + name
        if FileManager.default.isExecutableFile(atPath: p) { return p }
    }
    return nil
}

struct RunResult { let status: Int32; let out: String; let err: String }

/// Run a tool synchronously and capture its output (for ffprobe and other short calls).
func runTool(_ path: String, _ args: [String]) -> RunResult {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    p.standardInput = FileHandle.nullDevice
    let out = Pipe(), err = Pipe()
    p.standardOutput = out; p.standardError = err
    do { try p.run() } catch { return RunResult(status: 127, out: "", err: "\(error)") }
    let o = out.fileHandleForReading.readDataToEndOfFile()
    let e = err.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return RunResult(status: p.terminationStatus,
                     out: String(decoding: o, as: UTF8.self),
                     err: String(decoding: e, as: UTF8.self))
}

func ffprobe(_ file: URL, entries: String, audioStream: Bool = false) -> String {
    guard let probe = findTool("ffprobe") else { return "" }
    var args = ["-v", "error"]
    if audioStream { args += ["-select_streams", "a:0"] }
    args += ["-show_entries", entries, "-of", "csv=p=0", file.path]
    return runTool(probe, args).out.trimmingCharacters(in: .whitespacesAndNewlines)
}

func audioCodec(_ f: URL) -> String { ffprobe(f, entries: "stream=codec_name", audioStream: true).components(separatedBy: "\n").first ?? "" }
func hasVideo(_ f: URL) -> Bool { !runTool(findTool("ffprobe") ?? "/usr/bin/false", ["-v", "error", "-select_streams", "v:0", "-show_entries", "stream=codec_type", "-of", "csv=p=0", f.path]).out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
func duration(_ f: URL) -> Double? { Double(ffprobe(f, entries: "format=duration")) }
func mediaTag(_ f: URL, _ tag: String) -> String {
    // Tags may live on the container or on the stream (Ogg keeps them on the stream).
    let a = ffprobe(f, entries: "format_tags=\(tag)")
    if !a.isEmpty { return a }
    return ffprobe(f, entries: "stream_tags=\(tag)", audioStream: true)
}

/// PCM codec that preserves the source depth: 24-bit stays 24, 32 stays 32, float PCM stays float, everything else 16-bit.
func pcmCodec(for f: URL) -> String {
    let info = ffprobe(f, entries: "stream=bits_per_raw_sample,sample_fmt", audioStream: true) // "s32,24" or "flt,N/A"
    let parts = info.components(separatedBy: ",")
    let bits = parts.count > 1 ? parts[1] : ""
    switch bits {
    case "24": return "pcm_s24le"
    case "32": return "pcm_s32le"
    default: break
    }
    let codec = audioCodec(f)
    if codec.hasPrefix("pcm_f32") || codec.hasPrefix("pcm_f64") { return "pcm_f32le" }
    return "pcm_s16le"
}

// MARK: - Log

enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Convertify.log")
    static let fmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; return f }()
    static func write(_ s: String) {
        let line = "\(fmt.string(from: Date()))  \(s)\n"
        rotateIfNeeded()
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }
    static func rotateIfNeeded() {
        guard let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int, size > 1_048_576,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let tail = text.components(separatedBy: "\n").suffix(400).joined(separator: "\n")
        try? tail.write(to: url, atomically: true, encoding: .utf8)
    }
    /// Last N result lines for the window.
    static func recent(_ n: Int) -> [String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.components(separatedBy: "\n").filter { $0.contains("  ok:   ") || $0.contains("  FAIL: ") }.suffix(n).map { line in
            // "2026-09-12 08:15:39  ok:   /path/in -> /path/out"  ->  "08:15  MP3 Encode? " keep short: time + result + output name
            let parts = line.components(separatedBy: "  ")
            let time = parts.first.map { String($0.dropFirst(11)) } ?? ""
            if let r = line.range(of: "  ok:   ") {
                let rest = line[r.upperBound...]
                let outName = rest.components(separatedBy: " -> ").last.map { ($0 as NSString).lastPathComponent } ?? ""
                return "\(time)  done: \(outName)"
            } else if let r = line.range(of: "  FAIL: ") {
                return "\(time)  failed: \(line[r.upperBound...])"
            }
            return line
        }
    }
}

// MARK: - Output naming

/// Strip the extension of the last path component only.
func stem(_ url: URL) -> String {
    let name = url.lastPathComponent
    let base: String
    if name.hasPrefix(".") || !name.contains(".") { base = name } else { base = (name as NSString).deletingPathExtension }
    return url.deletingLastPathComponent().appendingPathComponent(base).path
}

/// Never overwrite. Clashes get " 2", " 3"...; converting to the same format gives " converted".
func outputPath(for input: URL, ext: String) -> URL {
    let s = stem(input)
    let same = (s + "." + ext).lowercased() == input.path.lowercased()
    var candidate = same ? "\(s) converted.\(ext)" : "\(s).\(ext)"
    var n = 2
    while FileManager.default.fileExists(atPath: candidate) {
        candidate = same ? "\(s) converted \(n).\(ext)" : "\(s) \(n).\(ext)"
        n += 1
    }
    return URL(fileURLWithPath: candidate)
}

// MARK: - Speech-friendly text

func spokenDuration(_ secs: Double) -> String {
    let s = Int(secs.rounded())
    let h = s / 3600, m = (s % 3600) / 60, r = s % 60
    var parts: [String] = []
    if h > 0 { parts.append("\(h) hour\(h == 1 ? "" : "s")") }
    if m > 0 { parts.append("\(m) minute\(m == 1 ? "" : "s")") }
    if h == 0 && (r > 0 || parts.isEmpty) { parts.append("\(r) second\(r == 1 ? "" : "s")") }
    return parts.joined(separator: " ")
}

// MARK: - Presets

enum PresetKind { case ffmpeg, oggPipe, flacDecodeDelete, flacEncodeDelete, videoMP4, videoMOV, imageAudio }

struct Preset {
    let id: String          // used for the service selector and the command line
    let title: String       // menu title
    let ext: String
    let kind: PresetKind
    let ffmpegArgs: (URL) -> [String]   // args between "-i input" and the output path (ffmpeg kinds only)
    let tools: [String]
    let types: [String]     // NSSendFileTypes

    static let all: [Preset] = [
        Preset(id: "mp3", title: "MP3 Encode", ext: "mp3", kind: .ffmpeg,
               ffmpegArgs: { _ in ["-map", "0:a:0", "-map_metadata", "0", "-id3v2_version", "3", "-c:a", "libmp3lame", "-q:a", "2"] },
               tools: ["ffmpeg"], types: ["public.audio", "public.movie"]),
        Preset(id: "mp3low", title: "MP3 Encode (Low Quality)", ext: "mp3", kind: .ffmpeg,
               ffmpegArgs: { _ in ["-map", "0:a:0", "-map_metadata", "0", "-id3v2_version", "3", "-c:a", "libmp3lame", "-b:a", "64k"] },
               tools: ["ffmpeg"], types: ["public.audio", "public.movie"]),
        Preset(id: "aac", title: "AAC Encode", ext: "m4a", kind: .ffmpeg,
               ffmpegArgs: { _ in ["-map", "0:a:0", "-map_metadata", "0", "-c:a", "aac_at", "-b:a", "128k", "-movflags", "+faststart"] },
               tools: ["ffmpeg"], types: ["public.audio", "public.movie"]),
        Preset(id: "opus", title: "Opus Encode", ext: "opus", kind: .ffmpeg,
               ffmpegArgs: { _ in ["-map", "0:a:0", "-map_metadata", "0", "-c:a", "libopus", "-b:a", "96k", "-vbr", "on"] },
               tools: ["ffmpeg"], types: ["public.audio", "public.movie"]),
        Preset(id: "ogg", title: "OGG Encode", ext: "ogg", kind: .oggPipe,
               ffmpegArgs: { _ in [] }, tools: ["ffmpeg", "oggenc"], types: ["public.audio", "public.movie"]),
        Preset(id: "wav", title: "File to Wav", ext: "wav", kind: .ffmpeg,
               ffmpegArgs: { f in ["-map", "0:a:0", "-c:a", pcmCodec(for: f)] },
               tools: ["ffmpeg"], types: ["public.audio", "public.movie"]),
        Preset(id: "flac2wav", title: "Flac to Wav and Delete", ext: "wav", kind: .flacDecodeDelete,
               ffmpegArgs: { _ in [] }, tools: ["flac"], types: ["public.audio"]),
        Preset(id: "wav2flac", title: "Wav to Flac and Delete", ext: "flac", kind: .flacEncodeDelete,
               ffmpegArgs: { _ in [] }, tools: ["flac", "ffmpeg"], types: ["public.audio"]),
        Preset(id: "mp4", title: "File to MP4", ext: "mp4", kind: .videoMP4,
               ffmpegArgs: { _ in [] }, tools: ["ffmpeg"], types: ["public.movie"]),
        Preset(id: "mov", title: "File to MOV", ext: "mov", kind: .videoMOV,
               ffmpegArgs: { _ in [] }, tools: ["ffmpeg"], types: ["public.movie"]),
        Preset(id: "imagevideo", title: "Image + Audio to Video", ext: "mp4", kind: .imageAudio,
               ffmpegArgs: { _ in [] }, tools: ["ffmpeg"], types: ["public.audio", "public.image"]),
    ]
    static func byId(_ id: String) -> Preset? { all.first { $0.id == id } }
}

// MARK: - Main

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
