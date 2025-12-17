import SwiftUI
import GoogleSignIn

@main
struct ContactDedupApp: App {
    @StateObject private var viewModel = ContactViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
