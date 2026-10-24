// PortalToggle — menü çubuğundan kafe modu (captive portal) açma/kapama
//
// Normal mod : dnsguard + zapret + dnscrypt-proxy açık → Discord çalışır, DNS şifreli
// Kafe modu  : hepsi kapalı, DNS DHCP'de → captive portal giriş ekranı açılabilir
//
// Ayrıcalıklı işlemler ~/bin/portal script'ine devredilir ve macOS'un kendi
// yönetici şifre penceresiyle çalıştırılır. Sistemde kalıcı sudo izni YOK.

import Cocoa

/// Must match DNSGUARD_LABEL in the portal script.
let dnsguardLabel = "com.gadz.dnsguard"

// MARK: - Kabuk yardımcıları

@discardableResult
func shell(_ path: String, _ args: [String]) -> (out: String, code: Int32) {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: path)
    task.arguments = args

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = Pipe()

    do { try task.run() } catch { return ("", -1) }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()

    let out = String(data: data, encoding: .utf8) ?? ""
    return (out.trimmingCharacters(in: .whitespacesAndNewlines), task.terminationStatus)
}

func isRunning(_ processName: String) -> Bool {
    shell("/usr/bin/pgrep", ["-x", processName]).code == 0
}

// MARK: - Durum

struct PortalState: Equatable {
    var dns: String
    var dnsguardLoaded: Bool
    var zapretRunning: Bool
    var dnscryptRunning: Bool

    /// Kafe modundayken DNS artık 127.0.0.1 değildir ve zapret durmuştur.
    var isNormal: Bool { dns.contains("127.0.0.1") && zapretRunning }

    static func read() -> PortalState {
        var dns = shell("/usr/sbin/networksetup", ["-getdnsservers", "Wi-Fi"]).out
        // Ayarlanmamışsa networksetup düz cümle döndürür, onu sadeleştir
        if dns.lowercased().contains("aren't any") || dns.lowercased().contains("there aren't") {
            dns = "DHCP (ağdan gelen)"
        } else {
            dns = dns.replacingOccurrences(of: "\n", with: ", ")
        }

        return PortalState(
            dns: dns,
            dnsguardLoaded: shell("/bin/launchctl", ["print", "system/\(dnsguardLabel)"]).code == 0,
            zapretRunning: isRunning("tpws"),
            dnscryptRunning: isRunning("dnscrypt-proxy")
        )
    }
}

// MARK: - Uygulama

final class PortalController: NSObject, NSMenuDelegate {

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let script = NSHomeDirectory() + "/bin/portal"

    private var state = PortalState.read()
    private var busy = false
    private var timer: Timer?

    override init() {
        super.init()
        menu.delegate = self
        statusItem.menu = menu
        render()

        // Dışarıdan (terminalden) yapılan değişiklikleri de yakala
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        // Tolerans, macOS'un bu uyandırmayı başka zamanlayıcılarla birleştirmesine
        // izin verir; işlemci kendi başına uyanmak yerine zaten uyanıkken işi yapar.
        timer?.tolerance = 5
    }

    // MARK: Menü çubuğu görünümü

    /// En son çizilen görünüm. Değişmediyse AppKit'i hiç rahatsız etmiyoruz.
    private var lastRendered: (symbol: String, title: String)?

    private func render() {
        guard let button = statusItem.button else { return }

        let symbol = busy ? "hourglass"
                          : (state.isNormal ? "lock.fill" : "lock.open.fill")
        let title = state.isNormal ? "" : " KAFE"

        // Görünüm aynıysa yeniden çizme — poll döngüsü sessizce geçsin.
        if let last = lastRendered, last.symbol == symbol, last.title == title { return }
        lastRendered = (symbol, title)

        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Portal")
        image?.isTemplate = true
        button.image = image
        button.title = title
        button.imagePosition = state.isNormal ? .imageOnly : .imageLeading
    }

    private func refresh() {
        state = PortalState.read()
        render()
    }

    // MARK: Menü içeriği

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
        build()
    }

    private func build() {
        menu.removeAllItems()

        let header = NSMenuItem(title: state.isNormal ? "Normal mod" : "KAFE MODU AÇIK",
                                action: nil, keyEquivalent: "")
        header.attributedTitle = NSAttributedString(
            string: state.isNormal ? "Normal mod" : "KAFE MODU AÇIK",
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: state.isNormal ? NSColor.labelColor : NSColor.systemOrange
            ])
        menu.addItem(header)

        if !state.isNormal {
            menu.addItem(dimmed("Şifreli DNS ve Discord bypass KAPALI"))
        }

        menu.addItem(.separator())

        let normal = NSMenuItem(title: "Normal mod", action: #selector(goNormal), keyEquivalent: "")
        normal.target = self
        normal.state = state.isNormal ? .on : .off
        normal.isEnabled = !busy && !state.isNormal
        menu.addItem(normal)

        let cafe = NSMenuItem(title: "Kafe modu (captive portal)", action: #selector(goCafe), keyEquivalent: "")
        cafe.target = self
        cafe.state = state.isNormal ? .off : .on
        cafe.isEnabled = !busy && state.isNormal
        menu.addItem(cafe)

        menu.addItem(.separator())

        menu.addItem(dimmed(row("dnsguard", state.dnsguardLoaded ? "açık" : "kapalı")))
        menu.addItem(dimmed(row("zapret", state.zapretRunning ? "çalışıyor" : "kapalı")))
        menu.addItem(dimmed(row("dnscrypt", state.dnscryptRunning ? "çalışıyor" : "kapalı")))
        menu.addItem(dimmed(row("DNS", state.dns)))

        menu.addItem(.separator())

        let portal = NSMenuItem(title: "Giriş sayfasını aç", action: #selector(openPortal), keyEquivalent: "")
        portal.target = self
        menu.addItem(portal)

        let quit = NSMenuItem(title: "Çıkış", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func row(_ label: String, _ value: String) -> String {
        let padded = label.padding(toLength: max(10, label.count), withPad: " ", startingAt: 0)
        return "\(padded)  \(value)"
    }

    private func dimmed(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor
            ])
        item.isEnabled = false
        return item
    }

    // MARK: Eylemler

    @objc private func goCafe() { run("off") }
    @objc private func goNormal() { run("on") }

    @objc private func openPortal() {
        if let url = URL(string: "http://captive.apple.com/hotspot-detect.html") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() { NSApplication.shared.terminate(nil) }

    /// portal script'ini macOS yönetici şifre penceresiyle çalıştırır.
    private func run(_ argument: String) {
        guard !busy else { return }
        busy = true
        render()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            let command = "do shell script \"\(self.script) \(argument)\" with administrator privileges"
            let result = shell("/usr/bin/osascript", ["-e", command])

            DispatchQueue.main.async {
                self.busy = false
                self.refresh()

                // -128 = kullanıcı şifre penceresini iptal etti, hata sayma
                if result.code != 0 && !result.out.contains("-128") {
                    self.notifyFailure(argument)
                } else if result.code == 0 && argument == "off" {
                    self.remindCafeMode()
                }
            }
        }
    }

    private func notifyFailure(_ argument: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Geçiş tamamlanamadı"
        alert.informativeText = """
            \(script) \(argument) çalıştırılamadı.

            Terminalden deneyip çıktıya bakabilirsin:
            sudo \(script) \(argument)
            """
        alert.runModal()
    }

    private func remindCafeMode() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Kafe modu açık"
        alert.informativeText = """
            Şimdi Wi-Fi'ye bağlan, giriş ekranı açılmalı. \
            Açılmazsa menüden "Giriş sayfasını aç" seçeneğini kullan.

            Giriş yaptıktan sonra normal moda dön — o zamana kadar şifreli DNS \
            ve Discord bypass kapalı.
            """
        alert.addButton(withTitle: "Tamam")
        alert.runModal()
    }
}

// MARK: - Başlat

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = PortalController()
app.run()
