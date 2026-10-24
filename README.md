# macos-menubar-tools

Small menu bar apps I wrote for my own Mac. Each one is a single Swift file with no dependencies, and Command Line Tools is enough to build them (no Xcode). The UI is in Turkish.

| App | Status |
|---|---|
| [KeyboardLock](keyboard-lock) | Working |
| [PortalToggle](portal-toggle) | Not Completed |

## KeyboardLock

Locks the keyboard so you can clean it. The mouse keeps working. Brightness, volume and media keys are blocked too.

Ways out: the unlock button on screen, the menu, a timer (5 minutes by default), or Force Quit from the Apple menu. If the app crashes the lock goes away with it. The power/Touch ID button can't be blocked, macOS doesn't allow that.

Needs Accessibility permission.

## PortalToggle

**Status: Not Completed.** Written for my own setup (dnscrypt-proxy + zapret + a service that keeps DNS on 127.0.0.1), so it won't work on another Mac as is. You'd need to change the service names at the top of `portal-toggle/portal` and `dnsguardLabel` in `main.swift`.

Captive portal pages (cafe, hotel, airport Wi-Fi) don't load when you're on encrypted DNS. PortalToggle switches to cafe mode in one click, which turns encrypted DNS and the DPI bypass off, and switches back after you log in.

The `portal` script does the actual work. The app runs it through the normal macOS admin password prompt, so there are no permanent sudo rules.

Next step is hooking it up to `cafe-mode.sh` from [discord-tr-fix](https://github.com/GADZ-X/discord-tr-fix).

## Build

```bash
bash keyboard-lock/build.sh    # ~/Applications/KeyboardLock.app
bash portal-toggle/build.sh    # ~/Applications/PortalToggle.app
mkdir -p ~/bin && cp portal-toggle/portal ~/bin/portal
```

Signing is ad-hoc and changes on every build, so macOS may ask for Accessibility permission again after a rebuild.
