#!/bin/sh
mkdir -p "$HOME/.idotmatrix" 2>/dev/null || true
printf '%s' "${1:-idle}" > "$HOME/.idotmatrix/state" 2>/dev/null || true
exit 0
