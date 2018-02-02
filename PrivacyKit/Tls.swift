import Foundation
import Security

private let ChunkSizeInBytes = 1024 * 1024

enum TlsStreamError: Error {
	case readingFailed(OSStatus, Int)
	case writingFailed(OSStatus, Int)
	case closingFailed(OSStatus)
	case handshakeFailed(OSStatus)
}

protocol TlsSessionDelegate {
	func finishOpen()
	func setError(_ error: TlsStreamError)
}

extension InputStream {
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

class PairedStream {
	let input: WrappedInputStream
	let output: WrappedOutputStream

	init(input: WrappedInputStream, output: WrappedOutputStream) {
		self.input = input
		self.output = output
	}

	func open() {
		input.open()
		output.open()
	}

	func close() {
		input.close()
		output.close()
	}

	var delegate: StreamDelegate? {
		get {
			return (input.delegate === output.delegate) ? input.delegate : nil
		}
		set(newDelegate) {
			input.delegate = newDelegate
			output.delegate = newDelegate
		}
	}

	func schedule(in runLoop: RunLoop, forMode mode: RunLoopMode) {
		input.schedule(in: runLoop, forMode: mode)
		output.schedule(in: runLoop, forMode: mode)
	}
}

class TlsSession {
	let context: SSLContext

	var delegates: [TlsSessionDelegate] = []

	private var interrupted = false

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

	var state: SSLSessionState {
		get {
			var sessionState: SSLSessionState = .idle
			let sslStatus = SSLGetSessionState(context, &sessionState)
			assert(sslStatus == noErr)
			return sessionState
		}
	}

	// MARK: Triggers

	func spaceAvailableForHandshake() {
		guard !interrupted else {
			return
		}

		handleHandshakeResult(status: shakeHands())
	}

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

	private func shakeHands() -> OSStatus {
		assert(state != .connected, "Already shook hands!")

		var status = errSSLWouldBlock

		repeat {
			status = SSLHandshake(context)
		} while status == errSSLWouldBlock

		return status
	}

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

class WrappedInputStream: InputStream, StreamDelegate {
	let _stream: InputStream
	var stream: InputStream { get { return _stream } }

	weak var _delegate: StreamDelegate? = nil

	init(_ stream: InputStream) {
		self._stream = stream

		super.init(data: Data())

		// Replace the original streams delegate
		_delegate = stream.delegate
		stream.delegate = self
	}

	// MARK: Stream

	override var delegate: StreamDelegate? {
		get { return _delegate }
		set(newDelegate) { _delegate = newDelegate }
	}

	override var streamStatus: Stream.Status {
		get { return stream.streamStatus }
	}

	override var streamError: Error? {
		get { return stream.streamError }
	}

	override func open() {
		stream.open()
	}

	override func close() {
		stream.close()
	}

	override func schedule(in runLoop: RunLoop, forMode mode: RunLoopMode) {
		stream.schedule(in: runLoop, forMode: mode)
	}

	override func remove(from runLoop: RunLoop, forMode mode: RunLoopMode) {
		stream.remove(from: runLoop, forMode: mode)
	}

	override func property(forKey key: Stream.PropertyKey) -> Any? {
		return stream.property(forKey: key)
	}

	override func setProperty(_ property: Any?, forKey key: Stream.PropertyKey) -> Bool {
		return stream.setProperty(property, forKey: key)
	}

	// MARK: InputStream

	override var hasBytesAvailable: Bool {
		get { return stream.hasBytesAvailable }
	}

	override func read(_ dataPtr: UnsafeMutablePointer<UInt8>, maxLength: Int) -> Int {
		let bytesProcessed = stream.read(dataPtr, maxLength: maxLength)

		assert(bytesProcessed <= maxLength, "More bytes processed than allowed!")

		return bytesProcessed
	}

	override func getBuffer(_ buffer: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>, length len: UnsafeMutablePointer<Int>) -> Bool {
		return stream.getBuffer(buffer, length: len)
	}

	// MARK: StreamDelegate

	func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
		assert(aStream === stream, "Do not act as a delegate to another stream!")
		assert(!eventCode.contains(.hasSpaceAvailable), "Event should not occur on InputStream!")

		notifyDelegate(handle: eventCode)
	}

	// MARK: Helpers

	func notifyDelegate(handle events: Stream.Event) {
		delegate?.stream!(self, handle: events)
	}
}

class WrappedOutputStream: OutputStream, StreamDelegate {
	let _stream: OutputStream
	var stream: OutputStream { get { return _stream } }
	let inputStream: WrappedInputStream

	weak var _delegate: StreamDelegate? = nil

	init(_ stream: OutputStream, boundTo inputStream: WrappedInputStream) {
		self._stream = stream
		self.inputStream = inputStream

		super.init(toMemory: ())

		// Replace the original streams delegate
		_delegate = stream.delegate
		stream.delegate = self
	}

	// MARK: Stream

	override var delegate: StreamDelegate? {
		get { return _delegate }
		set(newDelegate) { _delegate = newDelegate }
	}

	override var streamStatus: Stream.Status {
		get { return stream.streamStatus }
	}

	override var streamError: Error? {
		get { return stream.streamError }
	}

	override func open() {
		stream.open()
	}

	override func close() {
		stream.close()
	}

	override func schedule(in runLoop: RunLoop, forMode mode: RunLoopMode) {
		stream.schedule(in: runLoop, forMode: mode)
	}

	override func remove(from runLoop: RunLoop, forMode mode: RunLoopMode) {
		stream.remove(from: runLoop, forMode: mode)
	}

	override func property(forKey key: Stream.PropertyKey) -> Any? {
		return stream.property(forKey: key)
	}

	override func setProperty(_ property: Any?, forKey key: Stream.PropertyKey) -> Bool {
		return stream.setProperty(property, forKey: key)
	}

	// MARK: InputStream

	override var hasSpaceAvailable: Bool {
		get {
			return stream.hasSpaceAvailable
		}
	}

	override func write(_ dataPtr: UnsafePointer<UInt8>, maxLength: Int) -> Int {
		let bytesProcessed = stream.write(dataPtr, maxLength: maxLength)

		assert(bytesProcessed <= maxLength, "More bytes processed than allowed!")

		return bytesProcessed
	}

	// MARK: StreamDelegate

	func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
		assert(aStream === stream, "Do not act as a delegate to another stream!")
		assert(!eventCode.contains(.hasBytesAvailable), "Event should not occur on OutputStream!")

		notifyDelegate(handle: eventCode)
	}

	// MARK: Helpers

	func notifyDelegate(handle events: Stream.Event) {
		delegate?.stream!(self, handle: events)
	}
}

class TLSInputStream: WrappedInputStream, TlsSessionDelegate {
	let session: TlsSession

	var buffer = Data()
	var bufferIdx = 0

	var status: Stream.Status = .notOpen
	var error: Error? = nil

	override var stream: WrappedInputStream {
		get {
			return super.stream as! WrappedInputStream
		}
	}

	init(_ stream: WrappedInputStream, withSession session: TlsSession) {
		self.session = session

		super.init(stream)

		session.delegates.insert(self, at: 0)
	}

	var internalTlsBufferSize: Int {
		get {
			var result = 0
			let sslStatus = SSLGetBufferedReadSize(session.context, &result)
			assert(sslStatus == noErr)
			return result
		}
	}

	// MARK: Stream

	override var streamStatus: Stream.Status {
		get { return status }
	}

	override var streamError: Error? {
		get { return error }
	}

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

	override func close() {
		stream.close()
		status = .closed
	}

	override func property(forKey key: Stream.PropertyKey) -> Any? {
		return nil
	}

	override func setProperty(_ property: Any?, forKey key: Stream.PropertyKey) -> Bool {
		return false
	}

	// MARK: InputStream

	override var hasBytesAvailable: Bool {
		get { return !buffer.isEmpty || stream.hasBytesAvailable }
	}

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

	override func getBuffer(_ buffer: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>, length len: UnsafeMutablePointer<Int>) -> Bool {
		return false
	}

	// MARK: StreamDelegate

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

	func finishOpen() {
		status = .open
		notifyDelegate(handle: .openCompleted)
		if hasBytesAvailable {
			notifyDelegate(handle: .hasBytesAvailable)
		}
	}

	func setError(_ error: TlsStreamError) {
		self.error = error
		status = .error
		notifyDelegate(handle: .errorOccurred)
	}
}

class TLSOutputStream: WrappedOutputStream, TlsSessionDelegate {
	let session: TlsSession

	var buffer = Data()
	var bufferIdx = 0

	var status: Stream.Status = .notOpen
	var error: Error? = nil

	init(_ stream: OutputStream, boundTo inputStream: TLSInputStream, withSession session: TlsSession) {
		self.session = session

		super.init(stream, boundTo: inputStream)

		session.delegates.append(self)
	}

	private func flushBuffer() -> OSStatus {
		guard !buffer.isEmpty else {
			return noErr
		}

		var sslStatus = noErr
		while stream.hasSpaceAvailable && (sslStatus == errSSLWouldBlock || (sslStatus == noErr && bufferIdx < buffer.count)) {
			let maxLength = buffer.count - bufferIdx
			let chunkSize = min(maxLength, ChunkSizeInBytes)
			var bytesProcessed = 0
			sslStatus = buffer.withUnsafeBytes { bufferPtr in
				return SSLWrite(
					session.context,
					bufferPtr.advanced(by: bufferIdx), // UInt8
					chunkSize,
					&bytesProcessed
				)
			}
			assert(0 <= bytesProcessed)

			bufferIdx += bytesProcessed

			assert(bytesProcessed <= chunkSize, "More bytes processed than allowed!")
			assert(bufferIdx <= buffer.count, "More bytes processed than allowed!")
		}

		// Check if the buffer was completely flushed, remove from memory
		if  bufferIdx == buffer.count {
			buffer.removeAll()
			bufferIdx = 0
		}

		return sslStatus
	}

	// MARK: Stream

	override var streamStatus: Stream.Status {
		get { return status }
	}

	override var streamError: Error? {
		get { return error }
	}

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

	override func close() {
		let sslStatus = SSLClose(session.context)
		guard [noErr, errSSLClosedAbort, errSSLClosedGraceful, errSSLClosedNoNotify].contains(sslStatus) else {
			setError(.closingFailed(sslStatus))
			return
		}
		stream.close()
		status = .closed
	}

	override func property(forKey key: Stream.PropertyKey) -> Any? {
		return nil
	}

	override func setProperty(_ property: Any?, forKey key: Stream.PropertyKey) -> Bool {
		return false
	}

	// MARK: OutputStream

	override var hasSpaceAvailable: Bool {
		get {
			return buffer.isEmpty && stream.hasSpaceAvailable
		}
	}

	override func write(_ dataPtr: UnsafePointer<UInt8>, maxLength: Int) -> Int {
		assert(status == .open)

		// Do not write if the session has already been closed.
		guard session.state != .closed else {
			return 0
		}

		assert(session.state == .connected)

		buffer.append(dataPtr, count: maxLength)
		let sslStatus = flushBuffer()

		guard [noErr, errSSLWouldBlock, errSSLClosedAbort, errSSLClosedGraceful, errSSLClosedNoNotify].contains(sslStatus) else {
			setError(.writingFailed(sslStatus, bufferIdx))
			return -1
		}

		return maxLength
	}

	// MARK: StreamDelegate

	override func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
		assert(aStream === stream, "Do not act as a delegate to another stream!")
		assert(!eventCode.contains(.hasBytesAvailable), "Event should not occur on OutputStream!")

		if eventCode.contains(.hasSpaceAvailable) {
			let sslStatus = flushBuffer()

			if sslStatus == errSSLWouldBlock {
				{}() // Do nothing and wait until space is available again.
			} else if [noErr, errSSLClosedAbort, errSSLClosedGraceful, errSSLClosedNoNotify].contains(sslStatus) {
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
			} else {
				setError(.writingFailed(sslStatus, bufferIdx))
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

	func finishOpen() {
		status = .open
		notifyDelegate(handle: .openCompleted)
		if hasSpaceAvailable {
			notifyDelegate(handle: .hasSpaceAvailable)
		}
	}

	func setError(_ error: TlsStreamError) {
		self.error = error
		status = .error
		notifyDelegate(handle: .errorOccurred)
	}
}

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
