import Foundation

enum GenericError: Error {
	case generic(String)
}

/**
	#### Example

	```swift
	let target = Target(withHostname: "www.example.com", andPort: 443)!
	let shalon = Shalon(withTarget: target)

	shalon.addLayer(Target(withHostname: "proxy1.example.com", andPort: 8443)!)
	shalon.addLayer(Target(withHostname: "proxy2.example.com", andPort: 8442)!)
	shalon.addLayer(Target(withHostname: "proxy3.example.com", andPort: 8441)!)

	shalon.issue(request: Request(withMethod: .head, andUrl: url)!) {
	    optionalResponse, optionalError in
	    // TODO Do something
	}
	```
**/
public class Shalon: NSObject, StreamDelegate {

	private enum State {
		case inactive
		case shouldEstablishTunnelConnection
		case expectTunnelConnectionEstablished
		case shouldSendHttpRequest
		case expectHttpResponse
	}

	public typealias CompletionHandler = (Http.Response?, Error?) -> Void

	private var state: State = .inactive
	private var targets: [Target] = []
	private var streams: [PairedStream] = []
	private var currentLayer = 0

	private var request: Http.Request! = nil
	private var completionHandler: CompletionHandler! = nil

	public init(withTarget target: Target) {
		super.init()

		addLayer(target)
	}

	public func addLayer(_ target: Target) {
		targets.insert(target, at: 0)
	}

	public func issue(request: Http.Request, completionHandler: @escaping CompletionHandler) {
		assert(!targets.isEmpty)
		assert(streams.isEmpty)
		assert(self.request == nil)

		self.request = request
		self.completionHandler = completionHandler

		// Initialize streams
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
		let wrappedOutputStream = WrappedOutputStream(outputStream, boundTo: wrappedInputStream)
		let stream = PairedStream(input: wrappedInputStream, output: wrappedOutputStream)
		streams.append(stream)

		/*
			The established TCP connection should be TLS secured, as soon as
			bytes can be written to the output stream.
		 */
		state = nextState

		wrapCurrentLayerWithTls()
	}

	private func wrapCurrentLayerWithTls() {
		assert(currentLayer < targets.count, "Cannot have more layers than targets!")
		assert(currentLayer <= streams.count, "Cannot have more layers than streams!")

		let target = targets[currentLayer]
		let stream = streams.last!

		guard let session = TlsSession(forTarget: target, withStream: stream) else {
			print("Failed to create TLS session.")
			return
		}

		let wrappedInputStream = TLSInputStream(stream.input, withSession: session)
		let wrappedOutputStream = TLSOutputStream(stream.output, boundTo: wrappedInputStream, withSession: session)
		let wrappedStream = PairedStream(input: wrappedInputStream, output: wrappedOutputStream)
		streams.append(wrappedStream)

		currentLayer += 1

		wrappedStream.delegate = self
		wrappedStream.schedule(in: RunLoop.current, forMode: .defaultRunLoopMode)
		wrappedStream.open()

		if RunLoop.main != RunLoop.current {
			RunLoop.current.run()
		}
	}

	// MARK: StreamDelegate

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

	private func errorOccurred(_ error: GenericError) {
		errorOccurred(error as Error)
	}

	private func errorOccurred(_ error: Error) {
		completionHandler(nil, error)
		reset()
	}

	private func reset() {
		guard state != .inactive else {
			return
		}

		currentStream.delegate = nil // Ignore failures during close-up.
		currentStream.close()

		streams.removeAll()
		currentLayer = 0

		request = nil
		completionHandler = nil

		state = .inactive
	}

	private func expectHttpResponse(fromStream stream: InputStream) -> Http.Response? {
		assert(stream.hasBytesAvailable)

		guard let rawResponse = stream.readAll() else {
			return nil
		}
		return Http.Response(withRawData: rawResponse)
	}

	private func send(request: Http.Request, toStream stream: OutputStream) {
		assert(stream.hasSpaceAvailable)

		guard let rawRequest = request.compose() else {
			print("Failed to compose request")
			return
		}

		guard 0 < stream.write(data: rawRequest) else {
			print("Not everything was sent")
			return
		}
	}

	private var nextState: State {
		// There is one more layers than targets
		return (nextTargetIdx < targets.count) ? .shouldEstablishTunnelConnection : .shouldSendHttpRequest
	}

	private var firstHop: Target {
		return targets.first!
	}

	private var currentTargetIdx: Int {
		assert((0..<streams.count).contains(currentLayer))
		assert(currentLayer <= targets.count)

		return (currentLayer < 2) ? 0 : currentLayer - 1
	}

	private var nextTargetIdx: Int {
		return currentTargetIdx + 1
	}

	private var currentTarget: Target {
		return targets[currentTargetIdx]
	}

	private var nextTarget: Target {
		return targets[nextTargetIdx]
	}

	private var currentStream: PairedStream {
		assert((0..<streams.count).contains(currentLayer))

		return streams[currentLayer]
	}
}
