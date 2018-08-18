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

		## Example

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

		## Example

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

		## Example

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

		- returns:
			`nil` if the size is incorrect.
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

		- returns:
			`true` if and only if `lhs` equals to `rhs`.
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

	/**
		Store an encrypted value to the key-value storage backend for a given
		key.

		- parameters:
			- value: The encrypted value that should be stored.
			- key: The key that identifies the value.
			- callback: A closure that is called asynchronuously once the
				operation is finished.
			- error: An optional error that might have occurred during storing.
	*/
	func store(value: EncryptedValue, for key: EncryptedKey, callback: @escaping (Error?) -> Void)

	/**
		Retrieve an encrypted value from the key-value backend for a given key.

		- postcondition:
			(`value` = `nil`) ⊻ (`error` = `nil`)

		- parameters:
			- key: The key that identifies the value.
			- callback: A closure that is called asynchronuously once the
				operation is finished.
			- value: The value if no error occurred, `nil` else.
			- error: An optional error that might have occurred during storing.
	*/
	func retrieve(for key: EncryptedKey, callback: @escaping (EncryptedValue?, Error?) -> Void)

	/**
		Remove the encrypted value from the key-value backend for a given key.

		- parameters:
			- key: The key that identifies the value.
			- callback: A closure that is called asynchronuously once the
				operation is finished.
			- error: An optional error that might have occurred during storing.
	*/
	func remove(for key: EncryptedKey, callback: @escaping (Error?) -> Void)

}

// MARK: - Encryption

/**
	This class offers a key-value storage, where the values are encrypted and
	the keys are hashed, with a private hashing function. The key-value storage
	backend cannot link keys or values with others, assuming there are multiple
	users, using the same backend. If a network is used, an anonymous
	communication network should be used in order to avoid linkability through
	traffic data.

	- warning:
		The values are not protected by padding, meaning that the backend
		provider could still guess the content based on its size.

	- warning:
		There is no access protection of the keys. The sole protection is, that
		nobody can get your keys. The values are protected by encryption, so
		confidentiality and integrity are protected, but availability is not.
		The backend provider, who knows which keys are stored in the backend,
		could delete or overwrite them.
*/
public class SecureKeyValueStorage {

	/**
		The context that is used for deriving the cryptographic keys from a
		master key.
	*/
	public typealias Context = MasterKey.Context

	/**
		An error that might occur when storing or retrieving values.
	*/
	public enum Error: Swift.Error {

		/**
			This error indicates that a value does not exists if it is tried to
			retrieved or removed.
		*/
		case valueDoesNotExist

		/**
			This error indicates that there is no value for a given key.
			Meaning that the value exists (in contrast to `valueDoesNotExist`)
			but that the byte array is empty. This should not happen in normal
			circumstances.
		*/
		case noContent

		/**
			This error indicates that the encrypted value is too short. It
			means that there is something of the message authentication code is
			missing, which is used for checking the integrity of the value, or
			something of the nonce is missing. Since the format is erroneous,
			there is no way to decrypt the value. This should not happen in
			normal circumstances.
		*/
		case responseTooSmall

		/**
			This error indicates that the encrypted value has been tampered
			with and the integrity of the message is violated.
		*/
		case failedToDecrypt

	}

	/**
		The index used for deriving the key for private hashing from the master
		key.
	*/
	private static let HashKeyId: UInt64 = 1

	/**
		The index used for deriving the secret key for encrypting values from
		the master key.
	*/
	private static let SecretKeyId: UInt64 = 2

	/**
		The backend used for storing encrypted values.
	*/
	let backend: KeyValueStorageBackend

	/**
		The secret box used for encrypting values.
	*/
	let secretBox: SecretBox

	/**
		The key used for private hashing.
	*/
	let hashKey: GenericHash.Key

	/**
		Initialize a secure key-value storage with a given backend.

		- parameters:
			- backend: The backend used for storing encrypted values.
			- masterKey: The master key used for deriving they keys for
				encrypting values and the key used for private hashing.
			- context: The context used for deriving the keys from the master
				key.
	*/
	init(with backend: KeyValueStorageBackend, and masterKey: MasterKey, context: Context) {
		self.backend = backend
		self.secretBox = SecretBox(secretKey: masterKey.derive(with: SecureKeyValueStorage.SecretKeyId, and: context))
		self.hashKey = masterKey.derive(with: SecureKeyValueStorage.HashKeyId, and: context)!
	}

	/**
		Initialize a secure key-value storage with a given P-Service.

		- parameters:
			- service: The P-Service used for storing encrypted values.
			- masterKey: The master key used for deriving they keys for
				encrypting values and the key used for private hashing.
			- context: The context used for deriving the keys from the master
				key.
	*/
	public convenience init(with service: PrivacyService, and masterKey: MasterKey, context: Context) {
		self.init(with: service.keyValueStorageBackend, and: masterKey, context: context)
	}

	/**
		Initialize a secure key-value storage with a given backend and a given
		persona.

		- parameters:
			- backend: The backend used for storing encrypted values.
			- persona: The persona, whose keys are used.
			- context: The context used for deriving the keys from the master
				key of the persona.

		- returns:
			`nil` if there is an issue creating or retrieving the persona's keys
			from the Keychain.
	*/
	convenience init?(with backend: KeyValueStorageBackend, for persona: Persona, context: Context) {
		guard let masterKey = try? persona.masterKey() else { return nil }
		self.init(with: backend, and: masterKey, context: context)
	}

	/**
		Initialize a secure key-value storage with a given P-Service and a given
		persona.

		- parameters:
			- service: The P-Service used for storing encrypted values.
			- persona: The persona, whose keys are used.
			- context: The context used for deriving the keys from the master
				key of the persona.

		- returns:
			`nil` if there is an issue creating or retrieving the persona's keys
			from the Keychain.
	*/
	public convenience init?(with service: PrivacyService, for persona: Persona, context: Context) {
		self.init(with: service.keyValueStorageBackend, for: persona, context: context)
	}

	/**
		Perform private hashing on a key (as in key-value).

		- parameters:
			- key: The key (as in key-value).

		- returns:
			A private hash.
	*/
	func encrypt(_ key: Key) -> EncryptedKey {
		let hash = GenericHash(bytes: key.utf8Bytes, outputSizeInBytes: EncryptedKey.SizeInBytes, with: hashKey)!
		return EncryptedKey(hash)!
	}

	/**
		Encrypt a value.

		- parameters:
			- value: The plaintext value.

		- returns:
			The encrypte value.
	*/
	func encrypt(_ value: Value) -> EncryptedValue {
		return secretBox.encrypt(plaintext: value)
	}

	/**
		Decrypt a value.

		- parameters:
			- encryptedValue: The encrypted value.

		- returns:
			The plaintext value.

		- throws:
			`failedToDecrypt` if the value could not be decrypted.
	*/
	func decrypt(_ encrytedValue: EncryptedValue) throws -> Value {
		guard let value = secretBox.decrypt(ciphertext: encrytedValue) else {
			throw Error.failedToDecrypt
		}
		return value
	}

}

extension SecureKeyValueStorage: KeyValueStorage {

	/**
		Store a value in the key-value storage for a given key. The value will
		be encrypted. Both the original key and the plaintext value cannot be
		accessed by the backend.

		## Example

		```swift
		storage.store(key: "My PIN", value: Data("1234".utf8)) {
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
	public func store(value: Value, for key: Key, finished: @escaping (Swift.Error?) -> Void) {
		backend.store(value: encrypt(value), for: encrypt(key), callback: finished)
	}

	/**
		Retrieve a value from the key-value storage for a given key. The value,
		which is stored encrypted at the backend, will be automatically
		decrypted.

		## Example

		```swift
		storage.retrieve(for: "My PIN") {
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

	/**
		Remove the value from the key-value storage for a given key.

		## Example

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
	public func remove(for key: KeyValueStorage.Key, finished: @escaping (Swift.Error?) -> Void) {
		backend.remove(for: encrypt(key), callback: finished)
	}

}

// MARK: - P-Service API

extension PrivacyService {

	/**
		Key-value storage backend of the P-Service.
	*/
	var keyValueStorageBackend: KeyValueStorageBackend {
		return PrivacyService.KeyValueStorage(baseUrl: baseUrl)
	}

	/**
		This class handles the URL construction of the key-value storage API of
		the P-Service.
	*/
	class KeyValueStorage {

		/**
			The base URL of the P-Service.
		*/
		let baseUrl: URL

		/**
			Initialize the key-value storage backend.

			- parameters:
				- baseUrl: The base URL of the P-Service.
		*/
		init(baseUrl: URL) {
			self.baseUrl = baseUrl
		}

		/**
			The entry point of the key-value storage API.
		*/
		var entryPoint: URL {
			return baseUrl
				.appendingPathComponent("storage", isDirectory: true)
				.appendingPathComponent("v1", isDirectory: true)
		}

		/**
			Get the URL for a resource for a given key.

			- parameters:
				- key: The key that identifies the resource.

			- returns:
				The URL of the resource.
		*/
		func url(for key: EncryptedKey) -> URL {
			return entryPoint.appendingPathComponent(key.description, isDirectory: false)
		}

	}

}

extension PrivacyService.KeyValueStorage: KeyValueStorageBackend {

	/**
		The default URL session configuration, which is used in order to connect
		to the the key-value storage backend. This adds support for the Shalon
		URL protocol.
	*/
	func defaultSessionConfiguration() -> URLSessionConfiguration {
		let configuration = URLSessionConfiguration.ephemeral
		configuration.protocolClasses?.append(ShalonURLProtocol.self)
		return configuration
	}

	// MARK: KeyValueStorageBackend

	/**
		Store an encrypted value to the key-value storage backend for a given
		key.

		- parameters:
			- value: The encrypted value that should be stored.
			- key: The key that identifies the value.
			- callback: A closure that is called asynchronuously once the
				operation is finished.
			- error: An optional error that might have occurred during storing.
	*/
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

	/**
		Retrieve an encrypted value from the key-value backend for a given key.

		- postcondition:
			(`value` = `nil`) ⊻ (`error` = `nil`)

		- parameters:
			- key: The key that identifies the value.
			- callback: A closure that is called asynchronuously once the
				operation is finished.
			- value: The value if no error occurred, `nil` else.
			- error: An optional error that might have occurred during storing.
	*/
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

	/**
		Remove the encrypted value from the key-value backend for a given key.

		- parameters:
			- key: The key that identifies the value.
			- callback: A closure that is called asynchronuously once the
				operation is finished.
			- error: An optional error that might have occurred during storing.
	*/
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
