// DisplayDial by Grab Connected Tech, https://www.grabians.com

import SwiftUI

@main
struct DisplayDialApp: App {
    @State private var displays: Displays
    @State private var keys: Keys
    private let settings: SettingsWindow

    init() {
        let displays = Displays(), keys = Keys(displays: displays), settings = SettingsWindow(keys: keys)
        (_displays, _keys, self.settings) = (State(initialValue: displays), State(initialValue: keys), settings)
        // MenuBarExtra has no right-click menu, so catch right-clicks on our status item's window.
        NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { event in
            guard event.window?.className == "NSStatusBarWindow", let view = event.window?.contentView else { return event }
            let menu = NSMenu()
            menu.addItem(withTitle: "设置…", action: #selector(SettingsWindow.open), keyEquivalent: "").target = settings
            menu.addItem(withTitle: "关于 DisplayDial", action: #selector(SettingsWindow.about), keyEquivalent: "").target = settings
            menu.addItem(.separator())
            menu.addItem(withTitle: "退出 DisplayDial", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "").target = NSApp
            NSMenu.popUpContextMenu(menu, with: event, for: view)
            return nil
        }
        #if SCREENSHOTS
        DispatchQueue.main.async { Screenshots.run() }
        #endif
    }

    var body: some Scene {
        MenuBarExtra {
            Panel(displays: displays, keys: keys, settings: settings)
        } label: {
            if keys.needsAccess {
                Image(nsImage: dottedIcon).accessibilityLabel("DisplayDial 中文版需要辅助功能权限")
            } else {
                Image(nsImage: menuBarIcon).accessibilityLabel("DisplayDial")
            }
        }
        .menuBarExtraStyle(.window)
    }
}

private let menuBarIcon = NSImage(named: "MenuBarIconTemplate") ?? NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: nil)!

// Shown while the keyboard keys are on but macOS has dropped DisplayDial's Accessibility access.
private let dottedIcon: NSImage = {
    let icon = NSImage(size: menuBarIcon.size, flipped: false) { rect in
        menuBarIcon.draw(in: rect)
        NSBezierPath(ovalIn: NSRect(x: rect.maxX - 5, y: 0, width: 5, height: 5)).fill()
        return true
    }
    icon.isTemplate = true
    return icon
}()

struct Profile: Codable, Identifiable {
    var id = UUID()
    var name: String
    var values: [VCP: Int]
}

func screen(_ id: CGDirectDisplayID) -> NSScreen? {
    NSScreen.screens.first { $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID == id }
}

@Observable
final class Displays {
    var monitors: [Monitor] = []
    var selectedID: CGDirectDisplayID?
    var selected: Monitor? { monitors.first { $0.id == selectedID } ?? monitors.first }

    init() {
        rescan()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.rescan(rebind: true)
            // A freshly plugged monitor's DDC service can register a moment after the screen appears.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                guard let self else { return }
                self.rescan(rebind: true)
                self.monitors.filter { $0.responded == nil || $0 === self.selected }.forEach { $0.refresh() }
            }
        }
    }

    // Rebuilt on every panel open and display change, so replugged monitors get fresh IOAVService
    // handles; a Monitor object (and its cached capabilities) survives while its display stays online.
    func rescan(rebind: Bool = false) {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16), count: UInt32 = 0
        CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count)
        let external = ids.prefix(Int(count)).filter { CGDisplayIsBuiltin($0) == 0 }
        // Opening the menu must not replace an in-use DDC handle with a fresh one:
        // an older refresh task could still be reading from that same physical monitor.
        if !rebind, external.count == monitors.count,
           zip(external, monitors).allSatisfy({ $0.0 == $0.1.id }) { return }
        let services = DDC.externalDisplays()

        var pairs: [(id: CGDirectDisplayID, service: Int, score: Int)] = []
        for id in external {
            for (i, s) in services.enumerated() {
                let score = DDC.matchScore(s.attributes, vendor: CGDisplayVendorNumber(id), model: CGDisplayModelNumber(id),
                                           serial: CGDisplaySerialNumber(id), name: screen(id)?.localizedName)
                if score > 0 { pairs.append((id, i, score)) }
            }
        }
        var match: [CGDirectDisplayID: Int] = [:]
        for p in pairs.sorted(by: { $0.score > $1.score }) where match[p.id] == nil && !match.values.contains(p.service) {
            match[p.id] = p.service
        }
        // A future registry layout without attributes still works for the common one-monitor case.
        let unmatched = external.filter { match[$0] == nil }, spare = services.indices.filter { !match.values.contains($0) }
        if unmatched.count == 1, spare.count == 1 { match[unmatched[0]] = spare[0] }

        let baseNames = external.map { id in
            screen(id)?.localizedName ?? match[id].flatMap { services[$0].attributes["ProductName"] as? String } ?? "Display"
        }
        monitors = zip(external, baseNames).enumerated().map { i, pair in
            let (id, base) = pair
            let shared = baseNames.filter { $0 == base }.count > 1
            let name = shared ? "\(base) (\(baseNames[...i].filter { $0 == base }.count))" : base
            let m = monitors.first { $0.id == id } ?? Monitor(id: id, legacyProfilesKey: shared ? nil : "profiles.\(base)")
            m.name = name
            // Reuse a healthy service until topology actually changes. Creating a new
            // IOAVService on every panel open allows concurrent reads to interleave.
            if rebind || m.ddc == nil {
                m.ddc = match[id].map { services[$0].ddc }
            }
            return m
        }
    }
}

@Observable
final class Monitor: Identifiable {
    let id: CGDirectDisplayID
    var name = ""
    var ddc: DDC?
    // nil while the first read is in flight; false when the monitor never answered over DDC.
    var responded: Bool?
    var values: [VCP: Int] = [:]
    var maxes: [VCP: Int] = [:]
    // nil until the monitor's capabilities string is read; then code -> allowed values.
    var supported: [UInt8: [Int]]?
    // Dell (and most monitors) lock brightness/contrast while macOS drives them in HDR.
    var hdr = false
    var hdrSupported = false
    // Vendor-model-serial stays the same across reconnects and tells identical models apart.
    let key: String
    private var profilesKey: String { "profiles.\(key)" }
    var profiles: [Profile] {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(profiles), forKey: profilesKey) }
    }
    var volumeBeforeMute = 30
    // Keep the last successfully read values, but expose sustained read failures to UI.
    var readFailures = 0
    @ObservationIgnored private var refreshInFlight = false
    @ObservationIgnored private var refreshQueued = false

    init(id: CGDirectDisplayID, legacyProfilesKey: String?) {
        self.id = id
        key = "\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(CGDisplaySerialNumber(id))"
        let profilesKey = "profiles.\(key)"
        let defaults = UserDefaults.standard
        let data = defaults.data(forKey: profilesKey) ?? legacyProfilesKey.flatMap { defaults.data(forKey: $0) }
        profiles = data.flatMap { try? JSONDecoder().decode([Profile].self, from: $0) } ?? []
        if defaults.data(forKey: profilesKey) == nil, let data { defaults.set(data, forKey: profilesKey) }
    }

    func refresh(after delay: Double = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.refreshNow()
        }
    }

    private func refreshNow() {
        hdrSupported = HDR.supported(id)
        hdr = HDR.enabled(id) ?? ((screen(id)?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1) > 1)
        guard let ddc else { responded = false; return }
        // Coalesce refreshes from menu opens, display notifications and preset changes.
        // Each monitor should have only ONE DDC read sequence in flight at any moment.
        if refreshInFlight {
            refreshQueued = true
            return
        }
        refreshInFlight = true
        let known = supported
        Task.detached { [weak self, ddc, known] in
            var read: [VCP: (current: Int, max: Int)] = [:]
            // Probe the known-good VCP brightness code before asking for the much larger
            // capabilities string. This also lets us keep useful partial results.
            read[.brightness] = ddc.read(.brightness)
            let caps = known ?? ddc.capabilities().map(DDC.supportedCodes).flatMap { $0.isEmpty ? nil : $0 }
            for code in VCP.allCases where code != .brightness && (caps?[code.rawValue] != nil || caps == nil) {
                read[code] = ddc.read(code)
            }
            let (values, maxes) = (read.mapValues(\.current), read.mapValues(\.max))
            await MainActor.run {
                guard let self else { return }
                self.refreshInFlight = false
                // Discard responses from an old IOAVService after a screen reconnect.
                if self.ddc === ddc {
                    if !values.isEmpty {
                        self.supported = caps ?? self.supported
                        self.values.merge(values) { _, latest in latest }
                        self.maxes.merge(maxes) { _, latest in latest }
                        self.responded = true
                        self.readFailures = 0
                    } else {
                        self.readFailures += 1
                        // Do not turn a previously healthy monitor into "unsupported"
                        // after a single transient failure, or erase its last good data.
                        if self.values.isEmpty {
                            self.responded = self.readFailures >= 2 ? false : nil
                        }
                        if self.readFailures == 1 { self.refresh(after: 1) }
                    }
                }
                if self.refreshQueued {
                    self.refreshQueued = false
                    self.refreshNow()
                }
            }
        }
    }

    func setHDR(_ on: Bool) {
        hdr = on
        Task.detached { [id] in HDR.set(id, on) }
        refresh(after: 3)
    }

    var canRestoreColor: Bool { supported.map { $0[0x08] != nil } ?? true }

    func restoreFactoryColor() {
        ddc?.restoreFactoryColor()
        refresh(after: 1.5)
    }

    func set(_ code: VCP, _ value: Int) {
        values[code] = value
        ddc?.set(code, value)
    }

    func binding(_ code: VCP) -> Binding<Double> {
        Binding(get: { Double(self.values[code] ?? 0) }, set: { self.set(code, Int($0.rounded())) })
    }

    func supports(_ code: VCP) -> Bool { supported.map { $0[code.rawValue] != nil } ?? true }

    func options(_ code: VCP, fallback: [Int]) -> [Int] {
        supported?[code.rawValue].flatMap { $0.isEmpty ? nil : $0 } ?? fallback
    }

    // Changing mode/preset makes the monitor load that preset's own brightness, colour, etc.
    func switchPicture(_ code: VCP, _ value: Int) {
        set(code, value)
        refresh(after: 1)
    }

    // Many monitors (this Dell included) don't implement MCCS mute (0x8D), so mute is volume 0.
    func toggleMute() {
        let v = values[.volume] ?? 0
        if v > 0 { volumeBeforeMute = v; set(.volume, 0) } else { set(.volume, volumeBeforeMute) }
    }

    // Input (high byte is junk on Dell) and volume aren't part of a picture profile.
    var input: Int? { values[.input].map { $0 & 0xFF } }
    private static let profileCodes: [VCP] = [.presetMode, .colorPreset, .redGain, .greenGain, .blueGain, .brightness, .contrast]

    func saveProfile(_ name: String) {
        profiles.append(Profile(name: name, values: values.filter { Self.profileCodes.contains($0.key) }))
    }

    func updateProfile(_ p: Profile) {
        guard let i = profiles.firstIndex(where: { $0.id == p.id }) else { return }
        profiles[i].values = values.filter { Self.profileCodes.contains($0.key) }
    }

    func apply(_ p: Profile) {
        // Writing RGB gains under a fixed preset flips most monitors into their custom/user mode,
        // so gains are only restored when the profile was saved on a user preset (MCCS 0x0B–0x0D).
        let userPreset = p.values[.colorPreset].map { (0x0B...0x0D).contains($0) } ?? true
        for code in Self.profileCodes {
            guard let v = p.values[code], userPreset || ![.redGain, .greenGain, .blueGain].contains(code) else { continue }
            set(code, v)
        }
        refresh(after: 1)
    }

    func isActive(_ p: Profile) -> Bool {
        !p.values.isEmpty && p.values.allSatisfy { values[$0.key] == $0.value }
    }
}

struct Panel: View {
    let displays: Displays
    let keys: Keys
    let settings: SettingsWindow
    @AppStorage("hint.opens") private var opens = 0
    @AppStorage("hint.dismissed") private var hintDismissed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if displays.monitors.isEmpty {
                Label("未连接外接显示器", systemImage: "display.trianglebadge.exclamationmark")
                    .foregroundStyle(.secondary)
            }
            if displays.monitors.count > 1 {
                Picker("显示器", selection: Binding(get: { displays.selected?.id ?? 0 }, set: { displays.selectedID = $0 })) {
                    ForEach(displays.monitors) { Text($0.name).tag($0.id) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            if let monitor = displays.selected {
                MonitorSection(monitor: monitor, retryDetection: {
                    displays.rescan(rebind: true)
                    displays.selected?.refresh()
                }).id(monitor.id)
            }
            // Not on the first open, so the first look stays uncluttered.
            if opens >= 2, !hintDismissed, !keys.enabled, displays.selected?.responded == true {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "keyboard").foregroundStyle(.secondary)
                    Text("用键盘的亮度与音量键控制这台显示器？")
                    Spacer(minLength: 0)
                    Button("设置") { settings.show(highlightKeys: true) }
                        .buttonStyle(.link)
                    Button { hintDismissed = true } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("关闭提示")
                }
                .font(.callout)
            }
            Divider()
            HStack {
                Button { settings.show() } label: { Label("设置…", systemImage: "gearshape") }
                    .keyboardShortcut(",")
                Spacer()
                Button("退出") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .font(.callout)
            VStack(spacing: 2) {
                Text("由 Grab Connected Tech 用 ♥ 打造 · [grabians.com](https://www.grabians.com/?utm_source=displaydial&utm_medium=app)")
                Text("© 2026 Grab Connected Tech LLC · [MIT 开源许可](https://github.com/Grab-Connected-Tech/DisplayDial/blob/main/LICENSE)")
                Text("版本 \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev") · [发行版本](https://github.com/Grab-Connected-Tech/DisplayDial/releases)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .frame(width: 320)
        .onAppear {
            displays.rescan(); displays.selected?.refresh()
            if opens < 2 { opens += 1 }
        }
        .onChange(of: displays.selected?.id) { displays.selected?.refresh() }
    }
}

// MCCS names for VCP 0x60 / 0xDC / 0x14 values; 0x1B (USB-C) is Dell's.
private let inputNames = [0x01: "VGA", 0x03: "DVI", 0x0F: "DP 1", 0x10: "DP 2", 0x11: "HDMI 1", 0x12: "HDMI 2", 0x1B: "USB-C"]
private let modeNames = [0x00: "标准", 0x01: "办公", 0x02: "混合", 0x03: "电影", 0x04: "用户自定义",
                         0x05: "游戏", 0x06: "运动", 0x07: "专业"]
private let presetNames = [0x01: "sRGB", 0x02: "原生", 0x03: "4000K", 0x04: "5000K", 0x05: "6500K", 0x06: "7500K",
                           0x07: "8200K", 0x08: "9300K", 0x09: "10000K", 0x0A: "11500K", 0x0B: "用户 1", 0x0C: "用户 2", 0x0D: "用户 3"]
private func name(_ table: [Int: String], _ v: Int) -> String { table[v] ?? String(format: "0x%02X", v) }

struct MonitorSection: View {
    let monitor: Monitor
    let retryDetection: () -> Void
    @State private var showColor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(monitor.name, systemImage: "display")
                .font(.headline)

            if monitor.ddc == nil {
                hdrRow
                Label("未找到显示器的 DDC/CI 通信通道", systemImage: "slash.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("重新检测连接", action: retryDetection)
                    .buttonStyle(.link)
            } else if monitor.responded == false {
                hdrRow
                Label("暂时无法读取显示器硬件参数", systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("重试读取") { monitor.refresh() }
                    .buttonStyle(.link)
            } else if monitor.values.isEmpty {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity)
            } else {
                hdrRow
                if monitor.readFailures >= 2 {
                    Label("DDC/CI 读取异常，以下为上次成功读取的值", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("重试读取") { monitor.refresh() }
                        .buttonStyle(.link)
                }
                VStack(alignment: .leading, spacing: 12) {
                Group {
                    SliderRow(icon: "sun.max.fill", help: "亮度", monitor: monitor, code: .brightness)
                    SliderRow(icon: "circle.lefthalf.filled", help: "对比度", monitor: monitor, code: .contrast)
                }
                .disabled(monitor.hdr)
                if monitor.supports(.volume) {
                    SliderRow(icon: volumeIcon, help: (monitor.values[.volume] ?? 0) > 0 ? "静音" : "取消静音",
                              monitor: monitor, code: .volume) { monitor.toggleMute() }
                }

                let inputs = monitor.options(.input, fallback: [0x0F, 0x11, 0x12, 0x1B])
                Titled("输入源") {
                    Picker("输入源", selection: Binding(get: { monitor.input ?? -1 }, set: { monitor.set(.input, $0) })) {
                        ForEach(inputs, id: \.self) { Text(name(inputNames, $0)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .help("切换输入源后将看不到这台 Mac 的画面；请使用显示器实体按钮切回")
                }

                let modes = monitor.options(.presetMode, fallback: [])
                let presets = monitor.options(.colorPreset, fallback: [])
                if modes.count > 1 || presets.count > 1 || monitor.canRestoreColor {
                    Titled("画面设置") {
                        Group {
                            if modes.count > 1 {
                                Picker("画面模式", selection: Binding(get: { monitor.values[.presetMode] ?? -1 },
                                                                  set: { monitor.switchPicture(.presetMode, $0) })) {
                                    ForEach(modes, id: \.self) { Text(name(modeNames, $0)).tag($0) }
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                            }
                            if presets.count > 1 {
                                Picker("色彩预设", selection: Binding(get: { monitor.values[.colorPreset] ?? -1 },
                                                                          set: { monitor.switchPicture(.colorPreset, $0) })) {
                                    ForEach(presets, id: \.self) { Text(name(presetNames, $0)).tag($0) }
                                }
                                .font(.callout)
                            }
                        }
                        .disabled(monitor.hdr)
                        if monitor.canRestoreColor { FactoryColorButton(monitor: monitor) }
                    }
                }

                Titled("我的配置方案") { ProfilesRow(monitor: monitor) }

                DisclosureGroup("RGB 色彩调节", isExpanded: $showColor) {
                    VStack(spacing: 8) {
                        SliderRow(icon: "r.circle.fill", help: "红色", monitor: monitor, code: .redGain).tint(.red)
                        SliderRow(icon: "g.circle.fill", help: "绿色", monitor: monitor, code: .greenGain).tint(.green)
                        SliderRow(icon: "b.circle.fill", help: "蓝色", monitor: monitor, code: .blueGain).tint(.blue)
                    }
                    .padding(.top, 8)
                }
                .font(.callout)
                }
                // Stale settings remain visible for diagnosis, but must not be written
                // to the hardware until a successful read confirms the connection.
                .disabled(monitor.readFailures >= 2)
            }
        }
    }

    private var hdrRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15))
                    .frame(width: 22)
                    .foregroundStyle(.secondary)
                Text("HDR")
                Spacer()
                Text(monitor.hdr ? "开启" : monitor.hdrSupported ? "关闭" : "不支持")
                    .foregroundStyle(.secondary)
                if monitor.hdrSupported {
                    Toggle("HDR", isOn: Binding(get: { monitor.hdr }, set: { monitor.setHDR($0) }))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                }
            }
            .font(.callout)
            if monitor.hdr {
                Text("开启 HDR 后，显示器通常会锁定亮度、对比度和色彩预设。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var volumeIcon: String {
        let v = monitor.values[.volume] ?? 0
        return v == 0 ? "speaker.slash.fill" : v < 34 ? "speaker.wave.1.fill" : v < 67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
    }
}

private struct Titled<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content
        }
    }
}

struct ProfilesRow: View {
    let monitor: Monitor
    @State private var naming = false
    @State private var newName = ""
    @FocusState private var focused: Bool

    var body: some View {
        if naming {
            HStack(spacing: 6) {
                TextField("配置名称", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit(save)
                    .onExitCommand { naming = false }
                Button("保存", action: save)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.small)
            .onAppear { focused = true }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(monitor.profiles) { p in
                        Button(p.name) { monitor.apply(p) }
                            .buttonStyle(.bordered)
                            .tint(monitor.isActive(p) ? .accentColor : nil)
                            .help("点击应用配置；右键可更新或删除")
                            .contextMenu {
                                Button("更新为当前设置") { monitor.updateProfile(p) }
                                Button("删除", role: .destructive) { monitor.profiles.removeAll { $0.id == p.id } }
                            }
                    }
                    Button {
                        newName = ""
                        naming = true
                    } label: {
                        if monitor.profiles.isEmpty { Label("保存当前设置", systemImage: "plus") }
                        else { Image(systemName: "plus").accessibilityLabel("新建配置方案") }
                    }
                    .buttonStyle(.bordered)
                    .help("将当前画面设置保存为配置方案")
                }
                .buttonBorderShape(.capsule)
                .controlSize(.small)
            }
        }
    }

    private func save() {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        monitor.saveProfile(trimmed)
        naming = false
    }
}

// Two-step instead of an alert: alerts make the menu bar panel lose focus and close.
struct FactoryColorButton: View {
    let monitor: Monitor
    @State private var armed = false

    var body: some View {
        Button {
            if armed { monitor.restoreFactoryColor(); armed = false } else { armed = true }
        } label: {
            Label(armed ? "再次点击以确认恢复出厂颜色" : "恢复出厂颜色", systemImage: "arrow.counterclockwise")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(armed ? .red : .secondary)
        .font(.callout)
        .help("恢复色彩预设与红、绿、蓝增益的出厂值。建议先保存当前配置方案。")
        .task(id: armed) {
            guard armed else { return }
            try? await Task.sleep(for: .seconds(4))
            armed = false
        }
    }
}

struct SliderRow: View {
    let icon: String
    let help: String
    let monitor: Monitor
    let code: VCP
    var tap: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Button { tap?() } label: {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .frame(width: 22)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(tap == nil)
            .help(help)
            .accessibilityLabel(help)

            Slider(value: monitor.binding(code), in: 0...Double(max(monitor.maxes[code] ?? 100, 1)))
                .accessibilityLabel(help)

            Text("\(monitor.values[code] ?? 0)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .trailing)
        }
    }
}

// HDR on/off has no public API; these SkyLight calls are what macOS's own Displays settings use.
// Looked up at runtime so a future macOS that drops them just hides the toggle.
enum HDR {
    private static let sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    private static func fn<T>(_ name: String, as: T.Type) -> T? { dlsym(sky, name).map { unsafeBitCast($0, to: T.self) } }
    private static let supportsFn = fn("SLSDisplaySupportsHDRMode", as: (@convention(c) (CGDirectDisplayID) -> Bool).self)
    private static let enabledFn = fn("SLSDisplayIsHDRModeEnabled", as: (@convention(c) (CGDirectDisplayID) -> Bool).self)
    private static let setFn = fn("SLSDisplaySetHDRModeEnabled", as: (@convention(c) (CGDirectDisplayID, Bool, Int32, Int32) -> Int32).self)

    static func supported(_ id: CGDirectDisplayID) -> Bool { setFn != nil && supportsFn?(id) == true }
    static func enabled(_ id: CGDirectDisplayID) -> Bool? { enabledFn?(id) }
    static func set(_ id: CGDirectDisplayID, _ on: Bool) { _ = setFn?(id, on, 0, 0) }
}
