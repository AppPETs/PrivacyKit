import QRCode
import Tafelsalz

extension MasterKey {
	public func qrCode() -> QRCode? {
		return QRCode(base64EncodedString())
	}

	public func base64EncodedString() -> String {
		return copyBytes().base64EncodedString()
	}

	public convenience init?(base64Encoded encodedString: String) {
		guard var data = Data(base64Encoded: encodedString) else {
			return nil
		}

		self.init(bytes: &data)
	}
}
