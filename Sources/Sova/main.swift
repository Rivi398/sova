// Sova: keep a MacBook awake with the lid closed, from a switch in the menu bar.
//
// Sleep always comes back on its own: when the switch is turned off, when Sova quits or is
// signalled, when the battery drops below a floor, when the Mac runs hot, when Sova starts
// (so a crash never leaves the Mac sleepless), and via the root guard from `Setup`
// at boot and every minute while Sova is not running.

import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static let repoURL = URL(string: "https://github.com/Rivi398/sova")!

    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var statusLineItem: NSMenuItem?
    private var toggleSwitch: NSSwitch?
    private var ticker: Timer?
    private var signalSources: [DispatchSourceSignal] = []

    private var enabled = false
    private var lastOffReason: String?

    private let defaults = UserDefaults.standard
    private var batteryFloor: Int {
        get { defaults.object(forKey: "batteryFloor") as? Int ?? 20 }
        set { defaults.set(newValue, forKey: "batteryFloor") }
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        // Never inherit the mode from a previous run.
        if Pmset.isSleepDisabled() {
            Pmset.setSleepDisabled(false)
            lastOffReason = L("при запуске Sova", "when Sova started")
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu.delegate = self
        statusItem.menu = menu
        updateUI()

        NotificationCenter.default.addObserver(
            self, selector: #selector(thermalChanged),
            name: ProcessInfo.thermalStateDidChangeNotification, object: nil)

        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler { NSApp.terminate(nil) }
            src.resume()
            signalSources.append(src)
        }

        ticker = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.check() }
    }

    func applicationWillTerminate(_ note: Notification) {
        if enabled || Pmset.isSleepDisabled() { Pmset.setSleepDisabled(false) }
    }

    // MARK: Mode

    private func turnOn() {
        if let reason = blockReason() {
            alert(L("Сейчас включать нельзя", "Can't turn on right now"), reason)
            return
        }
        guard Setup.isInstalled else {
            // First use: set up after the menu has closed, then come back here.
            afterMenuCloses { [weak self] in
                Setup.install { result in
                    guard let self else { return }
                    switch result {
                    case .success:
                        self.enableLaunchAtLoginOnce()
                        if Setup.isInstalled { self.turnOn() }
                    case .failure(.cancelled):
                        break
                    case .failure(.failed(let msg)):
                        self.alert(L("Не удалось настроить", "Setup failed"), msg)
                    }
                }
            }
            return
        }
        guard Pmset.setSleepDisabled(true) else {
            alert(L("Нет разрешения на pmset", "No permission for pmset"),
                  L("Выбери в меню «Удалить системные настройки», затем включи снова: Sova заново попросит пароль.",
                    "Choose “Remove system settings” in the menu, then turn the switch on again to redo setup."))
            return
        }
        enabled = true
        lastOffReason = nil
        updateUI()
    }

    private func turnOff(reason: String) {
        Pmset.setSleepDisabled(false)
        let wasOn = enabled
        enabled = false
        lastOffReason = reason
        updateUI()
        if wasOn && reason != manualReason { NSSound(named: "Funk")?.play() }
    }

    private let manualReason = L("вручную", "manually")

    private func blockReason() -> String? {
        let p = PowerInfo.read()
        if p.onBattery, let pct = p.percent, pct <= batteryFloor {
            return L("батарея \(pct)%, порог \(batteryFloor)%", "battery \(pct)%, limit \(batteryFloor)%")
        }
        switch ProcessInfo.processInfo.thermalState {
        case .serious, .critical: return L("мак перегрелся", "the Mac is too hot")
        default: return nil
        }
    }

    private func check() {
        guard enabled else { return }
        if let reason = blockReason() { turnOff(reason: reason); return }
        if !Pmset.isSleepDisabled() { turnOff(reason: L("флаг сброшен снаружи", "reset outside Sova")) }
    }

    @objc private func thermalChanged() {
        DispatchQueue.main.async { self.check() }
    }

    // MARK: Launch at login

    private var launchesAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            alert(L("Не удалось изменить автозапуск", "Couldn't change the login item"), error.localizedDescription)
        }
    }

    /// Turned on once, right after the first successful setup; after that it is the user's call.
    private func enableLaunchAtLoginOnce() {
        guard !defaults.bool(forKey: "loginItemOffered") else { return }
        defaults.set(true, forKey: "loginItemOffered")
        try? SMAppService.mainApp.register()
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        check()
        menu.removeAllItems()
        actions.removeAll()

        menu.addItem(switchItem())
        menu.addItem(.separator())
        let line = disabledItem("")
        statusLineItem = line
        menu.addItem(line)
        if let r = lastOffReason, !enabled {
            menu.addItem(disabledItem(L("Сон вернулся: \(r)", "Sleep restored: \(r)")))
        }
        if !Setup.isInstalled {
            menu.addItem(disabledItem(L("При первом включении Sova попросит пароль", "First use asks for your password once")))
        }

        menu.addItem(.separator())
        let floorMenu = NSMenu()
        for pct in [10, 20, 30, 50] {
            let it = item("\(pct)%") { [weak self] in self?.batteryFloor = pct }
            it.state = pct == batteryFloor ? .on : .off
            floorMenu.addItem(it)
        }
        let floorItem = NSMenuItem(title: L("Выключать при батарее ниже \(batteryFloor)%",
                                            "Turn off below \(batteryFloor)% battery"),
                                   action: nil, keyEquivalent: "")
        floorItem.submenu = floorMenu
        menu.addItem(floorItem)

        let login = item(L("Запускать при входе", "Open at login")) { [weak self] in
            guard let self else { return }
            self.setLaunchAtLogin(!self.launchesAtLogin)
        }
        login.state = launchesAtLogin ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(item(L("Sova на GitHub", "Sova on GitHub")) { NSWorkspace.shared.open(Self.repoURL) })
        if Setup.isInstalled {
            menu.addItem(item(L("Удалить системные настройки…", "Remove system settings…")) { [weak self] in
                self?.removeSystemSettings()
            })
        }
        menu.addItem(item(L("Выйти (сон вернётся)", "Quit (sleep comes back)")) { NSApp.terminate(nil) })

        updateUI()
    }

    private func removeSystemSettings() {
        if enabled { turnOff(reason: manualReason) }
        afterMenuCloses { [weak self] in
            Setup.uninstall { result in
                guard let self else { return }
                switch result {
                case .success:
                    try? SMAppService.mainApp.unregister()
                    self.alert(L("Готово", "Done"),
                               L("Правило sudo и сторож удалены. Теперь Sova можно перетащить в Корзину.",
                                 "The sudo rule and the guard are gone. You can move Sova to the Trash now."))
                case .failure(.cancelled):
                    break
                case .failure(.failed(let msg)):
                    self.alert(L("Не удалось удалить", "Couldn't remove"), msg)
                }
            }
        }
    }

    private func switchItem() -> NSMenuItem {
        let label = NSTextField(labelWithString: L("Не засыпать с закрытой крышкой", "Stay awake with lid closed"))
        label.font = .menuFont(ofSize: 0)
        let sw = NSSwitch()
        sw.target = self
        sw.action = #selector(switchToggled(_:))
        sw.setAccessibilityLabel(label.stringValue)
        toggleSwitch = sw

        let view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 34))
        for v in [label, sw] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
        }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            sw.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            sw.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            sw.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 12),
        ])
        let it = NSMenuItem()
        it.view = view
        return it
    }

    @objc private func switchToggled(_ sender: NSSwitch) {
        if sender.state == .on { turnOn() } else { turnOff(reason: manualReason) }
        updateUI()   // turning on may have been refused
    }

    private func updateUI() {
        statusItem.button?.image = OwlIcon.image(awake: enabled)
        toggleSwitch?.state = enabled ? .on : .off

        let p = PowerInfo.read()
        let power = p.percent.map {
            p.onBattery ? L(" · батарея \($0)%", " · battery \($0)%") : L(" · от сети \($0)%", " · plugged in \($0)%")
        } ?? ""
        let text = (enabled ? L("● Включено: не засыпает", "● On: staying awake")
                            : L("○ Выключено: обычный сон", "○ Off: normal sleep")) + power
        statusLineItem?.attributedTitle = NSAttributedString(string: text, attributes: [
            .foregroundColor: enabled ? OwlIcon.awakeColor : NSColor.secondaryLabelColor,
            .font: NSFont.menuFont(ofSize: 0),
        ])
    }

    // MARK: Helpers

    private var actions: [ObjectIdentifier: () -> Void] = [:]

    private func item(_ title: String, _ action: @escaping () -> Void) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: #selector(fire(_:)), keyEquivalent: "")
        it.target = self
        actions[ObjectIdentifier(it)] = action
        return it
    }

    @objc private func fire(_ sender: NSMenuItem) { actions[ObjectIdentifier(sender)]?() }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        it.isEnabled = false
        return it
    }

    /// Runs `work` once the menu is closed. Anything modal opened while the menu is still
    /// tracking leaves the keyboard stuck in the menu, so the password field can't be typed in.
    private func afterMenuCloses(_ work: @escaping () -> Void) {
        menu.cancelTracking()
        // The default run loop mode only resumes after menu tracking has ended.
        RunLoop.main.perform(inModes: [.default], block: work)
    }

    private func alert(_ title: String, _ text: String) {
        afterMenuCloses {
            NSApp.activate(ignoringOtherApps: true)
            let a = NSAlert()
            a.messageText = title
            a.informativeText = text
            a.runModal()
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
