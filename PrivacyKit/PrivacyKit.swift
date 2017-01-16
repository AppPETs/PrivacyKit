//
//  PrivacyKit.swift
//  PrivacyKit
//
//  Created by Maximilian Blochberger on 2016-07-15.
//  Copyright © 2016 Universität Hamburg. All rights reserved.
//

import Foundation

/**
	Internal helper class for framework specific tasks.
*/
class PrivacyKit {

	/**
		The bundle ID of the framework.

		- todo:
			Find the bundle ID programmatically.
	*/
	static let bundleId = "de.uni-hamburg.informatik.PrivacyKit"

	/**
		Returns the framework's bundle. This is required to access asset
		catalogues which are compiled into the framework.

		- returns:
			The bundle for the `PrivacyKit` framework.
	*/
	static func bundle() -> Bundle {
		return Bundle(identifier: PrivacyKit.bundleId)!
	}

}
