
public class ShalonURLProtocol : URLProtocol {

	enum ParseError : Error {
		case tooFewProxies
		case incorrectProxySpecification
	}

	struct Parameters {
		let proxies: [Target]
		let requestUrl: URL
	}
	private var loadingShouldStop: Bool = false

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

	override public class func canInit(with task: URLSessionTask) -> Bool {
		guard let request = task.currentRequest else {
			return false
		}
		return canInit(with: request)
	}

	override public class func canonicalRequest(for request: URLRequest) -> URLRequest {
		return request
	}

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

		shalon.issue(request: Http.Request(withMethod: method, andUrl: shalonParameters.requestUrl, andBody: httpBody)!) {
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

	override public func stopLoading() {
		loadingShouldStop = true
	}

}
