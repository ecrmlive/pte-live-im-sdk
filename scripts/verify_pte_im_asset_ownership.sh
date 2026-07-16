#!/usr/bin/env bash
set -euo pipefail

# Core is UI-agnostic. Page slices must use the PteIMUI prefix and belong to
# PteIMUIKit, PteIMUIDemo, or the host application instead of PteIMSDK.
sdk_roots=(
  "ios/PteIMSDK"
  "android/pte-im-sdk"
  "harmony/PteIMSDK"
  "uni_modules/pte-im-sdk/utssdk"
)

found=0
for root in "${sdk_roots[@]}"; do
  while IFS= read -r asset; do
    printf 'PteIMSDK must not contain page visual asset: %s\n' "$asset" >&2
    found=1
  done < <(find "$root" -type f \( -iname 'PteIMUI*.png' -o -iname 'PteIMUI*.jpg' -o -iname 'PteIMUI*.jpeg' -o -iname 'PteIMUI*.webp' -o -iname 'PteIMUI*.gif' -o -iname 'PteIMUI*.svg' \) -print)
done

if [ "$found" -ne 0 ]; then
  exit 1
fi

printf 'PteIM visual asset ownership check passed.\n'
