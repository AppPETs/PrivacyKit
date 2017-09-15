import XCTest

import Tafelsalz

@testable import PrivacyKit

class PrivacyServiceTests: XCTestCase {

	func testRecordId() {
		typealias RecordId = PrivacyService.RecordId

		let validRecordId = Random.bytes(count: RecordId.lengthInBytes).hex

		XCTAssertNotNil(RecordId(validRecordId))
		XCTAssertNotNil(RecordId(validRecordId.uppercased()))

		XCTAssertNil(RecordId(""))
		XCTAssertNil(RecordId(Random.bytes(count: RecordId.lengthInBytes - 1).hex))
		XCTAssertNil(RecordId(Random.bytes(count: RecordId.lengthInBytes + 1).hex))

		XCTAssertNil(RecordId(validRecordId.replacingCharacters(in: validRecordId.startIndex..<validRecordId.endIndex, with: "x")))
	}

}
