import XCTest

import Tafelsalz

@testable import PrivacyKit

class TafelsalzExtensionsTest: XCTestCase {

	func testMasterKeyAsQrCode() {
		let masterKey = MasterKey()
		let qr = masterKey.qrCode()

		// <#FIXME#> Remove Android workaround (Todo-iOS/#2)
		XCTAssertEqual(String(bytes: qr.data, encoding: .utf8)!, MASTER_KEY_PREFIX + masterKey.base64EncodedString())
	}

	func testMasterKeyFromBase64Encoded() {
		let masterKey1 = MasterKey()
		let masterKey2 = MasterKey(base64Encoded: masterKey1.base64EncodedString())!

		XCTAssertEqual(masterKey2.copyBytes(), masterKey1.copyBytes())
		XCTAssertEqual(masterKey2.base64EncodedString(), masterKey1.base64EncodedString())

		let invalidLength = String(masterKey1.base64EncodedString()[String.Index(encodedOffset: 1)...])
		XCTAssertNil(MasterKey(base64Encoded: invalidLength))

		let invalidCharacter = ":" + masterKey1.base64EncodedString().dropFirst()
		XCTAssertNil(MasterKey(base64Encoded: invalidCharacter))
	}

}
