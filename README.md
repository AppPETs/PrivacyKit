# PrivacyKit

The `PrivacyKit` is a framework for iOS that provides functionality to handle
personal information appropriately.

- Repository: https://gitlab.prae.me/apppets/PrivacyKit
- Issues: https://gitlab.prae.me/apppets/PrivacyKit/issues

The `PrivacyKit` API includes the API of other libraries that can be used if more specific functionality is required: 
- Cryptography: [Tafelsalz](https://blochberger.github.io/Tafelsalz)
- Keychain Services: [Keychain](https://blochberger.github.io/Keychain)

## Usage

Assuming you have a Git repository for your project, than you can use the
`PrivacyKit` framework by adding it as a submodule:

```sh
git submodule add https://gitlab.prae.me/blochberger/PrivacyKit.git
git submodule update --init --recursive # This will also fetch dependencies
```

Then open your applications Xcode project and drag and drop the
`PrivacyKit.xcodeproj` into it. In the project and under Embedded Frameworks add
the `PrivacyKit.framework`.

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

The `CertificatePinner` is an `URLSessionDelegate` and can be used like
follows:

```swift
let session = URLSession(
	configuration: URLSessionConfiguration.default,
	delegate:      certificatePinner,
	delegateQueue: nil
)
```

[P-Service]: https://gitlab.prae.me/blochberger/PrivacyService
