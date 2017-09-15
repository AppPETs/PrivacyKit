/**
	Internal class that acts as an interface to the web service API.
*/
public class PrivacyService {

	let baseUrl: URL

	/**
		Initializes a `PrivacyService` instance.
	*/
	init(baseUrl: URL) {
		self.baseUrl = baseUrl
	}

}
