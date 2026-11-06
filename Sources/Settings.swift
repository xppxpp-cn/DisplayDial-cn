// DisplayDial by Grab Connected Tech, https://www.grabians.com

import SwiftUI
import ServiceManagement

// An AppKit window rather than a Settings scene: it opens from the panel, the hint and the right-click menu,
// and has to come to the front even though DisplayDial has no Dock icon. Closing it doesn't quit the app.
final class SettingsWindow: NSObject {
    let keys: Keys
    let displays: Displays
    let hotkey: InputHotkey
    private var window: NSWindow?

    init(keys: Keys, displays: Displays, hotkey: InputHotkey) {
        self.keys = keys
        self.displays = displays
        self.hotkey = hotkey
    }

    @objc func open() { show() }

    func show(highlightKeys: Bool = false) {
        let window = window ?? NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        if self.window == nil {
            window.title = "DisplayDial 中文版 · 设置"
            window.isReleasedWhenClosed = false
            self.window = window
        }
        window.contentViewController = NSHostingController(rootView: SettingsView(keys: keys, displays: displays, hotkey: hotkey, highlightKeys: highlightKeys))
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc func about() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }
}

private let otherMonitorApps: Set = ["me.guillaumeb.MonitorControl", "pro.betterdisplay.BetterDisplay", "fyi.lunar.Lunar"]
private let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"

struct SettingsView: View {
    let keys: Keys
    let displays: Displays
    let hotkey: InputHotkey
    let highlightKeys: Bool
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage("keys.brightness") private var brightnessTarget = "pointer"
    @AppStorage("keys.volume") private var volumeKeys = true
    @AppStorage("keys.speakers") private var speakers = ""
    @AppStorage("keys.osd") private var indicator = true
    @State private var explaining = false
    @State private var explainingHotkey = false
    @State private var turnedOff = false
    @State private var updateStatus: String?
    private let otherAppRunning = NSWorkspace.shared.runningApplications.contains { otherMonitorApps.contains($0.bundleIdentifier ?? "") }

    // Without a built-in display, switching the monitor away leaves this Mac with no picture at all.
    private var hasBuiltInDisplay: Bool {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16), count: UInt32 = 0
        CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count)
        return ids.prefix(Int(count)).contains { CGDisplayIsBuiltin($0) != 0 }
    }

    var body: some View {
        Form {
            Section("常规") {
                Toggle("登录时启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do { on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
                        catch { launchAtLogin = SMAppService.mainApp.status == .enabled }
                    }
            }

            Section("键盘控制") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("使用键盘按键控制外接显示器", isOn: Binding(get: { keys.enabled }, set: { on in
                        if on, !keys.trusted { explaining = true } else { keys.enabled = on }
                        turnedOff = !on && keys.trusted
                    }))
                    if keys.enabled {
                        if keys.trusted {
                            Label("已就绪", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        } else {
                            HStack {
                                Label("需要辅助功能权限", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                                Spacer()
                                // Prompting (not just opening the page) lists this exact build; ad-hoc builds each need their own entry.
                                Button("打开系统设置") { keys.requestAccess() }
                            }
                        }
                    } else if turnedOff {
                        Text("也可以在“系统设置 → 隐私与安全性 → 允许辅助应用程序控制电脑”中管理 DisplayDial 中文版的授权。")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
                .padding(highlightKeys ? 6 : 0)
                .background(highlightKeys ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))

                Group {
                    Picker("亮度键控制目标", selection: $brightnessTarget) {
                        Text("鼠标指针所在的显示器").tag("pointer")
                        Text("活动窗口所在的显示器").tag("window")
                        Text("所有显示器").tag("all")
                    }
                    Toggle("音量键控制显示器的音频输出", isOn: $volumeKeys)
                    let candidates = keys.speakerCandidates
                    if candidates.count > 1 {
                        Picker("当前使用的显示器音频设备", selection: $speakers) {
                            Text("自动选择").tag("")
                            ForEach(candidates) { Text($0.name).tag($0.key) }
                        }
                        .disabled(!volumeKeys)
                    }
                    Toggle("显示屏幕音量 / 亮度提示", isOn: $indicator)
                }
                .disabled(!keys.enabled)

                if otherAppRunning {
                    Label("检测到其他显示器管理软件也在运行，可能同时响应这些按键。", systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section("输入源切换") {
                Toggle("用快捷键在两个输入源之间切换", isOn: Binding(
                    get: { hotkey.enabled },
                    set: { on in
                        if on { explainingHotkey = true } else { hotkey.enabled = false }
                    }))

                if hotkey.enabled {
                    HStack {
                        Text("快捷键")
                        HotkeyRecorder(keyCode: Binding(get: { hotkey.keyCode }, set: { hotkey.keyCode = $0 }),
                                       modifiers: Binding(get: { hotkey.modifiers }, set: { hotkey.modifiers = $0 }),
                                       onEditing: { editing in editing ? hotkey.suspend() : hotkey.resume() })
                            .frame(width: 110, height: 22)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.12)))
                        Text("点一下，然后按下想用的组合键").font(.caption).foregroundStyle(.secondary)
                    }
                    if hotkey.conflict {
                        Label("这个组合键已被别的应用占用，请换一个。", systemImage: "exclamationmark.triangle.fill")
                            .font(.callout).foregroundStyle(.orange)
                    } else if hotkey.unavailable {
                        Label("系统没能注册这个组合键，请换一个。", systemImage: "exclamationmark.triangle.fill")
                            .font(.callout).foregroundStyle(.orange)
                    }
                    if let monitor = displays.selected {
                        let inputs = monitor.options(.input, fallback: [])
                        if inputs.count >= 2 {
                            let pair = monitor.pairedInputs
                            Picker("切换到", selection: Binding(get: { pair.first ?? -1 }, set: { monitor.setInputPair(0, $0) })) {
                                ForEach(inputs.filter { pair.count == 2 ? $0 != pair[1] : true }, id: \.self) {
                                    Text(Monitor.inputName($0)).tag($0)
                                }
                            }
                            Picker("和", selection: Binding(get: { pair.count == 2 ? pair[1] : -1 }, set: { monitor.setInputPair(1, $0) })) {
                                ForEach(inputs.filter { pair.count == 2 ? $0 != pair[0] : true }, id: \.self) {
                                    Text(Monitor.inputName($0)).tag($0)
                                }
                            }
                        } else {
                            Label("这块显示器没有上报可切换的输入源。", systemImage: "info.circle")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    Toggle("切换前先确认", isOn: Binding(get: { hotkey.confirm }, set: { hotkey.confirm = $0 }))
                    if !hasBuiltInDisplay {
                        Label("这台 Mac 没有内置屏幕。切走后你会暂时看不到画面，需要用显示器的按键切回，或在显示器的「输入源」里开启「自动选择」。",
                              systemImage: "exclamationmark.triangle")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
            }

            Section("关于") {
                LabeledContent("版本", value: version)
                Link("DisplayDial GitHub 项目", destination: URL(string: "https://github.com/Grab-Connected-Tech/DisplayDial")!)
                HStack {
                    Button("检查上游更新") { Task { await checkForUpdates() } }
                    if let updateStatus { Text(.init(updateStatus)).foregroundStyle(.secondary) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .sheet(isPresented: $explaining) { explanation }
        .sheet(isPresented: $explainingHotkey) { hotkeyExplanation }
    }

    private var hotkeyExplanation: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("用快捷键切换输入源").font(.headline)
            Text("按下快捷键后，显示器会切到另一个输入源。")
            if !hasBuiltInDisplay {
                Text("这台 Mac 没有内置屏幕，切走后你会暂时看不到画面。请用显示器自己的按键切回，或者在显示器的「输入源」里开启「自动选择」。")
            }
            Text("DisplayDial 用系统注册这个快捷键，不会监听你输入的文字。")
            Text("这个组合键会被 DisplayDial 独占，别的应用不会再收到它。")
            HStack {
                Spacer()
                Button("暂不开启") { explainingHotkey = false }
                    .keyboardShortcut(.cancelAction)
                Button("继续") {
                    explainingHotkey = false
                    hotkey.enabled = true
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(20)
        .frame(width: 420)
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("允许 DisplayDial 使用键盘媒体键").font(.headline)
            Text("若要让键盘的亮度键和音量键控制外接显示器，DisplayDial 需要先于 macOS 接收这些媒体键，因此需要辅助功能权限。")
            Text("DisplayDial 只监听亮度、音量及静音媒体键，不会读取你输入的文字。除手动检查更新外，不会主动访问网络。")
            HStack {
                Spacer()
                Button("暂不开启") { explaining = false }
                    .keyboardShortcut(.cancelAction)
                Button("继续") {
                    explaining = false
                    keys.enabled = true
                    keys.requestAccess()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(20)
        .frame(width: 400)
    }

    // DisplayDial's only network request, made only when this button is clicked.
    private func checkForUpdates() async {
        updateStatus = "正在检查上游版本…"
        let url = URL(string: "https://api.github.com/repos/Grab-Connected-Tech/DisplayDial/releases/latest")!
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let tag = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["tag_name"] as? String else {
            updateStatus = "无法检查上游更新"
            return
        }
        let latest = String(tag.trimmingPrefix("v"))
        updateStatus = latest.compare(version, options: .numeric) == .orderedDescending
            ? "上游发布了 \(latest) · [下载英文原版](https://github.com/Grab-Connected-Tech/DisplayDial/releases/latest)"
            : "当前已与上游最新版本一致"
    }
}
