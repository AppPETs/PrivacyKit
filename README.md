# PrivacyKit

[![Build Status](https://travis-ci.org/AppPETs/PrivacyKit.svg?branch=master)](https://travis-ci.org/AppPETs/PrivacyKit) [![Coverage](https://apppets.github.io/PrivacyKit/macos/coverage.svg)](https://apppets.github.io/PrivacyKit/macos/coverage/index.html) [![Documentation](https://apppets.github.io/PrivacyKit/macos/public/badge.svg)](https://apppets.github.io/PrivacyKit)

The `PrivacyKit` is a framework for iOS that provides functionality to handle personal information appropriately.

- Repository: https://github.com/AppPETs/PrivacyKit
- Documentation: https://apppets.github.io/PrivacyKit
  - macOS: [public](https://apppets.github.io/PrivacyKit/macos/public), [internal](https://apppets.github.io/PrivacyKit/macos/internal), [private](https://apppets.github.io/PrivacyKit/macos/private)
  - iOS: [public](https://apppets.github.io/PrivacyKit/iphone/public), [internal](https://apppets.github.io/PrivacyKit/iphone/internal), [private](https://apppets.github.io/PrivacyKit/iphone/private)
- Issues: https://github.com/AppPETs/PrivacyKit/issues

The `PrivacyKit` API includes the API of other libraries that can be used if more specific functionality is required:
- Cryptography: [Tafelsalz](https://blochberger.github.io/Tafelsalz)
- Keychain Services: [Keychain](https://blochberger.github.io/Keychain)

A proof-of-concept Implementation of privacy services can be found at https://github.com/AppPETs/PrivacyService

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
