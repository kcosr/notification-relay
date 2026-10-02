import AppKit

// Database reads and relay execution stay off the UI thread. Each pass reloads
// configuration, and the controller never starts overlapping passes.
private actor MenuBarMonitor {
    func poll() -> (error: String?, interval: Double, idle: Bool) {
        do {
            let config = try ConfigurationStore().prepare()
            if !config.resolvedMonitoringEnabled || config.relay.executable.isEmpty {
                return (nil, 5, true)
            }
            do {
                try NotificationMonitor(config: config).runOnce()
                return (nil, config.resolvedPollIntervalSeconds, false)
            } catch {
                return ((error as? LocalizedError)?.errorDescription ?? String(describing: error), config.resolvedPollIntervalSeconds, false)
            }
        } catch {
            return ((error as? LocalizedError)?.errorDescription ?? String(describing: error), 5, false)
        }
    }
}

@MainActor
final class MenuBarController: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let status = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
    private let lastCheck = NSMenuItem(title: "No successful checks yet", action: nil, keyEquivalent: "")
    private let details = NSMenuItem(title: "Show Error…", action: #selector(showError), keyEquivalent: "")
    private let monitor = MenuBarMonitor()
    private var pollingTask: Task<Void, Never>?
    private var lastError: String?
    private let settings = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let mainMenu = NSMenu()
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"),
                                     ("Copy", "copy:", "c"), ("Paste", "paste:", "v"),
                                     ("Select All", "selectAll:", "a")] {
            editMenu.addItem(withTitle: title, action: NSSelectorFromString(action), keyEquivalent: key)
        }
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
        // Finder doesn't load shell profiles; the existing relay uses env node.
        let inherited = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        setenv("PATH", "/opt/homebrew/bin:/usr/local/bin:" + inherited, 1)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.autoenablesItems = false
        status.isEnabled = false
        lastCheck.isEnabled = false
        menu.addItem(status)
        menu.addItem(lastCheck)
        details.target = self
        details.isHidden = true
        menu.addItem(details)
        menu.addItem(.separator())
        addItem("Settings…", action: #selector(openSettings), to: menu, key: ",")
        addItem("Open Full Disk Access Settings…", action: #selector(openPrivacy), to: menu)
        addItem("Reveal Configuration…", action: #selector(revealConfiguration), to: menu)
        menu.addItem(.separator())
        addItem("Quit Notification Relay", action: #selector(quit), to: menu, key: "q")
        statusItem.menu = menu
        updateIcon("bell", description: "Notification Relay: starting")

        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let result = await monitor.poll()
                lastError = result.error
                details.isHidden = result.error == nil
                if let error = result.error {
                    let accessDenied = error.localizedCaseInsensitiveContains("authorization denied")
                        || error.localizedCaseInsensitiveContains("permission denied")
                    status.title = accessDenied ? "Needs Full Disk Access" : "Monitoring error"
                    updateIcon("bell.badge", description: "Notification Relay: \(status.title)")
                } else if result.idle {
                    status.title = "Monitoring paused — configure in Settings"
                    updateIcon("bell.slash", description: "Notification Relay: paused")
                } else {
                    status.title = "Running — checks every \(Int(min(result.interval, 86400))) seconds"
                    lastCheck.title = "Last check: \(Date().formatted(date: .omitted, time: .standard))"
                    updateIcon("bell", description: "Notification Relay: running")
                }
                // Bound sleep conversion for malformed or extreme config values.
                try? await Task.sleep(for: .seconds(min(result.interval, 86400)))
            }
        }
        if let config = try? ConfigurationStore().prepare(), config.relay.executable.isEmpty {
            settings.show()
        }
    }

    private func addItem(_ title: String, action: Selector, to menu: NSMenu, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    private func updateIcon(_ symbol: String, description: String) {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = description
    }

    @objc private func showError() {
        let alert = NSAlert()
        alert.messageText = status.title
        alert.informativeText = lastError ?? "No current error."
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func openPrivacy() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
    }

    @objc private func revealConfiguration() {
        NSWorkspace.shared.activateFileViewerSelecting([
            URL(fileURLWithPath: ConfigurationStore.defaultConfigPath)
        ])
    }

    @objc private func openSettings() { settings.show() }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings.show()
        return true
    }

    @objc private func quit() {
        pollingTask?.cancel()
        NSApp.terminate(nil)
    }
}
