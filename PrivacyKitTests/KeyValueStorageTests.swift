import XCTest

import Tafelsalz

@testable import PrivacyKit

let tenSeconds: TimeInterval = 10

class KeyValueStorageTests: XCTestCase {

	func testEncryptedKey() {
		let hash: (PInt) -> GenericHash = { GenericHash(bytes: Data("foo".utf8), outputSizeInBytes: $0)! }

		XCTAssertNotNil(EncryptedKey(hash(EncryptedKey.SizeInBytes)))
		XCTAssertNil(EncryptedKey(hash(EncryptedKey.SizeInBytes - 1)))
		XCTAssertNil(EncryptedKey(hash(EncryptedKey.SizeInBytes + 1)))
	}

	func testSecureKeyValueStorage() {
		let backend = FakeKeyValueStorageBackend()
		let masterKey = MasterKey()
		let context = SecureKeyValueStorage.Context("TESTTEST")!
		let storage = SecureKeyValueStorage(with: backend, and: masterKey, context: context)

		let storeExpectation = expectation(description: "valueStored")

		let key = "foo"
		let value = Data("bar".utf8)

		var optionalError: Error? = nil

		storage.store(value: value, for: key) {
			receivedError in

			optionalError = receivedError

			storeExpectation.fulfill()
		}

		waitForExpectations(timeout: tenSeconds) {
			optionalExpectationError in

			XCTAssertNil(optionalExpectationError)

			XCTAssertNil(optionalError)
		}

		let retrieveExpectation = expectation(description: "retrievedValue")

		optionalError = nil
		var optionalValue: Data? = nil

		storage.retrieve(for: key) {
			(receivedValue, receivedError) in

			optionalValue = receivedValue
			optionalError = receivedError

			retrieveExpectation.fulfill()
		}

		waitForExpectations(timeout: tenSeconds) {
			optionalExpectationError in

			XCTAssertNil(optionalExpectationError)

			XCTAssertNil(optionalError)
			XCTAssertNotNil(optionalValue)

			XCTAssertEqual(optionalValue!, Data("bar".utf8))
		}
	}
	
}
