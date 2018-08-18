import Foundation
import Security

/**
	Defines how many bytes are send or retrieved at a time.
*/
private let ChunkSizeInBytes = 1024 * 1024

/**
	Errors that might occur while handling TLS streams.
*/
enum TlsStreamError: Error {

	/**
		This error indicates that reading from the TLS stream failed. The first
		argument is the error return from the TLS processing function and the
		second argument is the number of bytes that have been successfully
		processed before the error occurred.
	*/
	case readingFailed(OSStatus, Int)

	/**
		This error indicates that writing from the TLS stream failed. The first
		argument is the error return from the TLS processing function and the
		second argument is the number of bytes that have been successfully
		processed before the error occurred.
	*/
	case writingFailed(OSStatus, Int)

	/**
		This error indicates that the TLS stream could not be closed correctly.
	*/
	case closingFailed(OSStatus)

	/**
		This error indicates that the TLS handshake did not succeed.
	*/
	case handshakeFailed(OSStatus)
}

/**
	This protocol defines a deletgate for TLS sessions. It is implemented by
	input and output streams.
*/
protocol TlsSessionDelegate {

	/**
		This function is called, once a TLS session was established, i.e., after
		the TLS handshake was successfully performed. It indicates that the
		implementing stream's state can be set to `open`.
	*/
	func finishOpen()

	/**
		This function is called, once an error occurs.
	*/
	func setError(_ error: TlsStreamError)
}

extension InputStream {

	/**
		A convenience fuction to read all available data from an input stream.

		- returns:
			The data read from the input stream, `nil` if there are no bytes
			available.
	*/
	func readAll() -> Data? {
		guard hasBytesAvailable else {
			return nil
		}

		var data = Data()
		var bytesRead = 0
		var totalBytesRead = 0

		repeat {
			var chunk = Data(count: ChunkSizeInBytes)
			bytesRead = chunk.withUnsafeMutableBytes { chunkPtr in
				return self.read(chunkPtr, maxLength: ChunkSizeInBytes)
			}
			if 0 < bytesRead {
				totalBytesRead += bytesRead
				data.append(chunk.subdata(in: 0..<bytesRead))
			}
		} while self.hasBytesAvailable && bytesRead == ChunkSizeInBytes

		guard 0 < bytesRead else {
			return nil
		}

		return data
	}

}

extension OutputStream {

	/**
		A convenience function to write as much data to an output stream as
		possible. Maybe not all data can be written at once. The amount of bytes
		that have been written will be returned.

		- parameters:
			- data: The data that should be written to the output stream.

		- returns:
			The amount of bytes, that have been written to the output stream.
	*/
	func write(data: Data) -> Int {
		guard hasSpaceAvailable else {
			return -1
		}

		let totalBytesToSend = data.count

		var bytesSent = 0
		var totalBytesSent = 0

		repeat {
			let unsentData = data.subdata(in: totalBytesSent..<data.count)
			let bytesToSend = totalBytesToSend - totalBytesSent
			bytesSent = unsentData.withUnsafeBytes { unsentDataPtr in
				write(unsentDataPtr, maxLength: bytesToSend)
			}
			guard 0 <= bytesSent else {
				return bytesSent
			}
			totalBytesSent += bytesSent
		} while hasSpaceAvailable && 0 < bytesSent && totalBytesSent < totalBytesToSend

		return totalBytesSent
	}

}

/**
	This is a convenience class to tie input and output streams together. If a
	tunnel with multiple hops is established, each hop will have separate input
	and output streams.

	The API is similar to the [`Stream`](https://developer.apple.com/documentation/foundation/stream)
	class.
*/
class PairedStream {
	/// The input stream.
	let input: WrappedInputStream
	/// The output stream.
	let output: WrappedOutputStream

	/**
		Create a paired stream from an input and an output stream.

		- parameters:
			- input: The input stream.
			- output: The output stream.

		- see:
			[`Stream.open()`](https://developer.apple.com/documentation/foundation/stream/1411963-open)
	*/
	init(input: WrappedInputStream, output: WrappedOutputStream) {
		self.input = input
		self.output = output
	}

	/**
		Open both streams.

		- see:
			[`Stream.open()`](https://developer.apple.com/documentation/foundation/stream/1411963-open)
	*/
	func open() {
		input.open()
		output.open()
	}

	/**
		Close both streams.

		- see:
			[`Stream.close()`](https://developer.apple.com/documentation/foundation/stream/1410399-close)
	*/
	func close() {
		input.close()
		output.close()
	}

	/**
		Get or set the delegate for both streams.

		- see:
			[`Stream.delegate`](https://developer.apple.com/documentation/foundation/stream/1418423-delegate)
	*/
	var delegate: StreamDelegate? {
		get {
			return (input.delegate === output.delegate) ? input.delegate : nil
		}
		set(newDelegate) {
			input.delegate = newDelegate
			output.delegate = newDelegate
		}
	}

	/**
		Schedule both streams in a given run loop for a given mode.

		- parameters:
			- runLoop: The run loop.
			- mode: The run loop mode.

		- see:
			[`Stream.schedule(in:forMode:)`](https://developer.apple.com/documentation/foundation/stream/1417370-schedule)
	*/
	func schedule(in runLoop: RunLoop, forMode mode: RunLoopMode) {
		input.schedule(in: runLoop, forMode: mode)
		output.schedule(in: runLoop, forMode: mode)
	}

}

/**
	This class represents a TLS session. It manages the context for the session,
	which is used for input as well as output streams.
*/
class TlsSession {

	/// The TLS context.
	let context: SSLContext

	/// The session delegates.
	var delegates: [TlsSessionDelegate] = []

	/// Indicates whether the TLS handshake was interrupted.
	private var interrupted = false

	/**
		Initializes a TLS session for a given target and stream.

		- note:
			Default App Transport Security (ATS) settings are used. The ATS
			settings cannot be configured in the app's information property list
			(`Info.plist`).

		- parameters:
			- target: The target for the TLS session.
			- stream: The TCP stream to the target.
	*/
	init?(forTarget target: Target, withStream stream: PairedStream) {

		guard let context = SSLCreateContext(kCFAllocatorDefault, .clientSide, .streamType) else {
			print("Failed to create SSL context")
			return nil
		}
		guard SSLSetIOFuncs(context, tlsRead, tlsWrite) == errSecSuccess else {
			print("Unexpected result after setting IO functions")
			return nil
		}
		guard SSLSetConnection(context, Unmanaged.passRetained(stream).toOpaque()) == errSecSuccess else {
			print("Unexpected result after setting a connection reference")
			return nil
		}
		if let hostnameBytes = target.hostname.data(using: .ascii) {
			let status = hostnameBytes.withUnsafeBytes { hostnamePtr in
				SSLSetPeerDomainName(context, hostnamePtr, hostnameBytes.count)
			}
			guard status == errSecSuccess else {
				print("Unexpected result after setting the peer domain name for hostname validation: \(status)")
				return nil
			}
		}

		/*
			The default session configuration is not a secure one and uses
			TLSv1.0, therefore we should use a more secure configuration, such
			as ATS (App Transport Security).
		*/
		let config = kSSLSessionConfig_ATSv1
		guard SSLSetSessionConfig(context, config) == errSecSuccess else {
			print("Failed to set session config: \(config)")
			return nil
		}

		self.context = context
	}

	/**
		Destroys a TLS session.
	*/
	deinit {
		var connectionPtr: SSLConnectionRef? = nil
		SSLGetConnection(context, &connectionPtr)

		/*
			Release PairedStream that was passed as context to the SSLReadFunc
			and SSLWriteFunc callbacks.
		*/
		let _ = Unmanaged<PairedStream>.fromOpaque(connectionPtr!).takeRetainedValue()
	}

	// MARK: States

	/**
		The state of the TLS session.
	*/
	var state: SSLSessionState {
		var sessionState: SSLSessionState = .idle
		let sslStatus = SSLGetSessionState(context, &sessionState)
		assert(sslStatus == noErr)
		return sessionState
	}

	// MARK: Triggers

	/**
		This function is called when there is space available for the handshake.
		When called it will initiate a TLS handshake or send additional data in
		order to complete the handshake (it is a two-way process).
	*/
	func spaceAvailableForHandshake() {
		guard !interrupted else {
			return
		}

		handleHandshakeResult(status: shakeHands())
	}

	/**
		This function is called when there are bytes available for the
		handshake.
	*/
	func bytesAvailableForHandshake() {
		guard !interrupted else {
			return
		}

		guard state == .handshake else {
			return
		}

		handleHandshakeResult(status: shakeHands())
	}

	// MARK: Helpers

	/**
		Initiate a TLS handshake.

		- returns:
			A status returned by the secure transport library.
	*/
	private func shakeHands() -> OSStatus {
		assert(state != .connected, "Already shook hands!")

		var status = errSSLWouldBlock

		repeat {
			status = SSLHandshake(context)
		} while status == errSSLWouldBlock

		return status
	}

	/**
		Deceide how to handle the result while shaking hands. If there is no
		error, the streams will be opened. If the current handshake blocks, it
		needs to be continue, either by writing some more data, if space is
		available, or by waiting for a response of the target.

		- parameters:
			- status: The status from the secure transport library.
	*/
	private func handleHandshakeResult(status: OSStatus) {
		switch status {
			case noErr:
				assert(state == .connected)

				for delegate in delegates {
					delegate.finishOpen()
				}

				// Remove cyclic reference to delegates, they're no longer required
				delegates.removeAll()
			case errSSLWouldBlock:
				{}() // Do nothing
			default:
				interrupted = true
				for delegate in delegates {
					delegate.setError(.handshakeFailed(status))
				}

				// Remove cyclic reference to delegates, they're no longer required
				delegates.removeAll()
		}
	}
}

/**
	This class wraps an input stream.

	This somehow helps handling input streams. Looks like one cannot direcly
	use a sub-classed input stream, so there is a stream kept as an internal
	variable. In addition there is a computed property to return this variable.
	That way it can be overwritten by sub classe. Maybe there is a better way to
	handle this.

	- see:
		[`InputStream`](https://developer.apple.com/documentation/foundation/inputstream)
*/
class WrappedInputStream: InputStream, StreamDelegate {

	/// The internal input stream.
	let _stream: InputStream
	/// Returns the internal input stream.
	var stream: InputStream { return _stream }

	/// The internal delegate.
	weak var _delegate: StreamDelegate? = nil

	/**
		Initialize a wrapped stream with a given input stream.

		- parameters:
			- stream: The input stream.
	*/
	init(_ stream: InputStream) {
		self._stream = stream

		super.init(data: Data())

		// Replace the original streams delegate
		_delegate = stream.delegate
		stream.delegate = self
	}

	// MARK: Stream

	/**
		Get or set the delegate for the stream.

		- see:
			[`Stream.delegate`](https://developer.apple.com/documentation/foundation/stream/1418423-delegate)
	*/
	override var delegate: StreamDelegate? {
		get { return _delegate }
		set(newDelegate) { _delegate = newDelegate }
	}

	/**
		Get the status for the stream.

		- see:
			[`Stream.streamStatus`](https://developer.apple.com/documentation/foundation/stream/1413038-streamstatus)
	*/
	override var streamStatus: Stream.Status {
		return stream.streamStatus
	}

	/**
		Get the error for the stream.

		- see:
			[`Stream.streamError`](https://developer.apple.com/documentation/foundation/stream/1416359-streamerror)
	*/
	override var streamError: Error? {
		return stream.streamError
	}

	/**
		Open the stream.

		- see:
			[`Stream.open()`](https://developer.apple.com/documentation/foundation/stream/1411963-open)
	*/
	override func open() {
		stream.open()
	}

	/**
		Close the stream.

		- see:
			[`Stream.close()`](https://developer.apple.com/documentation/foundation/stream/1410399-close)
	*/
	override func close() {
		stream.close()
	}

	/**
		Schedule the stream in a given run loop for a given mode.

		- parameters:
			- runLoop: The run loop.
			- mode: The run loop mode.

		- see:
			[`Stream.schedule(in:forMode:)`](https://developer.apple.com/documentation/foundation/stream/1417370-schedule)
	*/
	override func schedule(in runLoop: RunLoop, forMode mode: RunLoopMode) {
		stream.schedule(in: runLoop, forMode: mode)
	}

	/**
		Remove the stream from a given run loop for a given mode.

		- parameters:
			- runLoop: The run loop.
			- mode: The run loop mode.

		- see:
			[`Stream.schedule(from:forMode:)`](https://developer.apple.com/documentation/foundation/stream/1411285-remove)
	*/
	override func remove(from runLoop: RunLoop, forMode mode: RunLoopMode) {
		stream.remove(from: runLoop, forMode: mode)
	}

	/**
		Get a property for a given key.

		- parameters:
			- key: The name of the property.

		- see:
			[`Stream.property(forKey:)`](https://developer.apple.com/documentation/foundation/stream/1410226-property)
	*/
	override func property(forKey key: Stream.PropertyKey) -> Any? {
		return stream.property(forKey: key)
	}

	/**
		Set a property for a given key to a given value.

		- parameters:
			- property: The value of the property.
			- key: The name of the property.

		- see:
			[`Stream.setProperty(_:forKey:)`](https://developer.apple.com/documentation/foundation/stream/1412045-setproperty)
	*/
	override func setProperty(_ property: Any?, forKey key: Stream.PropertyKey) -> Bool {
		return stream.setProperty(property, forKey: key)
	}

	// MARK: InputStream

	/**
		Indicates whether bytes are available on the wrapped input stream.

		- see:
			[`InputStream.hasBytesAvailable`](https://developer.apple.com/documentation/foundation/inputstream/1409410-hasbytesavailable)
	*/
	override var hasBytesAvailable: Bool {
		return stream.hasBytesAvailable
	}

	/**
		Read bytes from the wrapped input stream.

		- parameters:
			- dataPtr: A pointer to the buffer, to which the bytes should be
				read.
			- maxLength: The maximum lenghts of bytes to be read.

		- returns:
			The amount of bytes actually read.

		- see:
			[`InputStream.read(_:maxLength:)`](https://developer.apple.com/documentation/foundation/inputstream/1411544-read)
	*/
	override func read(_ dataPtr: UnsafeMutablePointer<UInt8>, maxLength: Int) -> Int {
		let bytesProcessed = stream.read(dataPtr, maxLength: maxLength)

		assert(bytesProcessed <= maxLength, "More bytes processed than allowed!")

		return bytesProcessed
	}

	/**
		Get the buffer of the wrapped input stream.

		- parameters:
			- buffer: A pointer to the buffer.
			- length: A pointer to a number, where the length of the buffer will
				be stored.

		- returns:
			`true` if the buffer is available.
	*/
	override func getBuffer(_ buffer: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>, length len: UnsafeMutablePointer<Int>) -> Bool {
		return stream.getBuffer(buffer, length: len)
	}

	// MARK: StreamDelegate

	/**
		Delegate function for the wrapped stream.

		- parameters:
			- aStream: The stream calling the delegate. Has to be the wrapped
				input stream.
			- eventCode: The event that occurred.

		- see:
			[`StreamDelegate.stream(_:handle:)`](https://developer.apple.com/documentation/foundation/streamdelegate/1410079-stream)
	*/
	func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
		assert(aStream === stream, "Do not act as a delegate to another stream!")
		assert(!eventCode.contains(.hasSpaceAvailable), "Event should not occur on InputStream!")

		notifyDelegate(handle: eventCode)
	}

	// MARK: Helpers

	/**
		Notify delegates that events occurred.

		- parameters:
			- events: The events.
	*/
	func notifyDelegate(handle events: Stream.Event) {
		delegate?.stream!(self, handle: events)
	}
}

/**
	This class wraps an output stream.

	This somehow helps handling output streams. Looks like one cannot direcly
	use a sub-classed output stream, so there is a stream kept as an internal
	variable. In addition there is a computed property to return this variable.
	That way it can be overwritten by sub classe. Maybe there is a better way to
	handle this.

	- see:
		[`OutputStream`](https://developer.apple.com/documentation/foundation/outputstream)
*/
class WrappedOutputStream: OutputStream, StreamDelegate {

	/// The internal output stream.
	let _stream: OutputStream
	/// Returns the internal output stream.
	var stream: OutputStream { return _stream }

	/// The internal delegate.
	weak var _delegate: StreamDelegate? = nil

	/**
		Initialize a wrapped stream with a given output stream.

		- parameters:
			- stream: The output stream.
	*/
	init(_ stream: OutputStream) {
		self._stream = stream

		super.init(toMemory: ())

		// Replace the original streams delegate
		_delegate = stream.delegate
		stream.delegate = self
	}

	// MARK: Stream

	/**
		Get or set the delegate for the stream.

		- see:
			[`Stream.delegate`](https://developer.apple.com/documentation/foundation/stream/1418423-delegate)
	*/
	override var delegate: StreamDelegate? {
		get { return _delegate }
		set(newDelegate) { _delegate = newDelegate }
	}

	/**
		Get the status for the stream.

		- see:
			[`Stream.streamStatus`](https://developer.apple.com/documentation/foundation/stream/1413038-streamstatus)
	*/
	override var streamStatus: Stream.Status {
		return stream.streamStatus
	}

	/**
		Get the error for the stream.

		- see:
			[`Stream.streamError`](https://developer.apple.com/documentation/foundation/stream/1416359-streamerror)
	*/
	override var streamError: Error? {
		return stream.streamError
	}

	/**
		Open the stream.

		- see:
			[`Stream.open()`](https://developer.apple.com/documentation/foundation/stream/1411963-open)
	*/
	override func open() {
		stream.open()
	}

	/**
		Close the stream.

		- see:
			[`Stream.close()`](https://developer.apple.com/documentation/foundation/stream/1410399-close)
	*/
	override func close() {
		stream.close()
	}

	/**
		Schedule the stream in a given run loop for a given mode.

		- parameters:
			- runLoop: The run loop.
			- mode: The run loop mode.

		- see:
			[`Stream.schedule(in:forMode:)`](https://developer.apple.com/documentation/foundation/stream/1417370-schedule)
	*/
	override func schedule(in runLoop: RunLoop, forMode mode: RunLoopMode) {
		stream.schedule(in: runLoop, forMode: mode)
	}

	/**
		Remove the stream from a given run loop for a given mode.

		- parameters:
			- runLoop: The run loop.
			- mode: The run loop mode.

		- see:
			[`Stream.schedule(from:forMode:)`](https://developer.apple.com/documentation/foundation/stream/1411285-remove)
	*/
	override func remove(from runLoop: RunLoop, forMode mode: RunLoopMode) {
		stream.remove(from: runLoop, forMode: mode)
	}

	/**
		Get a property for a given key.

		- parameters:
			- key: The name of the property.

		- see:
			[`Stream.property(forKey:)`](https://developer.apple.com/documentation/foundation/stream/1410226-property)
	*/
	override func property(forKey key: Stream.PropertyKey) -> Any? {
		return stream.property(forKey: key)
	}

	/**
		Set a property for a given key to a given value.

		- parameters:
			- property: The value of the property.
			- key: The name of the property.

		- see:
			[`Stream.setProperty(_:forKey:)`](https://developer.apple.com/documentation/foundation/stream/1412045-setproperty)
	*/
	override func setProperty(_ property: Any?, forKey key: Stream.PropertyKey) -> Bool {
		return stream.setProperty(property, forKey: key)
	}

	// MARK: InputStream

	/**
		Indicates whether space is available on the wrapped output stream.

		- see:
			[`OutputStream.hasSpaceAvailable`](https://developer.apple.com/documentation/foundation/outputstream/1411335-hasspaceavailable)
	*/
	override var hasSpaceAvailable: Bool {
		return stream.hasSpaceAvailable
	}

	/**
		Write bytes to the wrapped output stream.

		- parameters:
			- dataPtr: A pointer to the buffer, from which the bytes should be
				written.
			- maxLength: The maximum lenghts of bytes to be written.

		- returns:
			The amount of bytes actually written.

		- see:
			[`OutputStream.write(_:maxLength:)`](https://developer.apple.com/documentation/foundation/outputstream/1410720-write)
	*/
	override func write(_ dataPtr: UnsafePointer<UInt8>, maxLength: Int) -> Int {
		let bytesProcessed = stream.write(dataPtr, maxLength: maxLength)

		assert(bytesProcessed <= maxLength, "More bytes processed than allowed!")

		return bytesProcessed
	}

	// MARK: StreamDelegate

	/**
		Delegate function for the wrapped stream.

		- parameters:
			- aStream: The stream calling the delegate. Has to be the wrapped
				output stream.
			- eventCode: The event that occurred.

		- see:
			[`StreamDelegate.stream(_:handle:)`](https://developer.apple.com/documentation/foundation/streamdelegate/1410079-stream)
	*/
	func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
		assert(aStream === stream, "Do not act as a delegate to another stream!")
		assert(!eventCode.contains(.hasBytesAvailable), "Event should not occur on OutputStream!")

		notifyDelegate(handle: eventCode)
	}

	// MARK: Helpers

	/**
		Notify delegates that events occurred.

		- parameters:
			- events: The events.
	*/
	func notifyDelegate(handle events: Stream.Event) {
		delegate?.stream!(self, handle: events)
	}

}

/**
	This class is TLS encrypted input stream.
*/
class TLSInputStream: WrappedInputStream, TlsSessionDelegate {
	/// The TLS session
	let session: TlsSession

	/// A buffer of data, that have been read.
	var buffer = Data()

	/**
		The index pointing at a position in the buffer. This avoids moving
		around and re-allocating the buffer.
	*/
	var bufferIdx = 0

	/// The status of the stream.
	var status: Stream.Status = .notOpen
	/// An error that might have occurred.
	var error: Error? = nil

	/// Return the wrapped input stream.
	override var stream: WrappedInputStream {
		return super.stream as! WrappedInputStream
	}

	/**
		Initialize a TLS encrypted input stream with a given TLS session.

		- parameters:
			- stream: The wrapped input stream.
			- session: The TLS session.
	*/
	init(_ stream: WrappedInputStream, withSession session: TlsSession) {
		self.session = session

		super.init(stream)

		session.delegates.insert(self, at: 0)
	}

	/**
		Returns the size of the internal TLS buffer. Not to be confused with
		`buffer`.
	*/
	var internalTlsBufferSize: Int {
		var result = 0
		let sslStatus = SSLGetBufferedReadSize(session.context, &result)
		assert(sslStatus == noErr)
		return result
	}

	// MARK: Stream

	/**
		Get the status for the stream.

		- see:
			[`Stream.streamStatus`](https://developer.apple.com/documentation/foundation/stream/1413038-streamstatus)
	*/
	override var streamStatus: Stream.Status {
		return status
	}

	/**
		Get the error for the stream.

		- see:
			[`Stream.streamError`](https://developer.apple.com/documentation/foundation/stream/1416359-streamerror)
	*/
	override var streamError: Error? {
		return error
	}

	/**
		Open the stream. The stream will actually open after the TLS handshake
		is completed.

		- see:
			[`Stream.open()`](https://developer.apple.com/documentation/foundation/stream/1411963-open)
	*/
	override func open() {
		status = .opening

		switch stream.streamStatus {
			case .notOpen:
				stream.open()
			case .open:
				self.stream(stream, handle: .openCompleted)
				if stream.hasBytesAvailable {
					self.stream(stream, handle: .hasBytesAvailable)
				}
			default:
				assert(false, "Unexpected stream state: \(stream.streamStatus)")
		}
	}

	/**
		Close the stream.

		- see:
			[`Stream.close()`](https://developer.apple.com/documentation/foundation/stream/1410399-close)
	*/
	override func close() {
		stream.close()
		status = .closed
	}

	/**
		Get a property for a given key. This is a no-op and does nothing.

		- parameters:
			- key: The name of the property.

		- returns:
			This always returns `nil`.

		- see:
			[`Stream.property(forKey:)`](https://developer.apple.com/documentation/foundation/stream/1410226-property)
	*/
	override func property(forKey key: Stream.PropertyKey) -> Any? {
		return nil
	}

	/**
		Set a property for a given key to a given value. This is a no-op and
		does nothing.

		- parameters:
			- property: The value of the property.
			- key: The name of the property.

		- returns:
			This always returns `false`.

		- see:
			[`Stream.setProperty(_:forKey:)`](https://developer.apple.com/documentation/foundation/stream/1412045-setproperty)
	*/
	override func setProperty(_ property: Any?, forKey key: Stream.PropertyKey) -> Bool {
		return false
	}

	// MARK: InputStream

	/**
		Indicates whether bytes are available on the wrapped input stream.

		- see:
			[`InputStream.hasBytesAvailable`](https://developer.apple.com/documentation/foundation/inputstream/1409410-hasbytesavailable)
	*/
	override var hasBytesAvailable: Bool {
		return !buffer.isEmpty || stream.hasBytesAvailable
	}

	/**
		Read bytes from the wrapped input stream. This will decrypt the data.

		- parameters:
			- dataPtr: A pointer to the buffer, to which the bytes should be
				read.
			- maxLength: The maximum lenghts of bytes to be read.

		- returns:
			The amount of bytes actually read.

		- see:
			[`InputStream.read(_:maxLength:)`](https://developer.apple.com/documentation/foundation/inputstream/1411544-read)
	*/
	override func read(_ dataPtr: UnsafeMutablePointer<UInt8>, maxLength: Int) -> Int {
		assert(status == .open)

		/*
			Workaround (part 1): It is possible that we are trying to read data from a session
			that is already closed, and this read may succeed if there is data cached
			locally by the framework we are using (Security.framework, which is
			handling the SSL context)
		*/
		assert(session.state == .connected || session.state == .closed || session.state == .aborted)

		// Buffer everything from the wrapped stream
		var sslStatus = noErr
		while stream.hasBytesAvailable || sslStatus == errSSLWouldBlock {

			/*
				Workaround (part 2):
				Apple's Security framework has a peculiar behaviour.
				If data is cached by that framework, but we request more data than is
				currently cached, the framework will attempt to fetch the remaining data
				first before returning. Unfortunately, if the connection has already been closed,
				this attempt will result in an infinite loop (at least using this code).

				Therefore, in the event that the connection has already been closed, we
				get the size of the currently buffered data and simply request this data.
				For more information, see [0].

				It is worth noting that in this case, hasBytesAvailable will *still*
				return true because the underlying input stream returns true for that call,
				even though no more data is there. (This is the cause for the infinite loop)

				[0]: https://github.com/seanmonstar/reqwest/issues/26#issuecomment-290205986
			*/
			let chunkSize: Int
			if [errSSLClosedAbort, errSSLClosedGraceful, errSSLClosedNoNotify].contains(sslStatus) {
				chunkSize = min(internalTlsBufferSize, ChunkSizeInBytes)
				// internal buffer is empty, stop trying to read more data.
				guard 0 < chunkSize else { break }
			} else {
				chunkSize = ChunkSizeInBytes
			}

			var chunk = Data(count: chunkSize)
			var bytesProcessed = 0
			sslStatus = chunk.withUnsafeMutableBytes { chunkPtr in
				SSLRead(session.context, chunkPtr, chunkSize, &bytesProcessed)
			}
			assert(0 <= bytesProcessed)
			assert(bytesProcessed <= chunkSize, "More bytes processed than allowed!")

			buffer.append(chunk.subdata(in: 0..<bytesProcessed))
		}

		// Serve actual data from buffer.
		let nonConsumedBufferSize = buffer.count - bufferIdx
		let bytesProcessed = min(nonConsumedBufferSize, maxLength)

		buffer.copyBytes(to: dataPtr, from: bufferIdx..<(bufferIdx + bytesProcessed))

		bufferIdx += bytesProcessed

		// Clear buffer once everything was consumed.
		if bufferIdx == buffer.count {
			buffer.removeAll()
			bufferIdx = 0
		}

		/*
			Workaround (part 3)
			sslStatus is not noErr, and we still do not want to alert others, because the server
			closed the connection on us. The errSSLClosedAbort condition should ideally be
			treated as an error, but at the moment, this is needed to return a useful result.
			Further investigating is needed!
		*/
		guard [noErr, errSSLClosedAbort, errSSLClosedGraceful, errSSLClosedNoNotify].contains(sslStatus) else {
			setError(.readingFailed(sslStatus, bytesProcessed))
			return -1
		}

		return bytesProcessed
	}

	/**
		Get the buffer of the wrapped input stream. This is a no-op and does
		nothing.

		- parameters:
			- buffer: A pointer to the buffer.
			- length: A pointer to a number, where the length of the buffer will
				be stored.

		- returns:
			This always returns `false`.
	*/
	override func getBuffer(_ buffer: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>, length len: UnsafeMutablePointer<Int>) -> Bool {
		return false
	}

	// MARK: StreamDelegate

	/**
		Delegate function for the wrapped stream.

		- parameters:
			- aStream: The stream calling the delegate. Has to be the wrapped
				input stream.
			- eventCode: The event that occurred.

		- see:
			[`StreamDelegate.stream(_:handle:)`](https://developer.apple.com/documentation/foundation/streamdelegate/1410079-stream)
	*/
	override func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
		assert(aStream === stream, "Do not act as a delegate to another stream!")
		assert(!eventCode.contains(.hasSpaceAvailable), "Event should not occur on InputStream!")

		if eventCode.contains(.hasBytesAvailable) {
			switch status {
				case .opening:
					if [.idle, .handshake].contains(session.state) {
						session.bytesAvailableForHandshake()
					} else {
						assert(false)
					}
				case .open:
					notifyDelegate(handle: .hasBytesAvailable)
				default:
					assert(false, "Unexpected state: \(status)")
			}
		}

		if eventCode.contains(.errorOccurred) {
			error = stream.streamError
			status = .error
			notifyDelegate(handle: .errorOccurred)
		}

		if eventCode.contains(.endEncountered) {
			status = .atEnd
			notifyDelegate(handle: .endEncountered)
		}
	}

	// MARK: TlsSessionDelegate

	/**
		This function is called, once a TLS session was established, i.e., after
		the TLS handshake was successfully performed. It indicates that the
		implementing stream's state can be set to `open`.
	*/
	func finishOpen() {
		status = .open
		notifyDelegate(handle: .openCompleted)
		if hasBytesAvailable {
			notifyDelegate(handle: .hasBytesAvailable)
		}
	}

	/**
		This function is called, once an error occurs.
	*/
	func setError(_ error: TlsStreamError) {
		self.error = error
		status = .error
		notifyDelegate(handle: .errorOccurred)
	}

}

/**
	This class is TLS encrypted output stream.
*/
class TLSOutputStream: WrappedOutputStream, TlsSessionDelegate {
	/// The TLS session
	let session: TlsSession

	/// The status of the stream.
	var status: Stream.Status = .notOpen
	/// An error that might have occurred.
	var error: Error? = nil

	/**
		Initialize a TLS encrypted output stream with a given TLS session.

		- parameters:
			- stream: The wrapped output stream.
			- session: The TLS session.
	*/
	init(_ stream: OutputStream, withSession session: TlsSession) {
		self.session = session

		super.init(stream)

		session.delegates.append(self)
	}

	// MARK: Stream

	/**
		Get the status for the stream.

		- see:
			[`Stream.streamStatus`](https://developer.apple.com/documentation/foundation/stream/1413038-streamstatus)
	*/
	override var streamStatus: Stream.Status {
		return status
	}

	/**
		Get the error for the stream.

		- see:
			[`Stream.streamError`](https://developer.apple.com/documentation/foundation/stream/1416359-streamerror)
	*/
	override var streamError: Error? {
		return error
	}

	/**
		Open the stream. The stream will actually open after the TLS handshake
		is completed. This will initiate a handshake.

		- see:
			[`Stream.open()`](https://developer.apple.com/documentation/foundation/stream/1411963-open)
	*/
	override func open() {
		status = .opening

		switch stream.streamStatus {
			case .notOpen:
				stream.open()
			case .open:
				stream(stream, handle: .openCompleted)
				if hasSpaceAvailable {
					stream(stream, handle: .hasSpaceAvailable)
				}
			default:
				assert(false, "Unexpected stream state: \(stream.streamStatus)")
		}
	}

	/**
		Tries to gracefully close the TLS stream.

		- see:
			[`Stream.close()`](https://developer.apple.com/documentation/foundation/stream/1410399-close)
	*/
	override func close() {
		let sslStatus = SSLClose(session.context)
		guard [noErr, errSSLClosedAbort, errSSLClosedGraceful, errSSLClosedNoNotify].contains(sslStatus) else {
			setError(.closingFailed(sslStatus))
			return
		}
		stream.close()
		status = .closed
	}

	/**
		Get a property for a given key. This is a no-op and does nothing.

		- parameters:
			- key: The name of the property.

		- returns:
			This always returns `nil`.

		- see:
			[`Stream.property(forKey:)`](https://developer.apple.com/documentation/foundation/stream/1410226-property)
	*/
	override func property(forKey key: Stream.PropertyKey) -> Any? {
		return nil
	}

	/**
		Set a property for a given key to a given value. This is a no-op and
		does nothing.

		- parameters:
			- property: The value of the property.
			- key: The name of the property.

		- returns:
			This always returns `false`.

		- see:
			[`Stream.setProperty(_:forKey:)`](https://developer.apple.com/documentation/foundation/stream/1412045-setproperty)
	*/
	override func setProperty(_ property: Any?, forKey key: Stream.PropertyKey) -> Bool {
		return false
	}

	// MARK: OutputStream

	/**
		Indicates whether space is available on the wrapped output stream.

		- see:
			[`OutputStream.hasSpaceAvailable`](https://developer.apple.com/documentation/foundation/outputstream/1411335-hasspaceavailable)
	*/
	override var hasSpaceAvailable: Bool {
		return stream.hasSpaceAvailable
	}

	/**
		Write bytes to the wrapped output stream. The bytes will be encrypted.

		- parameters:
			- dataPtr: A pointer to the buffer, from which the bytes should be
				written.
			- maxLength: The maximum lenghts of bytes to be written.

		- returns:
			The amount of bytes actually written.

		- see:
			[`OutputStream.write(_:maxLength:)`](https://developer.apple.com/documentation/foundation/outputstream/1410720-write)
	*/
	override func write(_ dataPtr: UnsafePointer<UInt8>, maxLength: Int) -> Int {
		assert(status == .open)

		// Do not write if the session has already been closed.
		guard session.state != .closed else {
			return 0
		}

		assert(session.state == .connected)

		var processedBytes = 0
		var sslStatus = SSLWrite(session.context, dataPtr, maxLength, &processedBytes)

		// Workaround, see https://lists.apple.com/archives/macnetworkprog/2005/Oct/msg00075.html
		// The Security framework returns errSSLWouldBlock when the request could not be
		// sent in a single packet. However, the entire data is copied to an internal buffer
		// (but not automatically sent)
		// To force this data to be sent, we simply repeatedly SSLWrite with a 0 length
		// buffer, until a different status is returned.
		if (processedBytes == maxLength) {
			while (sslStatus == errSSLWouldBlock) {
				sslStatus = SSLWrite(session.context, dataPtr, 0, &processedBytes)
			}
		}

		guard [noErr, errSSLClosedAbort, errSSLClosedGraceful, errSSLClosedNoNotify].contains(sslStatus) else {
			setError(.writingFailed(sslStatus, processedBytes))
			return -1
		}

		return maxLength
	}

	// MARK: StreamDelegate

	/**
		Delegate function for the wrapped stream.

		- parameters:
			- aStream: The stream calling the delegate. Has to be the wrapped
				output stream.
			- eventCode: The event that occurred.

		- see:
			[`StreamDelegate.stream(_:handle:)`](https://developer.apple.com/documentation/foundation/streamdelegate/1410079-stream)
	*/
	override func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
		assert(aStream === stream, "Do not act as a delegate to another stream!")
		assert(!eventCode.contains(.hasBytesAvailable), "Event should not occur on OutputStream!")

		if eventCode.contains(.hasSpaceAvailable) {
			switch status {
				case .opening:
					if [.idle, .handshake].contains(session.state) {
						session.spaceAvailableForHandshake()
					} else {
						assert(false)
					}
				case .open:
					notifyDelegate(handle: .hasSpaceAvailable)
				default:
					assert(false, "Unexpected state '\(status)'")
			}
		}

		if eventCode.contains(.errorOccurred) {
			error = stream.streamError
			status = .error
			notifyDelegate(handle: .errorOccurred)
		}

		if eventCode.contains(.endEncountered) {
			status = .atEnd
			notifyDelegate(handle: .endEncountered)
		}
	}

	// MARK: TlsStreamDelegate

	/**
		This function is called, once a TLS session was established, i.e., after
		the TLS handshake was successfully performed. It indicates that the
		implementing stream's state can be set to `open`.
	*/
	func finishOpen() {
		status = .open
		notifyDelegate(handle: .openCompleted)
		if hasSpaceAvailable {
			notifyDelegate(handle: .hasSpaceAvailable)
		}
	}

	/**
		This function is called, once an error occurs.
	*/
	func setError(_ error: TlsStreamError) {
		self.error = error
		status = .error
		notifyDelegate(handle: .errorOccurred)
	}

}

/**
	The function that actually handles TLS reading. This has to be a static
	function, therefore a paired stream is stored inside the connection
	reference in order to be able to read data from it.

	- parameters:
		- connectionPtr: A pointer to the paired stream, from which data should
			be read and decrypted.
		- dataPtr: A pointer to a byte array, where the decrypted data should be
			stored.
		- dataLengthPtr: A pointer to an integer, where the amount of read bytes
			is stored.

	- returns:
		A status, as defined by the secure transport library.
*/
private func tlsRead(
	connectionPtr: SSLConnectionRef,
	dataPtr: UnsafeMutableRawPointer,
	dataLengthPtr: UnsafeMutablePointer<Int>
) -> OSStatus {
	let stream = Unmanaged<PairedStream>.fromOpaque(connectionPtr).takeUnretainedValue()
	let maxLength = dataLengthPtr.pointee
	dataLengthPtr.pointee = 0 // No bytes processed, yet

	guard 0 < maxLength else {
		return noErr
	}

	guard stream.input.hasBytesAvailable else {
		return errSSLWouldBlock
	}

	let bytesRead = stream.input.read(dataPtr.assumingMemoryBound(to: UInt8.self), maxLength: maxLength)

	guard 0 <= bytesRead else {
		switch errno {
			case ENOENT:
				return errSSLClosedGraceful
			case EWOULDBLOCK:
				return errSSLWouldBlock
			case ECONNRESET:
				return errSSLClosedAbort
			default:
				return errSecIO
		}
	}

	guard 0 != bytesRead else {
		return errSSLClosedNoNotify
	}

	dataLengthPtr.pointee = bytesRead
	return (bytesRead < maxLength) ? errSSLWouldBlock : noErr
}

/**
	A function that actually handles TLS writing. This has to be a static
	function, therefore a paired stream is stored inside the connection
	reference in order to be able to write data to it.

	- parameters:
		- connectionPtr: A pointer to the paired stream, to which data should be
			encrypted and written.
		- dataPtr: A pointer to the byte array containing the data which should
			be written.
		- dataLengthPtr: A pointer to an integer containing the maximum amount
			of bytes, that should be written. The number is replaced with the
			amount of bytes actually written.

	- returns:
		A status, as defined by the secure transport library.
*/
private func tlsWrite(
	connectionPtr: SSLConnectionRef,
	dataPtr: UnsafeRawPointer,
	dataLengthPtr: UnsafeMutablePointer<Int>
) -> OSStatus {
	let stream = Unmanaged<PairedStream>.fromOpaque(connectionPtr).takeUnretainedValue()
	let maxLength = dataLengthPtr.pointee
	dataLengthPtr.pointee = 0 // No bytes processed, yet

	guard 0 < maxLength else {
		return noErr
	}

	guard stream.output.hasSpaceAvailable else {
		return errSSLWouldBlock
	}

	let bytesWritten = stream.output.write(dataPtr.assumingMemoryBound(to: UInt8.self), maxLength: maxLength)

	guard 0 <= bytesWritten else {
		switch errno {
			case ENOENT:
				return errSSLClosedGraceful
			case EWOULDBLOCK:
				return errSSLWouldBlock
			case ECONNRESET:
				return errSSLClosedAbort
			default:
				return errSecIO
		}
	}

	guard 0 != bytesWritten else {
		return errSSLClosedNoNotify
	}

	dataLengthPtr.pointee = bytesWritten
	return (bytesWritten < maxLength) ? errSSLWouldBlock : noErr
}
