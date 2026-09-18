#if os(macOS)
import AppKit
import SwiftUI
import GymFeatures

/// Delegato e controller della finestra di anteprima.
///
/// Tiene lo stato scelto dai menu (dispositivo, aspetto, scenario di dati) e
/// ricostruisce il contenuto della finestra quando cambia. La finestra non è
/// ridimensionabile: la sua dimensione è quella dello schermo simulato più un
/// margine, e cambia solo cambiando dispositivo.
@MainActor
final class PreviewApp: NSObject, NSApplicationDelegate {

    private var device: PreviewDevice
    private var scenario: PreviewScenario
    private var isDark: Bool
    private var rigidSafeArea: Bool

    private var environment: AppEnvironment?
    private var window: NSWindow?
    private var isLoading = false

    init(options: PreviewOptions) {
        device = options.device
        scenario = options.scenario
        isDark = options.dark
        rigidSafeArea = options.rigidSafeArea
    }

    // MARK: - Ciclo di vita

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMenu()
        makeWindow()
        load(scenario: scenario)
        NSApp.activate()
    }

    /// Chiudere la finestra chiude lo strumento: non c'è nient'altro da fare.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: - Finestra

    private func makeWindow() {
        let size = DeviceFrameView.windowSize(for: device)
        // Niente `.resizable`: lo schermo simulato ha una dimensione precisa e
        // stirarlo renderebbe l'anteprima bugiarda.
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Gym · anteprima"
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        applyContent()
        window.makeKeyAndOrderFront(nil)
    }

    /// Ricostruisce la view della finestra e ne aggiorna dimensione e aspetto.
    private func applyContent() {
        guard let window else { return }
        window.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)

        let size = DeviceFrameView.windowSize(for: device)
        let root = DeviceFrameView(
            device: device,
            environment: environment,
            dark: isDark,
            rigidSafeArea: rigidSafeArea
        )
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: size)
        window.contentView = host
        window.setContentSize(size)
        updateMenuState()
    }

    // MARK: - Dati

    private func load(scenario newScenario: PreviewScenario) {
        guard !isLoading else { return }
        isLoading = true
        scenario = newScenario
        environment = nil
        applyContent()
        Task { @MainActor in
            let loaded = await PreviewMockData.environment(for: newScenario)
            environment = loaded
            isLoading = false
            applyContent()
        }
    }

    // MARK: - Azioni dei menu

    @objc private func selectDevice(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String,
              let device = PreviewDevice.named(key), device != self.device else { return }
        self.device = device
        applyContent()
    }

    /// "Safe area rigida": la cornice smette di passare safe area al contenuto e
    /// comunica le misure alla shell. È il caso che riproduce il telefono vero.
    @objc private func toggleRigidSafeArea(_ sender: NSMenuItem) {
        rigidSafeArea.toggle()
        applyContent()
    }

    @objc private func selectAppearance(_ sender: NSMenuItem) {
        let dark = (sender.representedObject as? String) == "scuro"
        guard dark != isDark else { return }
        isDark = dark
        applyContent()
    }

    @objc private func selectScenario(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let scenario = PreviewScenario(rawValue: raw) else { return }
        load(scenario: scenario)
    }

    // MARK: - Menu

    private func makeMenu() -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Anteprima")
        appMenu.addItem(withTitle: "Chiudi", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Esci", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let deviceItem = NSMenuItem()
        let deviceMenu = NSMenu(title: "Dispositivo")
        for (index, device) in PreviewDevice.all.enumerated() {
            let item = NSMenuItem(
                title: device.name,
                action: #selector(selectDevice(_:)),
                keyEquivalent: String(index + 1)
            )
            item.target = self
            item.representedObject = device.key
            deviceMenu.addItem(item)
        }
        deviceMenu.addItem(.separator())
        let rigidItem = NSMenuItem(
            title: "Safe area rigida",
            action: #selector(toggleRigidSafeArea(_:)),
            keyEquivalent: "r"
        )
        rigidItem.keyEquivalentModifierMask = [.command, .shift]
        rigidItem.target = self
        rigidItem.representedObject = "rigida"
        deviceMenu.addItem(rigidItem)

        deviceItem.submenu = deviceMenu
        main.addItem(deviceItem)

        let appearanceItem = NSMenuItem()
        let appearanceMenu = NSMenu(title: "Aspetto")
        for (key, title) in [("chiaro", "Chiaro"), ("scuro", "Scuro")] {
            let item = NSMenuItem(title: title, action: #selector(selectAppearance(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = key
            appearanceMenu.addItem(item)
        }
        appearanceItem.submenu = appearanceMenu
        main.addItem(appearanceItem)

        let dataItem = NSMenuItem()
        let dataMenu = NSMenu(title: "Dati")
        for (index, scenario) in PreviewScenario.allCases.enumerated() {
            let item = NSMenuItem(
                title: scenario.menuTitle,
                action: #selector(selectScenario(_:)),
                keyEquivalent: String(index + 1)
            )
            item.keyEquivalentModifierMask = [.command, .shift]
            item.target = self
            item.representedObject = scenario.rawValue
            dataMenu.addItem(item)
        }
        dataItem.submenu = dataMenu
        main.addItem(dataItem)

        menus = (device: deviceMenu, appearance: appearanceMenu, data: dataMenu)
        return main
    }

    private var menus: (device: NSMenu, appearance: NSMenu, data: NSMenu)?

    /// Spunta la voce attiva in ognuno dei tre menu.
    private func updateMenuState() {
        guard let menus else { return }
        for item in menus.device.items {
            if (item.representedObject as? String) == "rigida" {
                item.state = rigidSafeArea ? .on : .off
            } else {
                item.state = (item.representedObject as? String) == device.key ? .on : .off
            }
        }
        for item in menus.appearance.items {
            let key = (item.representedObject as? String) == "scuro"
            item.state = key == isDark ? .on : .off
        }
        for item in menus.data.items {
            item.state = (item.representedObject as? String) == scenario.rawValue ? .on : .off
        }
    }
}
#endif
