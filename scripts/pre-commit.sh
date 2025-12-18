#!/bin/bash

# Pre-commit Hook Script
# 1. Checks for sensitive files
# 2. Runs SwiftLint on staged Swift files

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

echo "Running pre-commit checks..."

# =============================================================================
# SECURITY CHECK - Block commits containing sensitive files
# =============================================================================

STAGED_FILES=$(git diff --cached --name-only)
BLOCKED=0

# Check for sensitive file extensions
for pattern in ".p8" ".p12" ".mobileprovision" ".cer" ".pem" ".key"; do
    MATCHES=$(echo "$STAGED_FILES" | grep "$pattern" || true)
    if [ -n "$MATCHES" ]; then
        echo ""
        echo "🚫 BLOCKED: Attempting to commit sensitive file(s):"
        echo "$MATCHES"
        BLOCKED=1
    fi
done

# Check for sensitive file names
for filename in ".env" "secrets.json" "credentials.json" "Connections.csv"; do
    if echo "$STAGED_FILES" | grep -q "^$filename$\|/$filename$"; then
        echo ""
        echo "🚫 BLOCKED: Attempting to commit sensitive file: $filename"
        BLOCKED=1
    fi
done

# Check for private keys in staged content (pattern split to avoid self-match)
STAGED_CONTENT=$(git diff --cached --diff-filter=ACM)
PK_PAT="BEGIN"
PK_PAT="${PK_PAT} PRIVATE KEY"
RSA_PAT="BEGIN RSA"
RSA_PAT="${RSA_PAT} PRIVATE KEY"
if echo "$STAGED_CONTENT" | grep -q "$PK_PAT\|$RSA_PAT"; then
    echo ""
    echo "🚫 BLOCKED: Private key detected in staged changes!"
    BLOCKED=1
fi

if [ $BLOCKED -eq 1 ]; then
    echo ""
    echo "❌ Commit blocked due to sensitive files."
    echo "Remove these files from staging with: git reset HEAD <file>"
    echo "Then add them to .gitignore"
    exit 1
fi

echo "✅ Security check passed"

# =============================================================================
# SWIFTLINT CHECK
# =============================================================================

if ! which swiftlint > /dev/null; then
    echo "⚠️  SwiftLint not installed, skipping lint check"
    exit 0
fi

SWIFT_FILES=$(echo "$STAGED_FILES" | grep "\.swift$" || true)

if [ -z "$SWIFT_FILES" ]; then
    echo "✅ No Swift files to lint"
    exit 0
fi

echo "Running SwiftLint on staged files..."

LINT_RESULT=0
for FILE in $SWIFT_FILES; do
    if [ -f "$FILE" ]; then
        swiftlint lint "$FILE" --quiet
        if [ $? -ne 0 ]; then
            LINT_RESULT=1
        fi
    fi
done

if [ $LINT_RESULT -ne 0 ]; then
    echo ""
    echo "⚠️  SwiftLint found issues. Please fix them before committing."
    echo "Run 'swiftlint --fix' to auto-fix some issues."
    exit 1
fi

echo "✅ SwiftLint passed!"
exit 0
