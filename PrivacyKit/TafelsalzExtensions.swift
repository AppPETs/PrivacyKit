import QRCode
import Tafelsalz

extension MasterKey {
	public func qrCode() -> QRCode? {
		return QRCode(copyBytes())
	}
}
