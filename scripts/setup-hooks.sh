#!/bin/bash

# Setup Git Hooks
# Run this script after cloning the repository

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
HOOKS_DIR="$ROOT_DIR/.git/hooks"

echo "Setting up Git hooks..."

# Create pre-commit hook that calls our script
cat > "$HOOKS_DIR/pre-commit" << 'EOF'
#!/bin/bash
# Git pre-commit hook - calls the shared script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
exec "$ROOT_DIR/scripts/pre-commit.sh"
EOF

chmod +x "$HOOKS_DIR/pre-commit"

echo "✅ Git hooks installed successfully!"
echo ""
echo "The pre-commit hook will:"
echo "  • Block commits containing sensitive files (.p8, .p12, .env, etc.)"
echo "  • Run SwiftLint on staged Swift files"
echo ""
echo "Make sure SwiftLint is installed:"
echo "  brew install swiftlint"
