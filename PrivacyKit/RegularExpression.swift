import Foundation

infix operator =~: ComparisonPrecedence

/**
	Infix operator for testing if a string matches a regular expression.

	#### Example

	```swift
	let sentence = "The world is flat."
	if sentence =~ "^The" {
		// The sentence starts with "The"
	}
	```

	- parameters:
		- input: The string that should be tested.
		- pattern: The regular expression that should be used for testing.
*/
public func =~(input: String, pattern: String) -> Bool {
	return input =~ RegularExpression(pattern)!
}

/**
	Infix operator for testing if a string matches a regular expression.

	#### Example

	```swift
	let pattern = RegularExpression("^The")!
	let sentence = "The world is flat."
	if sentence =~ pattern {
		// The sentence starts with "The"
	}
	```

	- parameters:
		- input: The string that should be tested.
		- pattern: The regular expression that should be used for testing.
*/
public func =~(input: String, pattern: RegularExpression) -> Bool {
	return pattern.matches(input)
}

/**
	This class represents a compiled regular expression.

	- see:
		Taken from http://benscheirman.com/2014/06/regex-in-swift/
*/
public class RegularExpression {

	/// The internal representation of the regular expression
	private let internalExpression: NSRegularExpression

	/**
		Compile a regular expression.

		- note:
			Matching will be performed case insensitive.

		- returns:
			`nil` if the expression cannot be compiled, i.e. if it is invalid.
	*/
	public init?(_ pattern: String) {
		do {
			self.internalExpression = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
		} catch {
			return nil
		}
	}

	/**
		Tests if the regular expression matches a given string `input`.

		#### Example

		```swift
		let pattern = RegularExpression("^The")!
		let sentence = "The world is flat."
		if pattern.matches(sentence) {
			// The sentence starts with "The"
		}
		```

		- parameters:
			- input: The string that shall be tested.

		- returns:
			`true` if the expression matches the string, `false` otherwise.
	*/
	public func matches(_ input: String) -> Bool {
		let matches = self.internalExpression.matches(in: input, options: .reportCompletion, range: NSMakeRange(0, input.count))
		return matches.count > 0
	}

}
