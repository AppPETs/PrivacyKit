//
//  RegularExpression.swift
//  PrivacyKit
//
//  Created by Maximilian Blochberger on 2016-07-13.
//  Copyright © 2016 Universität Hamburg. All rights reserved.
//

import Foundation

infix operator =~ {}

/**
	Infix operator for testing if a string matches a regular expression.

	#### Example
	```swift
	let sentence = "The world is flat."
	if sentence =~ "^The" {
	    // The sentence starts with "The"
	}
	```

	- see:
		`RegularExpression`

	- parameter input:
		The string that should be tested.

	- parameter pattern:
		The regular expression that should be used for testing.
*/
func =~ (input: String, pattern: String) -> Bool {
	return RegularExpression(pattern)!.test(input)
}

/**
	This class represents a compiled regular expression.

	- see:
		Taken from http://benscheirman.com/2014/06/regex-in-swift/
*/
class RegularExpression {

	/// The internal representation of the regular expression
	let internalExpression: NSRegularExpression

	/**
		Compile a regular expression.

		- note:
			Matching will be performed case insensitive.

		- returns:
			`nil` if the expression cannot be compiled, i.e. if it is invalid.
	*/
	init?(_ pattern: String) {
		do {
			self.internalExpression = try NSRegularExpression(pattern: pattern, options: .CaseInsensitive)
		} catch {
			return nil
		}
	}

	/**
		Tests if the regular expression matches a given string `input`.

		- parameter input:
			The string that shall be tested.

		- returns:
			`true` if the expression matches the string, `false` otherwise.
	*/
	func test(input: String) -> Bool {
		let matches = self.internalExpression.matchesInString(input, options: NSMatchingOptions.ReportCompletion, range:NSMakeRange(0, input.characters.count))
		return matches.count > 0
	}

}
