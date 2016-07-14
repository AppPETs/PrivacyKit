//
//  SecureRemoteStorage.swift
//  PrivacyKit
//
//  Created by Maximilian Blochberger on 2016-07-13.
//  Copyright © 2016 Universität Hamburg. All rights reserved.
//

import Foundation

// <#FIXME#> Data should first be updated in the cache. The configured server
// might not be available and we don't want to loose data. The cached data
// could then be uploaded afterwards (even in the background). We might want
// to reduce traffic and upload data in certain intervals or at certain
// check points such as the application quitting.

public class SecureRemoteStorage : AsynchronousKeyValueStorage {

	// MARK: Initializers

	public init?() {
		// Initialize security manager
		guard let securityManager = SecurityManager.instance else {
			print("Failed to initalize the SecurityManager")
			return nil
		}
		self.securityManager = securityManager
	}

	// MARK: AsynchronousKeyValueStorage

	public typealias KeyType   = String
	public typealias ValueType = NSData
	public typealias ErrorType = String

	public func storeValue(value: ValueType, forKey key: KeyType, finishedWithError: (error: ErrorType?) -> Void) {
		let privacyService = PrivacyService()

		guard let recordId = recordIdForKey(key) else {
			finishedWithError(error: "Failed to determine record ID for key \(key)")
			return
		}

		guard let encryptedData = securityManager.encryptData(value) else {
			finishedWithError(error: "Failed to encrypt data")
			return
		}

		let record = PrivacyService.Record(id: recordId, encryptedData: encryptedData)

		privacyService.storeRecord(record) {
			optionalError in

			finishedWithError(error: optionalError)
		}
	}

	public func retrieveValueForKey(key: KeyType, valueAvailable: (value: ValueType?, error: ErrorType?) -> Void) {
		let privacyService = PrivacyService()

		guard let recordId = recordIdForKey(key) else {
			valueAvailable(value: nil, error: "Failed to determine record ID")
			return
		}

		privacyService.retrieveRecordWithId(recordId) {
			optionalRecord, optionalError in

			// Assert postcondition
			assert((optionalRecord == nil) != (optionalError == nil), "Postcondition of PrivacyService failed")

			if let error = optionalError {
				valueAvailable(value: nil, error: error)
				return
			}

			// Successfully downloaded encrypted asset

			assert(optionalRecord != nil, "Data not correctly checked by the PrivacyService")

			let record = optionalRecord!
			let encryptedData = record.encryptedData

			guard let data = self.securityManager.decryptData(encryptedData) else {
				valueAvailable(value: nil, error: "Failed to decrypt data")
				return
			}

			valueAvailable(value: data, error: nil)
		}

	}

	// MARK: - Private

	// MARK: Constants

	private let securityManager:          SecurityManager

	// MARK: Methods

	// <#TODO#> Cache record IDs for performance – the phone's memory is trusted.
	private func recordIdForKey(key: KeyType) -> PrivacyService.RecordId? {

		guard let keyAsData = key.dataUsingEncoding(NSUTF8StringEncoding) else {
			return nil
		}

		guard let hashedKey = self.securityManager.hashOfKey(keyAsData, withOutputLengthInBytes: PrivacyService.RecordId.lengthInBytes) else {
			return nil
		}

		let recordId = PrivacyService.RecordId(hashedKey)

		return recordId
	}
}
