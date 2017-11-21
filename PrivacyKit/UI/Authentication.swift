import LocalAuthentication

/**
	A context for which the authentication is valid.

	The context should be invalidated by calling [`invalidate()`](https://developer.apple.com/documentation/localauthentication/lacontext/1514192-invalidate)
	as soon as it is no longer required. All outstanding authentications for
	this context will be cancelled.

	- see:
		[`LAContext`](https://developer.apple.com/documentation/localauthentication/lacontext)
*/
public typealias AuthenticationContext = LAContext

/**
	Errors that might arise during authentication.
*/
public enum AuthenticationError: Error {

	/**
		The user did not enter the correct credentials.
	*/
	case authenticationFailed

	/**
		The authentication context is invalid.
	*/
	case invalidContext

	/**
		There is no passcode set for the device and therefore the authentication
		mechanism is not present. A custom authentication function could be
		offered, e.g., by storing a password by using `HashedPassword`.
	*/
	case passcodeNotSet

	/**
		The OS cancelled the authentication, e.g., because another app moved
		into the foreground. Displaying an error message in this case might not
		be neccessary, see if it can be handled like `.userCancel`.
	*/
	case systemCancel

	/**
		The user cancelled the authentication. Avoid displaying error messages
		in this case and try to handle this gracefully.
	*/
	case userCancel

	/**
		The user was not able to authenticate via Touch ID or Face ID for three
		subsequent attempts.
	*/
	case tooManyFailedAttempts
}

/**
	Challenges the user to authenticate as the device owner. Biometric
	authentication (Face ID or Touch ID) is tried first if available and
	passcode authentication is used as a fallback.

	#### Example

	```swift
	context = authenticateDeviceOwner(reason: "Unlock something") {
	    authenticationError in

	    guard authenticationError == nil else {
	        // Failed to authenticate (the user just might have cancelled)
	        // TODO: Handle error
	        return
	    }

	    // Successfully authenticated
	    unlockSomething()
	}
	```

	- note:
		In order to use Face ID, add [`NSFaceIDUsageDescription`][https://developer.apple.com/library/content/documentation/General/Reference/InfoPlistKeyReference/Articles/CocoaKeys.html#//apple_ref/doc/uid/TP40009251-SW75]
		to your [`Info.plist`][https://developer.apple.com/library/content/documentation/General/Reference/InfoPlistKeyReference/Introduction/Introduction.html#//apple_ref/doc/uid/TP40009248-SW1].

	- parameters:
		- reason: The reason describing the purpose of the authentication.
		- completion: A function that is called after the authentication
			finished (not neccessarily successfully).
		- authenticationError: Upon successful authentication this is `nil` else
			it contains the cause for failure.

	- returns:
		The authentication context.
*/
public func authenticateDeviceOwner(
	reason: String,
	completion: @escaping (_ authenticationError: AuthenticationError?) -> Void
) -> AuthenticationContext {
	let context = AuthenticationContext()

	context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) {
		success, error in

		guard success else {
			switch error! {
				case LAError.authenticationFailed: completion(.authenticationFailed)
				case LAError.appCancel:            fatalError() // When does this happen?
				case LAError.invalidContext:       completion(.invalidContext)
				case LAError.notInteractive:       fatalError() // When does this happen?
				case LAError.passcodeNotSet:       completion(.passcodeNotSet)
				case LAError.systemCancel:         completion(.systemCancel)
				case LAError.userCancel:           completion(.userCancel)
				case LAError.biometryLockout:      completion(.tooManyFailedAttempts)
				case LAError.userFallback:         fatalError() // No fallback, policy falls back automatically
				case LAError.biometryNotEnrolled:  fatalError() // Policy falls back automatically
				case LAError.biometryNotAvailable: fatalError() // Policy falls back automatically
				default:                           fatalError("UNREACHABLE")
			}
			return
		}

		completion(nil)
	}

	return context
}
