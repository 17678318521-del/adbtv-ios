import SwiftUI
import UIKit

struct RemoteView: View {
    @EnvironmentObject var adb: ADBService

    @AppStorage("screenInterval") private var interval: Double = 1.2
    @AppStorage("refreshOnKey") private var refreshOnKey: Bool = true

    @State private var image: UIImage?
    @State private var paused = false
    @State private var loading = false
    @State private var loopTask: Task<Void, Never>?
    @State private var toast: String?
    @State private var swipeStart: CGPoint?

    var body: some View {
        VStack(spacing: 10) {
            header
            screenCard
            quickBar
            keypad
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(Theme.bg.ignoresSafeArea())
        .onAppear { startLoop() }
        .onDisappear { stopLoop() }
        .onChange(of: adb.isConnected) { connected in
            if connected { startLoop() } else { stopLoop(); image = nil }
        }
        .overlay(alignment: .bottom) {
            if let t = toast {
                Text(t)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Theme.deepBlue.opacity(0.9)))
                    .padding(.bottom, 12)
            }
        }
    }

    // MARK: 顶栏

    private var header: some View {
        HStack {
            Text("投屏遥控")
                .font(.system(size: 21, weight: .semibold))
                .foregroundColor(Theme.textMain)
            Spacer()
            Button {
                Task { await saveShot() }
            } label: {
                Image(systemName: "camera")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Theme.primaryDeep)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white))
                    .overlay(Circle().stroke(Theme.divider, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: 画面

    private var screenCard: some View {
        VStack(spacing: 0) {
            if let img = image {
                GeometryReader { geo in
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .background(Color.black)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { v in
                                    if swipeStart == nil { swipeStart = v.startLocation }
                                }
                                .onEnded { v in
                                    handleGesture(start: v.startLocation, end: v.location, in: geo.size, img: img)
                                    swipeStart = nil
                                }
                        )
                }
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(Theme.primarySoft)
                    VStack(spacing: 8) {
                        Image(systemName: adb.isConnected ? "display" : "wifi.slash")
                            .font(.system(size: 34, weight: .light))
                            .foregroundColor(Theme.textFaint)
                        Text(adb.isConnected ? (loading ? "正在获取画面…" : "暂无画面") : "连接后显示电视画面")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.textSub)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            if adb.isConnected {
                Text(paused ? "已暂停" : "实时 · \(String(format: "%.1f", interval))s")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.black.opacity(0.45)))
                    .padding(8)
            }
        }
    }

    // MARK: 快捷栏

    private var quickBar: some View {
        HStack(spacing: 8) {
            smallButton("刷新画面", "arrow.triangle.2.circlepath") {
                Task { await refresh() }
            }
            smallButton(paused ? "继续拉流" : "暂停拉流", paused ? "play.fill" : "pause.fill") {
                paused.toggle()
                if !paused { startLoop() } else { stopLoop() }
            }
            smallButton("同步剪贴板", "doc.on.clipboard") {
                let text = UIPasteboard.general.string ?? ""
                Task {
                    await adb.sendText(text)
                    show(text.isEmpty ? "剪贴板为空" : "已同步剪贴板")
                }
            }
        }
        .disabled(!adb.isConnected)
        .opacity(adb.isConnected ? 1 : 0.45)
    }

    private func smallButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(Theme.deepBlue)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 11).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.divider, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: 遥控键

    private var keypad: some View {
        VStack(spacing: 9) {
            HStack(spacing: 9) {
                key("返回", 4)
                key("主页", 3)
                key("菜单", 82)
            }

            HStack(spacing: 9) {
                VStack(spacing: 9) {
                    key("↑", 19)
                    HStack(spacing: 9) {
                        key("←", 21)
                        key("OK", 66, highlight: true)
                        key("→", 22)
                    }
                    key("↓", 20)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 9) {
                    key("音量+", 24)
                    key("静音", 164)
                    key("音量-", 25)
                }
                .frame(width: 92)
            }

            HStack(spacing: 9) {
                key("电源", 26)
                key("上个应用", 187)
                key("输入源", 172)
            }
        }
        .disabled(!adb.isConnected)
        .opacity(adb.isConnected ? 1 : 0.45)
    }

    private func key(_ title: String, _ code: Int, highlight: Bool = false) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            Task {
                await adb.key(code)
                if refreshOnKey && !paused { await sleepRefresh() }
            }
        } label: {
            Text(title)
        }
        .buttonStyle(KeyPadStyle(highlight: highlight))
    }

    // MARK: 画面交互

    private func handleGesture(start: CGPoint, end: CGPoint, in size: CGSize, img: UIImage) {
        guard adb.isConnected, size.width > 0, size.height > 0 else { return }
        let imgSize = img.size
        let scale = min(size.width / imgSize.width, size.height / imgSize.height)
        let dw = imgSize.width * scale
        let dh = imgSize.height * scale
        let ox = (size.width - dw) / 2
        let oy = (size.height - dh) / 2

        func map(_ p: CGPoint) -> CGPoint {
            let x = (p.x - ox) / scale
            let y = (p.y - oy) / scale
            // 换算到设备物理像素
            let kx = adb.screenSize.width / imgSize.width
            let ky = adb.screenSize.height / imgSize.height
            return CGPoint(x: max(0, x * kx), y: max(0, y * ky))
        }

        let a = map(start)
        let b = map(end)
        let dist = hypot(end.x - start.x, end.y - start.y)

        Task {
            if dist < 12 {
                await adb.tap(x: Int(a.x), y: Int(a.y))
            } else {
                await adb.swipe(from: a, to: b, ms: 240)
            }
            if refreshOnKey && !paused { await sleepRefresh() }
        }
    }

    // MARK: 拉流循环

    private func startLoop() {
        stopLoop()
        guard adb.isConnected, !paused else { return }
        loopTask = Task {
            while !Task.isCancelled {
                await refresh()
                let ns = UInt64(max(0.4, interval) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: ns)
            }
        }
    }

    private func stopLoop() {
        loopTask?.cancel()
        loopTask = nil
    }

    private func refresh() async {
        guard adb.isConnected, !loading else { return }
        loading = true
        let img = await adb.screenshot()
        if let img { image = img }
        loading = false
    }

    private func sleepRefresh() async {
        try? await Task.sleep(nanoseconds: 180_000_000)
        await refresh()
    }

    private func saveShot() async {
        guard let img = image ?? (await adb.screenshot()) else { show("截图失败"); return }
        UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
        show("已保存到相册")
    }

    private func show(_ t: String) {
        withAnimation { toast = t }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation { if toast == t { toast = nil } }
        }
    }
}
