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

	- Requires:
	  - `Foundation`
	  - [`Sodium`](https://github.com/jedisct1/swift-sodium)
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
	
		- Warning:
		Encryption is not enforced, so if you create an instance of this and
		just pass plaintext to the initializer, then private data might still
		leak. The main idea is to avoid mistakes, not to prevent acting
		maliciously. So please think twice when actually instantiating this.
		
		The class does not enforce the encryption used. Maybe this can still be
		improved.
	*/
	struct EncryptedData {
		let blob: NSData
	}

	// MARK: Class constants

	static let instance = SecurityManager()

	// MARK: Methods

	func hashOfKey(key: NSData, withOutputLengthInBytes outputLengthInBytes: Int) -> String? {
		// <#FIXME#> Okay to use secretKey as salt?
		// Uses Argon2i for hashing
		guard let hashedKeyAsData = sodium.pwHash.hash(outputLengthInBytes, passwd: key, salt: self.secretKey, opsLimit: sodium.pwHash.OpsLimitInteractive, memLimit: sodium.pwHash.MemLimitInteractive) else {
				print("Failed to hash key \(key)")
				return nil
		}

		let hashedKey = sodium.utils.bin2hex(hashedKeyAsData)
		return hashedKey
	}

	func encryptData(data: NSData) -> EncryptedData? {
		// Uses XSalsa20 for encryption and Poly1305 for MAC
		let optionalCiphertext: NSData? = sodium.secretBox.seal(data, secretKey: self.secretKey)
		guard let ciphertext = optionalCiphertext else {
			return nil
		}
		let encryptedData = EncryptedData(blob: ciphertext)
		return encryptedData
	}

	func decryptData(encryptedData: EncryptedData) -> NSData? {
		let data = sodium.secretBox.open(encryptedData.blob, secretKey: self.secretKey)
		return data
	}

	// MARK: - Private

	// MARK: Constants

	private static let SecretKeyFileName = "secret.key"
	private static let DocumentsDirectory = NSFileManager().URLsForDirectory(.DocumentDirectory, inDomains: .UserDomainMask).first!
	private static let SecretKeyLocation  = DocumentsDirectory.URLByAppendingPathComponent(SecretKeyFileName)

	private let sodium:    Sodium
	private let secretKey: Box.SecretKey

	// MARK: Initializers

	private init?() {

		// Init Sodium
		guard let sodium = Sodium() else {
			print("Failed to initialize sodium")
			return nil
		}
		self.sodium = sodium

		// Init key
		let fileManager = NSFileManager.defaultManager()
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
			// <#TODO#> Password protect key
			// <#TODO#> Store key in keychain
			let writingOptions: NSDataWritingOptions = [
				.DataWritingFileProtectionComplete,
				.DataWritingWithoutOverwriting
			]
			do {
				try secretKey.writeToURL(SecurityManager.SecretKeyLocation, options: writingOptions)
			} catch let error as NSError {
				print("Failed to store secret key: \(error)")
				return nil
			}
		}
	}
}
