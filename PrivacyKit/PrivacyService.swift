//
//  PrivacyService.swift
//  PrivacyKit
//
//  Created by Maximilian Blochberger on 2016-07-13.
//  Copyright © 2016 Universität Hamburg. All rights reserved.
//

import Foundation
import UIKit

/**
	Internal class that acts as an interface to the web service API.
*/
class PrivacyService {

	// MARK: Types

	/**
		Struct that holds a valid record ID which is basically a 128 character
		string containing only hexadecimal characters.
	*/
	struct RecordId {

		/// Length of the record ID in bytes.
		static let lengthInBytes = 512 / 8

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
		let encryptedData: SecurityManager.EncryptedData
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

		#### Example
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
			Singals that storing is finished. If an error occurred than `error`
			will contain a descriptive reason, otherwise it will be `nil`.
	*/
	func store(record: Record, finishedWithOptionalError: @escaping (_ error: String?) -> Void) {
		let sessionConfiguration = URLSessionConfiguration()
		let session = URLSession(configuration: sessionConfiguration, delegate: certificatePinner, delegateQueue: nil)
		var request = URLRequest(url: storageUrl(forRecord: record))

		request.httpMethod = PrivacyService.HttpMethods.HttpMethodForStore.rawValue

		// Set HTTP headers
		request.addValue(PrivacyService.DefaultContentTypeHttpHeaderVaulue, forHTTPHeaderField: PrivacyService.HttpHeaders.ContentTypeHeader.rawValue)

		showNetworkActivityIndicator()

		let task = session.uploadTask(with: request, from: record.encryptedData.blob) {
			optionalData, optionalResponse, optionalError in

			hideNetworkActivityIndicator()

			if let error = optionalError {
				finishedWithOptionalError("Error: \(error.localizedDescription)\nResponse: \(optionalResponse.debugDescription)")
				return
			}

			guard let response = optionalResponse as? HTTPURLResponse else {
				finishedWithOptionalError("Response is not HTTP")
				return
			}

			if response.statusCode != PrivacyService.HttpStatus.HttpStatusOk.rawValue {
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

		#### Example
		```swift
		privacyService.retrieveRecord(withId: recordId) {
		    optionalRecord, optionalError in
		    // Assert postcondition
		    assert((optionalRecord == nil) != (optionalError == nil), "Postcondition failed")
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
			 assert((record == nil) != (error == nil), "Postcondition failed")
			```
	*/
	func retrieveRecord(withId recordId: RecordId, finishedWithRecord: @escaping (_ record: Record?, _ error: String?) -> Void) {
		let sessionConfiguration = URLSessionConfiguration()
		let session = URLSession(configuration: sessionConfiguration, delegate: certificatePinner, delegateQueue: nil)
		var request = URLRequest(url: storageUrl(forRecordId: recordId))

		request.httpMethod = PrivacyService.HttpMethods.HttpMethodForRetrieve.rawValue

		showNetworkActivityIndicator()

		let task = session.dataTask(with: request) {
			optionalData, optionalResponse, optionalError in

			hideNetworkActivityIndicator()

			if let error = optionalError {
				finishedWithRecord(nil, "Error: \(error.localizedDescription)\nResponse: \(optionalResponse.debugDescription)")
				return
			}

			guard let response = optionalResponse as? HTTPURLResponse else {
				finishedWithRecord(nil, "Resonse is not HTTP")
				return
			}

			if response.statusCode != PrivacyService.HttpStatus.HttpStatusOk.rawValue {
				finishedWithRecord(nil, "HTTP Error \(response.statusCode): \(response.description)")
				return
			}

			// Successfully downloaded asset

			guard let retrievedData = optionalData else {
				finishedWithRecord(nil, "Response contains no content")
				return
			}

			let encryptedData = SecurityManager.EncryptedData(blob: retrievedData)
			let record = Record(id: recordId, encryptedData: encryptedData)
			finishedWithRecord(record, nil)

		}
		task.resume()
	}

	// MARK: - Private

	// MARK: Enums

	/// This enum is used to avoid hard-coded HTTP headers.
	private enum HttpHeaders: String {
		/// The HTTP "Content-Type" header.
		case ContentTypeHeader = "Content-Type"
	}

	/// This enum is used to avoid hard-coded HTTP methods.
	private enum HttpMethods: String {
		/// The HTTP method used to store records.
		case HttpMethodForStore    = "POST"
		/// The HTTP method used to retrieve records.
		case HttpMethodForRetrieve = "GET"
	}

	/// This enum is used to avoid hard-coded HTTP status codes.
	private enum HttpStatus: Int {
		/// The HTTP status code that signals success.
		case HttpStatusOk = 200
	}

	// MARK: Class constants

	/**
		The default content type of the encrypted value of an record. The value
		is transmitted in binary form.

		- todo:
			The value should be compressed to save bandwith.
	*/
	private static let DefaultContentTypeHttpHeaderVaulue = "application/octet-stream"

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

// MARK: - Helpers

/**
	Shows the network activity indicator in the status bar.

	This function is thread safe.

	- requires:
		[`UIKit`][1]

	- todo:
		Use a callback/delegate so that the security related functions can be
		offered to command line utilities or on macOS as well.

	[1]: https://developer.apple.com/reference/uikit
*/
func showNetworkActivityIndicator() {
	DispatchQueue.main.async {
		UIApplication.shared.isNetworkActivityIndicatorVisible = true
	}
}

/**
	Hides the network activity indicator in the status bar.

	This function is thread safe.

	- Requires:
		[`UIKit`][1]

	- todo:
		Use a callback/delegate so that the security related functions can be
		offered to command line utilities or on macOS as well.

	[1]: https://developer.apple.com/reference/uikit
*/
func hideNetworkActivityIndicator() {
	DispatchQueue.main.async {
		UIApplication.shared.isNetworkActivityIndicatorVisible = false
	}
}
