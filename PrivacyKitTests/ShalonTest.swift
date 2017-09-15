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

}
