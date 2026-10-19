// Everything Sova does outside its own process lives here: pmset, battery,
// and the one-time privileged setup.

import Foundation
import IOKit.ps

let isRussian = Locale.preferredLanguages.first?.hasPrefix("ru") ?? false
func L(_ ru: String, _ en: String) -> String { isRussian ? ru : en }

// MARK: - pmset

enum Pmset {
    /// Goes through the sudoers rule installed by `Setup`: exactly these two commands, no password.
    @discardableResult
    static func setSleepDisabled(_ on: Bool) -> Bool {
        run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", on ? "1" : "0"]).status == 0
    }

    /// `pmset -g` prints a SleepDisabled line only once the flag has been set at least once.
    static func isSleepDisabled() -> Bool {
        for line in run("/usr/bin/pmset", ["-g"]).output.split(separator: "\n") {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if parts.first == "SleepDisabled" { return parts.dropFirst().first == "1" }
        }
        return false
    }
}

@discardableResult
func run(_ path: String, _ args: [String]) -> (status: Int32, output: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return (-1, "") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(decoding: data, as: UTF8.self))
}

// MARK: - Power

struct PowerInfo {
    var onBattery = false
    var percent: Int?

    static func read() -> PowerInfo {
        var info = PowerInfo()
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return info }
        if let type = IOPSGetProvidingPowerSourceType(blob)?.takeUnretainedValue() {
            info.onBattery = (type as String) == kIOPSBatteryPowerValue
        }
        let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] ?? []
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any],
                  let cur = d[kIOPSCurrentCapacityKey] as? Int,
                  let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            info.percent = cur * 100 / max
        }
        return info
    }
}

// MARK: - Privileged setup

/// Installs two root-owned files, once, behind the standard macOS password prompt:
///
/// - `/etc/sudoers.d/sova` lets the current user run exactly
///   `pmset -a disablesleep 0` and `pmset -a disablesleep 1` without a password. Nothing else.
/// - a LaunchDaemon guard that runs at boot and every minute: if sleep is disabled
///   but Sova is not running (force quit, crash, reboot), it turns sleep back on.
///
/// The root script is generated here in full and passed base64-encoded, so it never reads
/// files a user-level process could swap in between the check and the install.
enum Setup {
    static let sudoersPath = "/etc/sudoers.d/sova"
    static let guardLabel = "ru.studiasok.sova.guard"
    static var guardPath: String { "/Library/LaunchDaemons/\(guardLabel).plist" }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: sudoersPath)
            && FileManager.default.fileExists(atPath: guardPath)
    }

    enum Failure: Error { case cancelled, failed(String) }
    typealias Completion = (Result<Void, Failure>) -> Void

    /// Asynchronous: the password prompt belongs to a separate osascript process, so Sova's
    /// own UI never blocks on it. `done` is called on the main queue.
    static func install(_ done: @escaping Completion) {
        let user = NSUserName()
        guard user.range(of: #"^[A-Za-z_][A-Za-z0-9_.-]*$"#, options: .regularExpression) != nil else {
            return done(.failure(.failed("unsupported user name: \(user)")))
        }
        let guardCheck = #"if /usr/bin/pmset -g | /usr/bin/grep -qE '^[[:space:]]*SleepDisabled[[:space:]]+1'; then /usr/bin/pgrep -xq Sova || /usr/bin/pmset -a disablesleep 0; fi"#
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>Label</key><string>\(guardLabel)</string>
        \t<key>ProgramArguments</key>
        \t<array><string>/bin/sh</string><string>-c</string><string>\(guardCheck.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;"))</string></array>
        \t<key>RunAtLoad</key><true/>
        \t<key>StartInterval</key><integer>60</integer>
        </dict>
        </plist>
        """
        let script = """
        set -e
        T=$(/usr/bin/mktemp -d)
        trap '/bin/rm -rf "$T"' EXIT
        /bin/cat > "$T/sova" <<'SOVA_EOF'
        # Sova (menu bar app): exactly two commands, nothing else.
        \(user) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1
        SOVA_EOF
        /usr/sbin/visudo -cf "$T/sova" >/dev/null
        /usr/bin/install -m 0440 -o root -g wheel "$T/sova" \(sudoersPath)
        /bin/cat > "$T/guard.plist" <<'SOVA_EOF'
        \(plist)
        SOVA_EOF
        /usr/bin/plutil -lint "$T/guard.plist" >/dev/null
        /usr/bin/install -m 0644 -o root -g wheel "$T/guard.plist" \(guardPath)
        /bin/launchctl bootout system/\(guardLabel) 2>/dev/null || true
        /bin/launchctl bootstrap system \(guardPath)
        """
        runAsAdmin(script, prompt: L(
            "Sova просит разрешение только на две команды: включить и выключить сон с закрытой крышкой.",
            "Sova needs permission for exactly two commands: turn lid-closed sleep off and back on."), done)
    }

    static func uninstall(_ done: @escaping Completion) {
        let script = """
        /usr/bin/pmset -a disablesleep 0
        /bin/launchctl bootout system/\(guardLabel) 2>/dev/null
        /bin/rm -f \(sudoersPath) \(guardPath)
        exit 0
        """
        runAsAdmin(script, prompt: L("Sova удалит свои системные настройки.",
                                     "Sova will remove its system settings."), done)
    }

    private static func runAsAdmin(_ script: String, prompt: String, _ done: @escaping Completion) {
        let b64 = Data(script.utf8).base64EncodedString()
        let escapedPrompt = prompt.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        do shell script "echo \(b64) | /usr/bin/base64 -D | /bin/sh" with administrator privileges with prompt "\(escapedPrompt)"
        """
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", source]
            let err = Pipe()
            p.standardError = err
            p.standardOutput = FileHandle.nullDevice
            var result: Result<Void, Failure> = .success(())
            do {
                try p.run()
                let msg = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                p.waitUntilExit()
                if p.terminationStatus != 0 {
                    // osascript reports a cancelled password prompt as error -128.
                    result = msg.contains("-128") ? .failure(.cancelled)
                        : .failure(.failed(msg.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            } catch {
                result = .failure(.failed(error.localizedDescription))
            }
            DispatchQueue.main.async { done(result) }
        }
    }
}
