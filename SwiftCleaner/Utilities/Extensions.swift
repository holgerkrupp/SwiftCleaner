import Foundation

extension URL {
    var isSwiftFile: Bool {
        pathExtension == "swift"
    }
}
