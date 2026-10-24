// KeyboardLock — klavyeyi geçici olarak kilitler (temizlik modu)
//
// Fare hiç etkilenmez; kilidi fareyle açarsın. Kilitlenip kalmamak için
// beş ayrı çıkış yolu var:
//   1. Ekrandaki panelin "Kilidi Aç" düğmesi
//   2. Menü çubuğu simgesi → Kilidi Aç
//   3. Otomatik süre dolumu (varsayılan 5 dk)
//   4. Elma menüsü → Zorla Çık (fareyle yapılabilir)
//   5. Uygulama çökerse tap ölür, klavye kendiliğinden geri gelir
//
// Parola alanları macOS'un Secure Input korumasındadır; event tap oraya
// karışamaz, yani giriş ekranında asla kilitli kalmazsın.

import Cocoa
import ApplicationServices

// MARK: - Klavye engelleyici

/// NX_SYSDEFINED — CGEventType enum'unda karşılığı yok, ham değerle kullanılıyor.
/// Parlaklık, ses, medya ve klavye ışığı tuşları bu türden gelir.
/// Dosya seviyesinde: C fonksiyon işaretçisi olan geri çağırım `Self.` yakalayamaz.
private let kSystemDefined: UInt32 = 14
/// NX_SUBTYPE_AUX_CONTROL_BUTTONS — özel klavye tuşlarının alt türü.
private let kAuxControlButtons: Int = 8

final class KeyboardBlocker {

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    var isActive: Bool { tap != nil }

    /// Erişilebilirlik izni yoksa false döner (ve sistem iznini ister).
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << kSystemDefined)     // parlaklık / ses / oynat-duraklat

        // C fonksiyon işaretçisi olduğu için bağlam yakalayamaz; self'i refcon ile taşıyoruz.
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            // Sistem tap'i askıya alırsa (zaman aşımı vb.) hemen geri aç
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let refcon {
                    Unmanaged<KeyboardBlocker>.fromOpaque(refcon)
                        .takeUnretainedValue()
                        .reenable()
                }
                return Unmanaged.passUnretained(event)
            }

            // NX_SYSDEFINED çok şeyi kapsıyor; sadece alt tür 8 (özel klavye
            // tuşları: parlaklık, ses, medya, klavye ışığı) yutulur. Diğer
            // sistem olaylarına dokunulmaz, yoksa fare davranışı bozulabilir.
            if type.rawValue == kSystemDefined {
                if let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == kAuxControlButtons {
                    return nil
                }
                return Unmanaged.passUnretained(event)
            }

            return nil   // nil döndürmek olayı yutar
        }

        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        tap = newTap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        return true
    }

    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        self.tap = nil
        self.source = nil
    }

    fileprivate func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }
}

// MARK: - Kilit paneli

final class UnlockPanel {

    private var panel: NSPanel?
    private var countdownLabel: NSTextField?
    private let onUnlock: () -> Void

    init(onUnlock: @escaping () -> Void) {
        self.onUnlock = onUnlock
    }

    func show() {
        guard panel == nil else { return }

        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 190),
                        styleMask: [.hudWindow, .titled, .nonactivatingPanel],
                        backing: .buffered,
                        defer: false)
        p.title = "Klavye Kilidi"
        p.level = .screenSaver              // her şeyin üstünde
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let title = NSTextField(labelWithString: "KLAVYE KİLİTLİ")
        title.font = .systemFont(ofSize: 20, weight: .bold)
        title.alignment = .center

        let hint = NSTextField(labelWithString: "Fare çalışıyor. Şimdi temizleyebilirsin.")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        hint.alignment = .center

        let countdown = NSTextField(labelWithString: "")
        countdown.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        countdown.textColor = .secondaryLabelColor
        countdown.alignment = .center
        countdownLabel = countdown

        let button = NSButton(title: "Kilidi Aç", target: self, action: #selector(unlockTapped))
        button.bezelStyle = .push
        button.controlSize = .large
        button.keyEquivalent = ""           // klavye kilitli, sadece fare

        let stack = NSStackView(views: [title, hint, countdown, button])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 22, bottom: 22, right: 22)
        stack.translatesAutoresizingMaskIntoConstraints = false

        p.contentView?.addSubview(stack)
        if let content = p.contentView {
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                stack.centerYAnchor.constraint(equalTo: content.centerYAnchor)
            ])
        }

        p.center()
        p.orderFrontRegardless()
        panel = p
    }

    func updateCountdown(_ text: String) {
        countdownLabel?.stringValue = text
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        countdownLabel = nil
    }

    @objc private func unlockTapped() { onUnlock() }
}

// MARK: - Denetleyici

final class Controller: NSObject, NSMenuDelegate {

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let blocker = KeyboardBlocker()
    private lazy var panel = UnlockPanel { [weak self] in self?.unlock() }

    /// Otomatik açılma süresi (saniye). 0 = süresiz.
    private var timeout: TimeInterval = 300
    private let timeoutChoices: [(String, TimeInterval)] = [
        ("1 dakika", 60), ("3 dakika", 180), ("5 dakika", 300), ("10 dakika", 600)
    ]

    private var deadline: Date?
    private var ticker: Timer?

    override init() {
        super.init()
        menu.delegate = self
        statusItem.menu = menu
        render()
    }

    // MARK: Görünüm

    private func render() {
        guard let button = statusItem.button else { return }
        let symbol = blocker.isActive ? "keyboard.badge.ellipsis" : "keyboard"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Klavye Kilidi")
        image?.isTemplate = true
        button.image = image
        button.title = blocker.isActive ? " KİLİTLİ" : ""
        button.imagePosition = blocker.isActive ? .imageLeading : .imageOnly
    }

    func menuWillOpen(_ menu: NSMenu) { build() }

    private func build() {
        menu.removeAllItems()

        if blocker.isActive {
            let item = NSMenuItem(title: "Kilidi Aç", action: #selector(unlock), keyEquivalent: "")
            item.target = self
            item.attributedTitle = NSAttributedString(
                string: "Kilidi Aç",
                attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize),
                             .foregroundColor: NSColor.systemOrange])
            menu.addItem(item)
        } else {
            let item = NSMenuItem(title: "Klavyeyi Kilitle", action: #selector(lock), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let durations = NSMenu()
        for (label, seconds) in timeoutChoices {
            let item = NSMenuItem(title: label, action: #selector(setTimeout(_:)), keyEquivalent: "")
            item.target = self
            item.tag = Int(seconds)
            item.state = (timeout == seconds) ? .on : .off
            durations.addItem(item)
        }
        let never = NSMenuItem(title: "Süresiz", action: #selector(setTimeout(_:)), keyEquivalent: "")
        never.target = self
        never.tag = 0
        never.state = (timeout == 0) ? .on : .off
        durations.addItem(never)

        let durationRoot = NSMenuItem(title: "Otomatik açılma", action: nil, keyEquivalent: "")
        durationRoot.submenu = durations
        menu.addItem(durationRoot)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Çıkış", action: #selector(quit), keyEquivalent: "")
        quit.target = self
        quit.isEnabled = !blocker.isActive   // kilitliyken kazara çıkmayı önle
        menu.addItem(quit)
    }

    // MARK: Eylemler

    @objc private func lock() {
        guard blocker.start() else {
            requestAccessibility()
            return
        }

        panel.show()

        if timeout > 0 {
            deadline = Date().addingTimeInterval(timeout)
            ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                self?.tick()
            }
            tick()
        } else {
            panel.updateCountdown("Otomatik açılma kapalı")
        }

        render()
    }

    @objc private func unlock() {
        ticker?.invalidate()
        ticker = nil
        deadline = nil
        blocker.stop()
        panel.hide()
        render()
    }

    private func tick() {
        guard let deadline else { return }
        let remaining = Int(deadline.timeIntervalSinceNow.rounded(.up))
        if remaining <= 0 {
            unlock()
            return
        }
        panel.updateCountdown(String(format: "%d:%02d sonra kendiliğinden açılır",
                                     remaining / 60, remaining % 60))
    }

    @objc private func setTimeout(_ sender: NSMenuItem) {
        timeout = TimeInterval(sender.tag)
    }

    @objc private func quit() { NSApplication.shared.terminate(nil) }

    // MARK: İzin

    private func requestAccessibility() {
        let alert = NSAlert()
        alert.messageText = "Erişilebilirlik izni gerekiyor"
        alert.informativeText = """
            Klavyeyi kilitleyebilmek için bu uygulamanın Erişilebilirlik iznine \
            ihtiyacı var. Açılacak pencerede KeyboardLock'u işaretle, sonra tekrar dene.
            """
        alert.addButton(withTitle: "Ayarları Aç")
        alert.addButton(withTitle: "Vazgeç")

        if alert.runModal() == .alertFirstButtonReturn {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

// MARK: - Başlat

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = Controller()
app.run()
