import Tafelsalz

// MARK: - Frontend

/**
	This protocol describes the interface of a key value storage, where the keys
	are `String`s and the values are `Data` objects.
*/
public protocol KeyValueStorage {

	/**
		A key is the identifier for a specific value stored in the key-value
		storage. The key is unique.
	*/
	typealias Key = String

	/**
		A value can contain arbitrary data and is identified by a key.
	*/
	typealias Value = Bytes

	/**
		Store a value in the key-value storage for a given key.

		#### Example

		```swift
		storage.store(key: "name", value: Data("John Doe".utf8)) {
		    optionalError in

		    if let error = optionalError {
		        // TODO Handle error
		    }
		}
		```

		- parameters:
			- value: The value that should be stored.
			- key: The key that identifies the value.
			- finished: A closure that is called asynchronuously once the
				operation is finished.
			- error: An optional error that might have occurred during storing.
	*/
	func store(value: Value, for key: Key, finished: @escaping (_ error: Error?) -> Void)

	/**
		Retrieve a value from the key-value storage for a given key.

		#### Example

		```swift
		storage.retrieve(for: "name") {
		    optionalValue, optionalError in

		    precondition((optionalValue != nil) == (optionalError != nil))

		    guard let value = optionalValue else {
		        let error = optionalError!
		        // TODO Handle error
		        return
		    }

		    // Success, do something with `value`
		}
		```

		- postcondition:
			(`value` = `nil`) ⊻ (`error` = `nil`)

		- parameters:
			- key: The key that identifies the value.
			- finished: A closure that is called asynchronuously once the
				operation is finished.
			- value: The value if no error occurred, `nil` else.
			- error: An optional error that might have occurred during storing.
	*/
	func retrieve(for key: Key, finished: @escaping (_ value: Value?, _ error: Error?) -> Void)

	/**
		Remove the value from the key-value storage for a given key.

		#### Example

		```swift
		storage.remove(key: "name") {
		    optionalError in

		    if let error = optionalError {
		        // TODO Handle error
		    }
		}
		```

		- parameters:
			- key: The key that identifies the value.
			- finished: A closure that is called asynchronuously once the
				operation is finished.
			- error: An optional error that might have occurred during storing.
	*/
	func remove(for key: Key, finished: @escaping (_ error: Error?) -> Void)

}

// MARK: - Backend

/**
	Encrypted values that are stored in a storage backend.
*/
typealias EncryptedValue = SecretBox.AuthenticatedCiphertext

// <#TODO#> Rename, because it is not really "encrypted"
/**
	Encrypted keys that are used to identify values in a storage backend.
*/
struct EncryptedKey {

	/**
		The size of the key in bytes.
	*/
	public static let SizeInBytes: UInt32 = 256 / 8

	/**
		The personalized hash of the plaintext key.
	*/
	let value: GenericHash

	/**
		Initialize an encrypted key.

		- parameters:
			- value: The personalized has of the plaintext key.
	*/
	init?(_ value: GenericHash) {
		guard value.sizeInBytes == EncryptedKey.SizeInBytes else { return nil }
		self.value = value
	}
}

extension EncryptedKey: Equatable {

	/**
		Compare two encrypted keys. Keys need to be comparable in order to do
		lookups.

		- parameters:
			- lhs: An encrypted key.
			- rhs: Another encrypted key.
	*/
	public static func ==(lhs: EncryptedKey, rhs: EncryptedKey) -> Bool {
		return lhs.value == rhs.value
	}

}

extension EncryptedKey: Hashable {

	/**
		The hash value, for being able to use encrypted keys in dictionaries or
		sets. This should not be confused with the personalized hash of the
		plaintext key.
	*/
	public var hashValue: Int { return value.hashValue }

}

extension EncryptedKey: CustomStringConvertible {

	/**
		A textual representation of an encrypted key.
	*/
	public var description: String {
		return value.hexlify
	}

}

/**
	A protocol defining a key-value storage backend. It basically is similar to
	the `KeyValueStorage` protocol but with encryped keys and encrypted values.

	You can use this to implement a custom protocol for storing a secure
	key-value storage.
*/
protocol KeyValueStorageBackend {
	func store(value: EncryptedValue, for key: EncryptedKey, callback: @escaping (Error?) -> Void)
	func retrieve(for key: EncryptedKey, callback: @escaping (EncryptedValue?, Error?) -> Void)
	func remove(for key: EncryptedKey, callback: @escaping (Error?) -> Void)
}

// MARK: - Encryption

public class SecureKeyValueStorage {

	public typealias Context = MasterKey.Context

	public enum Error: Swift.Error {
		case valueDoesNotExist
		case noContent
		case responseTooSmall
		case failedToDecrypt
	}

	private static let HashKeyId: UInt64 = 1
	private static let SecretKeyId: UInt64 = 2

	let backend: KeyValueStorageBackend
	let secretBox: SecretBox
	let hashKey: GenericHash.Key

	init(with backend: KeyValueStorageBackend, and masterKey: MasterKey, context: Context) {
		self.backend = backend
		self.secretBox = SecretBox(secretKey: masterKey.derive(with: SecureKeyValueStorage.SecretKeyId, and: context))
		self.hashKey = masterKey.derive(with: SecureKeyValueStorage.HashKeyId, and: context)!
	}

	public convenience init(with service: PrivacyService, and masterKey: MasterKey, context: Context) {
		self.init(with: service.keyValueStorageBackend, and: masterKey, context: context)
	}

	convenience init?(with backend: KeyValueStorageBackend, for persona: Persona, context: Context) {
		guard let masterKey = try? persona.masterKey() else { return nil }
		self.init(with: backend, and: masterKey, context: context)
	}

	public convenience init?(with service: PrivacyService, for persona: Persona, context: Context) {
		self.init(with: service.keyValueStorageBackend, for: persona, context: context)
	}

	func encrypt(_ key: Key) -> EncryptedKey {
		let hash = GenericHash(bytes: key.utf8Bytes, outputSizeInBytes: EncryptedKey.SizeInBytes, with: hashKey)!
		return EncryptedKey(hash)!
	}

	func encrypt(_ value: Value) -> EncryptedValue {
		return secretBox.encrypt(plaintext: value)
	}

	func decrypt(_ encrytedValue: EncryptedValue) throws -> Value {
		guard let value = secretBox.decrypt(ciphertext: encrytedValue) else {
			throw Error.failedToDecrypt
		}
		return value
	}
}

extension SecureKeyValueStorage: KeyValueStorage {

	public func store(value: Value, for key: Key, finished: @escaping (Swift.Error?) -> Void) {
		backend.store(value: encrypt(value), for: encrypt(key), callback: finished)
	}

	public func retrieve(for key: Key, finished: @escaping (Value?, Swift.Error?) -> Void) {
		let preparedKey = encrypt(key)
		backend.retrieve(for: preparedKey) {
			(optionalValue, optionalError) in

			assert((optionalValue == nil) != (optionalError == nil))

			guard let value = optionalValue else {
				finished(nil, optionalError)
				return
			}

			do {
				finished(try self.decrypt(value), nil)
			} catch {
				finished(nil, error)
			}
		}
	}

	public func remove(for key: KeyValueStorage.Key, finished: @escaping (Swift.Error?) -> Void) {
		backend.remove(for: encrypt(key), callback: finished)
	}

}

// MARK: - P-Service API

extension PrivacyService {

	var keyValueStorageBackend: KeyValueStorageBackend {
		return PrivacyService.KeyValueStorage(baseUrl: baseUrl)
	}

	class KeyValueStorage {

		let baseUrl: URL

		init(baseUrl: URL) {
			self.baseUrl = baseUrl
		}

		var entryPoint: URL {
			return baseUrl
				.appendingPathComponent("storage", isDirectory: true)
				.appendingPathComponent("v1", isDirectory: true)
		}

		func url(for key: EncryptedKey) -> URL {
			return entryPoint.appendingPathComponent(key.description, isDirectory: false)
		}
	}
}

extension PrivacyService.KeyValueStorage: KeyValueStorageBackend {

	func defaultSessionConfiguration() -> URLSessionConfiguration {
		let configuration = URLSessionConfiguration.ephemeral
		configuration.protocolClasses?.append(ShalonURLProtocol.self)
		return configuration
	}

	func store(value: EncryptedValue, for key: EncryptedKey, callback: @escaping (Swift.Error?) -> Void) {
		let session = URLSession(configuration: defaultSessionConfiguration())
		var request = URLRequest(url: url(for: key))

		request.set(method: .post)
		request.set(contentType: .octetStream)

		Indicators.showNetworkActivity()

		let task = session.uploadTask(with: request, from: Data(value.bytes)) {
			optionalData, optionalResponse, optionalError in

			Indicators.hideNetworkActivity()

			guard optionalError == nil else {
				callback(optionalError)
				return
			}

			guard let response = optionalResponse as? HTTPURLResponse else {
				callback(Http.Error.invalidResponse)
				return
			}

			guard response.status == .ok else {
				callback(response.unexpected)
				return
			}

			// Successfully uploaded
			callback(nil)
		}
		task.resume()
	}

	func retrieve(for key: EncryptedKey, callback: @escaping (EncryptedValue?, Swift.Error?) -> Void) {
		let session = URLSession(configuration: defaultSessionConfiguration())
		var request = URLRequest(url: url(for: key))

		request.set(method: .get)

		Indicators.showNetworkActivity()

		let task = session.dataTask(with: request) {
			optionalData, optionalResponse, optionalError in

			Indicators.hideNetworkActivity()

			guard optionalError == nil else {
				callback(nil, optionalError)
				return
			}

			guard let response = optionalResponse as? HTTPURLResponse else {
				callback(nil, Http.Error.invalidResponse)
				return
			}

			guard response.status != .notFound else {
				callback(nil, SecureKeyValueStorage.Error.valueDoesNotExist)
				return
			}

			guard response.status == .ok else {
				callback(nil, response.unexpected)
				return
			}

			// Successfully downloaded

			guard let data = optionalData else {
				callback(nil, SecureKeyValueStorage.Error.noContent)
				return
			}

			guard let ciphertext = EncryptedValue(bytes: Bytes(data)) else {
				callback(nil, SecureKeyValueStorage.Error.responseTooSmall)
				return
			}

			callback(ciphertext, nil)

		}
		task.resume()
	}

	func remove(for key: EncryptedKey, callback: @escaping (Swift.Error?) -> Void) {
		let session = URLSession(configuration: defaultSessionConfiguration())
		var request = URLRequest(url: url(for: key))

		request.set(method: .delete)

		Indicators.showNetworkActivity()

		let task = session.dataTask(with: request) {
			optionalData, optionalResponse, optionalError in

			Indicators.hideNetworkActivity()

			guard optionalError == nil else {
				callback(optionalError)
				return
			}

			guard let response = optionalResponse as? HTTPURLResponse else {
				callback(Http.Error.invalidResponse)
				return
			}

			guard response.status == .ok else {
				callback(response.unexpected)
				return
			}

			// Successfully removed
			callback(nil)
		}
		task.resume()
	}

}
