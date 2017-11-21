#if os(iOS)
	import UIKit

	public typealias Image = UIImage
	public typealias ImageView = UIImageView
#endif // iOS

#if os(macOS)
	import AppKit

	public typealias Image = NSImage
	public typealias ImageView = NSImageView
#endif

import QRCode

/**
	This class can be used to share secrets with other devices. A cover image,
	that can be set using Interface builder will be displayed and the QR code
	will only be uncovered if the user taps or clicks on the image view and
	has authenticated himself.
*/
public class ConfidentialQrCodeView: ImageView {

	private var coverImage: Image? = nil

	private var context: AuthenticationContext? = nil
	private var isConfidentialValueDisplayed = false
	public var qrCode: QRCode! = nil

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

	private func uncover() {
		DispatchQueue.main.async {
			self.image = self.qrCode.image
			self.isConfidentialValueDisplayed = true
		}
	}

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

	@objc
	private func toggleDisplayingConfidentialValue() {
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
