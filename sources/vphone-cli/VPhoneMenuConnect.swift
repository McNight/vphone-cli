import AppKit
import Foundation

// MARK: - Connect Menu

extension VPhoneMenuController {
    func buildConnectMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Connect")
        menu.addItem(makeItem("File Browser", action: #selector(openFiles)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeItem("Download IPA", action: #selector(downloadIPA)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeItem("Developer Mode Status", action: #selector(devModeStatus)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeItem("Ping", action: #selector(sendPing)))
        menu.addItem(makeItem("Guest Version", action: #selector(queryGuestVersion)))
        item.submenu = menu
        return item
    }

    @objc private func openFiles() {
        onFilesPressed?()
    }

    @objc private func devModeStatus() {
        Task {
            do {
                let status = try await control.sendDevModeStatus()
                showAlert(
                    title: "Developer Mode",
                    message: status.enabled ? "Developer Mode is enabled." : "Developer Mode is disabled.",
                    style: .informational
                )
            } catch {
                showAlert(title: "Developer Mode", message: "\(error)", style: .warning)
            }
        }
    }

    @objc private func sendPing() {
        Task {
            do {
                try await control.sendPing()
                showAlert(title: "Ping", message: "pong", style: .informational)
            } catch {
                showAlert(title: "Ping", message: "\(error)", style: .warning)
            }
        }
    }

    @objc private func queryGuestVersion() {
        Task {
            do {
                let hash = try await control.sendVersion()
                showAlert(title: "Guest Version", message: "build: \(hash)", style: .informational)
            } catch {
                showAlert(title: "Guest Version", message: "\(error)", style: .warning)
            }
        }
    }

    // MARK: - Download IPA

    @objc private func downloadIPA() {
        let alert = NSAlert()
        alert.messageText = "Download IPA"
        alert.informativeText = "Enter the App Store bundle identifier. Requires Apple ID authentication via ipatool."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 22))
        textField.placeholderString = "com.example.app"
        textField.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        alert.accessoryView = textField
        alert.window.initialFirstResponder = textField

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        let bundleID = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bundleID.isEmpty else { return }

        Task { await performIPADownload(bundleID: bundleID) }
    }

    private func ipatoolPath() -> String? {
        let candidates = ["/opt/homebrew/bin/ipatool", "/usr/local/bin/ipatool"]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = ["ipatool"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        try? proc.run()
        proc.waitUntilExit()
        let found = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (found?.isEmpty == false) ? found : nil
    }

    // MARK: - Progress Panel

    private func makeDownloadPanel(bundleID: String) -> (NSPanel, NSProgressIndicator, NSTextField) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 96),
            styleMask: [.titled, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Downloading IPA"
        panel.isReleasedWhenClosed = false
        panel.level = .floating

        let content = NSView()

        let idLabel = NSTextField(labelWithString: bundleID)
        idLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        idLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(idLabel)

        let bar = NSProgressIndicator()
        bar.style = .bar
        bar.minValue = 0
        bar.maxValue = 100
        bar.isIndeterminate = true
        bar.startAnimation(nil)
        bar.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(bar)

        let statusLabel = NSTextField(labelWithString: "Starting…")
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            idLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            idLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            idLabel.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -16),

            bar.topAnchor.constraint(equalTo: idLabel.bottomAnchor, constant: 8),
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),

            statusLabel.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 6),
            statusLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -16),
        ])

        panel.contentView = content
        return (panel, bar, statusLabel)
    }

    // MARK: - Download Execution

    private func performIPADownload(bundleID: String) async {
        guard let toolPath = ipatoolPath() else {
            showAlert(
                title: "ipatool Not Found",
                message: "Install ipatool via Homebrew:\n\nbrew install majd/taproom/ipatool",
                style: .warning
            )
            return
        }

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vphone-ipa-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        } catch {
            showAlert(title: "Download Failed", message: "Could not create temp directory: \(error)", style: .warning)
            return
        }
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let ipaURL = tmpDir.appendingPathComponent("\(bundleID).ipa")

        let (progressPanel, progressBar, statusLabel) = makeDownloadPanel(bundleID: bundleID)
        progressPanel.center()
        progressPanel.makeKeyAndOrderFront(nil)

        // ipatool's mpb progress bar writes to stdout (Go's os.Stdout default).
        // Stream stdout in real-time for live progress; collect stderr for error diagnosis.
        final class OutputBox: @unchecked Sendable { var stdout = ""; var stderr = "" }
        final class UIRefs: @unchecked Sendable {
            let bar: NSProgressIndicator
            let label: NSTextField
            init(_ b: NSProgressIndicator, _ l: NSTextField) { bar = b; label = l }
        }
        let box = OutputBox()
        let ui = UIRefs(progressBar, statusLabel)

        let (exitCode, combined): (Int32, String) = await withCheckedContinuation { continuation in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: toolPath)
            proc.arguments = ["download", "--bundle-identifier", bundleID, "--output", ipaURL.path]

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            proc.standardOutput = stdoutPipe
            proc.standardError = stderrPipe

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                box.stdout += chunk
                if let pct = Self.parseIPAToolProgress(from: chunk) {
                    DispatchQueue.main.async {
                        if ui.bar.isIndeterminate {
                            ui.bar.stopAnimation(nil)
                            ui.bar.isIndeterminate = false
                        }
                        ui.bar.doubleValue = pct
                        ui.label.stringValue = "Downloading… \(Int(pct))%"
                    }
                }
            }

            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                box.stderr += chunk
            }

            proc.terminationHandler = { process in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                let remOut = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let remErr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let out = [box.stdout + remOut, box.stderr + remErr].filter { !$0.isEmpty }.joined(separator: "\n")
                continuation.resume(returning: (process.terminationStatus, out))
            }

            do {
                try proc.run()
            } catch {
                continuation.resume(returning: (-1, "\(error)"))
            }
        }

        let cleanedOutput = stripANSI(combined)
        print("[download] ipatool exit=\(exitCode) output=\(cleanedOutput.prefix(300))")

        guard exitCode == 0 else {
            progressPanel.close()
            showAlert(title: "Download Failed", message: ipatoolErrorMessage(output: cleanedOutput, bundleID: bundleID), style: .warning)
            return
        }

        let resolvedIPA: URL
        if FileManager.default.fileExists(atPath: ipaURL.path) {
            resolvedIPA = ipaURL
        } else if let found = try? FileManager.default.contentsOfDirectory(at: tmpDir, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "ipa" }) {
            resolvedIPA = found
        } else {
            progressPanel.close()
            showAlert(title: "Download Failed", message: "ipatool exited successfully but no IPA was written.", style: .warning)
            return
        }

        let ipaData: Data
        do {
            ipaData = try Data(contentsOf: resolvedIPA)
        } catch {
            progressPanel.close()
            showAlert(title: "Download Failed", message: "Could not read downloaded IPA: \(error)", style: .warning)
            return
        }

        progressBar.isIndeterminate = true
        progressBar.startAnimation(nil)
        statusLabel.stringValue = "Uploading to VM…"
        print("[download] uploading \(ipaData.count) bytes to VM…")

        let remotePath = "/var/mobile/Downloads/\(bundleID).ipa"
        do {
            try? await control.createDirectory(path: "/var/mobile/Downloads")
            try await control.uploadFile(path: remotePath, data: ipaData, permissions: "644")
            progressPanel.close()
            showAlert(title: "Download Complete", message: "Saved to \(remotePath) on the VM.", style: .informational)
        } catch {
            progressPanel.close()
            showAlert(title: "Upload Failed", message: "IPA downloaded but could not upload to VM: \(error)", style: .warning)
        }
    }

    private nonisolated static func parseIPAToolProgress(from text: String) -> Double? {
        // ipatool's mpb writes "downloading  45% |...| " to stdout
        guard let regex = try? NSRegularExpression(pattern: #"(\d{1,3})%"#) else { return nil }
        var last: Double? = nil
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            if let range = Range(match.range(at: 1), in: text), let pct = Double(text[range]) {
                last = min(pct, 100)
            }
        }
        return last
    }

    private func stripANSI(_ string: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\x1B\[[0-9;]*[A-Za-z]"#) else { return string }
        let range = NSRange(string.startIndex..., in: string)
        return regex.stringByReplacingMatches(in: string, range: range, withTemplate: "")
    }

    private func ipatoolErrorMessage(output: String, bundleID: String) -> String {
        if let match = output.range(of: #"error="([^"]+)""#, options: .regularExpression) {
            let fragment = String(output[match])
            if let open = fragment.firstIndex(of: "\""),
               let close = fragment.lastIndex(of: "\""),
               open != close {
                let msg = String(fragment[fragment.index(after: open)..<close])
                return ipatoolSemanticError(msg, bundleID: bundleID)
            }
        }
        let lines = output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.contains("%") }
        let clean = lines.joined(separator: "\n")
        return ipatoolSemanticError(clean.isEmpty ? output : clean, bundleID: bundleID)
    }

    private func ipatoolSemanticError(_ msg: String, bundleID: String) -> String {
        let lower = msg.lowercased()
        if lower.contains("sign in") || lower.contains("authentication") || lower.contains("not logged in") || lower.contains("unauthorized") {
            return "Not authenticated with an Apple ID.\n\nRun: ipatool auth login"
        }
        if lower.contains("not found") || lower.contains("no app") || lower.contains("could not find") || lower.contains("no result") {
            return "'\(bundleID)' was not found in the App Store or is not available in this region."
        }
        if lower.contains("purchase") || lower.contains("not purchased") {
            return "'\(bundleID)' must be purchased before it can be downloaded.\n\nBuy it on your Apple ID first."
        }
        return msg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "ipatool exited with an error (no output)."
            : msg.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Alert

    private func showAlert(title: String, message: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}
