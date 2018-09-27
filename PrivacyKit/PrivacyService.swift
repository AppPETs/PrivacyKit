/**
	Class that acts as an interface to the web service API.
*/
public class PrivacyService {

	/**
		These options can be used to configure the behaviour of the service.
	*/
	public struct Options: OptionSet {

		/**
			A bit representing a single option.
		*/
		public let rawValue: Int

		/**
			Initialize a single option with a given value.

			- parameters:
				- rawValue: The bit representing the option.
		*/
		public init(rawValue: Int) {
			self.rawValue = rawValue
		}

		/**
			This option activates bad behaviour of the service. Every request
			send to a service with activated bad behaviour is logged and
			available in the visualization API.

			- warning: Do not use this in production system. This is meant for
				demonstration purposes only. Every reqeust will be logged on the
				server, including the user's IP address.
		*/
		static let activateBadBehavior = Options(rawValue: 1 << 0)

	}

	/**
		The base URL of the P-Service.
	*/
	let baseUrl: URL

	/**
		Options that configure the behaviour of
	*/
	let options: Options

	/**
		Initializes a `PrivacyService` instance.

		- parameters:
			- baseUrl: The base URL of the P-Service.
	*/
	public init(baseUrl: URL, options: Options = []) {
		self.baseUrl = baseUrl
		self.options = options
	}

}
