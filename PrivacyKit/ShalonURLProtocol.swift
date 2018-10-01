/**
	A [`URLProtocol`](https://developer.apple.com/documentation/foundation/urlprotocol)
	that adds support for Shalon by specifying URLs in the following format:
	`httpss://proxy:port/target:port/index.html`. To use more than one proxy
	(up to three), e.g., use `httpssss://proxy1/proxy2/proxy3/target/index.html`
	for connecting via three proxies.

	In order to support the protocol, it needs to be added to the
	`URLSessionConfiguration` first:

	```swift
	let configuration = URLSessionConfiguration.ephemeral
	configuration.protocolClasses?.append(ShalonURLProtocol.self)
	```

	## Examples

	```swift
	let configuration = URLSessionConfiguration.ephemeral
	configuration.protocolClasses?.append(ShalonURLProtocol.self)

	let session = URLSession(configuration: configuration)
	let url = URL(string: "httpss://shalon1.jondonym.net/example.com/")!
	let task = session.dataTask(with: url) {
	    optionalUrl, optionalResponse, optionalError in

	    // Handle response
	}
	```
*/
public class ShalonURLProtocol : URLProtocol {

	/**
		Errors that occur while parsing a Shalon URL.
	*/
	enum ParseError : Error {

		/**
			If this error occurs, too few proxies where specified in a Shalon
			URL. The URL `httpss://example.com/` will yield such an error, as
			there is only the target `example.com` given, but no proxy.
		*/
		case tooFewProxies

		/**
			If this error occurs, a proxy specification within an URL is
			invalid. The URL `httpsss://proxy1/proxy2:/example.com/` will yield
			such an error, as there is no port after the second proxy. An
			invalid IPv6 address, e.g., due to missing brackets will also lead
			to this error.
		*/
		case incorrectProxySpecification
	}

	/**
		An internal struct that keeps parameters, which will be used for
		establishing a connection via Shalon proxies.
	*/
	struct Parameters {

		/**
			A list of proxies to be connected to.
		*/
		let proxies: [Target]

		/**
			The request URL, which should be issued through the Shalon tunnel.
		*/
		let requestUrl: URL
	}

	/**
		This indicates if loading should stop.
	*/
	private var loadingShouldStop: Bool = false

	/**
		Parse a URL and return parameters that can be used for `Shalon`.

		- parameters:
			- url: The URL.

		- returns: Shalon parameters, `nil` if the URL does not match the
			specified format.

		- throws:
			Throws if there are not enough proxies specified. The amount of
			proxies is determined by the amount of `s`' in the URL schema.
			Throws also if a proxy is invalid, e.g., with an invalid hostname.
	*/
	static func parseShalonParams(from url: URL) throws -> Parameters? {
		var numProxies: Int
		var shalonProxies: [Target] = []

		let urlScheme = url.scheme!.lowercased()
		let sCount = urlScheme[urlScheme.range(of: "http")!.upperBound...].count

		// 1 to 3 proxies (httpss:// to httpssss://) supported
		guard (2...4).contains(sCount) else {
			return nil
		}

		numProxies = sCount - 1

		let urlString = url.absoluteString
		// The URL string, withouth the scheme part!
		let baseString = urlString[urlString.range(of: "://")!.upperBound...]
		// Examples:
		//   httpss://proxy:port/destination:port/index.html
		//   httpsss://proxy1:port/proxy2:port/destination:port/test.txt
		let components = baseString.components(separatedBy: "/")
		guard components.count > numProxies else {
			throw ParseError.tooFewProxies
		}

		for i in 0..<numProxies {
			let ithProxy: String = components[i]

			var proxyInfo = ithProxy.components(separatedBy: ":")

			let proxyPort = UInt16(proxyInfo.last!)

			if proxyPort != nil {
				proxyInfo.removeLast()
			}

			/*
				If it's an IPv4 address or domain name, only one element will be
				in `proxyInfo`. If it's an IPv6 address, it will insert the
				colons again. If it's an ivalid IPv6 address, e.g., missing the
				surrounding brackets, `Target(withHostname:andPort:)` will
				return `nil`.
			*/
			let proxyHost: String = proxyInfo.joined(separator: ":")

			guard let shalonProxy = Target(withHostname: proxyHost, andPort: proxyPort ?? 443) else {
				throw ParseError.incorrectProxySpecification
			}

			shalonProxies.append(shalonProxy)
		}

		// The requestUrl is now simply those components that were not used before,
		// along with the https:// scheme
		var requestUrl = URL(string: "https://" + components[numProxies..<components.count].joined(separator: "/"))

		if requestUrl?.path == "" {
			requestUrl = URL(string: requestUrl!.absoluteString + "/")
		}

		guard let actualUrl = requestUrl else {
			return nil
		}

		return Parameters(proxies: shalonProxies, requestUrl: actualUrl)
	}

	// MARK: URLProtocol

	/**
		Implementation of the [`URLProtocol`](https://developer.apple.com/documentation/foundation/urlprotocol).

		- parameters:
			- request: A request.

		- see:
			[`canInit(with:)`](https://developer.apple.com/documentation/foundation/urlprotocol/1411389-caninit)
	*/
	override public class func canInit(with request: URLRequest) -> Bool {

		if let url = request.url {
			let shalonParameters = try? parseShalonParams(from: url)
			if shalonParameters != nil {
				print("Shalon will handle request")
				return true
			} else {
				print("Shalon will not handle request")
				return false
			}
		}

		return false
	}

	/**
		Implementation of the [`URLProtocol`](https://developer.apple.com/documentation/foundation/urlprotocol).

		- parameters:
			- request: A task.

		- see:
			[`canInit(with:)`](https://developer.apple.com/documentation/foundation/urlprotocol/1416997-caninit)
	*/
	override public class func canInit(with task: URLSessionTask) -> Bool {
		guard let request = task.currentRequest else {
			return false
		}
		return canInit(with: request)
	}

	/**
		Implementation of the [`URLProtocol`](https://developer.apple.com/documentation/foundation/urlprotocol).

		- parameters:
			- request: A request.

		- see:
			[`canonicalRequest(for:)`](https://developer.apple.com/documentation/foundation/urlprotocol/1408650-canonicalrequest)
	*/
	override public class func canonicalRequest(for request: URLRequest) -> URLRequest {
		return request
	}

	/**
		Implementation of the [`URLProtocol`](https://developer.apple.com/documentation/foundation/urlprotocol).

		- see:
			[`startLoading()`](https://developer.apple.com/documentation/foundation/urlprotocol/1408989-startloading)
	*/
	override public func startLoading() {
		// ShalonParameters is only ever called if canInit returned true,
		// meaning that this function successfully executed and does not
		// return nil
		let shalonParameters = try! ShalonURLProtocol.parseShalonParams(from: request.url!)!

		print(shalonParameters.requestUrl)

		let port: UInt16
		if let parsedPort = shalonParameters.requestUrl.port {
			port = UInt16(parsedPort)
		} else {
			port = 443
		}

		let target = Target(withHostname: shalonParameters.requestUrl.host!, andPort: port)!
		let shalon = Shalon(withTarget: target)

		for proxy in shalonParameters.proxies {
			shalon.addLayer(proxy)
		}

		guard let method = Http.Method(rawValue: request.httpMethod!.uppercased()) else {
			fatalError("Unhandled HTTP method: \(String(describing: request.httpMethod))")
		}

		// Handle body data
		let httpBody: Data

		// HTTP Body data gets transformed into an input by the URL loading system.
		if let bodyStream = request.httpBodyStream {
			bodyStream.open()
			httpBody = bodyStream.readAll() ?? Data()
			bodyStream.close()
		} else {
			httpBody = Data()
		}

		let actualRequest = Http.Request(
			withMethod: method,
			andUrl: shalonParameters.requestUrl,
			andHeaders: request.allHTTPHeaderFields ?? [:],
			andBody: httpBody
		)!

		shalon.issue(request: actualRequest) {
			optionalResponse, optionalError in

			assert((optionalResponse != nil) != (optionalError != nil))

			print("Handling response from URLProtocol handler")
			guard !self.loadingShouldStop else {
				return
			}

			guard let response = optionalResponse else {
				self.client!.urlProtocol(self, didFailWithError: optionalError!)
				return
			}

			// Convert internal response type to URLResponse
			let urlResponse = HTTPURLResponse(
				url: self.request.url!,
				statusCode: Int(response.status.rawValue),
				httpVersion: "HTTP/1.1",
				headerFields: response.headers
			)
			self.client!.urlProtocol(self, didReceive: urlResponse!, cacheStoragePolicy: .allowed)
			if let responseBody = response.body {
				self.client!.urlProtocol(self, didLoad: responseBody)
			}
			self.client!.urlProtocolDidFinishLoading(self)
		}
	}

	/**
		Implementation of the [`URLProtocol`](https://developer.apple.com/documentation/foundation/urlprotocol).

		- see:
			[`stopLoading()`](https://developer.apple.com/documentation/foundation/urlprotocol/1408666-stoploading)
	*/
	override public func stopLoading() {
		loadingShouldStop = true
	}

}
