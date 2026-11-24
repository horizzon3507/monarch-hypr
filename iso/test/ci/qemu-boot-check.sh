#!/bin/bash
# Boot an ISO in QEMU on a CI runner, take periodic screenshots through QMP,
# OCR the last ones and fail unless the live installer is visibly running.
# usage: qemu-boot-check.sh <iso> <uefi|bios> <outdir>
set -uo pipefail
ISO=$1 MODE=$2 OUT=$3
WAIT=${BOOT_WAIT_SECONDS:-480}
# Only the installer welcome screen counts as a pass. Generic words are not enough:
# error screens also mention keyboards, disks and installers.
EXPECT=${BOOT_EXPECT_REGEX:-'press return to start install'}
FAIL_ON=${BOOT_FAIL_REGEX:-'kernel panic|emergency mode|emergency shell|no bootable|boot failed|grub rescue|failed to mount|dracut|cannot open root'}
mkdir -p "$OUT"

sudo apt-get update -qq
sudo apt-get install -y -qq qemu-system-x86 ovmf imagemagick tesseract-ocr socat >/dev/null

# Disposable GitHub-hosted runner only: opening /dev/kvm to every user is the
# documented way to let QEMU use KVM there. Never run this on a developer machine.
ACCEL=tcg
if [[ -e /dev/kvm ]]; then
  echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' | sudo tee /etc/udev/rules.d/99-kvm4all.rules >/dev/null
  sudo udevadm control --reload-rules; sudo udevadm trigger --name-match=kvm
  [[ -w /dev/kvm ]] || sudo chmod 666 /dev/kvm
  [[ -w /dev/kvm ]] && ACCEL=kvm
fi
echo "accel=$ACCEL mode=$MODE" | tee "$OUT/info.txt"

FW=()
if [[ $MODE == uefi ]]; then
  cp /usr/share/OVMF/OVMF_VARS_4M.fd "$OUT/vars.fd" 2>/dev/null || cp /usr/share/OVMF/OVMF_VARS.fd "$OUT/vars.fd"
  code=/usr/share/OVMF/OVMF_CODE_4M.fd; [[ -f $code ]] || code=/usr/share/OVMF/OVMF_CODE.fd
  FW=(-drive if=pflash,format=raw,readonly=on,file="$code" -drive if=pflash,format=raw,file="$OUT/vars.fd")
fi
qemu-img create -f qcow2 "$OUT/disk.qcow2" 30G >/dev/null
SOCK=$(mktemp -u /tmp/qmp.XXXX)

qemu-system-x86_64 -machine q35,accel=$ACCEL -cpu max -smp 4 -m 4096 \
  "${FW[@]}" -drive file="$OUT/disk.qcow2",if=virtio,format=qcow2 \
  -cdrom "$ISO" -boot d -vga std -display none \
  -nic user,model=virtio-net-pci -serial file:"$OUT/serial.log" \
  -qmp unix:"$SOCK",server,nowait -daemonize -pidfile "$OUT/qemu.pid" || { echo "qemu failed to start"; exit 2; }

shot() { # name
  printf '{"execute":"qmp_capabilities"}\n{"execute":"screendump","arguments":{"filename":"%s/%s.ppm"}}\n' "$PWD/$OUT" "$1" |
    socat - UNIX-CONNECT:"$SOCK" >/dev/null 2>&1
  sleep 1
  [[ -f $OUT/$1.ppm ]] && convert "$OUT/$1.ppm" "$OUT/$1.png" && rm -f "$OUT/$1.ppm"
}

start=$SECONDS; n=0
while (( SECONDS - start < WAIT )); do
  sleep 20; n=$((n+1)); shot "t$(printf %03d $((SECONDS-start)))s"
done
shot final
kill "$(cat "$OUT/qemu.pid")" 2>/dev/null || true

# The "Press Return" prompt is dim grey on a dark background, so plain OCR misses
# it. Stretch the contrast first (validated on the retained baseline screenshots).
convert "$OUT/final.png" -colorspace Gray -resize 300% -level 8%,28% -negate "$OUT/final-ocr-input.png"
tesseract "$OUT/final-ocr-input.png" "$OUT/final-ocr" --psm 11 >/dev/null 2>&1 || true
echo "--- OCR of final screen ---"; cat "$OUT/final-ocr.txt" 2>/dev/null
if grep -qiE "$FAIL_ON" "$OUT/final-ocr.txt" 2>/dev/null; then
  echo "BOOT CHECK FAIL ($MODE, $ACCEL): failure text on final screen"; exit 1
fi
if grep -qiE "$EXPECT" "$OUT/final-ocr.txt" 2>/dev/null; then
  echo "BOOT CHECK PASS ($MODE, $ACCEL)"; exit 0
fi
echo "BOOT CHECK FAIL ($MODE, $ACCEL): expected text not on final screen"; exit 1
