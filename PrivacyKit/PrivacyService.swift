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

	- Requires:
	  - `Foundation` for `NSURL`
*/
class PrivacyService {

	// MARK: Types

	struct RecordId {

		static let lengthInBytes = 512 / 8

		let value: String

		init?(_ valueAsString: String) {

			if !(valueAsString =~ "^[[:xdigit:]]{\(PrivacyService.RecordId.lengthInBytes * 2)}$") {
				return nil
			}

			self.value = valueAsString
		}
	}

	struct Record {
		let id:            RecordId
		let encryptedData: SecurityManager.EncryptedData
	}

	// MARK: Initializers

	init() {
		self.certificatePinner = CertificatePinner(forHost: baseUrl.host!)
	}

	// MARK: Methods

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

	private enum HttpHeaders: String {
		case ContentTypeHeader = "Content-Type"
	}

	private enum HttpMethods: String {
		case HttpMethodForStore    = "POST"
		case HttpMethodForRetrieve = "GET"
	}

	private enum HttpStatus: Int {
		case HttpStatusOk = 200
	}

	// MARK: Class constants

	private static let DefaultContentTypeHttpHeaderVaulue = "application/octet-stream"

	// MARK: Constants

	// <#FIXME#> Use real URL.
	private let baseUrl = NSURL(string: "https://privacyservice.test:8080")!
	private let certificatePinner: CertificatePinner?

	// MARK: Methods

	private func storageUrl() -> NSURL {
		return baseUrl.URLByAppendingPathComponent("storage", isDirectory: true)
	}

	private func storageUrlForRecord(recordId: RecordId) -> NSURL {
		return storageUrl().URLByAppendingPathComponent(recordId.value, isDirectory: false)
	}
}

// MARK: - Helpers

/**
	Shows the network activity indicator in the status bar.

	This function is thread safe.

	- Requires:
	  - `UIKit`
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
	 - `UIKit`
*/
func hideNetworkActivityIndicator() {
	dispatch_async(dispatch_get_main_queue()) {
		UIApplication.sharedApplication().networkActivityIndicatorVisible = false
	}
}
