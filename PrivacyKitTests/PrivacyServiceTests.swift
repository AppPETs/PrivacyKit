//
//  PrivacyServiceTests.swift
//  PrivacyServiceTests
//
//  Created by Maximilian Blochberger on 2016-07-13.
//  Copyright © 2016 Universität Hamburg. All rights reserved.
//

import XCTest
@testable import PrivacyKit

class PrivacyServiceTests: XCTestCase {
    
    
    func testRecordId() {
		XCTAssertEqual(PrivacyService.RecordId.lengthInBytes, 512/8)

		// sha512("deadbeef")
		let sha512_deadbeef = "113a3bc783d851fc0373214b19ea7be9fa3de541ecb9fe026d52c603e8ea19c174cc0e9705f8b90d312212c0c3a6d8453ddfb3e3141409cf4bedc8ef033590b4"

		let potentialRecordId = PrivacyService.RecordId(sha512_deadbeef)
		XCTAssertNotNil(potentialRecordId, "Valid record ID rejected unexpectedly")

		let upperCaseRecordId = PrivacyService.RecordId(sha512_deadbeef.uppercaseString)
		XCTAssertNotNil(upperCaseRecordId, "Valid record ID with upperase hex rejected unexpectedly")

		let emptyRecordId = PrivacyService.RecordId("")
		XCTAssertNil(emptyRecordId, "Empty record ID accepted unexpectedly")

		let shortRecordId = PrivacyService.RecordId("deadbeef")
		XCTAssertNil(shortRecordId, "Short record ID accepted unexpectedly")

		let longRecordId = PrivacyService.RecordId(sha512_deadbeef + "ff")
		XCTAssertNil(longRecordId, "Long record ID accepted unexpectedly")

		let nonHex512BitString = "X13a3bc783d851fc0373214b19ea7be9fa3de541ecb9fe026d52c603e8ea19c174cc0e9705f8b90d312212c0c3a6d8453ddfb3e3141409cf4bedc8ef033590b4"
		let nonHexRecordId = PrivacyService.RecordId(nonHex512BitString)
		XCTAssertNil(nonHexRecordId, "Non-hex record ID accepted unexpectedly")
    }
}
