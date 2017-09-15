import XCTest

import PrivacyKit

class RegularExpressionTest: XCTestCase {

	func testExampleWithString() {
		let sentence = "The world is flat."
		if sentence =~ "^The" {
			// The sentence starts with "The"
		}
	}

	func testExampleWithRegularExpression() {
		let pattern = RegularExpression("^The")!
		let sentence = "The world is flat."
		if sentence =~ pattern {
			// The sentence starts with "The"
		}
	}

	func testValid() {
		let sentence = "The world is flat."
		XCTAssertTrue((sentence =~ "^The"))
		XCTAssertFalse(sentence =~ "foo")
	}

	func testInvalid() {
		XCTAssertNil(RegularExpression("("))
	}

}
