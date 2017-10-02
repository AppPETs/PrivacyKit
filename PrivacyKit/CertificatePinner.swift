import Foundation

#if os(iOS)
	import UIKit
#endif // iOS

#if os(OSX)
	import AppKit
#endif // macOS

/**
	This class is used to pin certificates to a specific hosts. Certificate
	pinning avoids domain takeover or man-in-the-middle attacks with
	certificates that are considered trusted by the device, either by a
	compromised certificate authority or by a self-signed certificate marked as
	trusted.

	## Example

	Assuming the host is `www.example.com`:

	```swift
	let certificatePinner = CertificatePinner(forHost: "www.example.com")!
	let session = URLSession(
	    configuration: URLSessionConfiguration.defaultSessionConfiguration(),
	    delegate:      certificatePinner,
	    delegateQueue: nil
	)
	// Continue like you would with URLSession
	```

	- see:
		Discussions on how to implement certificate pinning on iOS / in Swift:
		- [Certificate and Public Key Pinning / iOS][1]
		- [iOS certificate pinning with Swift and NSURLSession][2]

	- todo:
		- Maybe consider [TrustKit][3]?
		- Maybe enable to use TOFU?

	[1]: https://www.owasp.org/index.php/Certificate_and_Public_Key_Pinning#iOS
	[2]: http://stackoverflow.com/a/34223292/5082444
	[3]: https://datatheorem.github.io/TrustKit/
*/
class CertificatePinner : NSObject, URLSessionDelegate {

	// MARK: Initializers

	/**
		Initialize a `CertificatePinner` instance for a given host `forHost`.

		The certificate for the host is read from the asset catalogue. The name
		of the asset needs to be exactly like the name of the host provided,
		e.g. `www.example.com`. If a certificate is used for multiple hosts, a
		starred name should be provided, such as `*.example.com`.

		The stored certificates are in binary DER format. If you have a
		certificate in PEM format, you can convert it by using the following
		command, assuming the host is `www.example.com`:

		```sh
		openssl x509 -in www.example.com.crt -outform der www.example.com.der
		```

		- parameter host:
			The name of the host, for which the certificate should be pinned,
			e.g. `www.example.com`.

		- returns:
			`nil` if no certificate is found in the asset catalogue.
	*/
	init?(forHost host: String) {

		guard let pinnedServerCertificate = NSDataAsset(name: NSDataAsset.Name(rawValue: host), bundle: PrivacyKit.bundle())?.data else {
			print("No pinned certificate for host in resources: \(host)")
			return nil
		}

		self.pinnedServerCertificate = pinnedServerCertificate
	}

	// MARK: URLSessionDelegate

	/**
		`URLSessionDelegate` implementation that validates the certificate
		used by the server and compares it to the pinned certificate. Connection
		will be refused if the certificates do not match.

		- see:
			Official documentation:
			- [`URLSessionDelegate`][1]
			- [`URLSession` delegate][2] (Parameters are quoted from there.)

		- parameter session:
			The session containing the task that requested authentication.

		- parameter didReceiveChallenge:
			An object that contains the request for authentication.

		- parameter completionHandler:
			A handler that your delegate method must call. Its parameters are:

			• `disposition` — One of several constants that describes how the
			  challenge should be handled.

			• `credential` — The credential that should be used for
			  authentication if disposition is
			  `NSURLSessionAuthChallengeUseCredential`, otherwise `nil`.

		[1]: https://developer.apple.com/reference/foundation/urlsessiondelegate
		[2]: https://developer.apple.com/reference/foundation/urlsessiondelegate/1409308-urlsession
	*/
	func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {

		guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
			// Don't handle other challenges, such as client certificates
			completionHandler(.performDefaultHandling, nil)
			return
		}

		guard let serverTrust = challenge.protectionSpace.serverTrust else {
			pinningFailed(completionHandler)
			return
		}

		var trustResult: SecTrustResultType = .invalid
		let trustStatus = SecTrustEvaluate(serverTrust, &trustResult)

		guard trustStatus == errSecSuccess else {
			pinningFailed(completionHandler)
			return
		}

		guard let serverCertificate = SecTrustGetCertificateAtIndex(serverTrust, 0) else {
			pinningFailed(completionHandler)
			return
		}

		let serverCertificateDataRef = SecCertificateCopyData(serverCertificate)
		let serverCertificateData = Data(bytes: CFDataGetBytePtr(serverCertificateDataRef), count: CFDataGetLength(serverCertificateDataRef))

		if !serverCertificateData.elementsEqual(pinnedServerCertificate) {
			pinningFailed(completionHandler)
			return
		}

		pinningSucceeded(withServerTrust: serverTrust, completionHandler)
	}

	// MARK: - Private

	// MARK: Constants

	/**
		Contains the binary server certificate in DER format.
	*/
	private let pinnedServerCertificate: Data

	// MARK: Methods

	/**
		Convenience method to signal that pinning has failed, by canceling the
		authentication challenge with the `completionHandler` passed to
		`URLSession(_:didReceive:completionHandler:)`. This will drop the
		session and cancel the request.

		- see:
			Official Documentation:
			- [`URLSessionDelegate`][1]
			- [`URLSession` delegate][2] (The `completionHandler` parameter is
			  quoted from there.)

		- parameter completionHandler:
			A handler that your delegate method must call. Its parameters are:

			• `disposition` — One of several constants that describes how the
			  challenge should be handled.

			• `credential` — The credential that should be used for
			  authentication if disposition is
			  `NSURLSessionAuthChallengeUseCredential`, otherwise `nil`.

		[1]: https://developer.apple.com/reference/foundation/urlsessiondelegate
		[2]: https://developer.apple.com/reference/foundation/urlsessiondelegate/1409308-urlsession

	*/
	private func pinningFailed(_ completionHandler: (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
		completionHandler(.cancelAuthenticationChallenge, nil)
	}

	/**
		Convenience method to signal that pinning has succeeded and continue by
		passing the explicit `serverTrust` to the `completionHandler`, which is
		originally passed to `URLSession(_:didReceive:completionHandler:)`.

		- see:
			Official Documentation:
			- [`URLSessionDelegate`][1]
			- [`URLSession` delegate][2] (The `completionHandler` parameter is
			  quoted from there.)
			- [`URLCredential`][3] (The `serverTrust` parameter is quoted from
			  there.)

		- parameter serverTrust: The accepted trust.

		- parameter completionHandler:
			A handler that your delegate method must call. Its parameters are:

			• `disposition` — One of several constants that describes how the
			  challenge should be handled.

			• `credential` — The credential that should be used for
			  authentication if disposition is
			  `NSURLSessionAuthChallengeUseCredential`, otherwise `nil`.

		[1]: https://developer.apple.com/reference/foundation/urlsessiondelegate
		[2]: https://developer.apple.com/reference/foundation/urlsessiondelegate/1409308-urlsession
		[3]: https://developer.apple.com/reference/foundation/urlcredential/1413935-init
	*/
	private func pinningSucceeded(withServerTrust serverTrust: SecTrust, _ completionHandler: (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
		completionHandler(.useCredential, URLCredential(trust: serverTrust))
	}

}
