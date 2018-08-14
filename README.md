# PrivacyKit

The `PrivacyKit` is a framework for iOS that provides functionality to handle personal information appropriately.

- Repository: https://github.com/AppPETs/PrivacyKit
- Issues: https://github.com/AppPETs/PrivacyKit/issues

The `PrivacyKit` API includes the API of other libraries that can be used if more specific functionality is required:
- Cryptography: [Tafelsalz](https://blochberger.github.io/Tafelsalz)
- Keychain Services: [Keychain](https://blochberger.github.io/Keychain)

A proof-of-concept Implementation of privacy services can be found at https://gitlab.prae.me/blochberger/PrivacyService

## Usage

Assuming you have a Git repository for your project, than you can use the
`PrivacyKit` framework by adding it as a submodule:

```sh
git submodule add https://github.com/AppPETs/PrivacyKit/issues
git submodule update --init --recursive # This will also fetch dependencies
```

Then open your applications Xcode project and drag and drop the
`PrivacyKit.xcodeproj` into it. In the project and under Embedded Frameworks add
the `PrivacyKit.framework`.
