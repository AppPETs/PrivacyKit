import XCTest

import Tafelsalz

@testable import PrivacyKit

let tenSeconds: TimeInterval = 10

class KeyValueStorageTests: XCTestCase {

	// MARK: Meta tests

	func metaTestStore(storage: SecureKeyValueStorage, key: SecureKeyValueStorage.Key, value: SecureKeyValueStorage.Value) {
		var optionalError: Error? = nil

		let storeExpectation = expectation(description: "stored '\(key)'")

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
	}

	func metaTestRetrieve(storage: SecureKeyValueStorage, key: SecureKeyValueStorage.Key, expectedValue: SecureKeyValueStorage.Value) {
		var optionalError: Error? = nil
		var optionalValue: Data? = nil

		let retrieveExpectation = expectation(description: "retrieved '\(key)'")

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

			XCTAssertEqual(optionalValue!, expectedValue)
		}
	}

	func metaTestRetrieve<ErrorType: Error & Equatable>(storage: SecureKeyValueStorage, key: SecureKeyValueStorage.Key, expectedError: ErrorType) {
		var optionalError: Error? = nil
		var optionalValue: Data? = nil

		let retrieveExpectation = expectation(description: "retrieved '\(key)'")

		storage.retrieve(for: key) {
			(receivedValue, receivedError) in

			optionalValue = receivedValue
			optionalError = receivedError

			retrieveExpectation.fulfill()
		}

		waitForExpectations(timeout: tenSeconds) {
			optionalExpectationError in

			XCTAssertNil(optionalExpectationError)

			XCTAssertNotNil(optionalError)
			XCTAssertNil(optionalValue)

			XCTAssertEqual(optionalError! as! ErrorType, expectedError)
		}
	}

	// MARK: Tests

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

		let key = "foo"
		let value = Data("bar".utf8)

		metaTestRetrieve(storage: storage, key: key, expectedError: FakeKeyValueStorageBackend.Error.valueDoesNotExist)
		metaTestStore(storage: storage, key: key, value: value)
		metaTestRetrieve(storage: storage, key: key, expectedValue: value)
	}
	
}
