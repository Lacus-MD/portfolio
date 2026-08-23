import Foundation

extension String {
    /// Removes the optional UTF-8 byte-order mark emitted by some banking
    /// exports. It is data, not part of the first CSV field name.
    var withoutUTF8BOM: String {
        hasPrefix("\u{FEFF}") ? String(dropFirst()) : self
    }
}
