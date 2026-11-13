import Foundation
import Testing
@testable import Clocky

/// 네트워크 없이 서버 응답을 흉내 낸다. 경로마다 다른 응답을 준다.
final class FakeServer: URLProtocol {
    nonisolated(unsafe) static var lastIfNoneMatch: String?

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "fake.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        Self.lastIfNoneMatch = request.value(forHTTPHeaderField: "If-None-Match")
        var status = 200
        var headers: [String: String] = [:]
        var body = Data("BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n".utf8)
        switch url.path {
        case "/etag.ics":
            headers["ETag"] = "\"v1\""
            if Self.lastIfNoneMatch == "\"v1\"" { status = 304; body = Data() }
        case "/huge.ics":
            body = Data(repeating: 65, count: 21 * 1024 * 1024)
        case "/html":
            body = Data("<html></html>".utf8)
        case "/missing.ics":
            status = 404
        default:
            break
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized) struct CalendarFetchTests {
    let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FakeServer.self]
        return URLSession(configuration: configuration)
    }()

    private func url(_ path: String) -> URL { URL(string: "https://fake.test\(path)")! }

    @Test func 받기와_ETag() async {
        let first = await CalendarSync.fetch(url("/etag.ics"), etag: nil, session: session)
        #expect(first == .text("BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n", etag: "\"v1\""))
        let second = await CalendarSync.fetch(url("/etag.ics"), etag: "\"v1\"", session: session)
        #expect(FakeServer.lastIfNoneMatch == "\"v1\"")
        #expect(second == .notModified)
    }

    @Test func 너무_크거나_iCal이_아니거나_없는_주소() async {
        if case .failure = await CalendarSync.fetch(url("/huge.ics"), etag: nil, session: session) {} else { Issue.record("큰 파일을 받음") }
        if case .failure = await CalendarSync.fetch(url("/html"), etag: nil, session: session) {} else { Issue.record("iCal이 아닌 것을 받음") }
        if case .failure = await CalendarSync.fetch(url("/missing.ics"), etag: nil, session: session) {} else { Issue.record("404를 받음") }
    }
}
