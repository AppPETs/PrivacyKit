#if os(iOS)
	import UIKit

	/**
		Platform-independent type alias: [`UIImage`](https://developer.apple.com/documentation/uikit/uiimage)
		on iOS and [`NSImage`](https://developer.apple.com/documentation/appkit/nsimage)
		on macOS.
	*/
	public typealias Image = UIImage

	/**
		Platform-independent type alias: [`UIImageView`](https://developer.apple.com/documentation/uikit/uiimageview)
		on iOS and [`NSImageView`](https://developer.apple.com/documentation/appkit/nsimageview)
		on macOS.
	*/
	public typealias ImageView = UIImageView
#endif // iOS

#if os(macOS)
	import AppKit

	/**
		Platform-independent type alias: [`UIImage`](https://developer.apple.com/documentation/uikit/uiimage)
		on iOS and [`NSImage`](https://developer.apple.com/documentation/appkit/nsimage)
		on macOS.
	*/
	public typealias Image = NSImage

	/**
		Platform-independent type alias: [`UIImageView`](https://developer.apple.com/documentation/uikit/uiimageview)
		on iOS and [`NSImageView`](https://developer.apple.com/documentation/appkit/nsimageview)
		on macOS.
	*/
	public typealias ImageView = NSImageView
#endif

import QRCode

/**
	This class can be used to share secrets with other devices. A cover image,
	that can be set using Interface builder will be displayed and the QR code
	will only be uncovered if the user taps or clicks on the image view and
	has authenticated himself.

	If the cover image is shown, then the user will be asked to authenticate
	himself as the owner of the device, e.g., by using Face/Touch ID or by
	asking for the device passcode. The authentication is performed by using
	the [`LocalAuthentication`](https://developer.apple.com/documentation/localauthentication)
	framework. Therefore the authentication credentials will be handled by the
	operating system an cannot be intercepted by the application.

	If the confidential value is shown, tapping on it will invalidate the
	authentication context. Therefore, in order to display the confidential
	value again, the user has to authenticate as the device owner anew.
*/
public class ConfidentialQrCodeView: ImageView {

	/**
		The image that should be displayed to the user if the confidential value
		is hidden. The image could describe the action the user has to perform
		in order to unhide the confidential value, e.g., "Tap to show secret."
	*/
	private var coverImage: Image? = nil

	/**
		The authentication context for displaying the confidential value. Once
		the confidential value is hidden again, the authentication context will
		be invalidated.
	*/
	private var context: AuthenticationContext? = nil

	/**
		Internal variable to keep track if the confidential value is displayed.
	*/
	private var isConfidentialValueDisplayed = false

	/**
		The confidential value in the format of a QR Code.
	*/
	public var qrCode: QRCode! = nil

	/**
		Initializes an `ImageView` from a coded state. For example, this is
		called if an `ImageView` was added via *Interface Builder*. The default
		image (e.g., as set in *Interface Builder*) is taken as the cover image.

		- parameters:
			- coder: The persisted state of the `ConfidentialImageView`.

		- returns:
			`nil` if `coder` does not contain a valid `ConfidentialImageView`.
	*/
	public required init?(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)

		coverImage = image

		#if os(iOS)
			isUserInteractionEnabled = true

			let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(toggleDisplayingConfidentialValue))
			tapGestureRecognizer.numberOfTapsRequired = 1
			tapGestureRecognizer.numberOfTouchesRequired = 1
			addGestureRecognizer(tapGestureRecognizer)
		#endif // iOS

		#if os(macOS)
			// <#TODO#> Untested.
			self.action = #selector(toggleDisplayingConfidentialValue)
			self.target = self
		#endif
	}

	/**
		Uncovers the confidential value.
	*/
	private func uncover() {
		DispatchQueue.main.async {
			self.image = self.qrCode.image
			self.isConfidentialValueDisplayed = true
		}
	}

	/**
		Shows an error dialog. The title of the dialog is "Authentication
		failed" and it can be dismissed by pressing/tapping "Ok".

		- parameters:
			- message: The error message.
	*/
	private func showError(message: String) {
		let title = "Authentication failed"

		#if os(iOS)
			let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
			alert.addAction(UIAlertAction(title: "Ok", style: .default))
			UIApplication.shared.keyWindow!.rootViewController!.present(alert, animated: true)
		#endif // iOS

		#if os(macOS)
			// <#TODO#> Untested.
			let alert = NSAlert()
			alert.addButton(withTitle: "Ok")
			alert.messageText = title
			alert.informativeText = message
			alert.alertStyle = .warning
			alert.beginSheetModal(for: NSApp.mainWindow!)
		#endif // macOS
	}

	/**
		Selector that is called upon tapping on the `ConfidentialImageView`. It
		toggles the confidential and the cover image.
	*/
	@objc
	private func toggleDisplayingConfidentialValue() {
		// <#TODO#> Hide the confidential value after a certain amount of time?

		if isConfidentialValueDisplayed {
			// Show cover image
			context?.invalidate()
			image = coverImage
			isConfidentialValueDisplayed = false
		} else {
			// Authenticate the user with FaceID or TouchID, if these methods
			// are available
			let reason = "You need to authenticate, in order to show the secret key."
			context = authenticateDeviceOwner(reason: reason) {
				authenticationError in

				// <#FIXME#> Why does an .invalidContext error sometimes occur here?
				guard authenticationError == nil else {
					// Ignored errors do not uncover the QR code.
					let ignoredAuthenticationErrors: [AuthenticationError] = [.systemCancel, .userCancel]
					if !ignoredAuthenticationErrors.contains(authenticationError!) {
						self.showError(message: authenticationError!.localizedDescription)
					}

					return
				}

				self.uncover()
			}
		}
	}

}
