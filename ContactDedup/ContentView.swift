import SwiftUI

struct ContentView: View {
    @EnvironmentObject var viewModel: ContactViewModel

    var body: some View {
        ZStack {
            TabView {
                ContactsListView()
                    .tabItem {
                        Label("Contacts", systemImage: "person.crop.circle")
                    }

                DuplicatesView()
                    .tabItem {
                        Label("Duplicates", systemImage: "person.2.fill")
                    }

                CleanupView()
                    .tabItem {
                        Label("Cleanup", systemImage: "trash")
                    }

                ImportView()
                    .tabItem {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }

                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gear")
                    }
            }

            // Loading overlay
            if viewModel.isLoading {
                LoadingOverlayView(
                    message: viewModel.loadingMessage,
                    progress: viewModel.loadingProgress
                )
            }

            // Duplicate detection indicator (non-blocking)
            if viewModel.isFindingDuplicates && !viewModel.isLoading {
                VStack {
                    Spacer()
                    VStack(spacing: 4) {
                        HStack {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            Text("Finding duplicates...")
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                        if !viewModel.duplicateCheckProgress.isEmpty {
                            Text(viewModel.duplicateCheckProgress)
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.8))
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(20)
                    .padding(.bottom, 100)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut, value: viewModel.isFindingDuplicates)
            }
        }
        .onAppear {
            viewModel.loadContacts()
        }
    }
}

struct LoadingOverlayView: View {
    let message: String
    let progress: Double

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ProgressView(value: progress) {
                    Text(message)
                        .font(.headline)
                }
                .progressViewStyle(LinearProgressViewStyle(tint: .accentColor))
                .frame(width: 250)

                Text("\(Int(progress * 100))%")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.accentColor)
            }
            .padding(30)
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(radius: 10)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ContactViewModel())
}
