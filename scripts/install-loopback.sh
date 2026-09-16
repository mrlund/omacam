#!/usr/bin/env bash
# One-time root setup for the Omacam virtual camera.
# The Omarchy plugin cannot run this for you (plugin install never uses sudo).
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this once with sudo:" >&2
  echo "  sudo $0" >&2
  exit 1
fi

modprobe_dir=/etc/modprobe.d
load_dir=/etc/modules-load.d
mkdir -p "$modprobe_dir" "$load_dir"

cat > "$load_dir/v4l2loopback.conf" <<'EOF'
v4l2loopback
EOF

cat > "$modprobe_dir/v4l2loopback.conf" <<'EOF'
options v4l2loopback exclusive_caps=1 card_label="Omacam" devices=1
EOF

if lsmod | grep -q '^v4l2loopback '; then
  echo "v4l2loopback is already loaded. Unload it first if you want the new card name:"
  echo "  sudo modprobe -r v4l2loopback && sudo modprobe v4l2loopback"
  echo "Skipping reload so an in-use camera is not yanked."
else
  modprobe v4l2loopback exclusive_caps=1 card_label="Omacam" devices=1
  echo "Loaded v4l2loopback as 'Omacam'."
fi

echo
echo "Wrote:"
echo "  $load_dir/v4l2loopback.conf"
echo "  $modprobe_dir/v4l2loopback.conf"
echo
echo "The module will load on boot. In meeting apps, pick the camera named Omacam."
