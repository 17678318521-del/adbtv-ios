import SwiftUI
import Photos

struct ConnectView: View {
    @EnvironmentObject var adb: ADBService

    @AppStorage("lastHost") private var host: String = "192.168.0.26"
    @AppStorage("lastPort") private var port: Int = 5555

    @State private var scanning = false
    @State private var scanProgress: Double = 0
    @State private var scanResults: [String] = []
    @State private var busy = false
    @State private var toast: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("ADB TV助手")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(Theme.textMain)
                    .padding(.top, 6)

                statusCard
                inputCard
                quickTools
                logCard
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Theme.bg.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            if let t = toast {
                Text(t)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(Theme.deepBlue.opacity(0.92)))
                    .padding(.bottom, 24)
                    .transition(.opacity)
            }
        }
        .onChange(of: adb.isConnected) { connected in
            if connected, adb.apps.isEmpty {
                Task { await adb.loadApps(includeSystem: false) }
            }
        }
    }

    // MARK: 状态卡

    private var statusCard: some View {
        HStack(spacing: 10) {
            StatusDot(color: statusColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(adb.state.text)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.textMain)
                Text(adb.isConnected ? "设备 \(adb.deviceModel) · Android \(adb.androidVersion)" : "请先连接电视或盒子")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSub)
            }
            Spacer()
            Button {
                Task { await doScan() }
            } label: {
                if scanning {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.7)
                        Text("\(Int(scanProgress * 100))%")
                    }
                } else {
                    Text("自动查找")
                }
            }
            .buttonStyle(SoftButtonStyle())
            .disabled(scanning || adb.isConnected)
        }
        .card()
    }

    private var statusColor: Color {
        switch adb.state {
        case .disconnected: return Theme.textFaint
        case .connecting: return Theme.primaryDeep
        case .connected: return Theme.success
        }
    }

    // MARK: 输入卡

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("电视/盒子 ADB 地址")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.textMain)

            HStack(spacing: 10) {
                TextField("192.168.0.26", text: $host)
                    .keyboardType(.numbersAndPunctuation)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .font(.system(size: 15))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.bg))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.fieldBorder, lineWidth: 1))

                TextField("5555", value: $port, formatter: NumberFormatter())
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 15))
                    .frame(width: 76)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.bg))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.fieldBorder, lineWidth: 1))
            }

            Button {
                Task {
                    busy = true
                    if adb.isConnected { adb.disconnect() }
                    else { await adb.connect(host: host, port: UInt16(port)) }
                    busy = false
                }
            } label: {
                Text(adb.isConnected ? "断开连接" : (adb.state == .connecting ? "连接中…" : "连接"))
            }
            .buttonStyle(PrimaryButtonStyle(enabled: !busy && adb.state != .connecting))

            if !scanResults.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("发现设备（点击连接）")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSub)
                    ForEach(scanResults, id: \.self) { addr in
                        Button {
                            let parts = addr.split(separator: ":")
                            host = String(parts[0])
                            port = Int(parts.count > 1 ? parts[1] : "5555") ?? 5555
                            scanResults = []
                            Task { await adb.connect(host: host, port: UInt16(port)) }
                        } label: {
                            HStack {
                                Image(systemName: "tv")
                                    .foregroundColor(Theme.primaryDeep)
                                Text(addr)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(Theme.textMain)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(Theme.textFaint)
                                    .font(.system(size: 12))
                            }
                            .padding(.vertical, 8)
                        }
                        Divider().background(Theme.divider)
                    }
                }
            }

            if let err = adb.lastError {
                Text(err)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.danger)
            }
        }
        .card()
    }

    // MARK: 快捷工具

    private var quickTools: some View {
        HStack(spacing: 10) {
            toolButton("通道检测", "bolt.horizontal") {
                Task {
                    let ok = await adb.ping()
                    show(ok ? "通道正常" : "通道异常")
                }
            }
            toolButton("重启设备", "arrow.clockwise") {
                Task { await adb.reboot(); show("已发送重启") }
            }
            toolButton("关机", "power") {
                Task { await adb.powerOff(); show("已发送关机") }
            }
            toolButton("截图保存", "camera") {
                Task { await saveScreenshot() }
            }
        }
        .disabled(!adb.isConnected)
        .opacity(adb.isConnected ? 1 : 0.45)
    }

    private func toolButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundColor(Theme.primaryDeep)
                Text(title)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSub)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.divider, lineWidth: 1))
            .shadow(color: Theme.primaryDeep.opacity(0.06), radius: 10, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }

    // MARK: 日志

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ADB 运行日志")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.textMain)
                Spacer()
                Button("清空") { adb.clearLogs() }
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSub)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(adb.logs.suffix(120).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundColor(Theme.textSub)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(height: 130)
        }
        .card()
    }

    // MARK: 动作

    private func doScan() async {
        scanning = true
        scanResults = []
        scanProgress = 0
        adb.log("开始扫描局域网 5555–5558…")
        let found = await LocalNetwork.scan(ports: [5555, 5556, 5557, 5558]) { p in
            Task { @MainActor in scanProgress = p }
        }
        scanResults = found
        scanning = false
        adb.log(found.isEmpty ? "未发现设备" : "发现 \(found.count) 台：\(found.joined(separator: ", "))")
        show(found.isEmpty ? "没有找到设备" : "发现 \(found.count) 台设备")
    }

    private func saveScreenshot() async {
        guard let img = await adb.screenshot() else { show("截图失败"); return }
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in show("没有相册权限") }
                return
            }
            UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
            Task { @MainActor in show("已保存到相册") }
        }
    }

    private func show(_ t: String) {
        withAnimation { toast = t }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation { if toast == t { toast = nil } }
        }
    }
}
