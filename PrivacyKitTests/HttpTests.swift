import XCTest
@testable import PrivacyKit

class HttpTests: XCTestCase {

	func testCategoryForStatus() {
		XCTAssertEqual(Http.category(for: .Continue), Http.StatusCategory.informal)
		XCTAssertEqual(Http.category(for: .ok), Http.StatusCategory.success)
		XCTAssertEqual(Http.category(for: .temporaryRedirect), Http.StatusCategory.redirection)
		XCTAssertEqual(Http.category(for: .notFound), Http.StatusCategory.clientError)
		XCTAssertEqual(Http.category(for: .internalServerError), Http.StatusCategory.serverError)
	}

	func testInvalidRequest() {
		// File URLs should not work
		XCTAssertNil(Http.Request(withMethod: .head, andUrl: URL.init(fileURLWithPath: "/tmp", isDirectory: true)))

		let url = URL(string: "http://example.com")!

		// CONNECT and OPTIONS require additional parameters
		XCTAssertNil(Http.Request(withMethod: .connect, andUrl: url))
		XCTAssertNil(Http.Request(withMethod: .options, andUrl: url))

		// CONNECT and HEAD have no body
		let body = Data("foo".utf8)
		XCTAssertNil(Http.Request(withMethod: .connect, andUrl: url, andHeaders: [:], andBody: body, andOptions: ""))
		XCTAssertNil(Http.Request(withMethod: .head, andUrl: url, andHeaders: [:], andBody: body))
	}

	func testHeaderPatching() {
		let url = URL(string: "http://example.com")!
		let body = Data("foo".utf8)

		// Test if Host header is set
		let request1 = Http.Request(withMethod: .head, andUrl: url)!
		XCTAssertEqual(request1.headers[Http.Header.host.rawValue], "example.com")
		let request2 = Http.Request(withMethod: .head, andUrl: url, andHeaders: [Http.Header.host.rawValue: "foobar"])!
		XCTAssertEqual(request2.headers[Http.Header.host.rawValue], "foobar")

		// Test if Content-Length header is correct
		let request3 = Http.Request(withMethod: .head, andUrl: url)!
		XCTAssertFalse(request3.headers.keys.contains(Http.Header.contentLength.rawValue))
		let request4 = Http.Request(withMethod: .post, andUrl: url, andHeaders: [:], andBody: body)!
		XCTAssertEqual(request4.headers[Http.Header.contentLength.rawValue], "\(body.count)")
		let request5 = Http.Request(withMethod: .post, andUrl: url, andHeaders: [Http.Header.contentLength.rawValue: "\(body.count + 1)"], andBody: body)!
		XCTAssertEqual(request5.headers[Http.Header.contentLength.rawValue], "\(body.count + 1)")
	}

	func testHostSanitization() {
		XCTAssertNil(Target(withHostname: "example.com", andPort: 0))
		XCTAssertNil(Target(withHostname: "", andPort: 80))
		XCTAssertNil(Target(withHostname: "😱", andPort: 80))
		XCTAssertNil(Target(withHostname: "::1", andPort: 80))
		XCTAssertNotNil(Target(withHostname: "example.com", andPort: 80))
		XCTAssertNotNil(Target(withHostname: "[::1]", andPort: 80))
		XCTAssertNotNil(Target(withHostname: "127.0.0.1", andPort: 80))
	}

	func testHeadRequest() {
		let request = Http.Request(withMethod: .head, andUrl: URL(string: "https://example.com/")!, andHeaders: ["X-Test": "foobar", "X-Foo": "Bar"])!

		let actual = String(data: request.compose()!, encoding: .utf8)!
		let expected = "HEAD / HTTP/1.1\r\nX-Test: foobar\r\nHost: example.com\r\nX-Foo: Bar\r\n\r\n"

		XCTAssertEqual(actual, expected)
	}

	func testConnectRequest() {
		let target = Target(withHostname: "example.com", andPort: 80)!
		let proxy = Target(withHostname: "localhost", andPort: 8888)!
		let request = Http.Request.connect(toTarget: target, viaProxy: proxy, withHeaders: ["X-Test": "foobar", "X-Foo": "Bar"])!

		let actual = String(data: request.compose()!, encoding: .utf8)!
		let expected = "CONNECT example.com:80 HTTP/1.1\r\nX-Test: foobar\r\nHost: localhost\r\nX-Foo: Bar\r\n\r\n"

		XCTAssertEqual(actual, expected)
	}

	func testPServiceUploadResponse() {
		let rawResponse = Data("HTTP/1.0 200 OK\r\nServer: BaseHTTP/0.6 Python/3.6.0\r\nDate: Wed, 25 Jan 2017 13:00:00 GMT\r\n\r\n".utf8)

		let expectedHeaders: Http.Headers = [
			"Server": "BaseHTTP/0.6 Python/3.6.0",
			"Date": "Wed, 25 Jan 2017 13:00:00 GMT",
		]

		let response = Http.Response(withRawData: rawResponse)!

		XCTAssertEqual(response.status, .ok)
		XCTAssertEqual(response.headers, expectedHeaders)
		XCTAssertNil(response.body)
	}

	func testConnectResponse() {
		let rawResponse = Data("HTTP/1.0 200 Connection Established\r\nProxy-agent: Apache\r\n\r\n".utf8)

		let response = Http.Response(withRawData: rawResponse)!

		XCTAssertEqual(response.status, .ok)
		XCTAssertEqual(response.headers, ["Proxy-agent": "Apache"])
		XCTAssertNil(response.body)
	}


}
