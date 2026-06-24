#if canImport(SwiftUI)
import SwiftUI

@main
struct PraeventusApp: App {
    var body: some Scene {
        WindowGroup {
            PraeventusRootView()
        }
    }
}
#else
import Foundation

@main
struct PraeventusCLI {
    static func main() {
        print("Praeventus is designed for Swift Playgrounds on iPad.")
    }
}
#endif
