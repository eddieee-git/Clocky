// 릴리스 서명 키(Ed25519)를 다룬다. Apple 계정 없이 CryptoKit만 쓴다.
//
//   swift scripts/release-key.swift public              공개키를 보여 준다(키가 없으면 새로 만든다)
//   swift scripts/release-key.swift sign <dmg> <버전>    <dmg>.sig를 만든다
//
// 비밀키는 저장소 밖 ~/.clocky-release/signing-key에 둔다. 이 키를 잃어버리면
// 이미 배포한 앱이 새 버전을 믿지 않으므로, 안전한 곳에 백업해 두어야 한다.
// 다른 Mac에서 릴리스하려면 이 파일을 같은 자리에 복사한다.
import CryptoKit
import Foundation

let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".clocky-release")
let keyFile = folder.appendingPathComponent("signing-key")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func loadKey(create: Bool) -> Curve25519.Signing.PrivateKey {
    if let text = try? String(contentsOf: keyFile, encoding: .utf8),
       let raw = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
       let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) {
        return key
    }
    guard create else { fail("서명 키가 없습니다: \(keyFile.path)") }
    let key = Curve25519.Signing.PrivateKey()
    try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                             attributes: [.posixPermissions: 0o700])
    FileManager.default.createFile(atPath: keyFile.path, contents: Data(key.rawRepresentation.base64EncodedString().utf8),
                                   attributes: [.posixPermissions: 0o600])
    FileHandle.standardError.write(Data("새 서명 키를 만들었습니다: \(keyFile.path) — 꼭 백업하세요.\n".utf8))
    return key
}

/// 앱(UpdateChecker.signedMessage)과 같은 형식이어야 한다. 버전을 함께 서명해 옛 dmg를 새 버전으로 속이지 못하게 한다.
func message(version: String, sha256: String) -> Data {
    Data("clocky-release:\(version):\(sha256)".utf8)
}

let args = CommandLine.arguments
switch args.count > 1 ? args[1] : "" {
case "public":
    print(loadKey(create: true).publicKey.rawRepresentation.base64EncodedString())
case "sign":
    guard args.count == 4 else { fail("쓰는 법: swift scripts/release-key.swift sign <dmg> <버전>") }
    let key = loadKey(create: false)
    guard let data = FileManager.default.contents(atPath: args[2]) else { fail("파일을 읽지 못했습니다: \(args[2])") }
    let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    let signature = try! key.signature(for: message(version: args[3], sha256: sha))
    try! signature.base64EncodedString().write(toFile: args[2] + ".sig", atomically: true, encoding: .utf8)
    print(args[2] + ".sig")
default:
    fail("쓰는 법: swift scripts/release-key.swift public | sign <dmg> <버전>")
}
