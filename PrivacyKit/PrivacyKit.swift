//
//  PrivacyKit.swift
//  PrivacyKit
//
//  Created by Maximilian Blochberger on 2016-07-15.
//  Copyright © 2016 Universität Hamburg. All rights reserved.
//

import Foundation

class PrivacyKit {

	// TODO Find bundle ID programmatically
	static let bundleId = "de.uni-hamburg.informatik.PrivacyKit"
	
	static func bundle() -> NSBundle {
		return NSBundle(identifier: PrivacyKit.bundleId)!
	}

}
