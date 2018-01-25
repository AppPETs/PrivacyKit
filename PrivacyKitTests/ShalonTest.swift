import XCTest
@testable import PrivacyKit

class ShalonTest: XCTestCase {

	func testExample() {
		let url = URL(string: "https://example.com/")!
		let target = Target(withHostname: url.host!, andPort: 443)!
		let shalon = Shalon(withTarget: target)

		var optionalResponse: Http.Response? = nil
		var optionalError: Error? = nil

		shalon.addLayer(Target(withHostname: "shalon1.jondonym.net", andPort: 443)!)

		let responseReceivedExpectation = expectation(description: "responseReceived")

		shalon.issue(request: Http.Request(withMethod: .head, andUrl: url)!) {
			receivedOptionalResponse, receivedOptionalError in

			optionalResponse = receivedOptionalResponse
			optionalError = receivedOptionalError

			responseReceivedExpectation.fulfill()
		}

		waitForExpectations(timeout: 10/*seconds*/) {
			optionalExpectationError in

			XCTAssertNil(optionalExpectationError, "Expectation handled erroneously")

			XCTAssertNotNil(optionalResponse)
			XCTAssertNil(optionalError)
		}
	}

	func testShalonURLProtocolParameterExtraction() {
		// Parsing of a normal URL should result in no parameter extraction
		XCTAssertNil(try! ShalonURLProtocol.parseShalonParams(from: URL(string: "https://www.google.com")!))
		XCTAssertNil(try! ShalonURLProtocol.parseShalonParams(from: URL(string: "http://www.example.com")!))

		// Testing incorrectly specified proxies
		XCTAssertThrowsError(try ShalonURLProtocol.parseShalonParams(from: URL(string: "httpss://shalon1.jondonym.de/www.google.com")!))
		XCTAssertThrowsError(try ShalonURLProtocol.parseShalonParams(from: URL(string: "httpsss://shalon1.jondonym.de:8080/shalon2.jondonym.de:/www.google.com")!))

		// Testing too few specified proxies
		XCTAssertThrowsError(try ShalonURLProtocol.parseShalonParams(from: URL(string: "httpss://www.google.com")!))
		XCTAssertThrowsError(try ShalonURLProtocol.parseShalonParams(from: URL(string: "httpsss://shalon1.jondonym.de:80/www.google.com")!))

		// Testing correct examples
		// One proxy only
		let shalonParameters = try! ShalonURLProtocol.parseShalonParams(from: URL(string: "httpss://shalon1.jondonym.de:443/www.google.com")!)
		XCTAssertNotNil(shalonParameters)
		XCTAssertEqual(shalonParameters!.proxies.count, 1)
		XCTAssertEqual(shalonParameters!.proxies[0], Target(withHostname: "shalon1.jondonym.de", andPort: 443))
		XCTAssertEqual(shalonParameters!.requestUrl, URL(string: "https://www.google.com")!)

		// Two proxies
		let shalonParameters1 = try! ShalonURLProtocol.parseShalonParams(from: URL(string: "httpsss://shalon1.jondonym.de:443/test.g.de:778/www.google.com")!)
		XCTAssertNotNil(shalonParameters1)
		XCTAssertEqual(shalonParameters1!.proxies.count, 2)
		XCTAssertEqual(shalonParameters1!.proxies[0], Target(withHostname: "shalon1.jondonym.de", andPort: 443))
		XCTAssertEqual(shalonParameters1!.proxies[1], Target(withHostname: "test.g.de", andPort: 778))
		XCTAssertEqual(shalonParameters1!.requestUrl, URL(string: "https://www.google.com")!)

		// One proxy and real target with port
		let shalonParameters2 = try! ShalonURLProtocol.parseShalonParams(from: URL(string: "httpss://shalon1.jondonym.net:443/apppets.aot.tu-berlin.de:2235")!)
		XCTAssertNotNil(shalonParameters2)
		XCTAssertEqual(shalonParameters2!.proxies.count, 1)
		XCTAssertEqual(shalonParameters2!.proxies[0], Target(withHostname: "shalon1.jondonym.net", andPort: 443))
		XCTAssertEqual(shalonParameters2!.requestUrl, URL(string: "https://apppets.aot.tu-berlin.de:2235")!)

		// Testing IPv6
		let ipv6Params = try! ShalonURLProtocol.parseShalonParams(from: URL(string: "httpss://[2001:db8:85a3::8a2e:370:7334]:443/www.google.com")!)
		XCTAssertNotNil(ipv6Params)
		XCTAssertEqual(ipv6Params!.proxies.count, 1)
		XCTAssertEqual(ipv6Params!.proxies[0], Target(withHostname: "[2001:db8:85a3::8a2e:370:7334]", andPort: 443))
		XCTAssertEqual(ipv6Params!.requestUrl, URL(string: "https://www.google.com")!)

		// Testing incorrectly specified IPv6 address
		XCTAssertThrowsError(try ShalonURLProtocol.parseShalonParams(from: URL(string: "httpss://2001:db8:85a3::8a2e:370:7334:443/www.google.com")!))
	}

	func testShalonProtocol1() {
		URLProtocol.registerClass(ShalonURLProtocol.self)

		// Shalon Test
		let shalonReceivedExpectation = expectation(description: "shalonResponseReceived")

		var shalonResponse: URLResponse? = nil

		let sharedSession = URLSession.shared
		let shalonTask = sharedSession.downloadTask(with: URL(string: "httpss://shalon1.jondonym.net:443/example.com/")!) {
			(potentialUrl, potentialResponse, potentialError) in

			shalonResponse = potentialResponse
			shalonReceivedExpectation.fulfill()
		}
		shalonTask.resume()

		waitForExpectations(timeout: 10/*seconds*/) {
			optionalExpectationError in

			XCTAssertNil(optionalExpectationError, "Expectation handled erroneously")
			XCTAssertNotNil(shalonResponse)
		}
	}

	func testShalonProtocol2() {
		let url = URL(string: "httpss://shalon1.jondonym.net:443/example.com/")!
		let sessionConfiguration = URLSessionConfiguration.ephemeral
		sessionConfiguration.protocolClasses?.append(ShalonURLProtocol.self)
		let session = URLSession(configuration: sessionConfiguration)
		var request = URLRequest(url: url)
		request.set(method: .head)

		let responseExpectation = expectation(description: "responseExpectation")

		var response: URLResponse? = nil

		let task = session.dataTask(with: request) {
			(potentialUrl, potentialResponse, potentialError) in

			response = potentialResponse
			responseExpectation.fulfill()
		}
		task.resume()

		waitForExpectations(timeout: 10/*seconds*/) {
			optionalExpectationError in

			XCTAssertNil(optionalExpectationError, "Expectation handled erroneously")
			XCTAssertNotNil(response)
		}
	}
}
