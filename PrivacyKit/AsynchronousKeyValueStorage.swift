/**
	A key-value store that supports asynchronous requests. Two basic functions
	are offered which can be used to store and retrieve values for a given key.

	## Example

	```swift
	class MyKeyValueStorage : AsynchronousKeyValueStorage {
	    typealias KeyType   = String
	    typealias ValueType = Data
	    typealias ErrorType = String
	    func store(
	        value:             ValueType,
	        forKey key:        KeyType,
	        finishedWithError: @escaping (_ error: ErrorType?) -> Void
	    ) {
	        // TODO Store the value
	        // If an error occurs, report and back out early
			finishedWithError("Error description")
			return
	        // If everything goes smoothly, signal success
	        finishedWithError(nil)
	    }
	    func retrieveValue(
	        forKey key:     KeyType,
	        valueAvailable: @escaping (_ value: ValueType?, _ error: ErrorType?) -> Void
	    ) {
	        // TODO Retrieve the value
	        // If an error occurs, report and back out early
			valueAvailable(nil, "Error description")
			return
	        // If everything goes smoothly, return value and signal success
	        valueAvailable(value, nil)
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

		## Example

		```swift
		storage.store(value: value, forKey: key) {
		    optionalError in
		    if let error = optionalError {
		        // TODO Handle error
		    }
		}
		```

		- parameter value:
			The asset that should be stored.

		- parameter forKey:
			The key that identifies the `value` uniquely.

		- parameter finishedWithError:
			A function that is called after the `value` is stored. Upon success
			`error` is `nil` and if the asset could not be stored, `error`
			then contains a desriptive error message explaining the reason.
	*/
	func store(value: ValueType, forKey key: KeyType, finishedWithError: @escaping (_ error: ErrorType?) -> Void)

	/**
		Retrieves data for key `forKey` asynchronously.

		## Example

		```swift
		storage.retrieveValue(forKey: key) {
		    optionalValue, optionalError in
		    // Assert postcondition
		    assert((optionalValue == nil) != (optionalError == nil), "Postcondition failed")
		    if let error = optionalError {
		        // TODO Handle error
		        return
		    }
		    let value = optionalValue!
		    // Do something with the retrieved value
		}
		```

		- postcondition:
			In `valueAvailable` either `value` is `nil` or `error` is `nil` but
			not both at the same time.

			```swift
			assert((value == nil) != (error == nil), "Postcondition failed")
			```

		- parameter forKey:
			The key that identifies the value that should be retrieved.

		- parameter valueAvailable:
			A function that is called when the asset for the identifier `key`
			was retrieved. The parameter `value` then contains the actual asset
			upon success and is `nil` if the asset could not be retrieved.
			An explanatory reason is then provided through the parameter `error`
			which is `nil` upon success respectively.
	*/
	func retrieveValue(forKey key: KeyType, valueAvailable: @escaping (_ value: ValueType?, _ error: ErrorType?) -> Void)

}
