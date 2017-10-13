import Tafelsalz

// MARK: - Frontend

protocol KeyValueStorage {
	typealias Key = String
	typealias Value = Data

	func store(value: Value, for key: Key, finished: @escaping (Error?) -> Void)
	func retrieve(for key: Key, finished: @escaping (Value?, Error?) -> Void)
}

// MARK: - Backend

typealias EncryptedValue = SecretBox.AuthenticatedCiphertext

struct EncryptedKey {
	static let SizeInBytes: PInt = 256 / 8

	let value: GenericHash

	init?(_ value: GenericHash) {
		guard value.sizeInBytes == EncryptedKey.SizeInBytes else { return nil }
		self.value = value
	}
}

extension EncryptedKey: Equatable {
	static func ==(lhs: EncryptedKey, rhs: EncryptedKey) -> Bool {
		return lhs.value == rhs.value
	}
}

extension EncryptedKey: Hashable {
	var hashValue: Int { get { return value.hashValue } }
}

extension EncryptedKey: CustomStringConvertible {
	/**
	A textual representation of an encrypted key.
	*/
	var description: String {
		get {
			return value.hex!
		}
	}
}

protocol KeyValueStorageBackend {
	func store(value: EncryptedValue, for key: EncryptedKey, callback: @escaping (Error?) -> Void)
	func retrieve(for key: EncryptedKey, callback: @escaping (EncryptedValue?, Error?) -> Void)
}

protocol KeyValueStorageService {
	var keyValueStorageBackend: KeyValueStorageBackend { get }
}

// MARK: - Encryption

class SecureKeyValueStorage {

	typealias Context = MasterKey.Context

	enum Error: Swift.Error {
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

	convenience init?(with backend: KeyValueStorageBackend, for persona: Persona, context: Context) {
		guard let masterKey = try? persona.masterKey() else { return nil }
		self.init(with: backend, and: masterKey, context: context)
	}

	convenience init?(with service: KeyValueStorageService, for persona: Persona, context: Context) {
		self.init(with: service.keyValueStorageBackend, for: persona, context: context)
	}

	func encrypt(_ key: Key) -> EncryptedKey {
		let hash = GenericHash(bytes: Data(key.utf8), outputSizeInBytes: EncryptedKey.SizeInBytes, with: hashKey)!
		return EncryptedKey(hash)!
	}

	func encrypt(_ value: Value) -> EncryptedValue {
		return secretBox.encrypt(data: value)
	}

	func decrypt(_ encrytedValue: EncryptedValue) throws -> Value {
		guard let value = secretBox.decrypt(data: encrytedValue) else {
			throw Error.failedToDecrypt
		}
		return value
	}
}

extension SecureKeyValueStorage: KeyValueStorage {

	func store(value: Value, for key: Key, finished: @escaping (Swift.Error?) -> Void) {
		backend.store(value: encrypt(value), for: encrypt(key), callback: finished)
	}

	func retrieve(for key: Key, finished: @escaping (Value?, Swift.Error?) -> Void) {
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
}

// MARK: - P-Service API

extension PrivacyService {
	class KeyValueStorage {

		enum Error: Swift.Error {
			case valueDoesNotExist
			case noContent
			case responseTooSmall
		}

		let baseUrl: URL

		init(baseUrl: URL) {
			self.baseUrl = baseUrl
		}

		var entryPoint: URL {
			get {
				return baseUrl
					.appendingPathComponent("storage", isDirectory: true)
					.appendingPathComponent("v1", isDirectory: true)
			}
		}

		func url(for key: EncryptedKey) -> URL {
			return entryPoint.appendingPathComponent(key.description, isDirectory: false)
		}
	}
}

extension PrivacyService.KeyValueStorage: KeyValueStorageBackend {

	func store(value: EncryptedValue, for key: EncryptedKey, callback: @escaping (Swift.Error?) -> Void) {
		let sessionConfiguration = URLSessionConfiguration.default
		let session = URLSession(configuration: sessionConfiguration)
		var request = URLRequest(url: url(for: key))

		request.set(method: .post)
		request.set(contentType: .octetStream)

		Indicators.showNetworkActivity()

		let task = session.uploadTask(with: request, from: value.bytes) {
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
		let sessionConfiguration = URLSessionConfiguration.default
		let session = URLSession(configuration: sessionConfiguration)
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
				callback(nil, Error.valueDoesNotExist)
				return
			}

			guard response.status == .ok else {
				callback(nil, response.unexpected)
				return
			}

			// Successfully downloaded

			guard let data = optionalData else {
				callback(nil, Error.noContent)
				return
			}

			guard let ciphertext = EncryptedValue(bytes: data) else {
				callback(nil, Error.responseTooSmall)
				return
			}

			callback(ciphertext, nil)

		}
		task.resume()
	}
}

extension PrivacyService: KeyValueStorageService {
	var keyValueStorageBackend: KeyValueStorageBackend {
		get {
			return PrivacyService.KeyValueStorage(baseUrl: baseUrl)
		}
	}
}
