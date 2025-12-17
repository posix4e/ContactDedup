import Foundation
import GoogleSignIn
import GoogleSignInSwift
import SwiftUI

struct GoogleAccount: Identifiable {
    let email: String
    var accessToken: String?
    var user: GIDGoogleUser?
    var isActive: Bool  // Whether this account is currently authenticated

    var id: String { email }
}

@MainActor
class GoogleAuthManager: ObservableObject {
    static let shared = GoogleAuthManager()

    @Published var accounts: [GoogleAccount] = []

    // Store known account emails to persist across sessions
    @AppStorage("googleAccountEmails") private var storedEmailsData: String = ""
    private var storedEmails: [String] {
        get {
            storedEmailsData.isEmpty ? [] : storedEmailsData.components(separatedBy: ",")
        }
        set {
            storedEmailsData = newValue.joined(separator: ",")
        }
    }

    var isAuthenticated: Bool { !accounts.isEmpty }

    // For backward compatibility
    var userEmail: String? { accounts.first?.email }
    var accessToken: String? { accounts.first?.accessToken }

    private init() {
        // Load stored accounts first, then try to restore active session
        loadStoredAccounts()
        restorePreviousSignIn()
    }

    private func loadStoredAccounts() {
        // Create inactive account entries for all stored emails
        for email in storedEmails where !accounts.contains(where: { $0.email == email }) {
            accounts.append(GoogleAccount(email: email, accessToken: nil, user: nil, isActive: false))
        }
        print("[GoogleAuth] Loaded \(accounts.count) stored accounts")
    }

    private func restorePreviousSignIn() {
        // Restore the current signed-in user from the SDK
        GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] user, error in
            Task { @MainActor in
                if let user = user {
                    self?.activateAccount(user)
                    print("[GoogleAuth] Restored previous sign-in: \(user.profile?.email ?? "unknown")")
                } else if let error = error {
                    print("[GoogleAuth] No previous sign-in to restore: \(error.localizedDescription)")
                } else {
                    print("[GoogleAuth] No previous sign-in found")
                }
            }
        }
    }

    func signIn() async throws {
        try await addAccount()
    }

    func addAccount() async throws {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            throw AuthError.noViewController
        }

        // Request contacts.readonly scope
        let additionalScopes = ["https://www.googleapis.com/auth/contacts.readonly"]

        print("[GoogleAuth] Starting sign-in...")

        let result = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: rootViewController,
            hint: nil,
            additionalScopes: additionalScopes
        )

        let user = result.user
        activateAccount(user)
        print("[GoogleAuth] Sign-in successful: \(user.profile?.email ?? "unknown")")
    }

    /// Ensures the specified account is the current SDK user and returns a fresh access token.
    /// This is required because the Google Sign-In SDK only maintains one active user at a time.
    func ensureCurrentAndGetToken(for email: String) async throws -> String {
        // Check if this account is already current
        if let currentUser = GIDSignIn.sharedInstance.currentUser,
           currentUser.profile?.email == email {
            // Refresh and return token
            try await currentUser.refreshTokensIfNeeded()
            let token = currentUser.accessToken.tokenString
            activateAccount(currentUser)
            return token
        }

        // Need to switch to this account - sign in with hint
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            throw AuthError.noViewController
        }

        let additionalScopes = ["https://www.googleapis.com/auth/contacts.readonly"]

        print("[GoogleAuth] Switching to account: \(email)")

        let result = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: rootViewController,
            hint: email,
            additionalScopes: additionalScopes
        )

        let user = result.user
        guard user.profile?.email == email else {
            // User selected a different account
            activateAccount(user)
            throw AuthError.signInFailed("Please select the account: \(email)")
        }

        activateAccount(user)
        return user.accessToken.tokenString
    }

    /// Activates an account with a valid GIDGoogleUser session
    private func activateAccount(_ user: GIDGoogleUser) {
        guard let email = user.profile?.email else {
            return
        }

        let accessToken = user.accessToken.tokenString

        // Mark all accounts as inactive first (SDK only supports one active user)
        for i in accounts.indices {
            accounts[i].isActive = false
        }

        let account = GoogleAccount(
            email: email,
            accessToken: accessToken,
            user: user,
            isActive: true
        )

        // Replace if already exists, otherwise add
        if let existingIndex = accounts.firstIndex(where: { $0.email == email }) {
            accounts[existingIndex] = account
            print("[GoogleAuth] Activated existing account: \(email)")
        } else {
            accounts.append(account)
            print("[GoogleAuth] Added and activated new account: \(email)")
        }

        // Persist the email list
        if !storedEmails.contains(email) {
            storedEmails += [email]
        }

        print("[GoogleAuth] Total accounts: \(accounts.count), active: \(email)")
    }

    func refreshTokenForImport(for email: String) async throws -> String {
        // If we have an active account with a user, refresh it
        if let account = accounts.first(where: { $0.email == email && $0.isActive }),
           let user = account.user {
            try await user.refreshTokensIfNeeded()
            let newToken = user.accessToken.tokenString
            activateAccount(user)
            return newToken
        }

        throw AuthError.noRefreshToken
    }

    func refreshToken(for email: String) async throws {
        _ = try await refreshTokenForImport(for: email)
    }

    func refreshToken() async throws {
        guard let email = accounts.first(where: { $0.isActive })?.email else {
            throw AuthError.noRefreshToken
        }
        try await refreshToken(for: email)
    }

    func getAccessToken(for email: String) -> String? {
        accounts.first(where: { $0.email == email })?.accessToken
    }

    func getFreshAccessToken(for email: String) async -> String? {
        // Try to refresh and get a fresh token
        if let account = accounts.first(where: { $0.email == email && $0.isActive }),
           let user = account.user {
            do {
                try await user.refreshTokensIfNeeded()
                let newToken = user.accessToken.tokenString
                activateAccount(user)
                return newToken
            } catch {
                print("[GoogleAuth] Failed to refresh token for \(email): \(error)")
            }
        }
        return accounts.first(where: { $0.email == email })?.accessToken
    }

    func getUser(for email: String) -> GIDGoogleUser? {
        accounts.first(where: { $0.email == email })?.user
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        accounts.removeAll()
        storedEmails = []
        print("[GoogleAuth] Signed out all accounts")
    }

    func removeAccount(_ email: String) {
        accounts.removeAll { $0.email == email }
        storedEmails = storedEmails.filter { $0 != email }
        if accounts.isEmpty {
            GIDSignIn.sharedInstance.signOut()
        }
        print("[GoogleAuth] Removed account: \(email)")
    }

    // Handle URL callback from Google Sign-In
    func handle(_ url: URL) -> Bool {
        return GIDSignIn.sharedInstance.handle(url)
    }

    enum AuthError: Error, LocalizedError {
        case noViewController
        case noRefreshToken
        case signInFailed(String)

        var errorDescription: String? {
            switch self {
            case .noViewController:
                return "Could not find root view controller"
            case .noRefreshToken:
                return "No refresh token available"
            case .signInFailed(let message):
                return "Sign-in failed: \(message)"
            }
        }
    }
}
