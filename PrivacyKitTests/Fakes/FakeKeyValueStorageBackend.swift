@testable import PrivacyKit

class FakeKeyValueStorageBackend {

	enum Error: Swift.Error {
		case valueDoesNotExist
	}

	var storage: [EncryptedKey: EncryptedValue] = [:]

	init() {}
}

extension FakeKeyValueStorageBackend: KeyValueStorageBackend {

	func store(value: EncryptedValue, for key: EncryptedKey, callback: @escaping (Swift.Error?) -> Void) {
		storage[key] = value
		callback(nil)
	}

	func retrieve(for key: EncryptedKey, callback: @escaping (EncryptedValue?, Swift.Error?) -> Void) {
		guard storage.keys.contains(key) else {
			callback(nil, Error.valueDoesNotExist)
			return
		}
		callback(storage[key], nil)
	}

	func remove(for key: EncryptedKey, callback: @escaping (Swift.Error?) -> Void) {
		storage.removeValue(forKey: key)
		callback(nil)
	}

}
