// licensetool — ClearDisplay 的授权签发与校验工具
//
// 离线签名授权，不需要服务器。原理：
//   开发者持私钥签发，应用内置公钥校验。
//   授权码 = base64url(载荷 JSON) + "." + base64url(Ed25519 签名)
//   载荷一旦被改动，签名就对不上，所以用户无法伪造或篡改。
//
// 编译：
//   swiftc -O licensetool.swift -o licensetool
//
// 用法：
//   ./licensetool keygen
//       生成一对密钥。私钥自己保管好，绝对不要放进应用里。
//
//   ./licensetool issue --key <私钥> --email <邮箱> --order <订单号>
//       签发一个授权码，打印出来发给客户。
//
//   ./licensetool verify --pub <公钥> --license <授权码>
//       校验授权码是否有效。

import Foundation
import CryptoKit

// MARK: - 编解码

func b64url(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

func fromB64url(_ s: String) -> Data? {
    var t = s.replacingOccurrences(of: "-", with: "+")
             .replacingOccurrences(of: "_", with: "/")
    while t.count % 4 != 0 { t += "=" }
    return Data(base64Encoded: t)
}

// MARK: - 载荷

struct LicensePayload: Codable {
    let product: String
    let email: String
    let order: String
    let issued: String
    let edition: String
}

// MARK: - 命令

func cmdKeygen() {
    let key = Curve25519.Signing.PrivateKey()
    let priv = key.rawRepresentation.base64EncodedString()
    let pub = key.publicKey.rawRepresentation.base64EncodedString()

    print("""
    === 密钥已生成 ===

    私钥（签发用，务必自己保存，不要泄露，不要放进应用）：
    \(priv)

    公钥（编译进应用，可以公开）：
    \(pub)

    把公钥填到 main.swift 的 LICENSE_PUBLIC_KEY 常量里。
    私钥建议存到密码管理器，或者 ~/.cleardisplay-key（权限 600）。
    """)
}

func cmdIssue(privB64: String, email: String, order: String, edition: String) {
    guard let privData = Data(base64Encoded: privB64),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: privData) else {
        FileHandle.standardError.write("私钥无效\n".data(using: .utf8)!)
        exit(1)
    }

    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy-MM-dd"
    let payload = LicensePayload(
        product: "ClearDisplay",
        email: email,
        order: order,
        issued: fmt.string(from: Date()),
        edition: edition
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let json = try? encoder.encode(payload) else {
        FileHandle.standardError.write("编码载荷失败\n".data(using: .utf8)!)
        exit(1)
    }
    guard let sig = try? key.signature(for: json) else {
        FileHandle.standardError.write("签名失败\n".data(using: .utf8)!)
        exit(1)
    }

    let license = b64url(json) + "." + b64url(sig)
    print(license)
    FileHandle.standardError.write("""

    已为 \(email)（订单 \(order)，\(edition) 版）签发授权码
    长度 \(license.count) 字符，可以直接发给客户。
    """.data(using: .utf8)!)
}

func cmdVerify(pubB64: String, license: String) {
    guard let pubData = Data(base64Encoded: pubB64),
          let pub = try? Curve25519.Signing.PublicKey(rawRepresentation: pubData) else {
        FileHandle.standardError.write("公钥无效\n".data(using: .utf8)!)
        exit(1)
    }
    let parts = license.split(separator: ".")
    guard parts.count == 2,
          let payloadData = fromB64url(String(parts[0])),
          let sigData = fromB64url(String(parts[1])) else {
        FileHandle.standardError.write("授权码格式错误\n".data(using: .utf8)!)
        exit(1)
    }
    guard pub.isValidSignature(sigData, for: payloadData) else {
        FileHandle.standardError.write("签名无效，授权码是伪造的或被改动过\n".data(using: .utf8)!)
        exit(1)
    }
    let payload = (try? JSONDecoder().decode(LicensePayload.self, from: payloadData))
    print("签名有效")
    if let p = payload {
        print("  产品：\(p.product)")
        print("  邮箱：\(p.email)")
        print("  订单：\(p.order)")
        print("  签发：\(p.issued)")
        print("  版本：\(p.edition)")
    }
}

// MARK: - 入口

let args = Array(CommandLine.arguments.dropFirst())
guard let cmd = args.first else {
    print("用法：licensetool keygen | issue --key <私钥> --email <邮箱> --order <订单号> [--edition pro] | verify --pub <公钥> --license <码>")
    exit(0)
}

func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: "--" + name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

switch cmd {
case "keygen":
    cmdKeygen()
case "issue":
    guard let k = option("key"), let e = option("email"), let o = option("order") else {
        FileHandle.standardError.write("缺少参数：--key --email --order\n".data(using: .utf8)!)
        exit(1)
    }
    cmdIssue(privB64: k, email: e, order: o, edition: option("edition") ?? "pro")
case "verify":
    guard let p = option("pub"), let l = option("license") else {
        FileHandle.standardError.write("缺少参数：--pub --license\n".data(using: .utf8)!)
        exit(1)
    }
    cmdVerify(pubB64: p, license: l)
default:
    FileHandle.standardError.write("未知命令：\(cmd)\n".data(using: .utf8)!)
    exit(1)
}
