import Foundation

public class ShalonURLProtocol : URLProtocol {

	enum ShalonParseError : Error {
		case tooFewProxies
		case incorrectProxySpecification
	}

	enum ShalonErrors : Error {
		case NotImplemented
		case UnknownHTTPMethod
		case NoContents
	}

	struct ShalonParams {
		let proxies : [Target]
		let requestUrl : URL
	}
	private var loadingShouldStop: Bool = false

	static func parseShalonParams(from url: URL) throws -> ShalonParams?{
		var numProxies : Int
		var shalonProxies : [Target] = []

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
		guard components.count >= numProxies else {
			throw ShalonParseError.tooFewProxies
		}

		for i in 0..<numProxies {
			let ithProxy : String = components[i]

			let proxyInfo = ithProxy.components(separatedBy: ":")

			var proxyHost : String
			var proxyPort : UInt16 = 0

			if proxyInfo.count == 2 && proxyInfo.last! != "" {
				// Handle IPv4 addresses or domain names
				proxyHost = proxyInfo.first!
				proxyPort = UInt16(proxyInfo.last!)!
			} else if proxyInfo.count > 2 && proxyInfo.last! != "" {
				// Handle IPv6 addresses

				// Assuming addresses are specified correctly
				// If they are not, Target(withHostname, andPort) should return nil
				proxyHost = proxyInfo.prefix(proxyInfo.count - 1).joined(separator: ":")
				proxyPort = UInt16(proxyInfo.last!)!
			} else {
				// Port missing, throw an error
				throw ShalonParseError.incorrectProxySpecification
			}

			let potentialShalonProxy = Target(withHostname: proxyHost, andPort: proxyPort)
			if let actualShalonProxy = potentialShalonProxy {
				shalonProxies.append(actualShalonProxy)
			} else {
				throw ShalonParseError.incorrectProxySpecification
			}
		}

		// The requestUrl is now simply those components that were not used before,
		// along with the https:// scheme
		var requestUrl = URL(string: "https://" + components[numProxies..<components.count].joined(separator: "/"))

		if requestUrl?.path == "" {
			requestUrl = URL(string: requestUrl!.absoluteString + "/")
		}

		if let actualUrl = requestUrl {
			return ShalonParams(proxies: shalonProxies, requestUrl: actualUrl)
		}

		return nil
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

		let optionalMethod = Http.Method(rawValue: request.httpMethod!.uppercased())
		guard optionalMethod != nil else {
			client!.urlProtocol(self, didFailWithError: ShalonErrors.UnknownHTTPMethod)
			return
		}

		// Handle body data
		var httpBody : Data? = nil

		// HTTP Body data gets transformed into an input by the URL loading system.
		if let bodyStream = request.httpBodyStream {
			bodyStream.open()
			httpBody = bodyStream.readAll()
			bodyStream.close()
		}

		shalon.issue(request: Http.Request(withMethod: optionalMethod!, andUrl: shalonParameters.requestUrl, andBody: httpBody ?? Data())!) {
			receivedOptionalResponse, receivedOptionalError in

			print("Handling response from URLProtocol handler")
			guard !self.loadingShouldStop else {
				return
			}

			// Handle any errors
			if let error = receivedOptionalError {
				self.client!.urlProtocol(self, didFailWithError: error)
				return
			}

			// Handle a correct response
			if let response = receivedOptionalResponse {
				// Convert internal response type to URLResponse
				let urlResponse = HTTPURLResponse(url: self.request.url!,
												   statusCode: Int(response.status.rawValue),
												   httpVersion: "HTTP/1.1",
												   headerFields: response.headers)
				self.client!.urlProtocol(self, didReceive: urlResponse!, cacheStoragePolicy: .allowed)
				if let responseBody = response.body {
					self.client!.urlProtocol(self, didLoad: responseBody)
				}
				self.client!.urlProtocolDidFinishLoading(self)
				return
			}

			self.client!.urlProtocol(self, didFailWithError: ShalonErrors.NoContents)
		}
	}

	override public func stopLoading() {
		loadingShouldStop = true
	}
}
