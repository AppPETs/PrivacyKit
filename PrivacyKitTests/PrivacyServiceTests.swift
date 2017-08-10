import XCTest
@testable import PrivacyKit

class PrivacyServiceTests: XCTestCase {

	func testRecordId() {
		XCTAssertEqual(PrivacyService.RecordId.lengthInBytes, 256/8)

		let validRecordId = "fcb6471961829d28270462a2d5cba7fd141d80c608d6df074f8e2e213c187471"

		let potentialRecordId = PrivacyService.RecordId(validRecordId)
		XCTAssertNotNil(potentialRecordId, "Valid record ID rejected unexpectedly")

		let upperCaseRecordId = PrivacyService.RecordId(validRecordId.uppercased())
		XCTAssertNotNil(upperCaseRecordId, "Valid record ID with upperase hex rejected unexpectedly")

		let emptyRecordId = PrivacyService.RecordId("")
		XCTAssertNil(emptyRecordId, "Empty record ID accepted unexpectedly")

		let shortRecordId = PrivacyService.RecordId("deadbeef")
		XCTAssertNil(shortRecordId, "Short record ID accepted unexpectedly")

		let longRecordId = PrivacyService.RecordId(validRecordId + "ff")
		XCTAssertNil(longRecordId, "Long record ID accepted unexpectedly")

		let nonHex512BitString = "xcb6471961829d28270462a2d5cba7fd141d80c608d6df074f8e2e213c187471"
		let nonHexRecordId = PrivacyService.RecordId(nonHex512BitString)
		XCTAssertNil(nonHexRecordId, "Non-hex record ID accepted unexpectedly")
	}

}
