import Foundation

import Tafelsalz

/**
	Internal class that acts as an interface to the web service API.
*/
class PrivacyService {

	// MARK: Types

	/**
		Struct that holds a valid record ID which is basically a 64 character
		string containing only hexadecimal characters.
	*/
	struct RecordId {

		/// Length of the record ID in bytes.
		static let lengthInBytes: PInt = 256 / 8

		/// The actual string representation of the record ID.
		let value: String

		/**
			Initializer for a record ID.

			- parameter valueAsString:
				String representation of a record ID.

			- returns:
				`nil` if `valueAsString` is not a valid record ID.
		*/
		init?(_ valueAsString: String) {

			if !(valueAsString =~ "^[[:xdigit:]]{\(PrivacyService.RecordId.lengthInBytes * 2)}$") {
				return nil
			}

			self.value = valueAsString
		}
	}

	/**
		Struct that represents a record – basically a key-value pair. A record
		can only contain encrypted data.
	*/
	struct Record {

		/// The ID of the record, or key of the key-value pair.
		let id: RecordId

		/// The encrypted value
		let encryptedData: SecretBox.AuthenticatedCiphertext
	}

	// MARK: Initializers

	/**
		Initializes a `PrivacyService` instance.
	*/
	init() {
		self.certificatePinner = CertificatePinner(forHost: baseUrl.host!)!
	}

	// MARK: Methods

	/**
		Function to store a record or key-value pair asynchronously.

		## Example

		```swift
		privacyService.store(record: record) {
		    optionalError in
		    if let error = optionalError {
		        // TODO Handle error
		    }
		}
		```

		- parameter record:
			The record that should be stored.

		- parameter finishedWithOptionalError:
			Signals that storing is finished. If an error occurred then `error`
			will contain a descriptive reason, otherwise it will be `nil`.
	*/
	func store(record: Record, finishedWithOptionalError: @escaping (_ error: String?) -> Void) {
		let sessionConfiguration = URLSessionConfiguration.default
		let session = URLSession(configuration: sessionConfiguration, delegate: certificatePinner, delegateQueue: nil)
		var request = URLRequest(url: storageUrl(forRecord: record))

		request.set(method: .post)

		// Set HTTP headers
		request.set(contentType: .octetStream)

		Indicators.showNetworkActivity()

		let task = session.uploadTask(with: request, from: record.encryptedData.bytes) {
			optionalData, optionalResponse, optionalError in

			Indicators.hideNetworkActivity()

			if let error = optionalError {
				finishedWithOptionalError("Error: \(error.localizedDescription)\nResponse: \(optionalResponse.debugDescription)")
				return
			}

			guard let response = optionalResponse as? HTTPURLResponse else {
				finishedWithOptionalError("Response is not HTTP")
				return
			}

			assert(0 <= response.statusCode)
			let status = Http.Status(rawValue: UInt16(response.statusCode))!

			if status != .ok {
				finishedWithOptionalError("HTTP Error \(response.statusCode): \(response.description)")
				return
			}

			// Successfully uploaded encrypted asset
			finishedWithOptionalError(nil)
		}
		task.resume()
	}

	/**
		Function to retrieve a record or key-value pair asynchronously.

		## Example

		```swift
		privacyService.retrieveRecord(withId: recordId) {
		    optionalRecord, optionalError in
		    // Assert postcondition
		    precondition((optionalRecord == nil) != (optionalError == nil), "Postcondition failed")
		    if let error = optionalError {
		        // Delegate error and back out
		        valueAvailable(nil, error)
		        return
		    }
		    // Successfully downloaded encrypted value
		    let record = optionalRecord!
		    // TODO Decrypt data and signal success
		    valueAvailable(decryptedValue, nil)
		}
		```

		- warning:
			The closure `finishedWithRecord` is called asynchronously. Therefore
			if multiple calls to `retrieveRecord(withId:finishedWithRecord:)`
			are made, the callbacks made to the closure might be performed in a
			different order.

		- postcondition:
			In `finishedWithRecord` either `record` is `nil` or `error` is `nil`
			but not both at the same time.

			```swift
			 precondition((record == nil) != (error == nil), "Postcondition failed")
			```
	*/
	func retrieveRecord(withId recordId: RecordId, finishedWithRecord: @escaping (_ record: Record?, _ error: String?) -> Void) {
		let sessionConfiguration = URLSessionConfiguration.default
		let session = URLSession(configuration: sessionConfiguration, delegate: certificatePinner, delegateQueue: nil)
		var request = URLRequest(url: storageUrl(forRecordId: recordId))

		request.set(method: .get)

		Indicators.showNetworkActivity()

		let task = session.dataTask(with: request) {
			optionalData, optionalResponse, optionalError in

			Indicators.hideNetworkActivity()

			if let error = optionalError {
				finishedWithRecord(nil, "Error: \(error.localizedDescription)\nResponse: \(optionalResponse.debugDescription)")
				return
			}

			guard let response = optionalResponse as? HTTPURLResponse else {
				finishedWithRecord(nil, "Resonse is not HTTP")
				return
			}

			assert(0 <= response.statusCode)
			let status = Http.Status(rawValue: UInt16(response.statusCode))!

			if status != .ok {
				finishedWithRecord(nil, "HTTP Error \(response.statusCode): \(response.description)")
				return
			}

			// Successfully downloaded asset

			guard let retrievedData = optionalData else {
				finishedWithRecord(nil, "Response contains no content")
				return
			}

			guard let encryptedData = SecretBox.AuthenticatedCiphertext(bytes: retrievedData) else {
				finishedWithRecord(nil, "Response has unexpected format")
				return
			}

			let record = Record(id: recordId, encryptedData: encryptedData)
			finishedWithRecord(record, nil)

		}
		task.resume()
	}

	// MARK: - Private

	// MARK: Constants

	/**
		The base URL for the Privacy-Service.

		- todo:
			Use real URL if a real Privacy-Service is established.
	*/
	private let baseUrl = URL(string: "https://privacyservice.test:8080")!

	/// The certificate pinner for the Privacy-Service in use.
	private let certificatePinner: CertificatePinner

	// MARK: Methods

	/**
		Returns a URL for the API entry point for storage operations.

		- returns:
			The URL which is used as entry point for storage operations.
	*/
	private func storageUrl() -> URL {
		return baseUrl
			.appendingPathComponent("storage", isDirectory: true)
			.appendingPathComponent("v1", isDirectory: true)
	}

	/**
		Returns a URL for the API entry point for storage operations of a
		specified `record`.

		- parameter forRecordId:
			The ID of the record, for which storage operations should be
			performed.

		- returns:
			The url which is used as entry point for storage operations for a
			specific record.
	*/
	private func storageUrl(forRecordId recordId: RecordId) -> URL {
		return storageUrl().appendingPathComponent(recordId.value, isDirectory: false)
	}

	/**
		Returns a URL for the API entry point for storage operations of a
		specified `record`.

		- parameter forRecord:
			The record, for which storage operations should be performed.

		- returns:
			The url which is used as entry point for storage operations for a
			specific record.
	*/
	private func storageUrl(forRecord record: Record) -> URL {
		return storageUrl(forRecordId: record.id)
	}

}
