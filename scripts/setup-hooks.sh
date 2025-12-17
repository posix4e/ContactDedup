#!/bin/bash

# Setup Git Hooks
# Run this script after cloning the repository

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
HOOKS_DIR="$ROOT_DIR/.git/hooks"

echo "Setting up Git hooks..."

# Create pre-commit hook
cat > "$HOOKS_DIR/pre-commit" << 'EOF'
#!/bin/bash

# SwiftLint Pre-commit Hook
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

if ! which swiftlint > /dev/null; then
    echo "warning: SwiftLint not installed, download from https://github.com/realm/SwiftLint"
    exit 0
fi

STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep "\.swift$")

if [ -z "$STAGED_FILES" ]; then
    exit 0
fi

echo "Running SwiftLint on staged files..."

LINT_RESULT=0
for FILE in $STAGED_FILES; do
    if [ -f "$FILE" ]; then
        swiftlint lint --path "$FILE" --quiet
        if [ $? -ne 0 ]; then
            LINT_RESULT=1
        fi
    fi
done

if [ $LINT_RESULT -ne 0 ]; then
    echo ""
    echo "SwiftLint found issues. Please fix them before committing."
    echo "Run 'swiftlint --fix' to auto-fix some issues."
    exit 1
fi

echo "SwiftLint passed!"
exit 0
EOF

chmod +x "$HOOKS_DIR/pre-commit"

echo "Git hooks installed successfully!"
echo ""
echo "Make sure SwiftLint is installed:"
echo "  brew install swiftlint"
