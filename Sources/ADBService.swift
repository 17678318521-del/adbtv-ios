import Foundation
import UIKit

struct TVApp: Identifiable, Hashable {
    var id: String { package }
    let package: String
    var version: String = ""
    var system: Bool = false

    var displayName: String {
        let parts = package.split(separator: ".").map(String.init)
        guard parts.count >= 2 else { return package }
        return parts.suffix(2).joined(separator: ".")
    }
}

enum ConnState: Equatable {
    case disconnected
    case connecting
    case connected(String)

    var text: String {
        switch self {
        case .disconnected: return "未连接"
        case .connecting: return "连接中…"
        case .connected(let addr): return "已连接 \(addr)"
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

@MainActor
final class ADBService: ObservableObject {
    @Published private(set) var state: ConnState = .disconnected
    @Published private(set) var logs: [String] = []
    @Published private(set) var apps: [TVApp] = []
    @Published private(set) var loadingApps = false
    @Published private(set) var deviceModel = "—"
    @Published private(set) var androidVersion = "—"
    @Published private(set) var screenSize = CGSize(width: 1920, height: 1080)
    @Published private(set) var installing = false
    @Published private(set) var installProgress: Double = 0
    @Published private(set) var installMessage = ""
    @Published var lastError: String?

    private let client = ADBClient()
    private var connectedAddress = ""

    var isConnected: Bool { state.isConnected }

    // MARK: 日志

    func log(_ s: String) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        logs.append("[\(f.string(from: Date()))] \(s)")
        if logs.count > 400 { logs.removeFirst(logs.count - 400) }
    }

    func clearLogs() { logs.removeAll() }

    // MARK: 连接

    func connect(host: String, port: UInt16) async {
        guard !host.isEmpty else { lastError = "请输入电视 IP"; return }
        state = .connecting
        lastError = nil
        log("正在连接 \(host):\(port)…")
        do {
            let banner = try await client.connect(host: host, port: port, timeout: 8)
            connectedAddress = "\(host):\(port)"
            state = .connected(connectedAddress)
            log("已连接：\(banner)")
            UserDefaults.standard.set(host, forKey: "lastHost")
            UserDefaults.standard.set(Int(port), forKey: "lastPort")
            await loadDeviceInfo()
            await loadApps(includeSystem: false)
        } catch {
            state = .disconnected
            lastError = error.localizedDescription
            log("连接失败：\(error.localizedDescription)")
        }
    }

    func disconnect() {
        client.disconnect()
        state = .disconnected
        apps = []
        log("已断开连接")
    }

    // MARK: 设备信息

    func loadDeviceInfo() async {
        guard isConnected else { return }
        if let r = try? await client.shell("getprop ro.product.model") {
            let m = r.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !m.isEmpty { deviceModel = m }
        }
        if let r = try? await client.shell("getprop ro.build.version.release") {
            let v = r.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !v.isEmpty { androidVersion = v }
        }
        if let r = try? await client.shell("wm size") {
            let line = r.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if let range = line.range(of: "size: ") {
                let dims = line[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                let parts = dims.split(separator: "x")
                if parts.count == 2, let w = Double(parts[0]), let h = Double(parts[1]) {
                    screenSize = CGSize(width: w, height: h)
                }
            }
        }
    }

    func deviceDetail() async -> String {
        guard isConnected else { return "" }
        let script = "echo 型号:$(getprop ro.product.model); " +
            "echo 系统:Android $(getprop ro.build.version.release); " +
            "echo 分辨率:$(wm size); " +
            "echo 内存:$(grep MemTotal /proc/meminfo); " +
            "echo 存储:$(df /data | tail -1)"
        let r = try? await client.shell(script)
        return r?.output ?? ""
    }

    // MARK: 应用

    func loadApps(includeSystem: Bool) async {
        guard isConnected else { return }
        loadingApps = true
        defer { loadingApps = false }
        let cmd = includeSystem ? "pm list packages" : "pm list packages -3"
        guard let r = try? await client.shell(cmd) else { return }
        var list: [TVApp] = []
        for line in r.output.split(separator: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)
            guard s.hasPrefix("package:") else { continue }
            let pkg = String(s.dropFirst("package:".count))
            list.append(TVApp(package: pkg, system: includeSystem))
        }
        apps = list.sorted { $0.package < $1.package }
        log("应用列表：\(apps.count) 个")
    }

    func launch(_ app: TVApp) async {
        guard isConnected else { return }
        _ = try? await client.shell("monkey -p \(app.package) -c android.intent.category.LAUNCHER 1")
        log("启动 \(app.package)")
    }

    func uninstall(_ app: TVApp) async -> Bool {
        guard isConnected else { return false }
        let r = try? await client.shell("pm uninstall --user 0 \(app.package)")
        let ok = (r?.output.contains("Success") ?? false)
        log(ok ? "已卸载 \(app.package)" : "卸载失败 \(app.package)")
        if ok { apps.removeAll { $0.package == app.package } }
        return ok
    }

    func install(apk: Data, name: String) async -> Bool {
        guard isConnected else { return false }
        installing = true
        installProgress = 0
        installMessage = "正在上传…"
        defer { installing = false }

        let remote = "/data/local/tmp/adbtv_install.apk"
        let sizeMB = Double(apk.count) / 1048576
        log("开始安装 \(name)（\(String(format: "%.1f", sizeMB)) MB）")
        do {
            try await client.push(data: apk, to: remote) { p in
                Task { @MainActor in
                    self.installProgress = p * 0.7
                    self.installMessage = "正在上传 \(Int(p * 100))%"
                }
            }
            installMessage = "正在安装…"
            installProgress = 0.8
            let r = try await client.shell("pm install -r -d \(remote)")
            let out = r.output
            let ok = out.contains("Success")
            installMessage = ok ? "安装成功" : "安装失败"
            installProgress = 1.0
            log(ok ? "安装成功：\(name)" : "安装失败：\(out.trimmingCharacters(in: .whitespacesAndNewlines))")
            _ = try? await client.shell("rm -f \(remote)")
            if ok { await loadApps(includeSystem: false) }
            return ok
        } catch {
            installMessage = "安装失败"
            log("安装出错：\(error.localizedDescription)")
            return false
        }
    }

    // MARK: 截图

    func screenshot() async -> UIImage? {
        guard isConnected else { return nil }
        guard let data = try? await client.execRaw("exec:screencap -p"), data.count > 1000 else {
            return nil
        }
        return UIImage(data: data)
    }

    // MARK: 遥控

    func key(_ code: Int) async {
        guard isConnected else { return }
        _ = try? await client.shell("input keyevent \(code)")
    }

    func tap(x: Int, y: Int) async {
        guard isConnected else { return }
        _ = try? await client.shell("input tap \(x) \(y)")
    }

    func swipe(from: CGPoint, to: CGPoint, ms: Int = 250) async {
        guard isConnected else { return }
        _ = try? await client.shell("input swipe \(Int(from.x)) \(Int(from.y)) \(Int(to.x)) \(Int(to.y)) \(ms)")
    }

    func sendText(_ text: String) async {
        guard isConnected, !text.isEmpty else { return }
        let escaped = text.replacingOccurrences(of: " ", with: "%s")
        _ = try? await client.shell("input text '\(escaped)'")
        log("已发送文字")
    }

    func reboot() async {
        _ = try? await client.shell("reboot")
        log("已发送重启命令")
    }

    func powerOff() async {
        _ = try? await client.shell("reboot -p")
        log("已发送关机命令")
    }

    func ping() async -> Bool {
        guard isConnected else { return false }
        let r = try? await client.shell("echo adbtv-ok")
        let ok = (r?.output.contains("adbtv-ok") ?? false)
        log(ok ? "通道检测正常" : "通道检测失败")
        return ok
    }
}
