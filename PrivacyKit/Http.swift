import CoreFoundation
import Foundation

/**
	A class that mainly acts as a namespace for HTTP-related functionality.
*/
public class Http {

	/**
		A type-safe HTTP error.
	*/
	public enum Error: Swift.Error {

		/**
			This error indicates that a response could not be parsed correctly.
		*/
		case invalidResponse

		/**
			This error indicates an unexpected response. Each response can
			potentially be unexpected, depending on the caller. The arguments of
			the error are an HTTP status code as well as a description.
		*/
		case unexpectedResponse(Http.Status, String)

	}

	/**
		A type-safe HTTP method.
	*/
	public enum Method: String {
		case connect = "CONNECT"
		case delete  = "DELETE"
		case get     = "GET"
		case head    = "HEAD"
		case options = "OPTIONS"
		case post    = "POST"
		case put     = "PUT"
		case trace   = "TRACE"
	}

	/**
		A type-safe HTTP status category.
	*/
	public enum StatusCategory {
		case informal
		case success
		case redirection
		case clientError
		case serverError
	}

	/**
		A type-safe HTTP status.
	*/
	public enum Status: UInt16 {
		// Informal
		case Continue                      = 100
		case switchingProtocols            = 101
		case processing                    = 102
		// Success
		case ok                            = 200
		case created                       = 201
		case accepted                      = 202
		case nonAuthoritativeInformation   = 203
		case noContent                     = 204
		case resetContent                  = 205
		case partialContent                = 206
		case multiStatus                   = 207
		case alreadyReported               = 208
		case imUsed                        = 226
		// Redirection
		case multipleChoices               = 300
		case movedPermanently              = 301
		case found                         = 302
		case seeOther                      = 303
		case notModified                   = 304
		case useProxy                      = 305
		case switchProxy                   = 306
		case temporaryRedirect             = 307
		case permanentRedirect             = 308
		// Client errors
		case badRequest                    = 400
		case unauthorized                  = 401
		case paymentRequired               = 402
		case forbidden                     = 403
		case notFound                      = 404
		case methodNotAllowed              = 405
		case notAcceptable                 = 406
		case proxyAuthenticationRequired   = 407
		case requestTimeout                = 408
		case conflict                      = 409
		case gone                          = 410
		case lengthRequired                = 411
		case preconditionFailed            = 412
		case payloadTooLarge               = 413
		case uriTooLong                    = 414
		case unsupportedMediaType          = 415
		case rangeNotSatisfiable           = 416
		case expectationFailed             = 417
		case teapot                        = 418
		case misdirectedRequest            = 421
		case unprocessableEntity           = 422
		case locked                        = 423
		case failedDependency              = 424
		case upgradeRequired               = 426
		case preconditionRequired          = 428
		case tooManyRequests               = 429
		case requestHeaderFieldsTooLarge   = 431
		case unavailableForLegalReasons    = 451
		// Server Errors
		case internalServerError           = 500
		case notImplemented                = 501
		case badGateway                    = 502
		case serviceUnavailable            = 503
		case gatewayTimeout                = 504
		case httpVersionNotSupported       = 505
		case variantAlsoNegotiates         = 506
		case insufficientStorage           = 507
		case loopDetected                  = 508
		case notExtended                   = 510
		case networkAuthenticationRequired = 511

		/**
			The HTTP status category for an HTTP status.
		*/
		public var category: StatusCategory {
			switch self.rawValue {
				case 100..<200:
					return .informal
				case 200..<300:
					return .success
				case 300..<400:
					return .redirection
				case 400..<500:
					return .clientError
				case 500..<600:
					return .serverError
				default:
					fatalError("Invalid status!")
			}
		}

	}

	// TODO Define custom class/struct for headers which also handle case-insensitivity
	/**
		Type-safe HTTP header keys.
	*/
	public enum Header: String {
		case host = "Host"
		case contentLength = "Content-Length"
		case contentType = "Content-Type"
	}

	/**
		Type-safe HTTP content types.
	*/
	public enum ContentType: String {
		case octetStream = "application/octet-stream"
	}

	/**
		An alias for HTTP headers.
	*/
	public typealias Headers = [String: String]

	/**
		A class representing HTTP messages.
	*/
	public class Message {

		/**
			The HTTP message's headers.
		*/
		let headers: Headers

		/**
			An optional body.
		*/
		let	body: Data?

		/**
			Initialize a message with headers and an optional body.

			- parameters:
				- headers: The HTTP message's headers.
				- body: An optional body.
		*/
		init(withHeaders headers: Headers = [:], andBody body: Data? = nil) {
			self.headers = headers
			self.body = body
		}

	}

	/**
		A class representing an HTTP request.
	*/
	public class Request: Message {

		/**
			The method of the request.
		*/
		let method: Method

		/**
			The requested URL.
		*/
		let url: URL

		/**
			HTTP options.
		*/
		let options: String?

		/**
			Initialize an HTTP request.

			- parameters:
				- method: The request's HTTP method.
				- url: The requested URL.
				- headers: Headers of the request.
				- body: An optional body of the request.
				- options: Optional HTTP options.
		*/
		init?(withMethod method: Method, andUrl url: URL, andHeaders headers: Headers = [:], andBody body: Data = Data(), andOptions options: String? = nil) {

			// Sanitize URL

			// No HTTP messages for `file`-URLs.
			guard !url.isFileURL else {
				return nil
			}

			// CONNECT and OPTIONS requests cannot be handled if only an URL is passed
			guard !([.connect, .options].contains(method) && options == nil) else {
				return nil
			}

			// CONNECT and HEAD requests have no body
			guard ![.connect, .head].contains(method) || body.isEmpty else {
				return nil
			}

			self.method = method
			self.url = url
			self.options = options

			// Patch headers
			var patchedHeaders = headers
			if !headers.keys.contains(Header.host.rawValue) {
				patchedHeaders[Header.host.rawValue] = url.host!
			}
			if !body.isEmpty && !headers.keys.contains(Header.contentLength.rawValue) {
				patchedHeaders[Header.contentLength.rawValue] = "\(body.count)"
			}

			super.init(withHeaders: patchedHeaders, andBody: body)
		}

		/**
			Construct a HTTP CONNECT request for establishing TCP tunnels
			through HTTP proxy server, which supports this.

			- parameters:
				- target: The target of the request, i.e., the server to which
					the tunnel should be established.
				- proxy: The proxy server, through which the tunnel should be
					established.
				- headers: The headers of the request.

			- returns:
				The request, `nil` if arguments are invalid.
		*/
		static func connect(toTarget target: Target, viaProxy proxy: Target, withHeaders headers: Headers = [:]) -> Request? {
			let proxyUrl = URL(string: "https://\(proxy.formatted())")!
			return Request(withMethod: .connect, andUrl: proxyUrl, andHeaders: headers, andBody: Data(), andOptions: target.formatted())
		}

		/**
			Compose a request into date that can be sent to the HTTP server.

			- returns:
				The composed request.
		*/
		var composed: Data {
			let args = (options == nil) ? url.path : options!

			var rawRequest = Data("\(method.rawValue) \(args) \(kCFHTTPVersion1_1 as NSString)\r\n".utf8)
			for (key, value) in headers {
				rawRequest.append(Data("\(key): \(value)\r\n".utf8))
			}
			rawRequest.append(Data("\r\n".utf8))
			if let body = body {
				rawRequest.append(body)
			}

			return rawRequest
		}

	}

	/**
		A class representing an HTTP response.
	*/
	public class Response: Message {

		/**
			The HTTP status code.
		*/
		let status: Status

		/**
			Construct an HTTP response from raw data.

			- returns:
				`nil` if the response is invalid.
		*/
		init?(withRawData rawData: Data) {
			let cfResponse = CFHTTPMessageCreateEmpty(kCFAllocatorDefault, /* isRequest: */ false).takeRetainedValue()
			let success = rawData.withUnsafeBytes { CFHTTPMessageAppendBytes(cfResponse, $0, rawData.count) }

			guard success && CFHTTPMessageIsHeaderComplete(cfResponse) else {
				return nil
			}

			// Parse status code
			let statusCode = CFHTTPMessageGetResponseStatusCode(cfResponse)
			guard let status = Status(rawValue: UInt16(statusCode)) else {
				return nil // Unknown status code
			}
			self.status = status

			// Parse headers
			guard let cfHeaders = CFHTTPMessageCopyAllHeaderFields(cfResponse)?.takeRetainedValue() else {
				return nil
			}

			/*
				Since the result of `CFHTTPMessageCopyAllHeaderFields` is of
				type `CFDictionary<CFString,CFString>` we can force-cast
				directly to `Headers`, which is basically a
				`Dictionary<String,String>`.
			*/
			let headers = cfHeaders as! Headers

			// Parse body
			let cfBody = CFHTTPMessageCopyBody(cfResponse)?.takeRetainedValue()
			let body = cfBody as Data?

			super.init(withHeaders: headers, andBody: body)
		}

	}

}

extension URLRequest {

	/**
		Add a HTTP header.

		- parameters:
			- value: The value of the header field.
			- header: The key of the header field.
	*/
	public mutating func add(value: String, for header: Http.Header) {
		addValue(value, forHTTPHeaderField: header.rawValue)
	}

	/**
		Set the content type of the HTTP request's body.

		- parameters:
			- contentType: The content type.
	*/
	public mutating func set(contentType: Http.ContentType) {
		add(value: contentType.rawValue, for: .contentType)
	}

	/**
		Set the HTTP method of the request.

		- parameters:
			- method: The HTTP method.
	*/
	public mutating func set(method: Http.Method) {
		httpMethod = method.rawValue
	}

}

extension HTTPURLResponse {

	/**
		A type-safe HTTP status.
	*/
	public var status: Http.Status {
		assert(0 <= statusCode)
		return Http.Status(rawValue: UInt16(statusCode))!
	}

	/**
		Construct an HTTP error from the current status and the description.
	*/
	public var unexpected: Http.Error {
		return .unexpectedResponse(status, description)
	}

}

/**
	A struct that represents a network target. It consists of a hostname or an
	IP address and a port number.
*/
public struct Target {

	/**
		The hostname or IP address of the target. The IP address can either be
		IPv4 or IPv6.
	*/
	public let hostname: String

	/**
		The port.
	*/
	public let port: UInt16

	/**
		Initialize a target with a given hostname and port.

		- parameters:
			- hostname: The hostname or IP address.
			- port: The port

		- returns:
			`nil` if `hostname` or `port` is invalid.
	*/
	public init?(withHostname hostname: String, andPort port: UInt16) {

		guard !hostname.isEmpty else {
			return nil
		}

		guard 0 < port else {
			return nil
		}

		guard let url = URL(string: "xxx://\(hostname):\(port)") else {
			return nil
		}

		guard let portAsInt = url.port else {
			return nil
		}

		self.hostname = url.host!
		self.port = UInt16(exactly: portAsInt)!
	}

	/**
		A string representation of the target.

		- returns:
			`example.com:80` if the hostname is `example.com` and the port is 80.
	*/
	public func formatted() -> String {
		return "\(hostname):\(port)"
	}

}

extension Target: Equatable {

	/**
		Compare two targets. Two targets are equal if their hostnames and their
		ports are equal.

		- parameters:
			- lhs: A target.
			- rhs: Another target.

		- returns:
			`true` if and only if `lhs` and `rhs` are equal.
	*/
	public static func == (lhs: Target, rhs: Target) -> Bool {
		return lhs.hostname == rhs.hostname && lhs.port == rhs.port
	}

}
