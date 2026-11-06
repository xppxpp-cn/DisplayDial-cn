// DisplayDial by Grab Connected Tech, https://www.grabians.com

import AppKit
import Carbon.HIToolbox
import SwiftUI

// A system-wide hotkey, registered with Carbon's RegisterEventHotKey. The system reports only the
// combination that was pressed; individual key events never reach the app, so it still cannot see
// what the user types and it needs no extra permission.
final class Hotkey {
    static let shared = Hotkey()
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var identifier: UInt32 = 0
    private var action: (() -> Void)?

    private static let signature: OSType = 0x4444_4331  // 'DDC1'


    // Carbon's modifier bits, which are not the same as NSEvent.ModifierFlags.
    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var out: UInt32 = 0
        if flags.contains(.command) { out |= UInt32(cmdKey) }
        if flags.contains(.shift) { out |= UInt32(shiftKey) }
        if flags.contains(.option) { out |= UInt32(optionKey) }
        if flags.contains(.control) { out |= UInt32(controlKey) }
        return out
    }

    @discardableResult
    func register(keyCode: UInt32, modifiers: NSEvent.ModifierFlags, action: @escaping () -> Void) -> OSStatus {
        unregister()
        guard let target = GetApplicationEventTarget() else { return OSStatus(-1) }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(target, { _, event, _ -> OSStatus in
            var id = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                    nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr,
                  id.signature == Hotkey.signature else { return OSStatus(eventNotHandledErr) }
            DispatchQueue.main.async { Hotkey.shared.action?() }
            return noErr
        }, 1, &eventType, nil, &handler)
        guard status == noErr else { return status }
        identifier &+= 1
        let hotKeyID = EventHotKeyID(signature: Hotkey.signature, id: identifier)
        // kEventHotKeyExclusive is what makes a clash visible. Carbon allows the same combination in
        // several processes, and then every one of them is notified, so without this flag a
        // shortcut owned by another app would silently take precedence here.
        // With it, Carbon refuses the registration (eventHotKeyExistsErr) when that key code and
        // those modifiers are already taken, so the conflict can be reported.
        let result = RegisterEventHotKey(keyCode, Hotkey.carbonModifiers(modifiers), hotKeyID, target,
                                         UInt32(kEventHotKeyExclusive), &reference)
        guard result == noErr else { removeHandler(); return result }
        self.action = action
        return noErr
    }

    func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
        action = nil
        removeHandler()
    }

    private func removeHandler() {
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }

    // The function keys are the only keys that may stand alone as a shortcut; a plain letter would
    // simply type, so it needs a modifier.
    static let standaloneKeys: Set<UInt32> = [
        64, 79, 80, 90,                                    // F17 - F20
        96, 97, 98, 99, 100, 101, 103, 105, 106, 107,      // F5 - F16
        109, 111, 113, 118, 120, 122,                     // F10, F12, F15, F4, F2, F1
    ]

    // The name of a key, as a person would call it.
    static func keyName(_ code: UInt32) -> String {
        switch Int(code) {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "O"
        case 32: return "U"
        case 33: return "["
        case 34: return "I"
        case 35: return "P"
        case 36: return "Return"
        case 37: return "L"
        case 38: return "J"
        case 39: return "'"
        case 40: return "K"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        case 48: return "Tab"
        case 49: return "Space"
        case 50: return "`"
        case 51: return "Delete"
        case 53: return "Escape"
        case 65: return "小键盘 ."
        case 67: return "小键盘 *"
        case 69: return "小键盘 +"
        case 71: return "小键盘 Clear"
        case 75: return "小键盘 /"
        case 76: return "小键盘 Enter"
        case 78: return "小键盘 -"
        case 81: return "小键盘 ="
        case 82: return "小键盘 0"
        case 83: return "小键盘 1"
        case 84: return "小键盘 2"
        case 85: return "小键盘 3"
        case 86: return "小键盘 4"
        case 87: return "小键盘 5"
        case 88: return "小键盘 6"
        case 89: return "小键盘 7"
        case 91: return "小键盘 8"
        case 92: return "小键盘 9"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 99: return "F3"
        case 100: return "F8"
        case 101: return "F9"
        case 103: return "F11"
        case 105: return "F13"
        case 106: return "F16"
        case 107: return "F14"
        case 109: return "F10"
        case 111: return "F12"
        case 113: return "F15"
        case 114: return "Help"
        case 115: return "Home"
        case 116: return "Page Up"
        case 117: return "Forward Delete"
        case 118: return "F4"
        case 119: return "End"
        case 120: return "F2"
        case 121: return "Page Down"
        case 122: return "F1"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 64: return "F17"
        case 79: return "F18"
        case 80: return "F19"
        case 90: return "F20"
        default: return "键码 \(code)"
        }
    }

    // A combination as macOS writes it, so it reads the same way as the menu bar and the settings.
    static func describe(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) -> String {
        var out = ""
        if modifiers.contains(.control) { out += "⌃" }
        if modifiers.contains(.option) { out += "⌥" }
        if modifiers.contains(.shift) { out += "⇧" }
        if modifiers.contains(.command) { out += "⌘" }
        out += keyName(keyCode)
        return out
    }
}

// The input-source shortcut: which combination to press, and which two inputs to toggle between.
@Observable
final class InputHotkey {
    private let displays: Displays
    // Another application already owns this key combination.
    private(set) var conflict = false
    // The shortcut could not be registered at all.
    private(set) var unavailable = false

    var enabled: Bool {
        didSet {
            guard enabled != oldValue else { return }
            UserDefaults.standard.set(enabled, forKey: "input.hotkey.enabled")
            update()
        }
    }
    var keyCode: UInt32 {
        didSet {
            UserDefaults.standard.set(Int(keyCode), forKey: "input.hotkey.key")
            update()
        }
    }
    var modifiers: NSEvent.ModifierFlags {
        didSet {
            UserDefaults.standard.set(Int(modifiers.rawValue), forKey: "input.hotkey.modifiers")
            update()
        }
    }
    // Switching the monitor away from this Mac blanks a Mac mini, so the first switch asks first.
    var confirm: Bool {
        didSet { UserDefaults.standard.set(confirm, forKey: "input.hotkey.confirm") }
    }

    init(displays: Displays) {
        self.displays = displays
        let defaults = UserDefaults.standard
        defaults.register(defaults: ["input.hotkey.enabled": false, "input.hotkey.key": 34,   // "I"
                                     "input.hotkey.modifiers": Int(NSEvent.ModifierFlags.control.rawValue
                                                                    | NSEvent.ModifierFlags.option.rawValue
                                                                    | NSEvent.ModifierFlags.command.rawValue),
                                     "input.hotkey.confirm": true])
        enabled = defaults.bool(forKey: "input.hotkey.enabled")
        keyCode = UInt32(defaults.integer(forKey: "input.hotkey.key"))
        modifiers = NSEvent.ModifierFlags(rawValue: UInt(defaults.integer(forKey: "input.hotkey.modifiers")))
        confirm = defaults.bool(forKey: "input.hotkey.confirm")
        update()
    }

    // A shortcut needs a modifier, so it can't fire on a plain key press. Function keys are fine alone.
    var isValid: Bool {
        guard keyCode > 0 else { return false }
        return !modifiers.isEmpty || Hotkey.standaloneKeys.contains(keyCode)
    }

    var combination: String { Hotkey.describe(keyCode: keyCode, modifiers: modifiers) }

    // While the combination is being recorded the global shortcut stands down, so the very keys
    // being typed don't fire it.
    func suspend() { Hotkey.shared.unregister() }
    func resume() { update() }

    // The monitor the shortcut last acted on. After switching the input away the display can drop
    // off macOS's display list, taking the panel's selection with it, but the shortcut has to keep
    // working so the picture can be brought back.
    private var lastMonitor: Monitor?

    private func update() {
        guard enabled, isValid else {
            Hotkey.shared.unregister(); conflict = false; unavailable = false; return
        }
        let status = Hotkey.shared.register(keyCode: keyCode, modifiers: modifiers) { [weak self] in
            self?.fire()
        }
        // Carbon refuses an exclusive registration when that key combination is already taken.
        conflict = status == OSStatus(eventHotKeyExistsErr)
        unavailable = status != noErr && !conflict
    }

    private func fire() {
        guard let monitor = displays.selected ?? lastMonitor, monitor.ddc != nil else { return }
        lastMonitor = monitor
        guard let target = Monitor.toggleTarget(current: monitor.input, pair: monitor.pairedInputs) else { return }
        if confirm {
            let alert = NSAlert()
            alert.messageText = "切换到 \(Monitor.inputName(target))？"
            alert.informativeText = "这台 Mac 没有内置屏幕，切换后你会暂时看不到画面。\n可以再按一次快捷键切回来；如果显示器不再响应，请用显示器的按键切回，或在显示器里开启「自动选择」。"
            alert.addButton(withTitle: "切换")
            alert.addButton(withTitle: "取消")
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        monitor.switchInput(to: target)
    }

}

// The field that records a combination. It is a real key-view, so nothing outside this control is watched.
struct HotkeyRecorder: NSViewRepresentable {
    @Binding var keyCode: UInt32
    @Binding var modifiers: NSEvent.ModifierFlags
    /// Called when the field gains or loses focus, so the global hotkey can stand down while recording.
    var onEditing: (Bool) -> Void = { _ in }

    func makeNSView(context: Context) -> Field {
        let view = Field(keyCode: $keyCode, modifiers: $modifiers)
        view.onEditing = onEditing
        return view
    }
    func updateNSView(_ nsView: Field, context: Context) { nsView.onEditing = onEditing; nsView.refresh() }

    final class Field: NSView {
        private var keyCode: Binding<UInt32>
        private var modifiers: Binding<NSEvent.ModifierFlags>
        private var pendingKey: UInt32
        private var pendingModifiers: NSEvent.ModifierFlags
        var onEditing: (Bool) -> Void = { _ in }

        init(keyCode: Binding<UInt32>, modifiers: Binding<NSEvent.ModifierFlags>) {
            self.keyCode = keyCode
            self.modifiers = modifiers
            pendingKey = keyCode.wrappedValue
            pendingModifiers = modifiers.wrappedValue
            super.init(frame: .zero)
        }
        @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

        func refresh() {
            pendingKey = keyCode.wrappedValue
            pendingModifiers = modifiers.wrappedValue
            needsDisplay = true
        }

        override var acceptsFirstResponder: Bool { true }
        override var canBecomeKeyView: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { window.makeFirstResponder(self) }
        }

        override func becomeFirstResponder() -> Bool {
            onEditing(true)
            return true
        }

        override func resignFirstResponder() -> Bool {
            onEditing(false)
            return true
        }

        override func draw(_ dirtyRect: NSRect) {
            let text = Hotkey.describe(keyCode: pendingKey, modifiers: pendingModifiers) as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
                .foregroundColor: NSColor.labelColor,
            ]
            let size = text.size(withAttributes: attributes)
            text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
                      withAttributes: attributes)
        }

        // A shortcut needs a modifier, unless it is a function key, so a plain key can't trigger it.
        private func usable(_ flags: NSEvent.ModifierFlags, _ code: UInt16) -> Bool {
            let plain = flags.subtracting([.shift, .capsLock])
            return !plain.isEmpty || Hotkey.standaloneKeys.contains(UInt32(code))
        }

        private func record(_ flags: NSEvent.ModifierFlags, _ code: UInt16) {
            pendingKey = UInt32(code)
            pendingModifiers = flags
            keyCode.wrappedValue = pendingKey
            modifiers.wrappedValue = pendingModifiers
            needsDisplay = true
            // Hand focus back to the app so the recorded shortcut can work right away.
            window?.makeFirstResponder(nil)
        }

        override func keyDown(with event: NSEvent) {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard usable(flags, event.keyCode) else { return }
            record(flags, event.keyCode)
        }

        override func flagsChanged(with event: NSEvent) {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            pendingModifiers = flags
            needsDisplay = true
        }

        // ⌘-based combinations arrive here instead of keyDown; record them and swallow them so they
        // don't also trigger a menu item.
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard usable(flags, event.keyCode) else { return false }
            record(flags, event.keyCode)
            return true
        }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
        }
    }
}
