/**
	Class that acts as an interface to the web service API.
*/
public class PrivacyService {

	/**
		The base URL of the P-Service.
	*/
	let baseUrl: URL

	/**
		Initializes a `PrivacyService` instance.

		- parameters:
			- baseUrl: The base URL of the P-Service.
	*/
	public init(baseUrl: URL) {
		self.baseUrl = baseUrl
	}

}
