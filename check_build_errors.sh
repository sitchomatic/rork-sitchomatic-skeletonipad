#!/bin/bash

# Build Error Check Script
# Checks Swift files for compilation errors while filtering out warnings
# Exit code: 0 if no errors, 1 if errors found

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$SCRIPT_DIR/ios"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "============================================"
echo "Build Error Check (Warnings Filtered)"
echo "============================================"
echo ""

# Check if swiftc is available
if ! command -v swiftc &> /dev/null; then
    echo -e "${RED}ERROR: swiftc not found. Please install Swift toolchain.${NC}"
    exit 1
fi

echo "Swift version: $(swiftc --version | head -1)"
echo ""

# Find all Swift files (app, widget, and tests)
SWIFT_FILES=$(find "$IOS_DIR" -name "*.swift" 2>/dev/null)
TOTAL_FILES=$(echo "$SWIFT_FILES" | wc -l | tr -d ' ')

echo "Checking $TOTAL_FILES Swift files..."
echo ""

# Create temp file for errors
TEMP_ERRORS=$(mktemp)
TEMP_OUTPUT=$(mktemp)

trap "rm -f $TEMP_ERRORS $TEMP_OUTPUT" EXIT

ERROR_COUNT=0
FILES_WITH_ERRORS=0
CHECKED_FILES=0

# Check each file
for file in $SWIFT_FILES; do
    CHECKED_FILES=$((CHECKED_FILES + 1))

    # Run swiftc -parse and capture output
    # Filter to only show error lines (not warnings)
    if ! swiftc -parse "$file" 2>&1 | grep -E "error:" > "$TEMP_OUTPUT"; then
        # No errors found (grep returns non-zero when no match)
        continue
    fi

    # Errors found
    if [ -s "$TEMP_OUTPUT" ]; then
        FILE_ERRORS=$(wc -l < "$TEMP_OUTPUT" | tr -d ' ')
        ERROR_COUNT=$((ERROR_COUNT + FILE_ERRORS))
        FILES_WITH_ERRORS=$((FILES_WITH_ERRORS + 1))

        echo -e "${RED}✗ Errors in: $file${NC}"
        cat "$TEMP_OUTPUT"
        echo ""

        # Also save to summary
        echo "=== $file ===" >> "$TEMP_ERRORS"
        cat "$TEMP_OUTPUT" >> "$TEMP_ERRORS"
        echo "" >> "$TEMP_ERRORS"
    fi
done

echo "============================================"
echo "Check Complete"
echo "============================================"
echo "Files checked: $CHECKED_FILES"
echo "Files with errors: $FILES_WITH_ERRORS"
echo "Total errors: $ERROR_COUNT"
echo ""

if [ $ERROR_COUNT -eq 0 ]; then
    echo -e "${GREEN}✓ No build errors found!${NC}"
    exit 0
else
    echo -e "${RED}✗ Found $ERROR_COUNT build error(s) in $FILES_WITH_ERRORS file(s)${NC}"
    echo ""
    echo "Summary of all errors:"
    echo "============================================"
    cat "$TEMP_ERRORS"
    exit 1
fi
