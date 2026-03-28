#!/bin/bash
# Xcode Cloud post-clone script
# Xcode Cloud resolves SPM dependencies automatically.
# This script is intentionally minimal to avoid timeout issues.
set -e

# Skip build if only documentation files changed (saves Xcode Cloud minutes)
if [ -n "$CI_PULL_REQUEST_NUMBER" ] || [ -z "$CI_COMMIT" ]; then
    echo "Post-clone: PR build or no commit info — proceeding with build."
else
    # Xcode Cloud may use shallow clones — git diff can fail with exit 128
    # if the parent commit object is not available. Handle gracefully.
    PREV_COMMIT=$(git rev-parse HEAD~1 2>/dev/null || echo "")
    if [ -n "$PREV_COMMIT" ]; then
        CHANGED_FILES=$(git diff --name-only "$PREV_COMMIT" HEAD 2>/dev/null || echo "")
        if [ -z "$CHANGED_FILES" ]; then
            echo "Post-clone: Could not determine changed files (shallow clone?) — proceeding with build."
        else
            CODE_CHANGES=$(echo "$CHANGED_FILES" | grep -v -E '\.(md|txt)$' | grep -v -E '^docs/' | grep -v -E '^\.claude/' || true)
            if [ -z "$CODE_CHANGES" ]; then
                echo "Post-clone: Only documentation changed — skipping build."
                echo "Changed files: $CHANGED_FILES"
                exit 1
            fi
        fi
    fi
fi

echo "Post-clone: Code changes detected — proceeding with build."
