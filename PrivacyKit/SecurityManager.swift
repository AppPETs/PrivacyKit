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
		let blob: NSData
	}

	// MARK: Class constants

	/// Singleton instance of the `SecurityManager`.
	static let instance = SecurityManager()

	// MARK: Methods

	/**
		Generates a deterministic secure hash of a given `key`. This means that
		if the given key is equal, the result will be equal as well.

		The hashing function used is the password hashing function provided by
		the [`Sodium`](https://github.com/jedisct1/swift-sodium) framework. It
		is implemented by the **Argon2i** algorithm.

		- parameter key:
			The key that should be hashed.

		- parameter outputLengthInBytes:
			The length of the generated hash in bytes.

		- returns:
			The hash as a hexadecimal string representation.
	*/
	func hashOfKey(key: NSData, withOutputLengthInBytes outputLengthInBytes: Int) -> String? {
		guard let hashedKeyAsData = sodium.pwHash.hash(outputLengthInBytes, passwd: key, salt: self.secretSalt, opsLimit: sodium.pwHash.OpsLimitInteractive, memLimit: sodium.pwHash.MemLimitInteractive) else {
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
			`decryptData(_:)`

		- parameter data:
			The data that should be encrypted.

		- returns:
			An encrypted data object or `nil` if the encryption failed.
	*/
	func encryptData(data: NSData) -> EncryptedData? {
		let optionalCiphertext: NSData? = sodium.secretBox.seal(data, secretKey: self.secretKey)
		guard let ciphertext = optionalCiphertext else {
			return nil
		}
		let encryptedData = EncryptedData(blob: ciphertext)
		return encryptedData
	}

	/**
		Decrypts data and validates integrity.

		- see:
			`encryptData(_:)`

		- parameter encryptedData:
			The encrypted data that should be decrypted.

		- returns:
			The decrypted data or `nil` if the decryption or integrity
			validation failed.
	*/
	func decryptData(encryptedData: EncryptedData) -> NSData? {
		let data = sodium.secretBox.open(encryptedData.blob, secretKey: self.secretKey)
		return data
	}

	// MARK: - Private

	// MARK: Constants

	/// The name of file, which is used to persist the secret encryption key.
	private static let SecretKeyFileName  = "secret.key"

	/**
		The name of the file, which is used to persist the secret salt, which in
		turn is used for hashing asset keys.
	*/
	private static let SecretSaltFileName = "secret.salt"

	/// The directory for storing documents
	private static let DocumentsDirectory = NSFileManager().URLsForDirectory(.DocumentDirectory, inDomains: .UserDomainMask).first!

	/**
		The location of the file, which is used to persist the secret encryption
		key.
	*/
	private static let SecretKeyLocation  = DocumentsDirectory.URLByAppendingPathComponent(SecretKeyFileName)

	/**
		The location of the file, which is used to persist the secret salt,
		which in turn is used for hashing asset keys.
	*/
	private static let SecretSaltLocation = DocumentsDirectory.URLByAppendingPathComponent(SecretSaltFileName)

	/**
		An instance of [`Sodium`](https://github.com/jedisct1/swift-sodium),
		which provides encryption and hashing functions.
	*/
	private let sodium: Sodium

	/// The secret encryption key.
	private let secretKey: Box.SecretKey

	/// The secret salt, which is used for hashing asset keys.
	private let secretSalt: NSData

	// MARK: Initializers

	/**
		Initializes a `SecurityManager` instance. Upon first start this will
		generate the required encryption key and the secret salt used for
		hashing asset keys and persist them on disk. If they were already
		persisted they will be loaded instead.

		- returns:
			`nil` if [`Sodium`](https://github.com/jedisct1/swift-sodium) could
			not be initialized, if the keys could not be generated, or if they
			could not be read if they were persisted.

		- todo:
			Store secret encyrption key and salt in Keychain.

		- todo:
			Password protect secret encryption key.
	*/
	private init?() {

		// Init Sodium
		guard let sodium = Sodium() else {
			print("Failed to initialize sodium")
			return nil
		}
		self.sodium = sodium

		let fileManager = NSFileManager.defaultManager()

		// Init key
		let secretKeyExists = fileManager.fileExistsAtPath(SecurityManager.SecretKeyLocation.path!)
		if secretKeyExists {
			// Load existing key
			guard let secretKey = NSData(contentsOfURL: SecurityManager.SecretKeyLocation) else {
				print("Could not load secret key from \(SecurityManager.SecretKeyLocation)")
				return nil
			}
			self.secretKey = secretKey
		} else {
			// Create and persist a new secret key
			guard let secretKey = sodium.secretBox.key() else {
				print("Failed to create new secret key!")
				return nil
			}
			self.secretKey = secretKey
			persistData(secretKey, toLocation: SecurityManager.SecretKeyLocation)
		}

		// Init salt
		let secretSaltExists = fileManager.fileExistsAtPath(SecurityManager.SecretSaltLocation.path!)
		if secretSaltExists {
			// Load existing salt
			guard let encryptedSecretSalt = NSData(contentsOfURL: SecurityManager.SecretSaltLocation) else {
				print("Could not load secret salt from \(SecurityManager.SecretSaltLocation)")
				return nil
			}
			// Unfortunately we can not use `decryptData()` here, as not all
			// constants were initialized.
			guard let secretSalt = sodium.secretBox.open(encryptedSecretSalt, secretKey: self.secretKey) else {
				print("Failed to decrypt secret salt")
				return nil
			}
			self.secretSalt = secretSalt
			assert(self.secretSalt == decryptData(EncryptedData(blob: encryptedSecretSalt)), "Implementation of decryptData() has changed, please decrypt secret salt accordingly!")
		} else {
			// Create and persist new secret salt
			guard let secretSalt = sodium.randomBytes.buf(sodium.pwHash.SaltBytes) else {
				print("Could not generate secret salt")
				return nil
			}
			self.secretSalt = secretSalt
			guard let encryptedSalt = encryptData(secretSalt) else {
				print("Failed to encrypt secret salt in order to persist it securely")
				return nil
			}
			persistData(encryptedSalt.blob, toLocation: SecurityManager.SecretSaltLocation)
		}
	}
}

// MARK: - Helpers

/**
	Helper function used to persist data on disk. It utilizes the encryption
	options offered by iOS.

	- parameter data:
		The data that should be persisted.
	
	- parameter location:
		The location at which the `data` should be persisted.

	- returns:
		`true` if persisting succeeded, `false` otherwise.
*/
func persistData(data: NSData, toLocation location: NSURL) -> Bool {
	let writingOptions: NSDataWritingOptions = [
		.DataWritingFileProtectionComplete,
		.DataWritingWithoutOverwriting
	]
	do {
		try data.writeToURL(location, options: writingOptions)
	} catch let error as NSError {
		print("Failed to persist \(location): \(error)")
		return false
	}
	return true
}
