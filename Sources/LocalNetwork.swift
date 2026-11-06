import Foundation

enum LocalNetwork {
    /// 手机当前 WiFi 的内网 IP（en0）
    static func currentIP() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            let ifa = p.pointee
            if let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
                let name = String(cString: ifa.ifa_name)
                if name == "en0" || name.hasPrefix("en") {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                                   &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                        let ip = String(cString: host)
                        if !ip.hasPrefix("127.") && !ip.hasPrefix("169.254") {
                            return ip
                        }
                    }
                }
            }
            ptr = p.pointee.ifa_next
        }
        return nil
    }

    /// 探测某 IP 的端口是否开放
    static func probe(host: String, port: UInt16, timeout: Double = 0.4) -> Bool {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM
        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &res) == 0, let info = res else { return false }
        defer { freeaddrinfo(info) }

        let fd = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
        guard fd >= 0 else { return false }
        defer { Darwin.close(fd) }

        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        let r = Darwin.connect(fd, info.pointee.ai_addr, info.pointee.ai_addrlen)
        if r == 0 { return true }
        if errno != EINPROGRESS { return false }

        var wset = fd_set()
        withUnsafeMutableBytes(of: &wset) { $0.initializeMemory(as: UInt8.self, repeating: 0) }
        let intOffset = Int(fd) / 32
        let bitOffset = Int(fd) % 32
        withUnsafeMutableBytes(of: &wset.fds_bits) { raw in
            let p = raw.bindMemory(to: Int32.self)
            if intOffset < p.count { p[intOffset] |= Int32(bitPattern: UInt32(1) << UInt32(bitOffset)) }
        }
        var tv = timeval(tv_sec: 0, tv_usec: Int32(timeout * 1_000_000))
        let sel = select(fd + 1, nil, &wset, nil, &tv)
        if sel <= 0 { return false }
        var err: Int32 = 0
        var len = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len)
        return err == 0
    }

    /// 扫描本机所在 /24 网段，返回开了 ADB 端口的 IP
    static func scan(ports: [UInt16], progress: @escaping (Double) -> Void) async -> [String] {
        guard let myIP = currentIP() else { return [] }
        let parts = myIP.split(separator: ".")
        guard parts.count == 4 else { return [] }
        let prefix = "\(parts[0]).\(parts[1]).\(parts[2])."

        let hosts = (1...254).map { prefix + String($0) }
        var found: [String] = []
        var done = 0
        let total = hosts.count * ports.count

        await withTaskGroup(of: String?.self) { group in
            var index = 0
            let maxConcurrent = 48

            func addTask() {
                guard index < hosts.count else { return }
                let host = hosts[index]
                index += 1
                group.addTask {
                    for port in ports where LocalNetwork.probe(host: host, port: port) {
                        return "\(host):\(port)"
                    }
                    return nil
                }
            }

            for _ in 0..<maxConcurrent { addTask() }

            for await result in group {
                done += ports.count
                progress(min(1.0, Double(done) / Double(total)))
                if let found1 = result { found.append(found1) }
                addTask()
            }
        }
        return found
    }
}
