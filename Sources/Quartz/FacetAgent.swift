import AppKit
import Foundation

struct FacetPageContext: Sendable {
    let url: String
    let title: String
    let selectedText: String
    let description: String
    let textExcerpt: String

    var hasUsefulContent: Bool {
        [url, title, selectedText, description, textExcerpt].contains { value in
            value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
    }
}

struct FacetCodexResult: Sendable {
    let output: String
    let exitStatus: Int32
    let wasCancelled: Bool

    var didSucceed: Bool {
        exitStatus == 0 && wasCancelled == false
    }
}

@MainActor
protocol FacetPanelViewDelegate: AnyObject {
    func facetPanel(_ panel: FacetPanelView, didSubmit prompt: String, includePageContext: Bool)
    func facetPanelDidRequestCancel(_ panel: FacetPanelView)
    func facetPanelDidRequestClose(_ panel: FacetPanelView)
}

@MainActor
final class FacetPanelView: NSView {
    weak var delegate: FacetPanelViewDelegate?

    private let titleLabel = NSTextField(labelWithString: "Facet")
    private let statusLabel = NSTextField(labelWithString: "Ready")
    private let transcriptTextView = NSTextView()
    private let promptField = NSTextField()
    private let includePageCheckbox = NSButton(checkboxWithTitle: "Current page", target: nil, action: nil)
    private let sendButton = FacetPanelView.makeCommandButton(
        title: "Send",
        symbolName: "paperplane.fill",
        description: "Send to Facet"
    )
    private let stopButton = FacetPanelView.makeCommandButton(
        title: "Stop",
        symbolName: "stop.fill",
        description: "Stop Facet"
    )
    private let closeButton = FacetPanelView.makeIconButton(symbolName: "xmark", description: "Hide Facet")

    private(set) var isRunning = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildView()
    }

    func focusPrompt() {
        window?.makeFirstResponder(promptField)
    }

    func appendUserMessage(_ body: String) {
        appendMessage(author: "You", body: body, color: .controlAccentColor)
    }

    func appendAgentMessage(_ body: String) {
        appendMessage(author: "Facet", body: body, color: .labelColor)
    }

    func appendSystemMessage(_ body: String) {
        appendMessage(author: "Facet", body: body, color: .secondaryLabelColor)
    }

    func setRunning(_ running: Bool) {
        isRunning = running
        statusLabel.stringValue = running ? "Thinking..." : "Ready"
        promptField.isEnabled = !running
        sendButton.isHidden = running
        stopButton.isHidden = !running
        includePageCheckbox.isEnabled = !running
    }

    private func buildView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .boldSystemFont(ofSize: 15)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .right

        closeButton.target = self
        closeButton.action = #selector(closePressed(_:))

        let titleRow = NSStackView(views: [titleLabel, statusLabel, closeButton])
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 8
        titleRow.translatesAutoresizingMaskIntoConstraints = false

        transcriptTextView.isEditable = false
        transcriptTextView.isSelectable = true
        transcriptTextView.drawsBackground = false
        transcriptTextView.textContainerInset = NSSize(width: 0, height: 8)
        transcriptTextView.font = .systemFont(ofSize: 13)
        transcriptTextView.string = ""

        let transcriptScrollView = NSScrollView()
        transcriptScrollView.borderType = .noBorder
        transcriptScrollView.hasVerticalScroller = true
        transcriptScrollView.drawsBackground = false
        transcriptScrollView.documentView = transcriptTextView
        transcriptScrollView.translatesAutoresizingMaskIntoConstraints = false

        promptField.placeholderString = "Ask Facet..."
        promptField.target = self
        promptField.action = #selector(sendPressed(_:))
        promptField.font = .systemFont(ofSize: 13)
        promptField.translatesAutoresizingMaskIntoConstraints = false

        includePageCheckbox.state = .on
        includePageCheckbox.font = .systemFont(ofSize: 12)

        sendButton.target = self
        sendButton.action = #selector(sendPressed(_:))
        stopButton.target = self
        stopButton.action = #selector(stopPressed(_:))
        stopButton.isHidden = true

        let actionRow = NSStackView(views: [includePageCheckbox, sendButton, stopButton])
        actionRow.orientation = .horizontal
        actionRow.alignment = .centerY
        actionRow.spacing = 8
        actionRow.translatesAutoresizingMaskIntoConstraints = false

        let content = NSStackView(views: [titleRow, transcriptScrollView, promptField, actionRow])
        content.orientation = .vertical
        content.alignment = .width
        content.spacing = 10
        content.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        content.translatesAutoresizingMaskIntoConstraints = false

        addSubview(separator)
        addSubview(content)

        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.widthAnchor.constraint(equalToConstant: 1),

            content.leadingAnchor.constraint(equalTo: separator.trailingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),

            closeButton.widthAnchor.constraint(equalToConstant: 28),
            transcriptScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 220),
            promptField.heightAnchor.constraint(equalToConstant: 28)
        ])
    }

    private func appendMessage(author: String, body: String, color: NSColor) {
        let cleanBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanBody.isEmpty == false else {
            return
        }

        let authorAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 12),
            .foregroundColor: color
        ]
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor
        ]
        let storage = transcriptTextView.textStorage
        storage?.append(NSAttributedString(string: "\(author)\n", attributes: authorAttributes))
        storage?.append(NSAttributedString(string: "\(cleanBody)\n\n", attributes: bodyAttributes))
        transcriptTextView.scrollToEndOfDocument(nil)
    }

    @objc private func sendPressed(_ sender: Any?) {
        submitPrompt()
    }

    @objc private func stopPressed(_ sender: Any?) {
        delegate?.facetPanelDidRequestCancel(self)
    }

    @objc private func closePressed(_ sender: Any?) {
        delegate?.facetPanelDidRequestClose(self)
    }

    private func submitPrompt() {
        guard isRunning == false else {
            return
        }

        let prompt = promptField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard prompt.isEmpty == false else {
            return
        }

        promptField.stringValue = ""
        delegate?.facetPanel(self, didSubmit: prompt, includePageContext: includePageCheckbox.state == .on)
    }

    private static func makeIconButton(symbolName: String, description: String) -> NSButton {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description) ?? NSImage()
        let button = NSButton(image: image, target: nil, action: nil)
        button.bezelStyle = .texturedRounded
        button.controlSize = .regular
        button.imagePosition = .imageOnly
        button.toolTip = description
        return button
    }

    private static func makeCommandButton(title: String, symbolName: String, description: String) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)
        button.imagePosition = .imageLeading
        button.toolTip = description
        return button
    }
}

final class FacetCodexRunner: @unchecked Sendable {
    private let queue = DispatchQueue(label: "FacetCodexRunner", qos: .userInitiated)
    private let lock = NSLock()
    private var activeProcess: Process?

    func run(prompt: String) async -> FacetCodexResult {
        await withCheckedContinuation { continuation in
            queue.async { [self, prompt, continuation] in
                let result = runSynchronously(prompt: prompt)
                continuation.resume(returning: result)
            }
        }
    }

    func cancel() {
        lock.lock()
        let process = activeProcess
        lock.unlock()

        process?.terminate()
    }

    private func runSynchronously(prompt: String) -> FacetCodexResult {
        guard let executableURL = Self.codexExecutableURL() else {
            return FacetCodexResult(
                output: "Facet could not find the Codex CLI. Install Codex or make sure the `codex` command is available at ~/.local/bin/codex, /opt/homebrew/bin/codex, /usr/local/bin/codex, or on PATH.",
                exitStatus: 127,
                wasCancelled: false
            )
        }

        let process = Process()
        process.executableURL = executableURL
        let lastMessageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("facet-codex-\(UUID().uuidString).txt", isDirectory: false)
        process.arguments = [
            "--ask-for-approval",
            "never",
            "exec",
            "--ephemeral",
            "--skip-git-repo-check",
            "--sandbox",
            "read-only",
            "--color",
            "never",
            "--output-last-message",
            lastMessageURL.path,
            "-C",
            FileManager.default.homeDirectoryForCurrentUser.path,
            "-"
        ]

        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = environment["TERM"] ?? "dumb"
        process.environment = environment

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        lock.lock()
        activeProcess = process
        lock.unlock()

        do {
            try process.run()
            if let inputData = prompt.data(using: .utf8) {
                inputPipe.fileHandleForWriting.write(inputData)
            }
            try? inputPipe.fileHandleForWriting.close()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            lock.lock()
            if activeProcess === process {
                activeProcess = nil
            }
            lock.unlock()

            let rawOutput = String(data: outputData, encoding: .utf8) ?? ""
            let lastMessage = (try? String(contentsOf: lastMessageURL, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            try? FileManager.default.removeItem(at: lastMessageURL)
            let output: String
            if let lastMessage, lastMessage.isEmpty == false {
                output = lastMessage
            } else {
                output = rawOutput
            }
            let wasCancelled = process.terminationStatus == 15
            return FacetCodexResult(
                output: output.trimmingCharacters(in: .whitespacesAndNewlines),
                exitStatus: process.terminationStatus,
                wasCancelled: wasCancelled
            )
        } catch {
            try? FileManager.default.removeItem(at: lastMessageURL)
            lock.lock()
            if activeProcess === process {
                activeProcess = nil
            }
            lock.unlock()

            return FacetCodexResult(
                output: error.localizedDescription,
                exitStatus: 1,
                wasCancelled: false
            )
        }
    }

    private static func codexExecutableURL() -> URL? {
        let pathValues = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":")
            .map(String.init) ?? []
        let fallbackPaths = [
            "~/.local/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin"
        ]
        let expandedSearchPaths = (pathValues + fallbackPaths).map { path in
            (path as NSString).expandingTildeInPath
        }

        for directory in expandedSearchPaths {
            let candidate = (directory as NSString).appendingPathComponent("codex")
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }

        return nil
    }
}
