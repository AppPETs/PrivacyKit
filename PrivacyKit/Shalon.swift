import Foundation

/**
	A generic error type.
*/
enum GenericError: Error {

	/**
		A generic error with a custom error message.
	*/
	case generic(String)

}

/**
	With this class you can connect to a target through a
	[Shalon](http://dx.doi.org/10.1109/ICCCN.2009.5235258) proxy. Connections to
	the proxy and connections to the target will each be encrypted using TLS.
	This means that your ISP or other people in your network cannot observe to
	which target you connect, because they only see connections to the proxy.
	The proxy itself does not see the content of your requests to the target.
	The target will only see the proxy's IP address (except if the IP address is
	otherwise embedded into the request).

	This implementation supports multiple hops. Simply add other layers.

	In order to use Shalon proxies with your `URLSession` connections, please
	take look at `ShalonURLProtocol`.

	## Examples

	```swift
	let proxy1 = Target(withHostname: "shalon1.jondonym.net", andPort: 443)!
	let proxy2 = Target(withHostname: "shalon2.jondonym.net", andPort: 443)!
	let proxy3 = Target(withHostname: "shalon3.jondonym.net", andPort: 443)!
	let target = Target(withHostname: "www.example.com", andPort: 443)!

	let shalon = Shalon(withTarget: target)

	shalon.addLayer(proxy3)
	shalon.addLayer(proxy2)
	shalon.addLayer(proxy1)

	shalon.issue(request: Request(withMethod: .head, andUrl: url)!) {
	    optionalResponse, optionalError in
	    // TODO Do something
	}
	```

	This will establish a nested tunnel, where `proxy1` cannot see what the
	`client` sends to `proxy2`, as depicted:

	```
	client           proxy1           proxy2           proxy3          target
	|                |                |                |               |
	+----------------+                |                |               |
	| CONNECT proxy2 |                |                |               |
	+---------------------------------+                |               |
	|                  CONNECT proxy3 |                |               |
	+--------------------------------------------------+               |
	|                                   CONNECT proxy4 |               |
	+------------------------------------------------------------------+
	|                                                    HEAD /        |
	+------------------------------------------------------------------+
	|                                                  |               |
	+--------------------------------------------------+               |
	|                                 |                |               |
	+---------------------------------+                |               |
	|                |                |                |               |
	+----------------+                |                |               |
	|                |                |                |               |
	```
**/
public class Shalon: NSObject, StreamDelegate {

	/**
		The state of the HTTP connection.

		```
		              inactive
		                  |
		                  |
		                  v
		+--- <Another layer available?> <---+
		|                 |                 |
		|                 |                 |
		|                 v                 |
		|  shouldEstablishTunnelConnection  |
		|                 |                 |
		|                 |                 |
		|                 v                 |
		| expectTunnelConnectionEstablished |
		|                 |                 |
		|                 +-----------------+
		|
		+-----------------+
		                  |
		                  v
		        shouldSendHttpRequest
		                  |
		                  |
		                  v
		         expectHttpResponse
		```
	*/
	private enum State {

		/**
			The connection has not been established.
		*/
		case inactive

		/**
			A connection to the proxy server has been established. This state
			indicates that a HTTP CONNECT request to the next hop (the next
			layer or the target) should be made.
		*/
		case shouldEstablishTunnelConnection

		/**
			This signal to wait for a HTTP response for a HTTP CONNECT request
			that was already made.
		*/
		case expectTunnelConnectionEstablished

		/**
			The tunnel to the target has been successfully established. This
			signals that we can now make the actual HTTP request.
		*/
		case shouldSendHttpRequest

		/**
			This signals, that we wait for the HTTP response of the actual
			request.
		*/
		case expectHttpResponse
	}

	/**
		A helper type for our callbacks, a function that gets either a HTTP
		response or an error.
	*/
	public typealias CompletionHandler = (Http.Response?, Error?) -> Void

	/**
		The state of the tunnel connection to the target.
	*/
	private var state: State = .inactive

	/**
		A list of hops. The last element is the actual target. All other
		elements are Shalon proxies. The first element is the proxy the user
		actually connects to.
	*/
	private var targets: [Target] = []

	/**
		A list of streams that are already established. The first element is the
		network stream to the first hop. All other elements are TLS encrypted
		streams to each hop (including the first one), i.e.
		1. TCP stream to first hop
		2. TLS stream to first hop
		3. TLS stream to second hop
		4. TLS stream to third hop…
	*/
	private var streams: [PairedStream] = []

	/**
		Returns the current layer. A layer is a TLS encrypted stream.
	*/
	private var currentLayer: Int {
		return (streams.count < 2) ? 0 : streams.count - 1
	}

	/**
		The HTTP request, that should be sent to the target.
	*/
	private var request: Http.Request! = nil

	/**
		A callback that is called, once the HTTP response from the target has
		arrived or when an error occurred.
	*/
	private var completionHandler: CompletionHandler! = nil

	/**
		Construct a Shalon object with a given target. After calling this,
		proxies can be added by calling `addLayer(_:)`.

		- warning:
			If no layer is added, a direct connection will be made. Which means
			that the IP address of the current device will be visible to the
			target.

		- parameters:
			- target: The address of the server, to which requests should be
				issued.
	*/
	public init(withTarget target: Target) {
		super.init()

		addLayer(target)
	}

	/**
		This adds a proxy, which is connected before each other layer that was
		previously added, i.e., the last layer added will be the layer the
		initial conenction is made to.

		- parameters:
			- target: A proxy address.
	*/
	public func addLayer(_ target: Target) {
		targets.insert(target, at: 0)
	}

	/**
		Issue an HTTP request. The request is send through a TLS tunnel via
		proxy servers added with `addLayer(_:)`.

		- warning:
			If no layer was added with `addLayer(_:)`, a direct connection to the
			target will be established. Which means that the IP address of the
			current device will be visible to the target.

		- postcondition:
			Either the response or the error parameter of the
			`completionHandler` is set, the other one is `nil`.

		- parameters:
			- request: The HTTP request.
			- completionHandler: A callback function. Its parameters are either
				an optional HTTP response or an error.
	*/
	public func issue(request: Http.Request, completionHandler: @escaping CompletionHandler) {
		assert(!targets.isEmpty)
		assert(streams.isEmpty)
		assert(self.request == nil)

		self.request = request
		self.completionHandler = completionHandler

		// Initialize streams
		let firstHop = targets.first!
		var optionalInputStream: InputStream? = nil
		var optionalOutputStream: OutputStream? = nil
		Stream.getStreamsToHost(withName: firstHop.hostname, port: Int(firstHop.port), inputStream: &optionalInputStream, outputStream: &optionalOutputStream)

		guard let inputStream = optionalInputStream else {
			print("No input stream.")
			return
		}

		guard let outputStream = optionalOutputStream else {
			print("No output stream.")
			return
		}

		let wrappedInputStream = WrappedInputStream(inputStream)
		let wrappedOutputStream = WrappedOutputStream(outputStream)
		let stream = PairedStream(input: wrappedInputStream, output: wrappedOutputStream)

		/*
			This stream is the actual network connection established by the
			current device. This is just a TCP stream, no TLS encryption, yet.
		*/
		streams.append(stream)

		/*
			The established TCP connection should be TLS secured, as soon as
			bytes can be written to the output stream.
		 */
		state = nextState

		wrapCurrentLayerWithTls()
	}

	/**
		Helper function that performs a TLS handshake for the current layer.
		This can be the initial TCP connection established by this device,
		i.e. by `issue(request:completionHandler:)` or a TCP tunnel established
		through a proxy, i.e., if the state is
		`expectTunnelConnectionEstablished`.
	*/
	private func wrapCurrentLayerWithTls() {
		assert(currentLayer < targets.count, "Cannot have more layers than targets!")

		let target = targets[currentLayer]
		let stream = streams.last!

		guard let session = TlsSession(forTarget: target, withStream: stream) else {
			print("Failed to create TLS session.")
			return
		}

		let wrappedInputStream = TLSInputStream(stream.input, withSession: session)
		let wrappedOutputStream = TLSOutputStream(stream.output, withSession: session)
		let wrappedStream = PairedStream(input: wrappedInputStream, output: wrappedOutputStream)
		streams.append(wrappedStream)

		wrappedStream.delegate = self
		wrappedStream.schedule(in: .current, forMode: .default)
		wrappedStream.open()

		if RunLoop.main != .current {
			RunLoop.current.run()
		}
	}

	// MARK: StreamDelegate

	/**
		Implementation of the [`StreamDelegate`](https://developer.apple.com/documentation/foundation/streamdelegate)
		protocol.

		- see: [`stream(_:handle:)`](https://developer.apple.com/documentation/foundation/streamdelegate/1410079-stream)

		- parameters:
			- stream: The stream on which streamEvent occurred.
			- handle: The stream event that occurred.
	*/
	public func stream(_ stream: Stream, handle eventCode: Stream.Event) {
		assert(stream === currentStream.input || stream == currentStream.output, "Should not act as a delegate to another stream!")

		guard !eventCode.contains(.endEncountered) else {
			reset()
			return
		}

		guard !eventCode.contains(.errorOccurred) else {
			errorOccurred(stream.streamError!)
			return
		}

		if stream == currentStream.input {
			inputStream(handle: eventCode)
		} else {
			outputStream(handle: eventCode)
		}
	}

	/**
		This is a convenience function, which is called if the stream in
		`stream(_:handle:)` is an input stream.

		- parameters:
			- handle: The stream event that occurred.
	*/
	private func inputStream(handle eventCode: Stream.Event) {
		assert(!eventCode.contains(.hasSpaceAvailable))

		let stream = currentStream.input

		if eventCode.contains(.openCompleted) {
			state = nextState
		}

		if eventCode.contains(.hasBytesAvailable) {
			switch state {
				case .expectTunnelConnectionEstablished:
					// Read HTTP response and check if it indicates success.
					state = nextState
					guard let response: Http.Response = expectHttpResponse(fromStream: stream) else {
						print("Failed to parse response")
						return
					}
					guard response.status == .ok else {
						errorOccurred(.generic("Server could not handle request, response: \(response.status)"))
						return
					}
					print("Connection to '\(currentTarget.formatted())' established")

					wrapCurrentLayerWithTls()
				case .expectHttpResponse:
					guard let response = expectHttpResponse(fromStream: stream) else {
						print("Failed to parse response")
						return
					}
					completionHandler(response, nil)
					reset()
				default:
					{}() // Do nothing
			}
		}
	}

	/**
		This is a convenience function, which is called if the stream in
		`stream(_:handle:)` is an output stream.

		- parameters:
			- handle: The stream event that occurred.
	*/
	private func outputStream(handle eventCode: Stream.Event) {
		assert(!eventCode.contains(.hasBytesAvailable))

		let stream = currentStream.output

		if eventCode.contains(.hasSpaceAvailable) {
			switch state {
				case .shouldEstablishTunnelConnection:
					assert(nextTargetIdx < targets.count, "More layers than targets")

					// Send HTTP CONNECT request to the next target
					state = .expectTunnelConnectionEstablished
					send(request: Http.Request.connect(toTarget: nextTarget, viaProxy: currentTarget)!, toStream: stream)
				case .shouldSendHttpRequest:
					assert(nextTargetIdx == targets.count)

					// Send the original request issued by the application
					state = .expectHttpResponse
					send(request: request!, toStream: stream)
				default:
					{}() // Do nothing
			}
		}
	}

	// MARK: Helpers

	/**
		Helper function that calls the completion handler with a specific error.

		- parameters:
			- error: A generic error.
	*/
	private func errorOccurred(_ error: GenericError) {
		errorOccurred(error as Error)
	}

	/**
		Helper function that calls the completion handler with a specific error.

		- parameters:
			- error: An error.
	*/
	private func errorOccurred(_ error: Error) {
		completionHandler(nil, error)
		reset()
	}

	/**
		Reset the internal state machine and remove all streams.
	*/
	private func reset() {
		guard state != .inactive else {
			return
		}

		currentStream.delegate = nil // Ignore failures during close-up.
		currentStream.close()

		streams.removeAll()

		request = nil
		completionHandler = nil

		state = .inactive
	}

	/**
		Parse the input stream and expect an HTTP response.

		- parameters:
			- stream: The input stream.

		- returns:
			The HTTP response or `nil` if the response is invalid.
	*/
	private func expectHttpResponse(fromStream stream: InputStream) -> Http.Response? {
		assert(stream.hasBytesAvailable)

		guard let rawResponse = stream.readAll() else {
			return nil
		}
		return Http.Response(withRawData: rawResponse)
	}

	/**
		Send an HTTP request to an output stream.

		- parameters:
			- request: The HTTP request.
			- stream: The output stream.
	*/
	private func send(request: Http.Request, toStream stream: OutputStream) {
		assert(stream.hasSpaceAvailable)

		guard 0 < stream.write(data: request.composed) else {
			print("Not everything was sent")
			return
		}
	}

	/**
		The next state, which is determined by the number of proxies, to which a
		connection has not been established.

		- note:
			Only call this, after a new direct or tunnelled connection has been
			established. The returned state might not make much sense, else.
	*/
	private var nextState: State {
		// There is one more layers than targets
		return (nextTargetIdx < targets.count) ? .shouldEstablishTunnelConnection : .shouldSendHttpRequest
	}

	/**
		The index of the current target to which a tunnel has been established.
	*/
	private var currentTargetIdx: Int {
		assert(currentLayer <= targets.count)

		return (currentLayer < 2) ? 0 : currentLayer - 1
	}

	/**
		The index of the next target.
	*/
	private var nextTargetIdx: Int {
		return currentTargetIdx + 1
	}

	/**
		The current target.
	*/
	private var currentTarget: Target {
		return targets[currentTargetIdx]
	}

	/**
		The next target.
	*/
	private var nextTarget: Target {
		return targets[nextTargetIdx]
	}

	/**
		The current stream.
	*/
	private var currentStream: PairedStream {
		return streams[currentLayer]
	}

}
