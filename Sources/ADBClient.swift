import Foundation

enum ADBError: LocalizedError {
    case connect(String)
    case closed
    case protocolError(String)
    case timeout
    case auth(String)
    case device(String)

    var errorDescription: String? {
        switch self {
        case .connect(let m): return m
        case .closed: return "连接已断开"
        case .protocolError(let m): return "协议错误：\(m)"
        case .timeout: return "连接超时"
        case .auth(let m): return "需要授权：\(m)"
        case .device(let m): return m
        }
    }
}

struct ADBMessage {
    var cmd: UInt32
    var arg0: UInt32
    var arg1: UInt32
    var data: Data
}

let A_CNXN: UInt32 = 0x4e584e43
let A_AUTH: UInt32 = 0x48545541
let A_OPEN: UInt32 = 0x4e45504f
let A_OKAY: UInt32 = 0x59414b4f
let A_CLSE: UInt32 = 0x45534c43
let A_WRTE: UInt32 = 0x45545257
let ADB_VERSION: UInt32 = 0x01000000
let ADB_MAXDATA: UInt32 = 256 * 1024

/// 底层 TCP + ADB 报文收发（阻塞式，调用方放在后台队列）
final class ADBSocket {
    private var fd: Int32 = -1

    var isOpen: Bool { fd >= 0 }

    func connect(host: String, port: UInt16, timeout: TimeInterval) throws {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM
        var res: UnsafeMutablePointer<addrinfo>?
        let rc = getaddrinfo(host, String(port), &hints, &res)
        guard rc == 0, let info = res else {
            throw ADBError.connect("无法解析地址 \(host)")
        }
        defer { freeaddrinfo(info) }

        fd = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
        guard fd >= 0 else { throw ADBError.connect("创建 socket 失败") }

        // 非阻塞 connect + select 控制超时
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        let r = Darwin.connect(fd, info.pointee.ai_addr, info.pointee.ai_addrlen)
        if r != 0 {
            if errno != EINPROGRESS {
                close()
                throw ADBError.connect("连接被拒绝，请检查 ADB 是否开启")
            }
            var wset = fd_set()
            fdZero(&wset)
            fdSet(fd, &wset)
            var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
            let sel = select(fd + 1, nil, &wset, nil, &tv)
            if sel <= 0 {
                close()
                throw ADBError.timeout
            }
            var err: Int32 = 0
            var len = socklen_t(MemoryLayout<Int32>.size)
            getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len)
            if err != 0 {
                close()
                throw ADBError.connect("连接被拒绝，请检查 ADB 是否开启")
            }
        }
        _ = fcntl(fd, F_SETFL, flags)

        var tv = timeval(tv_sec: 20, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
    }

    func close() {
        if fd >= 0 {
            Darwin.close(fd)
            fd = -1
        }
    }

    func send(cmd: UInt32, arg0: UInt32, arg1: UInt32, data: Data = Data()) throws {
        guard fd >= 0 else { throw ADBError.closed }
        var crc: UInt32 = 0
        for b in data { crc = crc &+ UInt32(b) }
        var header = Data()
        header.append(le32(cmd))
        header.append(le32(arg0))
        header.append(le32(arg1))
        header.append(le32(UInt32(data.count)))
        header.append(le32(crc))
        header.append(le32(cmd ^ 0xFFFFFFFF))
        try writeAll(header)
        if !data.isEmpty { try writeAll(data) }
    }

    func recv() throws -> ADBMessage {
        guard fd >= 0 else { throw ADBError.closed }
        let header = try readExactly(24)
        let cmd = de32(header, 0)
        let arg0 = de32(header, 4)
        let arg1 = de32(header, 8)
        let len = Int(de32(header, 12))
        let magic = de32(header, 20)
        guard magic == (cmd ^ 0xFFFFFFFF) else {
            throw ADBError.protocolError("magic 校验失败")
        }
        var payload = Data()
        if len > 0 {
            guard len <= 4 * 1024 * 1024 else {
                throw ADBError.protocolError("报文过长 \(len)")
            }
            payload = try readExactly(len)
        }
        return ADBMessage(cmd: cmd, arg0: arg0, arg1: arg1, data: payload)
    }

    // MARK: - 原始读写

    private func writeAll(_ data: Data) throws {
        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            var sent = 0
            while sent < data.count {
                let n = Darwin.send(fd, base + sent, data.count - sent, 0)
                if n <= 0 {
                    if errno == EAGAIN || errno == EWOULDBLOCK { continue }
                    throw ADBError.closed
                }
                sent += n
            }
        }
    }

    private func readExactly(_ n: Int) throws -> Data {
        var buf = [UInt8](repeating: 0, count: n)
        var got = 0
        while got < n {
            let r = buf.withUnsafeMutableBytes { ptr -> Int in
                Darwin.recv(fd, ptr.baseAddress!.advanced(by: got), n - got, 0)
            }
            if r == 0 { throw ADBError.closed }
            if r < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK { throw ADBError.timeout }
                throw ADBError.closed
            }
            got += r
        }
        return Data(buf)
    }

    private func le32(_ v: UInt32) -> Data {
        var x = v.littleEndian
        return Data(bytes: &x, count: 4)
    }

    private func de32(_ d: Data, _ off: Int) -> UInt32 {
        var v: UInt32 = 0
        withUnsafeMutableBytes(of: &v) { dst in
            d.withUnsafeBytes { src in
                dst.copyBytes(from: UnsafeRawBufferPointer(rebasing: src[off..<off + 4]))
            }
        }
        return UInt32(littleEndian: v)
    }

    // MARK: - fd_set 辅助

    private func fdZero(_ set: inout fd_set) {
        withUnsafeMutableBytes(of: &set) { $0.initializeMemory(as: UInt8.self, repeating: 0) }
    }

    private func fdSet(_ fd: Int32, _ set: inout fd_set) {
        let intOffset = Int(fd) / 32
        let bitOffset = Int(fd) % 32
        withUnsafeMutableBytes(of: &set.fds_bits) { raw in
            let ptr = raw.bindMemory(to: Int32.self)
            if intOffset < ptr.count {
                ptr[intOffset] |= Int32(bitPattern: UInt32(1) << UInt32(bitOffset))
            }
        }
    }
}

// MARK: - 会话

final class ADBClient {
    private let sock = ADBSocket()
    private let queue = DispatchQueue(label: "adb.serial")
    private var nextId: UInt32 = 1

    private(set) var host: String = ""
    private(set) var port: UInt16 = 5555
    var banner: String = ""

    private func nextLocalId() -> UInt32 {
        nextId += 1
        if nextId > 60000 { nextId = 2 }
        return nextId
    }

    // MARK: 建连

    func connect(host: String, port: UInt16, timeout: TimeInterval = 8) async throws -> String {
        try await onQueue {
            try self.sock.connect(host: host, port: port, timeout: timeout)
            let features = "shell_v2,cmd,stat_v2,ls_v2,fixed_push_mkdir,sendrecv_v2"
            var payload = Data("host::".utf8)
            payload.append(0)
            payload.append(Data(features.utf8))
            payload.append(0)
            try self.sock.send(cmd: A_CNXN, arg0: ADB_VERSION, arg1: ADB_MAXDATA, data: payload)

            while true {
                let m = try self.sock.recv()
                if m.cmd == A_CNXN {
                    self.host = host
                    self.port = port
                    let name = String(data: m.data, encoding: .utf8) ?? ""
                    self.banner = name.components(separatedBy: "\0").first ?? name
                    return self.banner
                }
                if m.cmd == A_AUTH {
                    throw ADBError.auth("设备要求授权，请在电视上允许 USB 调试")
                }
            }
        }
    }

    func disconnect() {
        queue.sync { sock.close() }
    }

    // MARK: shell

    struct ShellResult {
        var output: String
        var exitCode: Int32
    }

    func shell(_ command: String) async throws -> ShellResult {
        try await onQueue { try self.syncShell(command) }
    }

    private func syncShell(_ command: String) throws -> ShellResult {
        let lid = nextLocalId()
        var payload = Data("shell,v2,raw:\(command)".utf8)
        payload.append(0)
        try sock.send(cmd: A_OPEN, arg0: lid, arg1: 0, data: payload)

        var out = Data()
        while true {
            let m = try sock.recv()
            if m.arg1 != lid && m.arg1 != 0 { continue }   // 上一条流的迟到消息
            if m.cmd == A_WRTE {
                var i = 0
                let bytes = [UInt8](m.data)
                while i + 5 <= bytes.count {
                    let type = bytes[i]
                    let len = Int(bytes[i + 1]) | Int(bytes[i + 2]) << 8 | Int(bytes[i + 3]) << 16 | Int(bytes[i + 4]) << 24
                    let start = i + 5
                    if start + len <= bytes.count {
                        let chunk = bytes[start..<start + len]
                        if type == 1 { out.append(contentsOf: chunk) }
                    }
                    i = start + len
                }
                try sock.send(cmd: A_OKAY, arg0: lid, arg1: m.arg0)
            } else if m.cmd == A_CLSE && m.arg1 == lid {
                try? sock.send(cmd: A_CLSE, arg0: lid, arg1: m.arg0)
                break
            }
        }
        return ShellResult(output: String(data: out, encoding: .utf8) ?? "", exitCode: 0)
    }

    /// exec: 服务，取原始字节（截图）
    func execRaw(_ command: String) async throws -> Data {
        try await onQueue {
            let lid = self.nextLocalId()
            var payload = Data(command.utf8)
            payload.append(0)
            try self.sock.send(cmd: A_OPEN, arg0: lid, arg1: 0, data: payload)
            var buf = Data()
            while true {
                let m = try self.sock.recv()
                if m.arg1 != lid && m.arg1 != 0 { continue }
                if m.cmd == A_WRTE {
                    buf.append(m.data)
                    try self.sock.send(cmd: A_OKAY, arg0: lid, arg1: m.arg0)
                } else if m.cmd == A_CLSE && m.arg1 == lid {
                    try? self.sock.send(cmd: A_CLSE, arg0: lid, arg1: m.arg0)
                    break
                }
            }
            return buf
        }
    }

    /// sync 推文件
    func push(data: Data, to remote: String, progress: ((Double) -> Void)? = nil) async throws {
        try await onQueue {
            let lid = self.nextLocalId()
            var open = Data("sync:".utf8)
            open.append(0)
            try self.sock.send(cmd: A_OPEN, arg0: lid, arg1: 0, data: open)

            var dev: UInt32 = 0
            while true {
                let m = try self.sock.recv()
                if m.cmd == A_OKAY && m.arg1 == lid { dev = m.arg0; break }
                if m.cmd == A_CLSE && m.arg1 == lid { throw ADBError.device("接收文件服务被拒绝") }
            }

            var responses = [Data]()
            func write(_ req: Data) throws {
                try self.sock.send(cmd: A_WRTE, arg0: lid, arg1: dev, data: req)
                while true {
                    let m = try self.sock.recv()
                    if m.cmd == A_OKAY && m.arg1 == lid { return }
                    if m.cmd == A_WRTE {
                        responses.append(m.data)
                        try self.sock.send(cmd: A_OKAY, arg0: lid, arg1: m.arg0)
                    } else if m.cmd == A_CLSE && m.arg1 == lid {
                        throw ADBError.device("传输中断")
                    }
                }
            }

            let spec = Data("\(remote),33188".utf8)
            var req = Data("SEND".utf8)
            req.append(le32(UInt32(spec.count)))
            req.append(spec)
            try write(req)

            let chunkSize = 64 * 1024
            var offset = 0
            while offset < data.count {
                let end = min(offset + chunkSize, data.count)
                let chunk = data.subdata(in: offset..<end)
                var d = Data("DATA".utf8)
                d.append(le32(UInt32(chunk.count)))
                d.append(chunk)
                try write(d)
                offset = end
                progress?(Double(offset) / Double(max(data.count, 1)))
            }

            var done = Data("DONE".utf8)
            done.append(le32(0))
            try write(done)
            var quit = Data("QUIT".utf8)
            quit.append(le32(0))
            try write(quit)

            for r in responses {
                if r.count >= 4, String(data: r.prefix(4), encoding: .utf8) == "FAIL" {
                    var msg = "推送失败"
                    if r.count > 8 {
                        msg = String(data: r.subdata(in: 8..<r.count), encoding: .utf8) ?? msg
                    }
                    throw ADBError.device(msg)
                }
            }
            try? self.sock.send(cmd: A_CLSE, arg0: lid, arg1: dev)
        }
    }

    private func le32(_ v: UInt32) -> Data {
        var x = v.littleEndian
        return Data(bytes: &x, count: 4)
    }

    private func onQueue<T>(_ body: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { cont in
            queue.async {
                do { cont.resume(returning: try body()) }
                catch { cont.resume(throwing: error) }
            }
        }
    }
}
