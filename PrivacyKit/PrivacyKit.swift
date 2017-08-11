import Foundation

/**
	Internal helper class for framework specific tasks.
*/
class PrivacyKit {

	#if os(iOS)
		/**
			The bundle ID of the framework.

			- todo:
				Find the bundle ID programmatically.
		*/
		static let bundleId = "de.uni-hamburg.informatik.PrivacyKit.iOS"
	#endif // iOS

	#if os(OSX)
		/**
			The bundle ID of the framework.

			- todo:
				Find the bundle ID programmatically.
		*/
		static let bundleId = "de.uni-hamburg.informatik.PrivacyKit.macOS"
	#endif // macOS

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
