//
//  SecureRemoteStorage.swift
//  PrivacyKit
//
//  Created by Maximilian Blochberger on 2016-07-13.
//  Copyright © 2016 Universität Hamburg. All rights reserved.
//

import Foundation

/**
	This class can be used to store files securely in the Cloud. The files are
	encrypted on the device and then stored on a Privacy-Service.

	The values are byte arrays (`Data`), the keys are strings (`String`), and
	the errors are strings (`String`) as well.

	- todo:
		For performance/availability reasons data should be cached. The
		Privacy-Service might not be available, the internet connection might be
		slow, or data is changed more frequently than required to upload. The
		cached data can be uploaded in background, i.e. if the user closes the
		application. This can also be used to reduce traffic or limit uploads to
		Wi-Fi availability.
*/
public class SecureRemoteStorage : AsynchronousKeyValueStorage {

	// MARK: Initializers

	/**
		Initializes a SecureRemoteStorage.

		- returns:
			`nil` if the SecurityManager could not be initialized, i.e. if the
			encryption keys could not be generated or read from disk.
	*/
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
	public typealias ValueType = Data
	public typealias ErrorType = String

	/**
		Stores a value `value` for a given key `forKey` securely. Neither the
		key nor the value will be known to the server.

		#### Example
		```swift
		let key = "My PIN"
		let value = "1234".data(using: .utf8)!
		storage.store(value: value, forKey: key) {
		    optionalError in
		    if let error = optionalError {
		        print(error)
		    }
		}
		```

		- parameter value:
			The value that should be stored, such as a file.
	
		- parameter forKey:
			THe key that is used to identify the value.

		- parameter finishedWithError:
			This closure signals that storing has finished. If an error
			occurred, `error` will contain a descriptive reason. Otherwise it
			will be `nil`, which signals success.
	*/
	public func store(value: ValueType, forKey key: KeyType, finishedWithError: @escaping (_ error: ErrorType?) -> Void) {
		let privacyService = PrivacyService()

		guard let recordId = recordId(forKey: key) else {
			finishedWithError("Failed to determine record ID for key \(key)")
			return
		}

		guard let encryptedData = securityManager.encrypt(plaintext: value) else {
			finishedWithError("Failed to encrypt data")
			return
		}

		let record = PrivacyService.Record(id: recordId, encryptedData: encryptedData)

		privacyService.store(record: record) {
			optionalError in

			finishedWithError(optionalError)
		}
	}

	/**
		Retrieves a value for a given key `key` securely.

		#### Example
		```swift
		let key = "My PIN"
		storage.retrieveValueForKey(key) {
		    optionalValue, optionalError in
		    // Assert postcondition
		    assert((optionalValue == nil) != (optionalError == nil), "Postcondition failed")
		    if let error = optionalError {
		        print(error)
		        return
		    }
		    let retrievedValue = optionalValue!
		    // Do something with the retrieved Value
		    print(retrievedValue) // Will print "1234" if example from above was used
		}
		```

		- warning:
			The closure `valueAvailable` is called asynchronously. Therefore if
			the `value` is used to change a UI element, it should be done in the
			UI thread. Additionally if multiple calls to
			`retrieveValueForKey(_:valueAvailable:)` are made, the callbacks
			made to the closure might be performed in a different order.
	
		- parameter key:
			The key that is used to identify the value.

		- parameter valueAvailable:
			This closure signals that retrieving has finished. If an error
			occurred, `error` will contain a descriptive reason and `value` will
			be `nil`. Otherwise `error` will be `nil` and the `value` will
			contain the retrieved data. Note that the closure might be called in
			another thread and the retrieved data should be handled
			appropriately, i.e. if the value is used to change a UI element, it
			should be done in the UI thread.
	*/
	public func retrieveValue(forKey key: KeyType, valueAvailable: @escaping (_ value: ValueType?, _ error: ErrorType?) -> Void) {
		let privacyService = PrivacyService()

		guard let recordId = recordId(forKey: key) else {
			valueAvailable(nil, "Failed to determine record ID")
			return
		}

		privacyService.retrieveRecord(withId: recordId) {
			optionalRecord, optionalError in

			// Assert postcondition
			assert((optionalRecord == nil) != (optionalError == nil), "Postcondition failed")

			if let error = optionalError {
				valueAvailable(nil, error)
				return
			}

			// Successfully downloaded encrypted asset

			let record = optionalRecord!
			let encryptedData = record.encryptedData

			guard let data = self.securityManager.decrypt(ciphertext: encryptedData) else {
				valueAvailable(nil, "Failed to decrypt data")
				return
			}

			valueAvailable(data, nil)
		}

	}

	// MARK: - Private

	// MARK: Constants

	/// The security manager that handles encryption and key derivation.
	private let securityManager: SecurityManager

	// MARK: Methods

	/**
		Generate a record ID for a given `key`.

		- warning:
			The record ID is visible to the Privacy-Service, but should not be
			used otherwise, as everyone who knows the record ID can access the
			encrypted asset. They should not be able to decrypt the asset, but
			they might upload another asset instead, which essentialy deletes
			the previous asset on the remote side.

		- parameter key:
			The value that the application developer uses to identify an asset,
			e.g. a file name.

		- returns:
			A valid record ID or `nil` if it could not be derived.

		- todo:
			Cache record IDs as they are generated deterministically and the
			generation consumes energy and takes time. There is no need to
			repeat it. The device's memory is trusted. Persisting the cache on
			disk should be done with additional encryption and is should be
			measued which operation has higher performance/energy impact before
			taking action.
	*/
	private func recordId(forKey key: KeyType) -> PrivacyService.RecordId? {

		guard let keyAsData = key.data(using: .utf8) else {
			return nil
		}

		guard let hashedKey = self.securityManager.hash(ofKey: keyAsData, withOutputLengthInBytes: PrivacyService.RecordId.lengthInBytes) else {
			return nil
		}

		let recordId = PrivacyService.RecordId(hashedKey)

		return recordId
	}

}
