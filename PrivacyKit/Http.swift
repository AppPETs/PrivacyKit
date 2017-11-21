import CoreFoundation
import Foundation

class Http {

	enum Error: Swift.Error {
		case invalidResponse
		case unexpectedResponse(Http.Status, String)
	}

	enum Method: String {
		case connect = "CONNECT"
		case delete  = "DELETE"
		case get     = "GET"
		case head    = "HEAD"
		case options = "OPTIONS"
		case post    = "POST"
		case put     = "PUT"
		case trace   = "TRACE"
	}

	enum StatusCategory {
		case informal
		case success
		case redirection
		case clientError
		case serverError
	}

	enum Status: UInt16 {
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
	}

	static func category(for status: Status) -> StatusCategory {
		switch status.rawValue {
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

	// TODO Define custom class/struct for headers which also handle case-insensitivity
	enum Header: String {
		case host = "Host"
		case contentLength = "Content-Length"
		case contentType = "Content-Type"
	}

	enum ContentType: String {
		case octetStream = "application/octet-stream"
	}

	typealias Headers = [String: String]

	class Message {
		let headers: Headers
		let	body: Data?

		init(withHeaders headers: Headers = [:], andBody body: Data? = nil) {
			self.headers = headers
			self.body = body
		}
	}

	class Request: Message {

		let method: Method
		let url: URL
		let options: String?

		// FIXME Handle different casing for patched headers
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

		class func connect(toTarget target: Target, viaProxy proxy: Target, withHeaders headers: Headers = [:]) -> Request? {
			guard let proxyUrl = URL(string: "https://\(proxy.formatted())") else {
				return nil
			}
			return Request(withMethod: .connect, andUrl: proxyUrl, andHeaders: headers, andBody: Data(), andOptions: target.formatted())
		}

		// TODO Encoding
		func compose() -> Data? {
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

	class Response: Message {
		let status: Status

		init?(withRawData rawData: Data) {
			let cfResponse = CFHTTPMessageCreateEmpty(kCFAllocatorDefault, /* isRequest: */ false).takeRetainedValue()
			let success = rawData.withUnsafeBytes { rawDataPtr in
				return CFHTTPMessageAppendBytes(cfResponse, rawDataPtr, rawData.count)
			}

			guard success && CFHTTPMessageIsHeaderComplete(cfResponse) else {
				return nil
			}

			// Parse status code
			let statusCode = CFHTTPMessageGetResponseStatusCode(cfResponse)
			guard let status = Status(rawValue: UInt16(statusCode)) else {
				assert(false, "Unknown status code: \(statusCode)")
				print("Unknown status code: \(statusCode)")
				return nil
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
	mutating func add(value: String, for header: Http.Header) {
		addValue(value, forHTTPHeaderField: header.rawValue)
	}

	mutating func set(contentType: Http.ContentType) {
		add(value: contentType.rawValue, for: .contentType)
	}

	mutating func set(method: Http.Method) {
		httpMethod = method.rawValue
	}
}

extension HTTPURLResponse {
	var status: Http.Status {
		get {
			assert(0 <= statusCode)
			return Http.Status(rawValue: UInt16(statusCode))!
		}
	}

	var unexpected: Http.Error {
		get {
			return .unexpectedResponse(status, description)
		}
	}
}

struct Target {
	let hostname: String
	let port: UInt16

	init?(withHostname hostname: String, andPort port: UInt16) {

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

	func formatted() -> String {
		return "\(hostname):\(port)"
	}
}

extension Target: Equatable {
	static func == (lhs: Target, rhs: Target) -> Bool {
		return lhs.hostname == rhs.hostname && lhs.port == rhs.port
	}
}
