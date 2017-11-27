import QRCode
import Tafelsalz

// <#FIXME#> Remove Android workaround (Todo-iOS/#2)
let MASTER_KEY_PREFIX = "PLIB"

extension MasterKey {

	/**
		Export the master key as a QR Code.

		- returns:
			The QR Code.
	*/
	public func qrCode() -> QRCode {
		assert(self.sizeInBytes <= QRCode.MaximumSizeInBytes)
		assert(base64EncodedString().lengthOfBytes(using: .isoLatin1) <= QRCode.MaximumSizeInBytes)

		return QRCode(MASTER_KEY_PREFIX + base64EncodedString())!
	}

	/**
		Export the master key as a Base64-encoded string.

		- returns:
			The Base64-encoded representaiton of the master key.
	*/
	public func base64EncodedString() -> String {
		return copyBytes().base64EncodedString()
	}

	/**
		Initialize a master key from a Base64-encoded string.

		- parameters:
			- base64Encoded: The Base64-encoded representation of a master key.

		- returns:
			`nil` if `base64Encoded` is not a valid.
	*/
	public convenience init?(base64Encoded encodedString: String) {
		guard var data = Data(base64Encoded: encodedString) else {
			return nil
		}

		if data.starts(with: Data(MASTER_KEY_PREFIX.utf8)) {
			data.removeFirst(Data(MASTER_KEY_PREFIX.utf8).count)
		}

		self.init(bytes: &data)
	}

}
