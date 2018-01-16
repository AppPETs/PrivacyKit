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

	func metaTestRemove(storage: SecureKeyValueStorage, key: SecureKeyValueStorage.Key) {
		var optionalError: Error? = nil

		let removedExpectation = expectation(description: "removed '\(key)'")

		storage.remove(for: key) {
			receivedError in

			optionalError = receivedError

			removedExpectation.fulfill()
		}

		waitForExpectations(timeout: tenSeconds) {
			optionalExpectationError in

			XCTAssertNil(optionalExpectationError)

			XCTAssertNil(optionalError)
		}
	}

	// MARK: Tests

	func testEncryptedKey() {
		let hash: (UInt32) -> GenericHash = { GenericHash(bytes: Data("foo".utf8), outputSizeInBytes: $0)! }

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
		let value1 = Data("bar".utf8)
		let value2 = Data("baz".utf8)

		// Test retrieving invalid value
		metaTestRetrieve(storage: storage, key: key, expectedError: FakeKeyValueStorageBackend.Error.valueDoesNotExist)

		// Test storing a value
		metaTestStore(storage: storage, key: key, value: value1)
		metaTestRetrieve(storage: storage, key: key, expectedValue: value1)

		// Test overwriting a value
		metaTestStore(storage: storage, key: key, value: value2)
		metaTestRetrieve(storage: storage, key: key, expectedValue: value2)

		// Test removing a value
		metaTestRemove(storage: storage, key: key)
		metaTestRetrieve(storage: storage, key: key, expectedError: FakeKeyValueStorageBackend.Error.valueDoesNotExist)
	}

	func testTodolistVectors() {
		let service = PrivacyService(baseUrl: URL(string: "https://privacyservice.test:8080")!)
		var masterKeyBytes = Data(base64Encoded: "Lw2Qx8q5ub9T3Sw8QkwxH9bIMkdpZUFJo/+kz5FND5g=")!
		let masterKey = MasterKey(bytes: &masterKeyBytes)!
		let context = SecureKeyValueStorage.Context("TODOLIST")!
		let storage = SecureKeyValueStorage(with: service, and: masterKey, context: context)

		let expectedTaskMax = Data(base64Encoded: "AAQ=")!
		let expectedTask0 = Data(base64Encoded: "eyJkZXNjcmlwdGlvbiI6IjAiLCJpc0NvbXBsZXRlZCI6ZmFsc2V9")!
		let expectedTask1 = Data(base64Encoded: "eyJkZXNjcmlwdGlvbiI6IjEiLCJpc0NvbXBsZXRlZCI6ZmFsc2V9")!
		let expectedTask3 = Data(base64Encoded: "eyJkZXNjcmlwdGlvbiI6IjMiLCJpc0NvbXBsZXRlZCI6dHJ1ZX0=")!

		metaTestRetrieve(storage: storage, key: "task_max", expectedValue: expectedTaskMax)
		metaTestRetrieve(storage: storage, key: "task_0", expectedValue: expectedTask0)
		metaTestRetrieve(storage: storage, key: "task_1", expectedValue: expectedTask1)
		metaTestRetrieve(storage: storage, key: "task_3", expectedValue: expectedTask3)

		metaTestRetrieve(storage: storage, key: "task_2", expectedError: SecureKeyValueStorage.Error.valueDoesNotExist)
	}

	func testRemote() {
		let service = PrivacyService(baseUrl: URL(string: "https://privacyservice.test:8080")!)
		let masterKey = MasterKey()
		let context = SecureKeyValueStorage.Context("TESTTEST")!
		let storage = SecureKeyValueStorage(with: service, and: masterKey, context: context)

		let key = "foo"
		let value1 = Data("bar".utf8)
		let value2 = Data("baz".utf8)

		// Test retrieving invalid value
		metaTestRetrieve(storage: storage, key: key, expectedError: SecureKeyValueStorage.Error.valueDoesNotExist)

		// Test storing a value
		metaTestStore(storage: storage, key: key, value: value1)
		metaTestRetrieve(storage: storage, key: key, expectedValue: value1)

		// Test overwriting a value
		metaTestStore(storage: storage, key: key, value: value2)
		metaTestRetrieve(storage: storage, key: key, expectedValue: value2)

		// Test removing a value
		metaTestRemove(storage: storage, key: key)
		metaTestRetrieve(storage: storage, key: key, expectedError: SecureKeyValueStorage.Error.valueDoesNotExist)
	}
	
}
