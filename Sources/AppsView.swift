import SwiftUI
import UniformTypeIdentifiers

struct AppsView: View {
    @EnvironmentObject var adb: ADBService
    @AppStorage("showSystemApps") private var showSystem = false

    @State private var query = ""
    @State private var showPicker = false
    @State private var pendingUninstall: TVApp?
    @State private var toast: String?

    private var filtered: [TVApp] {
        guard !query.isEmpty else { return adb.apps }
        let q = query.lowercased()
        return adb.apps.filter { $0.package.lowercased().contains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("应用管理")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(Theme.textMain)
                Spacer()
                Button {
                    showPicker = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("选择APK")
                    }
                }
                .buttonStyle(SoftButtonStyle())
                .disabled(!adb.isConnected)
            }
            .padding(.horizontal, 16)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Theme.textFaint)
                TextField("搜索包名", text: $query)
                    .font(.system(size: 14))
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(Theme.textFaint)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.fieldBorder, lineWidth: 1))
            .padding(.horizontal, 16)

            HStack(spacing: 10) {
                Text("\(adb.apps.count) 个应用")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSub)
                Spacer()
                Toggle("显示系统应用", isOn: $showSystem)
                    .font(.system(size: 12))
                    .toggleStyle(SwitchToggleStyle(tint: Theme.primaryDeep))
                    .fixedSize()
                    .onChange(of: showSystem) { v in
                        Task { await adb.loadApps(includeSystem: v) }
                    }
            }
            .padding(.horizontal, 16)

            if adb.loadingApps && adb.apps.isEmpty {
                Spacer()
                HStack { Spacer(); ProgressView(); Spacer() }
                Spacer()
            } else if adb.apps.isEmpty {
                emptyView
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filtered) { app in
                            row(app)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
            }
        }
        .padding(.top, 6)
        .background(Theme.bg.ignoresSafeArea())
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [UTType.data]) { result in
            handlePick(result)
        }
        .alert("卸载应用", isPresented: Binding(
            get: { pendingUninstall != nil },
            set: { if !$0 { pendingUninstall = nil } }
        ), presenting: pendingUninstall) { app in
            Button("卸载 \(app.package)", role: .destructive) {
                Task {
                    let ok = await adb.uninstall(app)
                    show(ok ? "已卸载" : "卸载失败")
                }
                pendingUninstall = nil
            }
            Button("取消", role: .cancel) { pendingUninstall = nil }
        } message: { app in
            Text("确认从电视卸载 \(app.package)？卸载后应用数据会一起删除。")
        }
        .overlay {
            if adb.installing {
                installOverlay
            }
        }
        .overlay(alignment: .bottom) {
            if let t = toast {
                Text(t)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(Theme.deepBlue.opacity(0.92)))
                    .padding(.bottom, 20)
            }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(Theme.textFaint)
            Text(adb.isConnected ? "暂无应用，下拉刷新或点右上角安装" : "请先在「连接」页连接设备")
                .font(.system(size: 13))
                .foregroundColor(Theme.textSub)
            if adb.isConnected {
                Button("刷新列表") {
                    Task { await adb.loadApps(includeSystem: showSystem) }
                }
                .buttonStyle(SoftButtonStyle())
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func row(_ app: TVApp) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11)
                    .fill(Theme.primarySoft)
                Text(String(app.displayName.prefix(1)).uppercased())
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Theme.deepBlue)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(app.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.textMain)
                    .lineLimit(1)
                Text(app.package)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSub)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)

            Button("打开") {
                Task { await adb.launch(app) }
            }
            .buttonStyle(SoftButtonStyle())

            Button {
                pendingUninstall = app
            } label: {
                Text("卸载")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.danger)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Theme.danger.opacity(0.10))
                    )
            }
            .buttonStyle(.plain)
            .disabled(app.system)
            .opacity(app.system ? 0.4 : 1)
        }
        .card(padding: 12)
    }

    private var installOverlay: some View {
        ZStack {
            Color.black.opacity(0.18).ignoresSafeArea()
            VStack(spacing: 14) {
                Text("推送安装到电视")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.textMain)
                Text(adb.installMessage)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textSub)
                ProgressView(value: adb.installProgress)
                    .tint(Theme.primaryDeep)
                    .frame(width: 220)
                Text("\(Int(adb.installProgress * 100))%")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Theme.textFaint)
            }
            .padding(24)
            .background(RoundedRectangle(cornerRadius: 20).fill(Color.white))
            .shadow(color: Theme.primaryDeep.opacity(0.18), radius: 24, x: 0, y: 8)
        }
    }

    // MARK: 选择 APK

    private func handlePick(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let name = url.lastPathComponent
        guard name.lowercased().hasSuffix(".apk") else {
            show("请选择 .apk 文件")
            return
        }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            Task {
                let ok = await adb.install(apk: data, name: name)
                show(ok ? "安装成功" : "安装失败")
            }
        } catch {
            show("读取文件失败")
        }
    }

    private func show(_ t: String) {
        withAnimation { toast = t }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation { if toast == t { toast = nil } }
        }
    }
}
