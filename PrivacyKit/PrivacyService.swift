//
//  PrivacyService.swift
//  PrivacyKit
//
//  Created by Maximilian Blochberger on 2016-07-13.
//  Copyright © 2016 Universität Hamburg. All rights reserved.
//

import Foundation

/**
	Internal class that acts as an interface to the web service API.

	- Requires:
	  - `Foundation` for `NSURL`
*/
class PrivacyService {

	// MARK: Constants

	static let DefaultContentTypeHttpHeaderVaulue = "application/octet-stream"

	// MARK: Enums

	enum HttpHeaders: String {
		case ContentTypeHeader = "Content-Type"
	}

	enum HttpMethods: String {
		case HttpMethodForStore    = "POST"
		case HttpMethodForRetrieve = "GET"
	}

	enum HttpStatus: Int {
		case HttpStatusOk = 200
	}

	// MARK: Methods

	func storageUrlForRecord(recordId: String) -> NSURL {
		return storageUrl().URLByAppendingPathComponent(recordId, isDirectory: false)
	}

	// MARK: - Private

	// MARK: Constants

	// <#FIXME#> We should support HTTPS here, as HTTP is discouraged by Apple and
	// the default policy is not to allow HTTP connections to be established.
	// Exceptions can be added to the Info.plist file or directly within the
	// Simulator.
	// <#FIXME#> Do not use localhost here, works only when using the Simulator.
	private let baseUrl    = NSURL(string: "http://localhost:8080")!

	// MARK: Methods

	private func storageUrl() -> NSURL {
		return baseUrl.URLByAppendingPathComponent("storage", isDirectory: true)
	}
}
