import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var adb: ADBService

    @AppStorage("lastPort") private var port: Int = 5555
    @AppStorage("screenInterval") private var interval: Double = 1.2
    @AppStorage("refreshOnKey") private var refreshOnKey: Bool = true
    @AppStorage("showSystemApps") private var showSystem = false
    @AppStorage("keepApkCache") private var keepCache = true
    @AppStorage("autoOpenAfterInstall") private var autoOpen = false

    @State private var toast: String?

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("设置")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(Theme.textMain)
                    .padding(.top, 6)

                group("ADB 设置") {
                    row("默认端口", value: String(port))
                    Divider().background(Theme.divider)
                    row("连接超时", value: "8 秒")
                    Divider().background(Theme.divider)
                    row("扫描范围", value: "5555–5558")
                }

                group("投屏设置") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("刷新间隔")
                                .font(.system(size: 14))
                                .foregroundColor(Theme.textMain)
                            Spacer()
                            Text(String(format: "%.1f 秒", interval))
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(Theme.textSub)
                        }
                        Slider(value: $interval, in: 0.5...3.0, step: 0.1)
                            .tint(Theme.primaryDeep)
                    }
                    .padding(.vertical, 4)

                    Divider().background(Theme.divider)

                    toggleRow("按键后自动刷新画面", isOn: $refreshOnKey)
                }

                group("安装设置") {
                    toggleRow("显示系统应用", isOn: $showSystem) {
                        Task { await adb.loadApps(includeSystem: showSystem) }
                    }
                    Divider().background(Theme.divider)
                    toggleRow("保留 APK 缓存", isOn: $keepCache)
                    Divider().background(Theme.divider)
                    toggleRow("安装后自动打开", isOn: $autoOpen)
                }

                group("设备") {
                    row("型号", value: adb.deviceModel)
                    Divider().background(Theme.divider)
                    row("系统版本", value: "Android \(adb.androidVersion)")
                    Divider().background(Theme.divider)
                    row("分辨率", value: "\(Int(adb.screenSize.width)) × \(Int(adb.screenSize.height))")
                    Divider().background(Theme.divider)
                    row("状态", value: adb.state.text)
                }

                group("关于") {
                    row("版本", value: version)
                    Divider().background(Theme.divider)
                    Button {
                        show("ADB TV助手 · 局域网直连，数据不经过任何服务器")
                    } label: {
                        HStack {
                            Text("隐私说明")
                                .font(.system(size: 14))
                                .foregroundColor(Theme.textMain)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11))
                                .foregroundColor(Theme.textFaint)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Theme.bg.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            if let t = toast {
                Text(t)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Theme.deepBlue.opacity(0.92)))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: title)
            VStack(spacing: 12) { content() }
                .card()
        }
    }

    private func row(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 14))
                .foregroundColor(Theme.textMain)
            Spacer()
            Text(value)
                .font(.system(size: 13))
                .foregroundColor(Theme.textSub)
        }
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>, onChange: (() -> Void)? = nil) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(.system(size: 14))
                .foregroundColor(Theme.textMain)
        }
        .toggleStyle(SwitchToggleStyle(tint: Theme.primaryDeep))
        .onChange(of: isOn.wrappedValue) { _ in onChange?() }
    }

    private func show(_ t: String) {
        withAnimation { toast = t }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation { if toast == t { toast = nil } }
        }
    }
}
