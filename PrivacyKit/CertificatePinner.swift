//
//  CertificatePinner.swift
//  PrivacyKit
//
//  Created by Maximilian Blochberger on 2016-07-15.
//  Copyright © 2016 Universität Hamburg. All rights reserved.
//

import Foundation

/**
	This class is used to pin certificates to a specific hosts.

	- Seealso:
		[Certificate and Public Key Pinning / iOS](https://www.owasp.org/index.php/Certificate_and_Public_Key_Pinning#iOS),
		[iOS certificate pinning with Swift and NSURLSession](http://stackoverflow.com/a/34223292/5082444)

	- Todo:
		Maybe consider [TrustKit](https://datatheorem.github.io/TrustKit/)?

*/
class CertificatePinner : NSObject, NSURLSessionDelegate {

	// MARK: Initializers
	
	init?(forHost host: String) {

		guard let pinnedServerCertificate = NSDataAsset(name: host, bundle: PrivacyKit.bundle())?.data else {
			print("No pinned certificate for host in resources: \(host)")
			return nil
		}

		self.pinnedServerCertificate = pinnedServerCertificate
	}

	// MARK: NSURLSessionDelegate

	func URLSession(session: NSURLSession, didReceiveChallenge challenge: NSURLAuthenticationChallenge, completionHandler: (NSURLSessionAuthChallengeDisposition, NSURLCredential?) -> Void) {

		guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
			// Don't handle other challenges, such as client certificates
			completionHandler(.PerformDefaultHandling, nil)
			return
		}

		guard let serverTrust = challenge.protectionSpace.serverTrust else {
			pinningFailed(completionHandler)
			return
		}

		var trustResult = SecTrustResultType(kSecTrustResultInvalid)
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
		let serverCertificateData = NSData(bytes: CFDataGetBytePtr(serverCertificateDataRef), length: CFDataGetLength(serverCertificateDataRef))

		if !serverCertificateData.isEqualToData(pinnedServerCertificate) {
			pinningFailed(completionHandler)
			return
		}

		pinningSucceededForServerTrust(serverTrust, completionHandler)
	}

	// MARK: - Private

	// MARK: Constants

	private let pinnedServerCertificate: NSData

	// MARK: Methods

	private func pinningFailed(completionHandler: (NSURLSessionAuthChallengeDisposition, NSURLCredential?) -> Void) {
		completionHandler(.CancelAuthenticationChallenge, nil)
	}

	private func pinningSucceededForServerTrust(serverTrust: SecTrust, _ completionHandler: (NSURLSessionAuthChallengeDisposition, NSURLCredential?) -> Void) {
		completionHandler(.UseCredential, NSURLCredential(forTrust: serverTrust))
	}

}
