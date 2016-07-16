# PrivacyKit

The `PrivacyKit` is a framework for iOS that provides functionality to handle
personal information appropriately.

This is a demonstrator project and contains an implementation of a secure remote
storage as provided by [`PrivacyService`][P-Service].

## Usage

Assuming you have a Git repository for your project, than you can use the
`PrivacyKit` framework by adding it as a submodule:

```sh
git submodule add https://gitlab.prae.me/blochberger/PrivacyKit.git
git submodule update --init --recursive # This will also fetch Sodium
```

Then open your applications Xcode project and drag and drop the
`PrivacyKit.xcodeproj` into it. In the project and under Linked Frameworks and
Libraries add the `PrivacyKit.framework`.

Then you can use the `SecureRemoteStorage` as in the following snippet:

```swift
let storage = SecureRemoteStorage()!

// Store a key-value pair securely
let key = "My PIN"
let value = "1234".dataUsingEncoding(NSUTF8StringEncoding)!
storage.storeValue(value, forKey: key) {
	optionalError in

	if let error = optionalError {
		print("ERROR: \(error)")
	}
}

// Retrieve a key-value pair securely
storage.retrieveValueForKey(key) {
	optionalValue, optionalError in

	// Assert postcondition
	assert((optionalValue == nil) != (optionalError == nil))

	if let error = optionalError {
		print("ERROR: \(error)")
		return
	}

	let retrievedValue = optionalValue!

	// Do something with the retrieved Value
	print(retrievedValue) // Will print "1234"
}
```

Note that the `SecureRemoteStorage` protocol is asynchronous and you might need
to handle your data in a specific thread, i.e. the UI thread.

Also note that if you are using the [`PrivacyService`][P-Service] with a
self-signed certificate, the certificate needs to be added to the trust store of
your iOS device or simulator.
Even though the certificate is pinned it is not trusted, i.e. signed by a
trusted root Certificate Authority (CA).

In order to mark a certificate as trusted, get the `privacyservice.test.crt`
file onto the device or simulator and open it. The Settings application will
guide you through the steps to install the certificate (which is called
"Profile" there).

Please use self-signed certificates only in development environments.

## Notes for `PrivacyKit` Developers

### Certificate Pinning of a [`PrivacyService`][P-Service]

Assuming the certificate of the service is `privacyservice.test.crt` and the
domain of the service is `privacyservice.test`. Further assuming that the
certificate is stored in PEM format, then it needs to be converted to DER
format, i.e. with the following command:

```sh
openssl x509 -in privacyservice.test.crt -outform der -out privacyservice.test.der
```

Then drag and drop the file `privacyservice.test.der` into the
`PinnedCertificates` folder in the `Assets.xcassets` asset catalogue of
`PrivacyKit`. The assets name will not contain the `.der` suffix and therefore
be equal to the host name of the `PrivacyService` behind the certificate.
This certificate can now be pinned with the help of the `CertificatePinner` by
simply instantiating it like follows:

```swift
let certificatePinner = CertificatePinner(forHost: "privacyservice.test")
```

The `CertificatePinner` is an `NSURLSessionDelegate` and can be used like
follows:

```swift
let session = NSURLSession(configuration: NSURLSessionConfiguration.defaultSessionConfiguration(), delegate: certificatePinner, delegateQueue: nil)
```

[P-Service]: https://gitlab.prae.me/blochberger/PrivacyService-Qt
