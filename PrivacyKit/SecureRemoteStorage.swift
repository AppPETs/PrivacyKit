import Foundation

import Tafelsalz

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
		Initializes a personalized SecureRemoteStorage.

		- parameters:
			- persona: The persona that is able to decrypt the files stored by
				the secure storage.

		- returns:
			`nil` if the SecurityManager could not be initialized, i.e. if the
			encryption keys could not be generated or read from disk.
	*/
	public init?(persona: Persona = Persona(uniqueName: "default")) {
		guard let secretBox = SecretBox(persona: persona) else { return nil }
		self.persona = persona
		self.secretBox = secretBox
	}

	// MARK: AsynchronousKeyValueStorage

	/**
		The type of key (in sense of key-value).
	*/
	public typealias KeyType   = String

	/**
		The type of the value.
	*/
	public typealias ValueType = Data

	/**
		The type of errors that might occur.
	*/
	public typealias ErrorType = String

	/**
		Stores a value `value` for a given key `forKey` securely. Neither the
		key nor the value will be known to the server.

		## Example

		```swift
		let key = "My PIN"
		let value = Data("1234".utf8)
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
			The key that is used to identify the value.

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

		let encryptedData = secretBox.encrypt(data: value)

		let record = PrivacyService.Record(id: recordId, encryptedData: encryptedData)

		privacyService.store(record: record) {
			optionalError in

			finishedWithError(optionalError)
		}
	}

	/**
		Retrieves a value for a given key `key` securely.

		## Example

		```swift
		let key = "My PIN"
		storage.retrieveValueForKey(key) {
		    optionalValue, optionalError in
		    // Assert postcondition
		    precondition((optionalValue == nil) != (optionalError == nil), "Postcondition failed")
		    guard let retrievedValue = optionalValue else {
		        print(error!)
		        return
		    }
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
			precondition((optionalRecord == nil) != (optionalError == nil), "Postcondition failed")

			if let error = optionalError {
				valueAvailable(nil, error)
				return
			}

			// Successfully downloaded encrypted asset

			let record = optionalRecord!

			guard let data = self.secretBox.decrypt(data: record.encryptedData) else {
				valueAvailable(nil, "Failed to decrypt data")
				return
			}

			valueAvailable(data, nil)
		}

	}

	// MARK: - Private

	// MARK: Constants

	/**
		The persona to which this secret storage belongs.
	*/
	private let persona: Persona

	/**
		The security manager that handles encryption and key derivation.
	*/
	private let secretBox: SecretBox

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
	*/
	private func recordId(forKey key: KeyType) -> PrivacyService.RecordId? {

		guard let keyAsData = key.data(using: .utf8) else {
			return nil
		}

		guard let hashedKey = GenericHash(bytes: keyAsData, for: persona, outputSizeInBytes: PrivacyService.RecordId.lengthInBytes) else {
			return nil
		}

		guard let recordId = hashedKey.hex else {
			return nil
		}

		return PrivacyService.RecordId(recordId)
	}

}
