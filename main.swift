// ClearDisplay — 让非 Retina 外接显示器用上 HiDPI
// 仅用 Command Line Tools 即可编译，无需 Xcode
//
// 编译：
//   SDK=$(xcrun --show-sdk-path)
//   swiftc -sdk "$SDK" -target arm64-apple-macos14.0 -parse-as-library -O main.swift -o ClearDisplay

import SwiftUI
import CoreGraphics
import Foundation
import CryptoKit
import Security

// MARK: - 数据模型

struct DisplayInfo: Identifiable {
    let id: CGDirectDisplayID
    let name: String
    let vendor: Int
    let product: Int
    let panelWidth: Int
    let panelHeight: Int
    let logicalWidth: Int
    let logicalHeight: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let refreshRate: Double
    let isMain: Bool

    var isHiDPI: Bool { pixelWidth != logicalWidth }
    var summary: String {
        "\(logicalWidth)×\(logicalHeight)"
            + (isHiDPI ? "（\(pixelWidth / max(1, logicalWidth))× HiDPI）" : "（非 HiDPI）")
    }
}

struct ModeOption: Identifiable, Hashable {
    let id: String
    let logicalWidth: Int
    let logicalHeight: Int
    let pixelWidth: Int
    let pixelHeight: Int
    var label: String { "\(logicalWidth)×\(logicalHeight)" }
    var detail: String { "渲染 \(pixelWidth)×\(pixelHeight)" }
}

// MARK: - 显示器服务

enum DisplayService {
    static func onlineDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)
        return Array(ids.prefix(Int(count)))
    }

    /// 关键：必须传 showDuplicateLowResolutionModes，
    /// 否则系统只返回 LoDPI 变体，HiDPI 档位一个都看不到。
    static func allModes(for id: CGDirectDisplayID) -> [CGDisplayMode] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
        return (CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode]) ?? []
    }

    /// 面板原生尺寸：取所有非 HiDPI 模式里最大的那个
    static func panelSize(for id: CGDirectDisplayID) -> (Int, Int) {
        var w = 0, h = 0
        for m in allModes(for: id) where m.pixelWidth == m.width {
            if m.width > w { w = m.width; h = m.height }
        }
        return (w, h)
    }

    static func info(for id: CGDirectDisplayID) -> DisplayInfo? {
        guard let mode = CGDisplayCopyDisplayMode(id) else { return nil }
        let (pw, ph) = panelSize(for: id)
        let vendor = Int(CGDisplayVendorNumber(id))
        return DisplayInfo(
            id: id,
            name: vendorName(vendor),
            vendor: vendor,
            product: Int(CGDisplayModelNumber(id)),
            panelWidth: pw,
            panelHeight: ph,
            logicalWidth: mode.width,
            logicalHeight: mode.height,
            pixelWidth: mode.pixelWidth,
            pixelHeight: mode.pixelHeight,
            refreshRate: mode.refreshRate,
            isMain: CGDisplayIsMain(id) != 0
        )
    }

    static func vendorName(_ vendor: Int) -> String {
        switch vendor {
        case 0x2163: return "HKC 显示器"
        case 0x10AC: return "DELL 显示器"
        case 0x1E6D: return "LG 显示器"
        case 0x22F0: return "AOC 显示器"
        case 0x4C2D: return "Samsung 显示器"
        case 0x0469: return "Apple 显示器"
        case 0x756E6B6E: return "虚拟显示器"
        default: return String(format: "显示器 (厂商 0x%04X)", vendor)
        }
    }

    static func hiDPIOptions(for id: CGDirectDisplayID) -> [ModeOption] {
        var seen = Set<String>()
        var result: [ModeOption] = []
        for m in allModes(for: id) where m.pixelWidth != m.width {
            let key = "\(m.width)x\(m.height)"
            guard !seen.contains(key), m.width >= 1024 else { continue }
            seen.insert(key)
            result.append(ModeOption(id: key, logicalWidth: m.width, logicalHeight: m.height,
                                     pixelWidth: m.pixelWidth, pixelHeight: m.pixelHeight))
        }
        return result.sorted { $0.logicalWidth < $1.logicalWidth }
    }

    /// 切换分辨率必须走配置事务。直接调 CGDisplaySetDisplayMode 在 macOS 26+
    /// 会返回成功但被系统回滚，表现就是"命令说成功、屏幕没动"。
    static func apply(_ opt: ModeOption, to id: CGDirectDisplayID) -> Bool {
        let modes = allModes(for: id)
        guard let target = modes.first(where: {
            $0.width == opt.logicalWidth && $0.height == opt.logicalHeight && $0.pixelWidth != $0.width
        }) else { return false }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let cfg = config else { return false }
        guard CGConfigureDisplayWithDisplayMode(cfg, id, target, nil) == .success else {
            CGCancelDisplayConfiguration(cfg)
            return false
        }
        return CGCompleteDisplayConfiguration(cfg, .permanently) == .success
    }
}

// MARK: - 覆盖文件管理

enum OverrideManager {
    static let root = "/Library/Displays/Contents/Resources/Overrides"
    static var backupDir: String {
        NSString(string: "~/Documents/display-backup/overrides").expandingTildeInPath
    }

    /// Apple 约定目录名用小写十六进制
    static func path(vendor: Int, product: Int) -> String {
        let v = String(vendor, radix: 16, uppercase: false)
        return "\(root)/DisplayVendorID-\(v)/DisplayProductID-\(product)"
    }

    static func exists(vendor: Int, product: Int) -> Bool {
        FileManager.default.fileExists(atPath: path(vendor: vendor, product: product))
    }

    static let commonLoDPI: [(Int, Int)] = [
        (1024, 768), (1280, 720), (1280, 800), (1280, 960), (1280, 1024),
        (1366, 768), (1440, 900), (1600, 900), (1600, 1200),
        (1680, 1050), (1920, 1080), (1920, 1200),
        (2048, 1152), (2560, 1440), (2560, 1600), (2880, 1620),
        (3008, 1692), (3200, 1800), (3360, 1890), (3440, 1440),
        (3840, 2160),
    ]

    /// 把一串 UInt32 按大端序拼成字节
    /// 注意：不能对 Array 用 withUnsafeBytes(of:&arr)，那拿到的是数组结构体本身
    /// （8 字节指针），不是元素内容。必须逐个元素转。
    static func beBytes(_ values: [UInt32]) -> Data {
        var out = Data(capacity: values.count * 4)
        for v in values {
            var x = v.bigEndian
            withUnsafeBytes(of: &x) { out.append(contentsOf: $0) }
        }
        return out
    }

    /// 生成 scale-resolutions 数组
    ///   8 字节  = 普通模式 (宽, 高)
    ///   16 字节 = HiDPI 模式 (帧缓冲宽, 帧缓冲高, 0x9, 0x00200000)，逻辑 = 帧缓冲 / 2
    static func buildEntries(panelWidth: Int, panelHeight: Int) -> (lo: Int, hi: Int, data: [Data]) {
        var entries: [Data] = []

        for (w, h) in commonLoDPI where w <= panelWidth && h <= panelHeight {
            entries.append(beBytes([UInt32(w), UInt32(h)]))
        }
        if !commonLoDPI.contains(where: { $0 == (panelWidth, panelHeight) }) {
            entries.append(beBytes([UInt32(panelWidth), UInt32(panelHeight)]))
        }
        let loCount = entries.count

        // HiDPI 阶梯：逻辑宽度从面板一半到面板宽度，步进 16。
        // 逻辑 = 面板/2 时帧缓冲正好等于面板，整数 2 倍，最锐利。
        // 高度不做偶数对齐 —— 真实文件里存在 2224x1251 这种奇数高度。
        let aspect = Double(panelHeight) / Double(panelWidth)
        var w = max(1024, panelWidth / 2)
        while w <= panelWidth {
            let h = Int((Double(w) * aspect).rounded())
            entries.append(beBytes([UInt32(w * 2), UInt32(h * 2), 0x0000_0009, 0x0020_0000]))
            w += 16
        }
        return (loCount, entries.count - loCount, entries)
    }

    static func generatePlist(vendor: Int, product: Int,
                              panelWidth: Int, panelHeight: Int) throws -> (Data, Int, Int) {
        let (lo, hi, entries) = buildEntries(panelWidth: panelWidth, panelHeight: panelHeight)
        let dict: [String: Any] = [
            "DisplayProductID": product,
            "DisplayVendorID": vendor,
            "scale-resolutions": entries,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: dict,
                                                      format: .xml,
                                                      options: 0)
        return (data, lo, hi)
    }

    static func backupExisting(vendor: Int, product: Int) -> String? {
        let src = path(vendor: vendor, product: product)
        guard FileManager.default.fileExists(atPath: src) else { return nil }
        try? FileManager.default.createDirectory(atPath: backupDir, withIntermediateDirectories: true)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd-HHmmss"
        let dst = "\(backupDir)/DisplayProductID-\(product).\(fmt.string(from: Date())).plist"
        try? FileManager.default.copyItem(atPath: src, toPath: dst)
        return FileManager.default.fileExists(atPath: dst) ? dst : nil
    }

    /// 通过 osascript 请求管理员权限执行，会弹系统标准密码框
    static func runAsAdmin(_ shellCommand: String) -> (Bool, String) {
        let escaped = shellCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        let errPipe = Pipe()
        p.standardError = errPipe
        p.standardOutput = Pipe()
        do { try p.run() } catch { return (false, error.localizedDescription) }
        p.waitUntilExit()
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                         encoding: .utf8) ?? ""
        return (p.terminationStatus == 0, err.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func install(vendor: Int, product: Int,
                        panelWidth: Int, panelHeight: Int) -> (Bool, String, String?) {
        guard let (data, lo, hi) = try? generatePlist(vendor: vendor, product: product,
                                                      panelWidth: panelWidth,
                                                      panelHeight: panelHeight) else {
            return (false, "生成配置失败", nil)
        }
        let backup = backupExisting(vendor: vendor, product: product)

        let tmp = NSTemporaryDirectory() + "ClearDisplay-\(UUID().uuidString).plist"
        try? data.write(to: URL(fileURLWithPath: tmp))

        let target = path(vendor: vendor, product: product)
        let dir = (target as NSString).deletingLastPathComponent
        let cmd = "mkdir -p \"\(dir)\" && cp \"\(tmp)\" \"\(target)\" && "
            + "chown root:wheel \"\(target)\" && chmod 644 \"\(target)\""
        let (ok, err) = runAsAdmin(cmd)
        try? FileManager.default.removeItem(atPath: tmp)

        if ok {
            return (true, "已写入 \(lo) 个普通档位、\(hi) 个 HiDPI 档位", backup)
        }
        return (false, err, backup)
    }

    static func revert(vendor: Int, product: Int) -> (Bool, String) {
        let target = path(vendor: vendor, product: product)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: backupDir))?
            .filter { $0.hasPrefix("DisplayProductID-\(product).") }
            .sorted() ?? []

        if let latest = files.last {
            let src = "\(backupDir)/\(latest)"
            let cmd = "cp \"\(src)\" \"\(target)\" && chown root:wheel \"\(target)\" && chmod 644 \"\(target)\""
            let (ok, err) = runAsAdmin(cmd)
            return ok ? (true, "已还原到备份 \(latest)") : (false, err)
        }
        let (ok, err) = runAsAdmin("rm -f \"\(target)\"")
        return ok ? (true, "已删除覆盖文件，恢复系统默认") : (false, err)
    }
}

// MARK: - 授权

/// 离线签名授权。应用只内置公钥，私钥由开发者在自己的机器上保管。
/// 授权码 = base64url(载荷 JSON) + "." + base64url(Ed25519 签名)
/// 载荷被改一个字节，签名就对不上。
enum Licensing {
    static let publicKeyB64 = "5HorVZxk+umK7PBUMPcWv+HP6MCmbiXyAzDbGm7bFy0="
    static let trialDays = 7
    static let service = "com.cleardisplay.app"
    static let account = "license-state"

    struct Payload: Codable {
        let product: String
        let email: String
        let order: String
        let issued: String
        let edition: String
    }

    struct State: Codable {
        var firstRun: Date
        var license: String?
    }

    // MARK: base64url

    static func b64url(_ d: Data) -> String {
        d.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func fromB64url(_ s: String) -> Data? {
        var t = s.replacingOccurrences(of: "-", with: "+")
                 .replacingOccurrences(of: "_", with: "/")
        while t.count % 4 != 0 { t += "=" }
        return Data(base64Encoded: t)
    }

    // MARK: 校验

    static func verify(_ license: String) -> Payload? {
        guard let pubData = Data(base64Encoded: publicKeyB64),
              let pub = try? Curve25519.Signing.PublicKey(rawRepresentation: pubData) else { return nil }
        let parts = license.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".")
        guard parts.count == 2,
              let payloadData = fromB64url(String(parts[0])),
              let sigData = fromB64url(String(parts[1])) else { return nil }
        guard pub.isValidSignature(sigData, for: payloadData) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: payloadData)
    }

    // MARK: 持久化（钥匙串 + 文件双写，取更早的首次运行时间，防止删文件重置试用）

    static func loadState() -> State {
        var fromKeychain: State?
        if let data = keychainRead(), let s = try? JSONDecoder().decode(State.self, from: data) {
            fromKeychain = s
        }
        var fromFile: State?
        if let data = try? Data(contentsOf: stateURL),
           let s = try? JSONDecoder().decode(State.self, from: data) {
            fromFile = s
        }
        var state = fromKeychain ?? fromFile ?? State(firstRun: Date(), license: nil)
        if let f = fromFile, f.firstRun < state.firstRun { state.firstRun = f.firstRun }
        if let k = fromKeychain, k.firstRun < state.firstRun { state.firstRun = k.firstRun }
        if state.license == nil { state.license = fromFile?.license ?? fromKeychain?.license }
        return state
    }

    static func saveState(_ s: State) {
        guard let data = try? JSONEncoder().encode(s) else { return }
        keychainWrite(data)
        try? FileManager.default.createDirectory(
            at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: stateURL)
    }

    static var stateURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ClearDisplay/state.json")
    }

    private static func keychainRead() -> Data? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    private static func keychainWrite(_ data: Data) {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(q as CFDictionary)
        var add = q
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }

    // MARK: 状态判定

    enum Status {
        case licensed(Payload)
        case trial(daysLeft: Int)
        case expired
    }

    static func status(_ s: State) -> Status {
        if let lic = s.license, let p = verify(lic) { return .licensed(p) }
        let elapsed = Calendar.current.dateComponents([.day], from: s.firstRun, to: Date()).day ?? 0
        let left = trialDays - elapsed
        return left > 0 ? .trial(daysLeft: left) : .expired
    }
}

// MARK: - 状态

@MainActor
final class AppState: ObservableObject {
    @Published var displays: [DisplayInfo] = []
    @Published var options: [ModeOption] = []
    @Published var status: String = ""
    @Published var busy = false
    @Published var hasOverride = false
    @Published var licenseState = Licensing.loadState()
    @Published var showLicenseSheet = false
    @Published var licenseInput = ""

    init() {
        // 首次启动就把试用起始时间落盘，否则每次打开都算第一天
        Licensing.saveState(licenseState)
    }

    var current: DisplayInfo? { displays.first }

    var licenseStatus: Licensing.Status { Licensing.status(licenseState) }

    var isUnlocked: Bool {
        switch licenseStatus {
        case .licensed: return true
        case .trial: return true
        case .expired: return false
        }
    }

    var licenseBadge: (text: String, isPro: Bool) {
        switch licenseStatus {
        case .licensed(let p): return ("已授权 · \(p.edition)", true)
        case .trial(let d): return ("试用剩 \(d) 天", false)
        case .expired: return ("试用已结束", false)
        }
    }

    func refresh() {
        displays = DisplayService.onlineDisplays().compactMap { DisplayService.info(for: $0) }
        guard let d = current else { options = []; return }
        options = DisplayService.hiDPIOptions(for: d.id)
        hasOverride = OverrideManager.exists(vendor: d.vendor, product: d.product)
    }

    func activateLicense() {
        let code = licenseInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let payload = Licensing.verify(code) else {
            status = "授权码无效，请检查是否完整复制"
            return
        }
        licenseState.license = code
        Licensing.saveState(licenseState)
        showLicenseSheet = false
        licenseInput = ""
        status = "已激活，感谢支持（\(payload.email)）"
    }

    func apply(_ opt: ModeOption) {
        guard let id = current?.id else { return }
        busy = true
        status = "正在切换到 \(opt.label)…"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let ok = DisplayService.apply(opt, to: id)
            self.busy = false
            self.status = ok ? "已切换到 \(opt.label)" : "切换失败，系统拒绝了该模式"
            self.refresh()
        }
    }

    func installOverride() {
        guard let d = current else { return }
        busy = true
        status = "正在生成配置…"
        let vendor = d.vendor, product = d.product
        let pw = d.panelWidth, ph = d.panelHeight
        DispatchQueue.global(qos: .userInitiated).async {
            let (ok, msg, backup) = OverrideManager.install(vendor: vendor, product: product,
                                                           panelWidth: pw, panelHeight: ph)
            DispatchQueue.main.async {
                self.busy = false
                self.status = ok ? msg + "。请拔插显示器线或重启后生效。"
                                 : "写入失败：\(msg)"
                if let b = backup { self.status += "（已备份到 \(b)）" }
                self.refresh()
            }
        }
    }

    func revertOverride() {
        guard let d = current else { return }
        busy = true
        status = "正在还原…"
        let vendor = d.vendor, product = d.product
        DispatchQueue.global(qos: .userInitiated).async {
            let (ok, msg) = OverrideManager.revert(vendor: vendor, product: product)
            DispatchQueue.main.async {
                self.busy = false
                self.status = ok ? msg + "。请拔插显示器线或重启后生效。" : "还原失败：\(msg)"
                self.refresh()
            }
        }
    }
}

// MARK: - 界面

struct ContentView: View {
    @StateObject private var state = AppState()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if state.options.isEmpty { emptyState } else { modeList }
            Divider()
            footer
        }
        .frame(width: 520, height: 580)
        .onAppear { state.refresh() }
        .sheet(isPresented: $state.showLicenseSheet) {
            licenseSheet
        }
    }

    private var licenseSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("输入授权码")
                .font(.system(size: 15, weight: .semibold))
            Text("购买后会收到一串授权码，粘贴到这里即可激活。\n授权码是离线校验的，不需要联网。")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineSpacing(3)

            TextEditor(text: $state.licenseInput)
                .font(.system(size: 11, design: .monospaced))
                .frame(height: 90)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1))

            if !state.status.isEmpty {
                Text(state.status)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("取消") {
                    state.showLicenseSheet = false
                    state.licenseInput = ""
                }
                Button("激活") { state.activateLicense() }
                    .buttonStyle(.borderedProminent)
                    .disabled(state.licenseInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "display").font(.system(size: 20, weight: .light))
                Text(state.current?.name ?? "未检测到显示器")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(state.licenseBadge.text)
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(state.licenseBadge.isPro ? Color.accentColor.opacity(0.15)
                                                          : Color.secondary.opacity(0.12))
                    .foregroundStyle(state.licenseBadge.isPro ? Color.accentColor : Color.secondary)
                    .clipShape(Capsule())
                if let d = state.current {
                    Text(d.isHiDPI ? "HiDPI" : "普通模式")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(d.isHiDPI ? Color.green.opacity(0.18) : Color.orange.opacity(0.18))
                        .foregroundStyle(d.isHiDPI ? Color.green : Color.orange)
                        .clipShape(Capsule())
                }
            }
            if let d = state.current {
                Text("面板 \(d.panelWidth)×\(d.panelHeight)　当前 \(d.summary)　\(Int(d.refreshRate))Hz")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 34, weight: .ultraLight))
                .foregroundStyle(.secondary)
            Text("这块显示器还没有 HiDPI 档位")
                .font(.system(size: 14, weight: .medium))
            Text("系统只给 Retina 级面板原生提供 HiDPI。\n写入显示配置后就能按 2 倍渲染，文字会明显变清晰。")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            Button {
                state.installOverride()
            } label: {
                Text(state.isUnlocked ? "为这块显示器开启 HiDPI" : "试用已结束，请先激活")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 18).padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .disabled(state.busy || !state.isUnlocked)

            if !state.isUnlocked {
                Button("输入授权码") { state.showLicenseSheet = true }
                    .buttonStyle(.link).font(.system(size: 11.5))
            }

            if state.hasOverride {
                Text("配置已存在，可能只是还没拔插显示器线。")
                    .font(.system(size: 10.5)).foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    private var modeList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("可用清晰度")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                if state.hasOverride {
                    Button("还原配置") { state.revertOverride() }
                        .buttonStyle(.link).font(.system(size: 11))
                        .disabled(state.busy)
                }
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(state.options) { opt in modeRow(opt) }
                }
                .padding(.horizontal, 12).padding(.bottom, 12)
            }
        }
    }

    private func modeRow(_ opt: ModeOption) -> some View {
        let isCurrent = state.current.map {
            $0.logicalWidth == opt.logicalWidth && $0.logicalHeight == opt.logicalHeight
        } ?? false
        let isNative = state.current.map {
            opt.pixelWidth == $0.panelWidth && opt.pixelHeight == $0.panelHeight
        } ?? false

        return Button {
            state.apply(opt)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isCurrent ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary.opacity(0.4))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(opt.label).font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                        if isNative {
                            Text("最清晰")
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color.accentColor.opacity(0.15))
                                .foregroundStyle(Color.accentColor)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }
                    Text(opt.detail).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 7).padding(.horizontal, 10)
            .background(isCurrent ? Color.accentColor.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(state.busy)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if state.busy { ProgressView().scaleEffect(0.6).frame(width: 14, height: 14) }
            Text(state.status)
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            if case .licensed = state.licenseStatus {
                // 已授权不显示入口
            } else {
                Button("授权") { state.showLicenseSheet = true }
                    .buttonStyle(.link).font(.system(size: 11))
            }
            Button("刷新") { state.refresh() }
                .buttonStyle(.link).font(.system(size: 11))
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}

// MARK: - 入口

@main
struct ClearDisplayApp: App {
    init() {
        // 调试用：ClearDisplay --dump-config <宽> <高> 直接打印生成的 plist 到 stdout
        // 用来在不开界面的情况下验证生成结果
        let args = CommandLine.arguments
        if args.count >= 4, args[1] == "--dump-config",
           let w = Int(args[2]), let h = Int(args[3]) {
            if let (data, lo, hi) = try? OverrideManager.generatePlist(
                vendor: 0x2163, product: 0, panelWidth: w, panelHeight: h) {
                FileHandle.standardError.write("普通 \(lo) 个，HiDPI \(hi) 个\n".data(using: .utf8)!)
                FileHandle.standardOutput.write(data)
            }
            exit(0)
        }
    }

    var body: some Scene {
        WindowGroup("ClearDisplay") {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}
