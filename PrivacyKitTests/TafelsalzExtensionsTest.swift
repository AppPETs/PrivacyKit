import XCTest

import Tafelsalz

@testable import PrivacyKit

class TafelsalzExtensionsTest: XCTestCase {

	func testMasterKeyAsQrCode() {
		let masterKey = MasterKey()
		let qr = masterKey.qrCode()!

		XCTAssertEqual(qr.data, masterKey.copyBytes())
	}

}
