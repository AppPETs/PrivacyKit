#if os(iOS)
	import UIKit
#endif // iOS

/**
	A class that wraps access to indicators, such as network activity.
*/
public class Indicators {

	/**
		Shows the network activity indicator in the status bar (iOS).

		This function is thread safe.
	
		- note:
			This function does nothing on macOS.
	*/
	public static func showNetworkActivity() {
		#if os(iOS)
			DispatchQueue.main.async {
				UIApplication.shared.isNetworkActivityIndicatorVisible = true
			}
		#endif // iOS
	}

	/**
		Hides the network activity indicator in the status bar (iOS).

		This function is thread safe.
	
		- note:
			This function does nothing on macOS.
	*/
	public static func hideNetworkActivity() {
		#if os(iOS)
			DispatchQueue.main.async {
				UIApplication.shared.isNetworkActivityIndicatorVisible = false
			}
		#endif // iOS
	}
}
