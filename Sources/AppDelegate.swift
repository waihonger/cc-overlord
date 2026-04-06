import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, @unchecked Sendable {
    private var statusItem: NSStatusItem!
    private var signalWatcher: SignalWatcher!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "bell", accessibilityDescription: "CC Overlord")
            button.image?.size = NSSize(width: 16, height: 16)
        }

        signalWatcher = SignalWatcher { [weak self] signals in
            DispatchQueue.main.async {
                self?.updateMenu(signals: signals)
            }
        }
        signalWatcher.start()
        updateMenu(signals: [])
    }

    @MainActor private func updateMenu(signals: [Signal]) {
        let menu = NSMenu()

        if signals.isEmpty {
            let item = NSMenuItem(title: "No terminals awaiting", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            // Group by project
            let grouped = Dictionary(grouping: signals, by: { $0.project })
            let sortedProjects = grouped.keys.sorted()

            for project in sortedProjects {
                let projectSignals = grouped[project]!.sorted { $0.timestamp > $1.timestamp }

                let header = NSMenuItem(title: project, action: nil, keyEquivalent: "")
                header.isEnabled = false
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.boldSystemFont(ofSize: 13),
                ]
                header.attributedTitle = NSAttributedString(string: project, attributes: attrs)
                menu.addItem(header)

                for signal in projectSignals {
                    let ago = signal.agoString
                    let title = "  \(signal.terminalName)  —  \(ago)"
                    let item = NSMenuItem(title: title, action: #selector(signalClicked(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = signal
                    menu.addItem(item)
                }

                menu.addItem(NSMenuItem.separator())
            }
        }

        // Update button appearance
        if let button = statusItem.button {
            if signals.isEmpty {
                button.image = NSImage(systemSymbolName: "bell", accessibilityDescription: "CC Overlord")
            } else {
                button.image = NSImage(systemSymbolName: "bell.badge.fill", accessibilityDescription: "CC Overlord")
                button.title = " \(signals.count)"
            }
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit CC Overlord", action: #selector(quit), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    @objc private func signalClicked(_ sender: NSMenuItem) {
        guard let signal = sender.representedObject as? Signal else { return }
        signal.openInVSCode()
        signalWatcher.clearSignal(signal)
    }

    @MainActor @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
