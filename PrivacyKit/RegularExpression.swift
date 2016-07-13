//
//  RegularExpression.swift
//  PrivacyKit
//
//  Created by Maximilian Blochberger on 2016-07-13.
//  Copyright © 2016 Universität Hamburg. All rights reserved.
//

import Foundation

// Taken from http://benscheirman.com/2014/06/regex-in-swift/

infix operator =~ {}

func =~ (input: String, pattern: String) -> Bool {
	return RegularExpression(pattern)!.test(input)
}

class RegularExpression {
	let internalExpression: NSRegularExpression
	let pattern: String

	init?(_ pattern: String) {
		self.pattern = pattern
		do {
			self.internalExpression = try NSRegularExpression(pattern: pattern, options: .CaseInsensitive)
		} catch {
			return nil
		}
	}

	func test(input: String) -> Bool {
		let matches = self.internalExpression.matchesInString(input, options: NSMatchingOptions.ReportCompletion, range:NSMakeRange(0, input.characters.count))
		return matches.count > 0
	}
}