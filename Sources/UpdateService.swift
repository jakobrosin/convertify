// Convertify update service.
// Based on UpdateService.swift from Clipman by Andre Louis (https://github.com/OnjLouis/Clipman), MIT licence.
// Adapted for Convertify: release discovery through the GitHub Releases API as in Clipman; integrity is checked
// with the SHA-256 digest GitHub publishes for each asset (Convertify is not Developer ID signed), plus a
// codesign structural check; installs from a zip or a disk image; the install script waits for the app to quit,
// replaces the copy in /Applications, re-registers the Finder services, relaunches, and removes its staging folder.

import AppKit
import CryptoKit
import Foundation

final class UpdateService {
    static let shared = UpdateService()
    static let repository = "jakobrosin/convertify"
    static let releasesPage = URL(string: "https://github.com/\(repository)/releases")!
    private let releasesAPI = URL(string: "https://api.github.com/repos/\(repository)/releases?per_page=20")!

    private struct GitHubRelease: Decodable { let tag_name: String; let html_url: String; let draft: Bool; let prerelease: Bool; let body: String?; let assets: [GitHubAsset] }
    private struct GitHubAsset: Decodable { let name: String; let browser_download_url: String; let size: Int?; let digest: String? }
    private struct Candidate { let version: String; let releaseURL: URL; let downloadURL: URL; let assetName: String; let size: Int?; let sha256: String?; let notes: String }

    private var busy = false

    // MARK: Public entry points

    /// manual: started from the menu (always reports a result). installSilently: install without asking.
    func check(currentVersion: String, manual: Bool, installSilently: Bool, on window: NSWindow?) {
        guard !busy else { return }
        var request = URLRequest(url: releasesAPI, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Convertify/\(currentVersion) (+https://github.com/\(Self.repository))", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                Prefs.d.set(Date().timeIntervalSince1970, forKey: "lastUpdateCheck")
                if let error = error {
                    if manual { self.alert("Could not check for updates", error.localizedDescription, on: window) }
                    return
                }
                guard let data = data, let releases = try? JSONDecoder().decode([GitHubRelease].self, from: data) else {
                    if manual { self.alert("Could not check for updates", "GitHub did not return a release list.", on: window) }
                    return
                }
                guard let candidate = self.bestUpdate(in: releases, currentVersion: currentVersion) else {
                    if manual { self.alert("Convertify is up to date", "Version \(currentVersion) is the newest.", on: window) }
                    return
                }
                if installSilently { self.downloadAndInstall(candidate, on: window) }
                else { self.promptForUpdate(candidate, currentVersion: currentVersion, on: window) }
            }
        }.resume()
    }

    func openVersionHistory() { NSWorkspace.shared.open(Self.releasesPage) }

    /// Install a staged Convertify.app (from an update, or the running copy when moving to /Applications) and relaunch.
    func installAndRelaunch(stagedApp: URL, cleanup: URL?) {
        let target = "/Applications/Convertify.app"
        let lsr = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("ConvertifyInstall-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let scriptURL = staging.appendingPathComponent("install-convertify.zsh")
        let script = """
        #!/bin/zsh
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
        rm -rf \(q(target))
        /usr/bin/ditto \(q(stagedApp.path)) \(q(target))
        /usr/bin/xattr -dr com.apple.quarantine \(q(target)) 2>/dev/null
        \(q(lsr)) -f \(q(target))
        /System/Library/CoreServices/pbs -flush; /System/Library/CoreServices/pbs -update
        /usr/bin/open \(q(target))
        \(cleanup.map { "rm -rf \(q($0.path))" } ?? "")
        rm -rf \(q(staging.path))
        """
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/zsh"); p.arguments = [scriptURL.path]
            p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
            try p.run()
        } catch {
            Log.write("could not start the install script: \(error.localizedDescription)"); return
        }
        Log.write("installing \(stagedApp.path) into \(target) and relaunching")
        NSApp.terminate(nil)
    }

    // MARK: Release selection

    private func bestUpdate(in releases: [GitHubRelease], currentVersion: String) -> Candidate? {
        releases
            .filter { !$0.draft && !$0.prerelease }
            .compactMap { r -> Candidate? in
                let version = normalizedVersion(r.tag_name)
                guard isVersion(version, newerThan: currentVersion), let asset = preferredAsset(in: r.assets),
                      let releaseURL = URL(string: r.html_url), let dl = URL(string: asset.browser_download_url) else { return nil }
                let sha = asset.digest.flatMap { $0.lowercased().hasPrefix("sha256:") ? String($0.dropFirst(7)).lowercased() : nil }
                return Candidate(version: version, releaseURL: releaseURL, downloadURL: dl, assetName: asset.name, size: asset.size, sha256: sha, notes: r.body ?? "")
            }
            .sorted { versionParts($0.version).lexicographicallyPrecedes(versionParts($1.version)) == false }
            .first
    }

    /// The updater prefers the zip (no mounting); the disk image is the human download.
    private func preferredAsset(in assets: [GitHubAsset]) -> GitHubAsset? {
        let zips = assets.filter { $0.name.lowercased().hasSuffix(".zip") && $0.name.lowercased().hasPrefix("convertify") }
        if let z = zips.first { return z }
        return assets.first { $0.name.lowercased() == "convertify.dmg" }
    }

    // MARK: Prompts

    private func promptForUpdate(_ c: Candidate, currentVersion: String, on window: NSWindow?) {
        let a = NSAlert()
        a.messageText = "Convertify \(c.version) is available"
        let notes = Self.plainText(fromMarkdown: c.notes)
        a.informativeText = "You have \(currentVersion).\n\n" + (notes.isEmpty ? "" : String(notes.prefix(1200)) + "\n\n") + "Install downloads \(c.assetName), checks it, replaces the copy in Applications and relaunches. Nothing is left behind."
        a.addButton(withTitle: "Install"); a.addButton(withTitle: "Version History"); a.addButton(withTitle: "Later")
        present(a, on: window) { r in
            switch r {
            case .alertFirstButtonReturn: self.downloadAndInstall(c, on: window)
            case .alertSecondButtonReturn: NSWorkspace.shared.open(c.releaseURL)
            default: break
            }
        }
    }

    private func alert(_ title: String, _ text: String, on window: NSWindow?) {
        let a = NSAlert(); a.messageText = title; a.informativeText = text
        present(a, on: window) { _ in }
    }

    private func present(_ a: NSAlert, on window: NSWindow?, _ handler: @escaping (NSApplication.ModalResponse) -> Void) {
        if let w = window, w.isVisible { a.beginSheetModal(for: w, completionHandler: handler) }
        else { NSApp.activate(ignoringOtherApps: true); handler(a.runModal()) }
    }

    // MARK: Download, verify, stage, install

    private func downloadAndInstall(_ c: Candidate, on window: NSWindow?) {
        busy = true
        Log.write("downloading update \(c.version) from \(c.downloadURL)")
        var request = URLRequest(url: c.downloadURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 300)
        request.setValue("Convertify (+https://github.com/\(Self.repository))", forHTTPHeaderField: "User-Agent")
        URLSession.shared.downloadTask(with: request) { location, _, error in
            // The temporary download disappears when this handler returns, so keep it first.
            let staging = FileManager.default.temporaryDirectory.appendingPathComponent("ConvertifyUpdate-\(UUID().uuidString)", isDirectory: true)
            var archive: URL?
            if let location = location, (try? FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)) != nil {
                let dest = staging.appendingPathComponent(c.assetName)
                if (try? FileManager.default.moveItem(at: location, to: dest)) != nil { archive = dest }
            }
            DispatchQueue.main.async {
                defer { self.busy = false }
                guard let archive = archive else {
                    try? FileManager.default.removeItem(at: staging)
                    self.alert("Could not download the update", error?.localizedDescription ?? "The download did not produce a file.", on: window); return
                }
                do {
                    try self.verify(archive, expectedSize: c.size, expectedSHA256: c.sha256)
                    let app = try self.stage(archive, in: staging)
                    try self.verifyStructure(of: app)
                    self.installAndRelaunch(stagedApp: app, cleanup: staging)
                } catch {
                    try? FileManager.default.removeItem(at: staging)
                    Log.write("update failed: \(error.localizedDescription)")
                    self.alert("Update not installed", error.localizedDescription, on: window)
                }
            }
        }.resume()
    }

    private func verify(_ file: URL, expectedSize: Int?, expectedSHA256: String?) throws {
        if let size = expectedSize, let real = try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int, real != size {
            throw err("The downloaded file has the wrong size, so it was discarded.")
        }
        guard let sha = expectedSHA256, !sha.isEmpty else { throw err("GitHub did not publish a checksum for this download, so it was not installed.") }
        let got = Self.sha256Hex(of: file)
        guard got == sha else { Log.write("checksum mismatch: expected \(sha) got \(got)"); throw err("The downloaded file failed its checksum, so it was discarded.") }
    }

    /// Unpack a zip or open a disk image; returns the staged Convertify.app inside `staging`.
    private func stage(_ archive: URL, in staging: URL) throws -> URL {
        let extract = staging.appendingPathComponent("extract", isDirectory: true)
        try FileManager.default.createDirectory(at: extract, withIntermediateDirectories: true)
        if archive.pathExtension.lowercased() == "zip" {
            try run("/usr/bin/ditto", ["-x", "-k", archive.path, extract.path])
        } else {
            let mount = staging.appendingPathComponent("mount", isDirectory: true).path
            try run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-mountpoint", mount, archive.path])
            defer { _ = try? run("/usr/bin/hdiutil", ["detach", mount, "-force"]) }
            guard FileManager.default.fileExists(atPath: mount + "/Convertify.app") else { throw err("The disk image does not contain Convertify.") }
            try run("/usr/bin/ditto", [mount + "/Convertify.app", extract.appendingPathComponent("Convertify.app").path])
        }
        try? FileManager.default.removeItem(at: archive)
        guard let app = findApp(in: extract) else { throw err("The download did not contain Convertify.app.") }
        return app
    }

    /// Not a Developer ID check (Convertify is only ad-hoc signed), but codesign still proves the bundle is intact.
    private func verifyStructure(of app: URL) throws {
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        let id = Bundle(url: app)?.bundleIdentifier ?? ""
        guard id == Maintenance.bundleID else { throw err("The downloaded app is not Convertify (bundle identifier \(id)).") }
    }

    private func findApp(in folder: URL) -> URL? {
        guard let e = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil) else { return nil }
        for case let u as URL in e where u.lastPathComponent == "Convertify.app" { return u }
        return nil
    }

    private func run(_ exe: String, _ args: [String]) throws {
        let p = Process(); p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try p.run(); p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw err("\((exe as NSString).lastPathComponent) failed with exit code \(p.terminationStatus).") }
    }

    static func sha256Hex(of url: URL) -> String {
        guard let h = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? h.close() }
        var hasher = SHA256()
        while let chunk = try? h.read(upToCount: 4 * 1024 * 1024), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Versions

    private func normalizedVersion(_ v: String) -> String { v.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "vV ")) }
    private func versionParts(_ v: String) -> [Int] { v.split { !$0.isNumber }.map { Int($0) ?? 0 } }
    func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let l = versionParts(candidate), r = versionParts(current)
        for i in 0..<max(l.count, r.count) {
            let a = i < l.count ? l[i] : 0, b = i < r.count ? r[i] : 0
            if a != b { return a > b }
        }
        return false
    }

    /// Release notes are markdown; the sheet is plain text VoiceOver reads, so drop the markup.
    static func plainText(fromMarkdown md: String) -> String {
        var t = md.replacingOccurrences(of: "\r\n", with: "\n")
        t = t.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)   // [text](url) -> text
        t = t.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "")
        t = t.replacingOccurrences(of: #"(?m)^#+\s*"#, with: "", options: .regularExpression)                    // headings
        t = t.replacingOccurrences(of: #"(?m)^\s*[-*]\s+"#, with: "• ", options: .regularExpression)             // bullets
        t = t.replacingOccurrences(of: "`", with: "")
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    private func err(_ m: String) -> NSError { NSError(domain: "ConvertifyUpdate", code: 1, userInfo: [NSLocalizedDescriptionKey: m]) }
}
