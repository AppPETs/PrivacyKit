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
		/// CONNECT
		case connect = "CONNECT"
		/// DELETE
		case delete  = "DELETE"
		/// GET
		case get     = "GET"
		/// HEAD
		case head    = "HEAD"
		/// OPTIONS
		case options = "OPTIONS"
		/// POST
		case post    = "POST"
		/// PUT
		case put     = "PUT"
		/// TRACE
		case trace   = "TRACE"
	}

	/**
		A type-safe HTTP status category.
	*/
	public enum StatusCategory {
		/// Informal response (1xx)
		case informal
		/// Success (2xx)
		case success
		/// Redirection (3xx)
		case redirection
		/// Client errors (4xx)
		case clientError
		/// Server errors (5xx)
		case serverError
	}

	/**
		A type-safe HTTP status.
	*/
	public enum Status: UInt16 {

		// Informal response

		/// Continue
		case Continue                      = 100
		/// Swithing protocols
		case switchingProtocols            = 101
		/// Processing
		case processing                    = 102

		// Success

		/// OK
		case ok                            = 200
		/// Created
		case created                       = 201
		/// Accepted
		case accepted                      = 202
		/// Non-authoritative information
		case nonAuthoritativeInformation   = 203
		/// No content
		case noContent                     = 204
		/// Reset content
		case resetContent                  = 205
		/// Partial content
		case partialContent                = 206
		/// Multi-status
		case multiStatus                   = 207
		/// Already reported
		case alreadyReported               = 208
		/// IM used
		case imUsed                        = 226

		// Redirection

		/// Multiple choices
		case multipleChoices               = 300
		/// Moved permanently
		case movedPermanently              = 301
		/// Found
		case found                         = 302
		/// See other
		case seeOther                      = 303
		/// Not modified
		case notModified                   = 304
		/// Use proxy
		case useProxy                      = 305
		/// Switch proxy
		case switchProxy                   = 306
		/// Temporary redirect
		case temporaryRedirect             = 307
		/// Permanent redirect
		case permanentRedirect             = 308

		// Client errors

		/// Bad request
		case badRequest                    = 400
		/// Unauthorized
		case unauthorized                  = 401
		/// Payment required
		case paymentRequired               = 402
		/// Forbidden
		case forbidden                     = 403
		/// Not found
		case notFound                      = 404
		/// Method not allowed
		case methodNotAllowed              = 405
		/// Not acceptable
		case notAcceptable                 = 406
		/// Proxy authentication required
		case proxyAuthenticationRequired   = 407
		/// Request timeout
		case requestTimeout                = 408
		/// Conflict
		case conflict                      = 409
		/// Gone
		case gone                          = 410
		/// Length required
		case lengthRequired                = 411
		/// Precodition failed
		case preconditionFailed            = 412
		/// Payload too large
		case payloadTooLarge               = 413
		/// URI too long
		case uriTooLong                    = 414
		/// Unsupported media type
		case unsupportedMediaType          = 415
		/// Range not satisfiable
		case rangeNotSatisfiable           = 416
		/// Expectation failed
		case expectationFailed             = 417
		/// Teapot
		case teapot                        = 418
		/// Misdirected request
		case misdirectedRequest            = 421
		/// Unprocessable entity
		case unprocessableEntity           = 422
		/// Locked
		case locked                        = 423
		/// Failed dependency
		case failedDependency              = 424
		/// Upgrade required
		case upgradeRequired               = 426
		/// Precondition required
		case preconditionRequired          = 428
		/// Too many requests
		case tooManyRequests               = 429
		/// Request header fields too large
		case requestHeaderFieldsTooLarge   = 431
		/// Unavailable for legal reasons
		case unavailableForLegalReasons    = 451

		// Server Errors

		/// Internal server error
		case internalServerError           = 500
		/// Not implemented
		case notImplemented                = 501
		/// Bad gateway
		case badGateway                    = 502
		/// Service unavailable
		case serviceUnavailable            = 503
		/// Gateway timeout
		case gatewayTimeout                = 504
		/// HTTP version not supported
		case httpVersionNotSupported       = 505
		/// Variant also negotiates
		case variantAlsoNegotiates         = 506
		/// Insufficient storage
		case insufficientStorage           = 507
		/// Loop detected
		case loopDetected                  = 508
		/// Not extended
		case notExtended                   = 510
		/// Network authentication required
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
		/// `Host`
		case host = "Host"
		/// `Content-Length`
		case contentLength = "Content-Length"
		/// `Content-Type`
		case contentType = "Content-Type"

		/**
			A header used to activating bad behaviour of a service provider.
			This should be used for demonstration purposes only.

			- warning: Do not use this in production systems, as all requests
				will be logged, if this header is set.
		*/
		case badProvider = "X-AppPETs-BadProvider"
	}

	/**
		Type-safe HTTP content types.
	*/
	public enum ContentType: String {
		/// `application/octet-stream`
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
public struct Target: Hashable {

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
