//
//  SecurityManager.swift
//  PrivacyKit
//
//  Created by Maximilian Blochberger on 2016-07-13.
//  Copyright © 2016 Universität Hamburg. All rights reserved.
//

import Foundation

import Sodium

/**
	Internal class that leverages the `Sodium` library and offers cryptographic
	primitives used throughout the `PrivacyKit`.
	The class takes care of managing the cryptographic keys as well, including
	generating and persisting them.

	- requires:
	  `Foundation`, [`Sodium`](https://github.com/jedisct1/swift-sodium)
*/
class SecurityManager {

	// MARK: Type aliases

	/**
		Internal wrapper for encrypted data objects, which can be passed to
		external sources.
	
		The plain purpose of this class is to ensure that the compiler complies
		if plaintext is used in contexts where it is required to have the data
		encrypted. A plain `typealias EncryptedData = NSData` would not allow
		such control.
	
		- warning:
			Encryption is not enforced, so if you create an instance of this and
			just pass plaintext to the initializer, then private data might
			still leak. The main idea is to avoid mistakes, not to prevent
			acting maliciously. So please think twice when actually
			instantiating this.
		
			The class does not enforce the encryption used. Maybe this can still
			be improved.
	*/
	struct EncryptedData {
		/// The encrypted data blob.
		let blob: Data
	}

	// MARK: Class constants

	/// Singleton instance of the `SecurityManager`.
	static let instance = SecurityManager()

	// MARK: Methods

	/**
		Generates a deterministic secure hash of a given `key`. This means that
		if the given key is equal, the result will be equal as well.

		The hashing function used is the generic hashing function provided by
		the [`Sodium`](https://github.com/jedisct1/swift-sodium) framework. It
		is implemented by the **Blake2b** algorithm.

		- parameter ofKey:
			The key that should be hashed.

		- parameter outputLengthInBytes:
			The length of the generated hash in bytes.

		- returns:
			The hash as a hexadecimal string representation.
	*/
	func hash(ofKey key: Data, withOutputLengthInBytes outputLengthInBytes: Int) -> String? {
		guard let hashedKeyAsData = sodium.genericHash.hash(message: key, key: self.hashKey, outputLength: outputLengthInBytes) else {
			print("Failed to hash key \(key)")
			return nil
		}

		let hashedKey = sodium.utils.bin2hex(hashedKeyAsData)
		return hashedKey
	}

	/**
		Encrypts and secures integrity of given `data` indeterministically.

		The encryption function used is the symmetric encryption function
		provided by the [`Sodium`](https://github.com/jedisct1/swift-sodium)
		framework. Encryption is performed using the XSalsa20 algorithm and
		integrity protection is done by calculating a MAC with the Poly1305
		algorithm. Nonces are used, to avoid that equal plaintext leads to equal
		ciphertext.

		- see:
			`decrypt(ciphertext:)`

		- parameter plaintext:
			The data that should be encrypted.

		- returns:
			An encrypted data object or `nil` if the encryption failed.
	*/
	func encrypt(plaintext: Data) -> EncryptedData? {
		let optionalCiphertext: Data? = sodium.secretBox.seal(message: plaintext, secretKey: self.encryptionKey)
		guard let ciphertext = optionalCiphertext else {
			return nil
		}
		return EncryptedData(blob: ciphertext)
	}

	/**
		Decrypts data and validates integrity.

		- see:
			`encrypt(plaintext:)`

		- parameter ciphertext:
			The encrypted data that should be decrypted.

		- returns:
			The decrypted data or `nil` if the decryption or integrity
			validation failed.
	*/
	func decrypt(ciphertext: EncryptedData) -> Data? {
		let plaintext = sodium.secretBox.open(nonceAndAuthenticatedCipherText: ciphertext.blob, secretKey: self.encryptionKey)
		return plaintext
	}

	// MARK: - Private

	// MARK: Constants

	/// The name of file, which is used to persist the encryption key.
	private static let EncryptionKeyFileName  = "encryption.key"

	/**
		The name of the file, which is used to persist the hash key, which in
		turn is used for hashing asset keys.
	*/
	private static let HashKeyFileName = "hash.key"

	/// The directory for storing documents
	private static let DocumentsDirectory = FileManager().urls(for: .documentDirectory, in: .userDomainMask).first!

	/// The location of the file, which is used to persist the encryption key.
	private static let EncryptionKeyLocation = DocumentsDirectory.appendingPathComponent(EncryptionKeyFileName, isDirectory: false)

	/**
		The location of the file, which is used to persist the hash key,
		which in turn is used for hashing asset keys.
	*/
	private static let HashKeyLocation = DocumentsDirectory.appendingPathComponent(HashKeyFileName, isDirectory: false)

	/**
		An instance of [`Sodium`](https://github.com/jedisct1/swift-sodium),
		which provides encryption and hashing functions.
	*/
	private let sodium: Sodium

	/// The encryption key.
	private let encryptionKey: Box.SecretKey

	/// The hash key, which is used for hashing asset keys.
	private let hashKey: Data

	// MARK: Initializers

	/**
		Initializes a `SecurityManager` instance. Upon first start this will
		generate the required encryption key and the hash key used for
		hashing asset keys and persist them on disk. If they were already
		persisted they will be loaded instead.

		- returns:
			`nil` if [`Sodium`](https://github.com/jedisct1/swift-sodium) could
			not be initialized, if the keys could not be generated, or if they
			could not be read if they were persisted.

		- todo:
			Store encryption and hash keys in Keychain.

		- todo:
			Password protect encryption key.
	*/
	private init?() {

		// Init Sodium
		guard let sodium = Sodium() else {
			print("Failed to initialize sodium")
			return nil
		}
		self.sodium = sodium

		let fileManager = FileManager()

		// Init encryption key
		let encryptionKeyExists = fileManager.fileExists(atPath: SecurityManager.EncryptionKeyLocation.path)
		if encryptionKeyExists {
			// Load existing encryption key
			guard let encryptionKey = try? Data(contentsOf: SecurityManager.EncryptionKeyLocation) else {
				print("Could not load encryption key from \(SecurityManager.EncryptionKeyLocation)")
				return nil
			}
			self.encryptionKey = encryptionKey
		} else {
			// Create and persist a new encryption key
			guard let encryptionKey = sodium.secretBox.key() else {
				print("Failed to create new encryption key!")
				return nil
			}
			self.encryptionKey = encryptionKey
			guard persist(data: encryptionKey, toLocation: SecurityManager.EncryptionKeyLocation) else {
				print("Could not persist encryption key")
				return nil
			}
		}

		// Init hash key
		let hashKeyExists = fileManager.fileExists(atPath: SecurityManager.HashKeyLocation.path)
		if hashKeyExists {
			// Load existing hash key
			guard let encryptedHashKey = try? Data(contentsOf: SecurityManager.HashKeyLocation) else {
				print("Could not load hash key from \(SecurityManager.HashKeyLocation)")
				return nil
			}
			// Unfortunately we can not use `decryptData()` here, as not all
			// constants were initialized.
			guard let hashKey = sodium.secretBox.open(nonceAndAuthenticatedCipherText: encryptedHashKey, secretKey: self.encryptionKey) else {
				print("Failed to decrypt hash key")
				return nil
			}
			self.hashKey = hashKey
			assert(
				self.hashKey == decrypt(ciphertext: EncryptedData(blob: encryptedHashKey)),
				"Implementation of decrypt(ciphertext:_) has changed, please decrypt hash key accordingly!"
			)
		} else {
			// Create and persist new hash key
			guard let hashKey = sodium.randomBytes.buf(length: sodium.genericHash.Keybytes) else {
				print("Could not generate hash key")
				return nil
			}
			self.hashKey = hashKey
			guard let encryptedHashKey = encrypt(plaintext: hashKey) else {
				print("Failed to encrypt hash key in order to persist it securely")
				return nil
			}
			guard persist(data: encryptedHashKey.blob, toLocation: SecurityManager.HashKeyLocation) else {
				print("Coult not persist hash key")
				return nil
			}
		}
	}
}

// MARK: - Helpers

/**
	Helper function used to persist data on disk. It utilizes the encryption
	options offered by iOS.

	- parameter data:
		The data that should be persisted.
	
	- parameter toLocation:
		The location at which the `data` should be persisted.

	- returns:
		`true` if persisting succeeded, `false` otherwise.
*/
func persist(data: Data, toLocation location: URL) -> Bool {
	let writingOptions: Data.WritingOptions = [
		.completeFileProtection,
		.withoutOverwriting
	]
	do {
		try data.write(to: location, options: writingOptions)
	} catch let error {
		print("Failed to persist \(location): \(error)")
		return false
	}
	return true
}
