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

	- requires:
		[`Foundation`][1] for [`NSURL`][2]

	[1]: https://developer.apple.com/library/ios/documentation/Cocoa/Reference/Foundation/ObjC_classic/index.html
	[2]: https://developer.apple.com/library/ios/documentation/Cocoa/Reference/Foundation/Classes/NSURL_Class/index.html
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
		privacyService.storeRecord(record) {
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
	func storeRecord(record: Record, finishedWithOptionalError: (error: String?) -> Void) {
		let sessionConfiguration = NSURLSessionConfiguration.defaultSessionConfiguration()
		let session = NSURLSession(configuration: sessionConfiguration, delegate: certificatePinner, delegateQueue: nil)
		let request = NSMutableURLRequest(URL: storageUrlForRecord(record.id))

		request.HTTPMethod = PrivacyService.HttpMethods.HttpMethodForStore.rawValue

		// Set HTTP headers
		request.addValue(PrivacyService.DefaultContentTypeHttpHeaderVaulue, forHTTPHeaderField: PrivacyService.HttpHeaders.ContentTypeHeader.rawValue)

		showNetworkActivityIndicator()

		let task = session.uploadTaskWithRequest(request, fromData: record.encryptedData.blob) {
			optionalData, optionalResponse, optionalError in

			hideNetworkActivityIndicator()

			if let error = optionalError {
				finishedWithOptionalError(error: "Error: \(error.localizedDescription)\nResponse: \(optionalResponse.debugDescription)")
				return
			}

			guard let response = optionalResponse as? NSHTTPURLResponse else {
				finishedWithOptionalError(error: "Response is not HTTP")
				return
			}

			if response.statusCode != PrivacyService.HttpStatus.HttpStatusOk.rawValue {
				finishedWithOptionalError(error: "HTTP Error \(response.statusCode): \(response.description)")
				return
			}

			// Successfully uploaded encrypted asset
			finishedWithOptionalError(error: nil)
		}
		task.resume()
	}

	/**
		Function to retrieve a record or key-value pair asynchronously.

		#### Example
		```swift
		privacyService.retrieveRecordWithId(recordId) {
		    optionalRecord, optionalError in
		    // Assert postcondition
		    assert((optionalRecord == nil) != (optionalError == nil), "Postcondition failed")
		    if let error = optionalError {
		        // Delegate error and back out
		        valueAvailable(value: nil, error: error)
		        return
		    }
		    // Successfully downloaded encrypted value
		    let record = optionalRecord!
		    // TODO Decrypt data and signal success
		    valueAvailable(value: decryptedValue, error: nil)
		}
		```

		- warning:
			The closure `finishedWithRecord` is called asynchronously. Therefore
			if multiple calls to `retrieveRecordWithId(_:finishedWithRecord:)`
			are made, the callbacks made to the closure might be performed in a
			different order.

		- postcondition:
			In `finishedWithRecord` either `record` is `nil` or `error` is `nil`
			but not both at the same time.

			```swift
			 assert((record == nil) != (error == nil), "Postcondition failed")
			```
	*/
	func retrieveRecordWithId(recordId: RecordId, finishedWithRecord: (record: Record?, error: String?) -> Void) {
		let sessionConfiguration = NSURLSessionConfiguration.defaultSessionConfiguration()
		let session = NSURLSession(configuration: sessionConfiguration, delegate: certificatePinner, delegateQueue: nil)
		let request = NSMutableURLRequest(URL: storageUrlForRecord(recordId))
		request.HTTPMethod = PrivacyService.HttpMethods.HttpMethodForRetrieve.rawValue

		showNetworkActivityIndicator()

		let task = session.dataTaskWithRequest(request) {
			optionalData, optionalResponse, optionalError in

			hideNetworkActivityIndicator()

			if let error = optionalError {
				finishedWithRecord(record: nil, error: "Error: \(error.localizedDescription)\nResponse: \(optionalResponse.debugDescription)")
				return
			}

			guard let response = optionalResponse as? NSHTTPURLResponse else {
				finishedWithRecord(record: nil, error: "Resonse is not HTTP")
				return
			}

			if response.statusCode != PrivacyService.HttpStatus.HttpStatusOk.rawValue {
				finishedWithRecord(record: nil, error: "HTTP Error \(response.statusCode): \(response.description)")
				return
			}

			// Successfully downloaded asset

			guard let retrievedData = optionalData else {
				finishedWithRecord(record: nil, error: "Response contains no content")
				return
			}

			let encryptedData = SecurityManager.EncryptedData(blob: retrievedData)
			let record = Record(id: recordId, encryptedData: encryptedData)
			finishedWithRecord(record: record, error: nil)

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
	private let baseUrl = NSURL(string: "https://privacyservice.test:8080")!

	/// The certificate pinner for the Privacy-Service in use.
	private let certificatePinner: CertificatePinner

	// MARK: Methods

	/**
		Returns a URL for the API entry point for storage operations.

		- returns:
			The URL which is used as entry point for storage operations.
	*/
	private func storageUrl() -> NSURL {
		return baseUrl.URLByAppendingPathComponent("storage", isDirectory: true)
	}

	/**
		Returns a URL for the API entry point for storage operations of a
		specified `record`.

		- parameter record:
			The ID of the record, for which storage operations should be
			performed.

		- returns:
			The url which is used as entry point for storage operations for a
			specific record.
	*/
	private func storageUrlForRecord(recordId: RecordId) -> NSURL {
		return storageUrl().URLByAppendingPathComponent(recordId.value, isDirectory: false)
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

	[1]: https://developer.apple.com/library/ios/documentation/UIKit/Reference/UIKit_Framework/index.html
*/
func showNetworkActivityIndicator() {
	dispatch_async(dispatch_get_main_queue()) {
		UIApplication.sharedApplication().networkActivityIndicatorVisible = true
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

	[1]: https://developer.apple.com/library/ios/documentation/UIKit/Reference/UIKit_Framework/index.html
*/
func hideNetworkActivityIndicator() {
	dispatch_async(dispatch_get_main_queue()) {
		UIApplication.sharedApplication().networkActivityIndicatorVisible = false
	}
}
