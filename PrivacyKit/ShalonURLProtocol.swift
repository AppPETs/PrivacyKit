import Foundation

public class ShalonURLProtocol : URLProtocol {
	var loadingShouldStop: Bool = false

	struct ShalonParams {
		let proxies : [Target]
		let requestUrl : URL
	}

	enum ShalonParseError : Error {
		case tooFewProxies
		case incorrectProxySpecification
	}

	class func parseShalonParams(from url: URL) throws -> ShalonParams?{
		var numProxies : Int
		var shalonProxies : [Target] = []

		let urlScheme = url.scheme!.lowercased()
		let sCount = urlScheme.substring(from: urlScheme.range(of: "http")!.upperBound).characters.count

		// 1 to 3 proxies (httpss:// to httpssss://) supported
		guard (2...4).contains(sCount) else {
			return nil
		}

		numProxies = sCount - 1

		let urlString = url.absoluteString
		// The URL string, withouth the scheme part!
		let baseString = urlString.substring(from: urlString.range(of: "://")!.upperBound)
		// Examples:
		//   httpss://proxy:port/destination:port/index.html
		//   httpsss://proxy1:port/proxy2:port/destination:port/test.txt
		let components = baseString.components(separatedBy: "/")
		guard components.count >= numProxies else {
			throw ShalonParseError.tooFewProxies
		}

		for i in 0..<numProxies {
			let ithProxy : String = components[i]
			guard ithProxy =~ "^[a-zA-Z0-9\\.]*\\:\\d+$" else {
				throw ShalonParseError.incorrectProxySpecification
			}

			let proxyInfo = ithProxy.components(separatedBy: ":")

			let shalonProxy = Target(withHostname: proxyInfo[0], andPort: UInt16(proxyInfo[1])!)
			shalonProxies.append(shalonProxy!)
		}

		// The requestUrl is now simply those components that were not used before,
		// along with the https:// scheme
		let requestUrl = URL(string: "https://" + components[numProxies..<components.count].joined(separator: "/"))
		if let actualUrl = requestUrl {
			return ShalonParams(proxies: shalonProxies, requestUrl: actualUrl)
		}

		return nil
	}

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

	override public class func canonicalRequest(for request: URLRequest) -> URLRequest {
		return request
	}

	enum ShalonErrors : Error {
		case NotImplemented
		case UnknownHTTPMethod
		case NoContents
	}

	override public func startLoading() {
		// ShalonParameters is only ever called if canInit returned true,
		// meaning that this function successfully executed and does not
		// return nil
		let shalonParameters = try! ShalonURLProtocol.parseShalonParams(from: request.url!)!

		print(shalonParameters.requestUrl)

		let target = Target(withHostname: shalonParameters.requestUrl.host!, andPort: 443)!
		let shalon = Shalon(withTarget: target)

		for proxy in shalonParameters.proxies {
			shalon.addLayer(proxy)
		}

		let optionalMethod = Http.Method(rawValue: request.httpMethod!.uppercased())
		guard optionalMethod != nil else {
			client!.urlProtocol(self, didFailWithError: ShalonErrors.UnknownHTTPMethod)
			return
		}

		shalon.issue(request: Http.Request(withMethod: optionalMethod!, andUrl: shalonParameters.requestUrl)!) {
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
