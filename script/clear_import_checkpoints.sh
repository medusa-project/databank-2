#!/usr/bin/env bash
# Clear flat bundle import checkpoint and lock files from a BUNDLE_ROOT directory.
#
# Use this before a fresh cutover import run to ensure all chunked importers
# start from the beginning rather than resuming from a previous run.
#
# Usage:
#   script/clear_import_checkpoints.sh [BUNDLE_ROOT]
#
# Arguments:
#   BUNDLE_ROOT  Path to the export root directory (default: /tmp/databank_exports)
#
# Files removed (searched recursively under BUNDLE_ROOT):
#   flat_bundle_import.checkpoint.json
#   flat_bundle_structure_import.checkpoint.json
#   flat_bundle_nested_items_import.checkpoint.json
#   flat_bundle_import.lock
#
# Example:
#   script/clear_import_checkpoints.sh /tmp/databank_exports

set -euo pipefail

BUNDLE_ROOT="${1:-/tmp/databank_exports}"

if [[ ! -d "$BUNDLE_ROOT" ]]; then
  echo "ERROR: directory not found: $BUNDLE_ROOT" >&2
  exit 1
fi

PATTERNS=(
  "flat_bundle_import.checkpoint.json"
  "flat_bundle_structure_import.checkpoint.json"
  "flat_bundle_nested_items_import.checkpoint.json"
  "flat_bundle_import.lock"
)

removed=0

for pattern in "${PATTERNS[@]}"; do
  while IFS= read -r -d '' file; do
    echo "Removing: $file"
    rm -f "$file"
    (( removed++ )) || true
  done < <(find "$BUNDLE_ROOT" -name "$pattern" -print0)
done

echo ""
echo "Done. Removed $removed file(s) from $BUNDLE_ROOT"
