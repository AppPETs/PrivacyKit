//
//  AsynchronousKeyValueStorage.swift
//  PrivacyKit
//
//  Created by Maximilian Blochberger on 2016-07-13.
//  Copyright © 2016 Universität Hamburg. All rights reserved.
//

/**
	A key-value store that supports asynchronous requests. Two basic functions
	are offered which can be used to store and retrieve values for a given key.

	#### Example:
	```swift
	class MyKeyValueStorage : AsynchronousKeyValueStorage {
	    typealias KeyType   = String
	    typealias ValueType = NSData
	    typealias ErrorType = String
	    func storeValue(value: ValueType, forKey key: KeyType, finishedWithError: (error: ErrorType?) -> Void) {
	        // TODO Store the value
	        // If an error occurs, report and back out early
	        finishedWithError(error: "Error description")
	        return
	        // If everything goes smoothly, signal success
	        finishedWithError(error: nil)
	    }
	    func retrieveValueForKey(key: KeyType, valueAvailable: (value: ValueType?, error: ErrorType?) -> Void) {
	        // TODO Retrieve the value
	        // If an error occurs, report and back out early
	        valueAvailable(value: nil, error: "Error description")
	        return
	        // If everything goes smoothly, return value and signal success
	        valueAvailable(value: value: error: nil)
	    }
	}
	```
*/
public protocol AsynchronousKeyValueStorage {

	/**
		The type that should be used for identifiers of stored assets.
	*/
	associatedtype KeyType

	/**
		The type that should be used for stored assets.
	*/
	associatedtype ValueType

	/**
		The type that should be used for signaling errors.
	*/
	associatedtype ErrorType

	/**
		Stores an asset `value` for an identifier `forKey` asynchronously.

		#### Example:
		```swift
		storage.storeValue(value, forKey: key) {
		    optionalError in
		    if let error = optionalError {
		        // TODO Handle error
		    }
		}
		```

		- Parameters:

		  - value:
		    The asset that should be stored.

		  - forKey:
		    The key that identifies the `value` uniquely.

		  - finishedWithError:
		    A function that is called after the `value` is stored. Upon success
		    `error` is **`nil`** and if the asset could not be stored, `error`
		    then contains a desriptive error message explaining the reason.
	*/
	func storeValue(value: ValueType, forKey key: KeyType, finishedWithError: (error: ErrorType?) -> Void)


	/**
		Retrieves data for key `key` asynchronously.

		#### Example:
		```swift
		storage.retrieveValueForKey(key) {
		    optionalValue, optionalError in
		    // Assert postcondition
		    assert((optionalValue == nil) != (optionalError == nil))
		    if let error = optionalError {
		        // TODO Handle error
		        return
		    }
		    let value = optionalValue!
		    // Do something with the retrieved value
		}
		```

		- Postcondition:
		In `valueAvailable` either `value` is **`nil`** or `error` is
		**`nil`** but not both at the same time.
		````
		assert((value == nil) != (error == nil))
		````

		- Parameters:

		  - key:
		  The key that identifies the data value that should be retrieved.

		  - valueAvailable:
		  A function that is called when the asset for the identifier `key`
		  was retrieved. The parameter `value` then contains the actual asset
		  upon success and is **`nil`** if the asset could not be retrieved.
		  An explanatory reason is then provided through the parameter `error`
		  which is **`nil`** upon success respectively.
	*/
	func retrieveValueForKey(key: KeyType, valueAvailable: (value: ValueType?, error: ErrorType?) -> Void)
}
