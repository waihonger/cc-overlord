import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, @unchecked Sendable {
    private var menuItem: NSStatusItem!
    private var labelItem: NSStatusItem!
    private var signalWatcher: SignalWatcher!
    private var mostRecentSignal: Signal?
    private var blinkTimer: Timer?
    private var blinkVisible = true
    private var hasSignals = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Label item (right side, click to jump to most recent)
        labelItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = labelItem.button {
            button.title = ""
            button.action = #selector(labelClicked)
            button.target = self
        }

        // Menu item (left side: "N 🔔", click for dropdown)
        menuItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = menuItem.button {
            button.image = NSImage(systemSymbolName: "bell", accessibilityDescription: "CC Overlord")
            button.image?.size = NSSize(width: 14, height: 14)
            button.imagePosition = .imageRight
        }

        signalWatcher = SignalWatcher { [weak self] signals in
            DispatchQueue.main.async {
                self?.update(signals: signals)
            }
        }
        signalWatcher.start()
        update(signals: [])
    }

    @MainActor private func update(signals: [Signal]) {
        mostRecentSignal = signals.sorted(by: { $0.timestamp > $1.timestamp }).first

        // Menu item: "N 🔔" or just 🔔
        hasSignals = !signals.isEmpty
        if let button = menuItem.button {
            if signals.isEmpty {
                button.title = ""
                stopBlinking()
            } else {
                button.title = "\(signals.count) "
                startBlinking()
            }
        }

        // Label: most recent project name (click to jump)
        if let button = labelItem.button {
            if let recent = mostRecentSignal {
                button.title = truncate(recent.project, to: 14)
            } else {
                button.title = ""
            }
        }

        // Build dropdown menu
        let menu = NSMenu()

        if signals.isEmpty {
            let item = NSMenuItem(title: "No terminals awaiting", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            let grouped = Dictionary(grouping: signals, by: { $0.project })
            for project in grouped.keys.sorted() {
                let projectSignals = grouped[project]!.sorted { $0.timestamp > $1.timestamp }

                let header = NSMenuItem(title: project, action: nil, keyEquivalent: "")
                header.isEnabled = false
                header.attributedTitle = NSAttributedString(
                    string: project,
                    attributes: [.font: NSFont.boldSystemFont(ofSize: 13)]
                )
                menu.addItem(header)

                for signal in projectSignals {
                    let title = "  \(signal.terminalName)  —  \(signal.agoString)"
                    let item = NSMenuItem(title: title, action: #selector(signalClicked(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = signal
                    menu.addItem(item)
                }
                menu.addItem(NSMenuItem.separator())
            }
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit CC Overlord", action: #selector(quit), keyEquivalent: "q"))
        menuItem.menu = menu
    }

    @objc private func labelClicked() {
        guard let signal = mostRecentSignal else { return }
        signal.openInVSCode()
        signalWatcher.clearSignal(signal)
    }

    @objc private func signalClicked(_ sender: NSMenuItem) {
        guard let signal = sender.representedObject as? Signal else { return }
        signal.openInVSCode()
        signalWatcher.clearSignal(signal)
    }

    private func startBlinking() {
        guard blinkTimer == nil else { return }
        blinkVisible = true
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.blinkVisible.toggle()
                if let button = self.menuItem.button {
                    let bellName = self.blinkVisible ? "bell.fill" : "bell"
                    button.image = NSImage(systemSymbolName: bellName, accessibilityDescription: "CC Overlord")
                    button.image?.size = NSSize(width: 14, height: 14)
                }
            }
        }
    }

    @MainActor private func stopBlinking() {
        blinkTimer?.invalidate()
        blinkTimer = nil
        blinkVisible = true
        if let button = menuItem.button {
            button.image = NSImage(systemSymbolName: "bell", accessibilityDescription: "CC Overlord")
            button.image?.size = NSSize(width: 14, height: 14)
        }
    }

    private func truncate(_ s: String, to maxLen: Int) -> String {
        if s.count <= maxLen { return s }
        return String(s.prefix(maxLen - 1)) + "…"
    }

    @MainActor @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
