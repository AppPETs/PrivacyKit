import XCTest
@testable import PrivacyKit

class ShalonTest: XCTestCase {

    func testExample() {
        let url = URL(string: "https://example.com/")!
        let target = Target(withHostname: url.host!, andPort: 443)!
        let shalon = Shalon(withTarget: target)

        var optionalResponse: Response? = nil
        var optionalError: Error? = nil

        shalon.addLayer(Target(withHostname: "shalon1.jondonym.net", andPort: 443)!)

        let responseReceivedExpectation = expectation(description: "responseReceived")

        shalon.issue(request: Request(withMethod: .head, andUrl: url)!) {
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

    func testShalonProtocol() {
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
}
