# ContactDedup

[![Build and Upload to TestFlight](https://github.com/posix4e/ContactDedup/actions/workflows/testflight.yml/badge.svg)](https://github.com/posix4e/ContactDedup/actions/workflows/testflight.yml)

A powerful iOS app to clean up and manage your contacts by finding duplicates, importing from multiple sources, and keeping everything organized.

## Features

### Duplicate Detection
- **Smart matching** - Finds duplicates by name, email, phone number, or similar patterns
- **Adjustable sensitivity** - Control how strict the matching should be
- **One-tap merge** - Combine duplicate contacts while preserving all information
- **Batch operations** - Merge all duplicates at once or by category

### Multi-Source Import
- **Apple Contacts** - Sync with your device contacts
- **Google Contacts** - Import from multiple Google accounts
- **LinkedIn** - Import connections from LinkedIn CSV exports

### Contact Management
- **Incomplete contact detection** - Find contacts missing key information
- **Bulk cleanup** - Delete incomplete contacts in one tap
- **Edit contacts** - Update contact details directly in the app

## Installation

### TestFlight
The app is available for beta testing on TestFlight.

### Building from Source
1. Clone the repository:
   ```bash
   git clone https://github.com/posix4e/ContactDedup.git
   cd ContactDedup
   ```

2. Set up development environment:
   ```bash
   brew install swiftlint
   ./scripts/setup-hooks.sh
   ```

3. Open in Xcode:
   ```bash
   open ContactDedup.xcodeproj
   ```

4. Select your development team in Signing & Capabilities

5. Build and run on your device

## Requirements

- iOS 17.0+
- Xcode 15.0+

## CI/CD

This project uses GitHub Actions for continuous integration and deployment:

- **SwiftLint** - Code style enforcement on every push
- **Automatic builds** - Archives built on push to main
- **TestFlight deployment** - Automatic upload to TestFlight

### Required Secrets

To set up CI/CD for your fork, configure these GitHub secrets:

| Secret | Description |
|--------|-------------|
| `APPLE_TEAM_ID` | Your Apple Developer Team ID |
| `APP_STORE_CONNECT_KEY_ID` | App Store Connect API Key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | App Store Connect Issuer ID |
| `APP_STORE_CONNECT_API_KEY` | App Store Connect API Key (.p8 content, base64) |
| `CERTIFICATE_P12` | Distribution certificate (.p12, base64) |
| `CERTIFICATE_PASSWORD` | Password for the .p12 certificate |
| `PROVISIONING_PROFILE` | Provisioning profile (.mobileprovision, base64) |

## Privacy

ContactDedup respects your privacy:
- All contact processing happens on-device
- No contact data is sent to external servers
- Google sign-in only accesses contacts you explicitly import

## License

MIT License - see [LICENSE](LICENSE) for details.

## Contributing

Contributions are welcome! Please open an issue or submit a pull request.
