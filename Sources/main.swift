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

/// Container extension for an audio codec copied without re-encoding (same table as the Windows SendTo helper).
func extractExtension(forCodec codec: String) -> String {
    if codec.hasPrefix("pcm_") { return "wav" }
    let map: [String: String] = ["aac": "m4a", "alac": "m4a", "mp3": "mp3", "opus": "opus", "vorbis": "ogg", "flac": "flac",
        "wmav1": "wma", "wmav2": "wma", "wmapro": "wma", "wmavoice": "wma", "ape": "ape", "wavpack": "wv", "tta": "tta",
        "speex": "spx", "amr_nb": "amr", "amr_wb": "amr", "ac3": "ac3", "eac3": "eac3", "dts": "dts", "truehd": "thd", "mlp": "mlp"]
    return map[codec] ?? "mka"
}
let rawAudioCodecs: Set<String> = ["ac3", "eac3", "dts", "truehd", "mlp"]   // raw containers cannot carry metadata

/// True when ffprobe can open the file and it is not empty.
func outputLooksValid(_ url: URL) -> Bool {
    guard let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int, size > 0,
          let probe = findTool("ffprobe") else { return false }
    return runTool(probe, ["-v", "error", url.path]).status == 0
}

// MARK: - Media info report (speech-friendly)

enum MediaInfo {
    static func report(for url: URL) -> String {
        guard let probe = findTool("ffprobe") else { return "ffprobe is not available." }
        let r = runTool(probe, ["-v", "error", "-show_format", "-show_streams", "-show_chapters", "-of", "json", url.path])
        guard r.status == 0, let data = r.out.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            return "\(url.lastPathComponent)\nNot a media file that ffprobe understands. Size: \(sizeText(size))."
        }
        var lines: [String] = [url.lastPathComponent, "Location: \(url.deletingLastPathComponent().path)"]
        let fmt = json["format"] as? [String: Any] ?? [:]
        if let f = fmt["format_long_name"] as? String { lines.append("Container: \(f)") }
        if let d = Double(fmt["duration"] as? String ?? ""), d > 0 { lines.append("Duration: \(spokenDuration(d))") }
        if let sz = Int(fmt["size"] as? String ?? "") { lines.append("Size: \(sizeText(sz))") }
        if let br = Int(fmt["bit_rate"] as? String ?? "") { lines.append("Overall bitrate: \(br / 1000) kilobits per second") }
        let streams = json["streams"] as? [[String: Any]] ?? []
        var a = 0, v = 0, o = 0
        for st in streams {
            let type = st["codec_type"] as? String ?? ""
            let codec = st["codec_long_name"] as? String ?? st["codec_name"] as? String ?? "unknown"
            switch type {
            case "audio":
                a += 1
                var parts = ["Audio \(a): \(codec)"]
                if let sr = st["sample_rate"] as? String { parts.append("\(sr) hertz") }
                if let ch = st["channels"] as? Int { parts.append(ch == 1 ? "mono" : ch == 2 ? "stereo" : "\(ch) channels") }
                if let b = Int(st["bits_per_raw_sample"] as? String ?? ""), b > 0 { parts.append("\(b) bit") }
                else if let b = st["bits_per_sample"] as? Int, b > 0 { parts.append("\(b) bit") }
                if let br = Int(st["bit_rate"] as? String ?? "") { parts.append("\(br / 1000) kilobits per second") }
                lines.append(parts.joined(separator: ", "))
            case "video":
                v += 1
                var parts = ["Video \(v): \(codec)"]
                if let w = st["width"] as? Int, let h = st["height"] as? Int { parts.append("\(w) by \(h) pixels") }
                if let fr = st["avg_frame_rate"] as? String, fr != "0/0" {
                    let p = fr.split(separator: "/").compactMap { Double($0) }
                    if p.count == 2, p[1] > 0 { parts.append(String(format: "%.3g frames per second", p[0] / p[1])) }
                }
                if let br = Int(st["bit_rate"] as? String ?? "") { parts.append("\(br / 1000) kilobits per second") }
                if (st["disposition"] as? [String: Int])?["attached_pic"] == 1 { parts.append("cover picture") }
                lines.append(parts.joined(separator: ", "))
            default:
                o += 1
                lines.append("\(type.capitalized) stream: \(codec)")
            }
        }
        if streams.isEmpty { lines.append("No streams found.") }
        let tags = (fmt["tags"] as? [String: Any]) ?? (streams.first?["tags"] as? [String: Any]) ?? [:]
        let wanted = ["title", "artist", "album", "album_artist", "date", "genre", "track", "comment", "encoder"]
        let present = wanted.compactMap { k -> String? in
            guard let vv = tags.first(where: { $0.key.lowercased() == k })?.value else { return nil }
            return "\(k.replacingOccurrences(of: "_", with: " ").capitalized): \(vv)"
        }
        if !present.isEmpty { lines.append("Tags:"); lines += present.map { "  " + $0 } }
        if let ch = json["chapters"] as? [[String: Any]], !ch.isEmpty { lines.append("Chapters: \(ch.count)") }
        return lines.joined(separator: "\n")
    }
    static func sizeText(_ bytes: Int) -> String {
        let f = ByteCountFormatter(); f.countStyle = .file; return f.string(fromByteCount: Int64(bytes))
    }
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

/// Never overwrite. Same scheme as the Windows SendTo encoders: "name.ext", then "name-converted.ext",
/// then "name-converted-2.ext", "name-converted-3.ext"... Converting a file to its own format lands on "-converted" too.
func outputPath(for input: URL, ext: String) -> URL {
    let s = stem(input)
    let fm = FileManager.default
    let desired = "\(s).\(ext)"
    if desired.lowercased() != input.path.lowercased() && !fm.fileExists(atPath: desired) { return URL(fileURLWithPath: desired) }
    var candidate = "\(s)-converted.\(ext)"
    var n = 2
    while fm.fileExists(atPath: candidate) { candidate = "\(s)-converted-\(n).\(ext)"; n += 1 }
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

enum PresetKind { case ffmpeg, oggPipe, flacDecodeDelete, flacEncodeDelete, videoMP4, videoMOV, imageAudio, remuxMKV, extractAudio, imageJPEG, imagePNG }

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
               ffmpegArgs: { _ in ["-map", "0:a:0", "-map_metadata", "0", "-map_chapters", "0", "-id3v2_version", "3", "-c:a", "libmp3lame", "-q:a", "2"] },
               tools: ["ffmpeg"], types: ["public.audio", "public.movie"]),
        Preset(id: "mp3low", title: "MP3 Encode (Low Quality)", ext: "mp3", kind: .ffmpeg,
               ffmpegArgs: { _ in ["-map", "0:a:0", "-map_metadata", "0", "-map_chapters", "0", "-id3v2_version", "3", "-c:a", "libmp3lame", "-b:a", "64k"] },
               tools: ["ffmpeg"], types: ["public.audio", "public.movie"]),
        Preset(id: "aac", title: "AAC Encode", ext: "m4a", kind: .ffmpeg,
               ffmpegArgs: { _ in ["-map", "0:a:0", "-map_metadata", "0", "-map_chapters", "0", "-c:a", "aac_at", "-b:a", "128k", "-movflags", "+faststart"] },
               tools: ["ffmpeg"], types: ["public.audio", "public.movie"]),
        Preset(id: "opus", title: "Opus Encode", ext: "opus", kind: .ffmpeg,
               ffmpegArgs: { _ in ["-map", "0:a:0", "-map_metadata", "0", "-map_chapters", "0", "-c:a", "libopus", "-b:a", "96k", "-vbr", "on"] },
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
        Preset(id: "mkv", title: "File to MKV", ext: "mkv", kind: .remuxMKV,
               ffmpegArgs: { _ in [] }, tools: ["ffmpeg"], types: ["public.movie", "public.audio"]),
        Preset(id: "extractaudio", title: "Extract Audio", ext: "", kind: .extractAudio,
               ffmpegArgs: { _ in [] }, tools: ["ffmpeg"], types: ["public.movie", "public.audio"]),
        Preset(id: "jpeg", title: "Image to JPEG", ext: "jpg", kind: .imageJPEG,
               ffmpegArgs: { _ in [] }, tools: [], types: ["public.image"]),
        Preset(id: "png", title: "Image to PNG", ext: "png", kind: .imagePNG,
               ffmpegArgs: { _ in [] }, tools: [], types: ["public.image"]),
    ]
    static func byId(_ id: String) -> Preset? { all.first { $0.id == id } }
}

// MARK: - Main

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
