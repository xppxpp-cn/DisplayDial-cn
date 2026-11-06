// DisplayDial by Grab Connected Tech, https://www.grabians.com

import SwiftUI
import ServiceManagement

// An AppKit window rather than a Settings scene: it opens from the panel, the hint and the right-click menu,
// and has to come to the front even though DisplayDial has no Dock icon. Closing it doesn't quit the app.
final class SettingsWindow: NSObject {
    let keys: Keys
    private var window: NSWindow?

    init(keys: Keys) { self.keys = keys }

    @objc func open() { show() }

    func show(highlightKeys: Bool = false) {
        let window = window ?? NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        if self.window == nil {
            window.title = "DisplayDial 中文版 · 设置"
            window.isReleasedWhenClosed = false
            self.window = window
        }
        window.contentViewController = NSHostingController(rootView: SettingsView(keys: keys, highlightKeys: highlightKeys))
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
    let highlightKeys: Bool
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage("keys.brightness") private var brightnessTarget = "pointer"
    @AppStorage("keys.volume") private var volumeKeys = true
    @AppStorage("keys.speakers") private var speakers = ""
    @AppStorage("keys.osd") private var indicator = true
    @State private var explaining = false
    @State private var turnedOff = false
    @State private var updateStatus: String?
    private let otherAppRunning = NSWorkspace.shared.runningApplications.contains { otherMonitorApps.contains($0.bundleIdentifier ?? "") }

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

            Section("关于") {
                LabeledContent("版本", value: version)
                Link("DisplayDial GitHub 项目", destination: URL(string: "https://github.com/Grab-Connected-Tech/DisplayDial")!)
                HStack {
                    Button("检查更新") { Task { await checkForUpdates() } }
                    if let updateStatus { Text(.init(updateStatus)).foregroundStyle(.secondary) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .sheet(isPresented: $explaining) { explanation }
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
        updateStatus = "正在检查…"
        let url = URL(string: "https://api.github.com/repos/Grab-Connected-Tech/DisplayDial/releases/latest")!
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let tag = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["tag_name"] as? String else {
            updateStatus = "无法检查更新"
            return
        }
        let latest = String(tag.trimmingPrefix("v"))
        updateStatus = latest.compare(version, options: .numeric) == .orderedDescending
            ? "发现新版本 \(latest) · [下载官方版本](https://github.com/Grab-Connected-Tech/DisplayDial/releases/latest)"
            : "已是最新版本"
    }
}
