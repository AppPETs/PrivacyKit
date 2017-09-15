import XCTest
@testable import PrivacyKit

class HttpTests: XCTestCase {

	func testHeadRequest() {
		let request = Http.Request(withMethod: .head, andUrl: URL(string: "https://example.com/")!, andHeaders: ["X-Test": "foobar", "X-Foo": "Bar"])!

		let actual = String(data: request.compose()!, encoding: .utf8)!
		let expected = "HEAD / HTTP/1.1\r\nX-Test: foobar\r\nHost: example.com\r\nX-Foo: Bar\r\n\r\n"

		XCTAssertEqual(actual, expected)
	}

	func testConnectRequest() {
		let request = Http.Request.connect(
			toHost: "example.com",
			withPort: 80,
			viaProxy: URL(string: "https://localhost:8888")!,
			withHeaders: ["X-Test": "foobar", "X-Foo": "Bar"]
		)!

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
		XCTAssertEqual(response.body, Data())
	}

	func testConnectResponse() {
		let rawResponse = Data("HTTP/1.0 200 Connection Established\r\nProxy-agent: Apache\r\n\r\n".utf8)

		let response = Http.Response(withRawData: rawResponse)!

		XCTAssertEqual(response.status, .ok)
		XCTAssertEqual(response.headers, ["Proxy-agent": "Apache"])
		XCTAssertEqual(response.body, Data())
	}


}
