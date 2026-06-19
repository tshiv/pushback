#!/bin/bash
#
# pushback installer. Downloads the `pushback` script to a directory on your
# PATH. Usage:
#
#   curl -fsSL https://raw.githubusercontent.com/tshiv/pushback/main/install.sh | bash
#
# Override the install location with PREFIX:
#   curl -fsSL .../install.sh | PREFIX="$HOME/.local/bin" bash

set -euo pipefail

REPO="tshiv/pushback"
BRANCH="main"
RAW="https://raw.githubusercontent.com/${REPO}/${BRANCH}/pushback"

# Choose a bin dir: explicit PREFIX, else the first writable PATH candidate.
choose_bindir() {
    if [ -n "${PREFIX:-}" ]; then echo "$PREFIX"; return; fi
    for d in /usr/local/bin "$HOME/.local/bin" "$HOME/bin"; do
        if [ -d "$d" ] && [ -w "$d" ]; then echo "$d"; return; fi
    done
    # Fall back to ~/.local/bin, creating it.
    mkdir -p "$HOME/.local/bin"
    echo "$HOME/.local/bin"
}

BINDIR="$(choose_bindir)"
DEST="$BINDIR/pushback"

echo "Installing pushback → $DEST"
curl -fsSL "$RAW" -o "$DEST"
chmod +x "$DEST"

echo "✓ Installed pushback $("$DEST" --version 2>/dev/null | awk '{print $2}')"
case ":$PATH:" in
    *":$BINDIR:"*) ;;
    *) echo "  Note: $BINDIR is not on your PATH. Add it:"
       echo "    echo 'export PATH=\"$BINDIR:\$PATH\"' >> ~/.zshrc" ;;
esac
echo "  Next: copy .pushbackrc.example into your project and run 'pushback --help'."
