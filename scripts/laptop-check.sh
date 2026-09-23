#!/usr/bin/env bash
set -uo pipefail

REPORT_DIR="${LAPTOP_CHECK_REPORT_DIR:-/tmp/laptop-check/reports}"
PATTERNS="${LAPTOP_CHECK_PATTERNS:-/etc/laptop-check/patterns}"

heading() { printf '\n===== %s =====\n' "$1"; }
reference() { printf 'REFERENCE: %s\n' "$*"; }
field() {
  local path="$1" label="$2"
  if [[ -r "$path" ]]; then printf '  %-20s %s\n' "$label" "$(cat "$path")"; else printf '  %-20s unavailable\n' "$label"; fi
}
root() {
  if (( EUID == 0 )); then "$@"; else sudo -n "$@"; fi
}

help() {
  cat <<'HELP'
laptop-check [quick|battery|storage|inventory|firmware|stress|memory|display|input|camera|audio|network|ports|save|help]

In-person workflow (X1 Carbon Gen 9, MTM 20XXS02700):
  1. Before boot: F1 BIOS -> check Supervisor/Power-On/System Management/
     drive passwords are unset; Absolute/Computrace is not activated.
  2. Boot ISO. A terminal automatically runs quick; rerun it if needed.
  3. Read battery health and SSD warnings. Run stress (3 min) and memory.
  4. Run display, input, camera, audio, network and ports, using real devices.
     Move the lid gently while observing the screen and system stability.
  5. Run save /path/to/writable/USB to retain all reports before shutdown.

Commands (each prints a reference and writes a timestamped report):
  quick       Model/CPU/RAM, battery, NVMe health, panel, sensors, kernel errors
  battery     Design/full Wh, health, cycles, discharge power (unplug first)
  storage     NVMe SMART for every controller; no read/write stress
  inventory   Detailed inxi/PCI/USB hardware inventory (long output)
  firmware    BIOS/DMI, fwupd security, Thunderbolt devices; manual BIOS check
  stress      Three-minute CPU + memory workload with verification; no disk writes
  memory      One 4 GiB memtester pass; soldered RAM merits a longer test if suspect
  display     Fullscreen colors/gradient (Left/Right to advance, Esc to quit)
  input       libinput events; Ctrl+C to stop; check every key and pointing device
  camera      Preview webcam; close physical shutter to verify it works
  audio       Speaker channels then record/play back five seconds of microphone
  network     Wi-Fi/Bluetooth inventory; connect to phone hotspot manually
  ports       Live USB device events; Ctrl+C to stop; test both USB-C data/charging
  save DIR    Copy reports to an already mounted writable directory; never writes
              to the laptop's internal disk or mounts a device for you
  help        Show this workflow and command explanations

Reference values are purchase guidelines, not manufacturer pass/fail limits.
Reports live in /tmp (lost on shutdown) until copied with save. Reports contain
serial numbers, so remove them before sharing publicly.
HELP
}

machine() {
  heading MACHINE
  reference 'X1 Carbon Gen 9 / MTM 20XXS02700; i7-1165G7 = 4 cores/8 threads; installed RAM = 16 GB (about 15 GiB). Verify the label and the seller claim.'
  field /sys/class/dmi/id/product_name Model
  field /sys/class/dmi/id/product_version MTM
  field /sys/class/dmi/id/product_serial Serial
  field /sys/class/dmi/id/bios_version 'BIOS version'
  printf '  %-20s %s\n' CPU "$(awk -F: '/model name/{sub(/^ +/, "", $2); print $2; exit}' /proc/cpuinfo)"
  free -h | awk '/^Mem:/{print "  RAM                 " $2}'
  printf '  %-20s %s\n' 'Logical CPUs' "$(getconf _NPROCESSORS_ONLN)"
}

battery() {
  heading BATTERY
  reference '57 Wh design; >=54 Wh excellent, 51-54 very good, 48.5-51 good, 45.5-48.5 worn, <45.5 negotiate/replace. 203 cycles previously reported; cycles alone do not determine health.'
  local bat full design rate
  bat="$(find /sys/class/power_supply -maxdepth 1 -name 'BAT*' -print -quit 2>/dev/null)"
  if [[ -z "$bat" ]]; then echo 'UNKNOWN: No battery detected'; return 0; fi
  field "$bat/manufacturer" Manufacturer
  field "$bat/model_name" Model
  field "$bat/serial_number" Serial
  field "$bat/cycle_count" Cycles
  field "$bat/status" Status
  field "$bat/capacity" 'Current charge %'
  if [[ -r "$bat/energy_full" && -r "$bat/energy_full_design" ]]; then
    full="$(cat "$bat/energy_full")"; design="$(cat "$bat/energy_full_design")"
    if [[ "$design" =~ ^[0-9]+$ ]] && (( design > 0 )) && [[ "$full" =~ ^[0-9]+$ ]]; then
      awk -v f="$full" -v d="$design" 'BEGIN {printf "  Design / full       %.2f / %.2f Wh\n  Battery health      %.1f%% (controller estimate)\n", d/1000000, f/1000000, 100*f/d}'
      awk -v f="$full" 'BEGIN {if(f>=54000000) s="EXCELLENT"; else if(f>=51000000) s="VERY GOOD"; else if(f>=48500000) s="GOOD"; else if(f>=45500000) s="WORN"; else s="NEGOTIATE / REPLACE"; print "  Capacity guideline  " s}'
    fi
  else
    reference 'If energy_* absent, check charge_full and charge_full_design (mAh); do not compare charge to Wh without voltage.'
    field "$bat/charge_full" 'Full charge (uAh)'
    field "$bat/charge_full_design" 'Design (uAh)'
  fi
  rate="$(cat "$bat/power_now" 2>/dev/null || true)"
  if [[ "$rate" =~ ^[0-9]+$ ]]; then
    awk -v r="$rate" 'BEGIN {printf "  Current power       %.2f W\n", r/1000000}'
  fi
  reference 'Unplug and wait a few minutes at ~50% brightness: single-digit W in light use is desirable. An instantaneous 20 W reading is not a runtime prediction.'
  reference 'Optional ThinkPad detail from tlp-stat follows; firmware/controller estimates may be stale until calibrated.'
  root tlp-stat -b 2>&1 || true
}

storage() {
  heading STORAGE
  reference 'NVMe critical_warning = 0, media_errors = 0; percentage_used <20% generally fine, >50% inspect. Hours and unsafe shutdowns alone are not failure criteria. Expected advertised SSD: 256 GB.'
  lsblk -dn -o NAME,SIZE,MODEL,TRAN 2>/dev/null || true
  local dev output warning errors used found=0
  for dev in /dev/nvme[0-9]; do
    [[ -e "$dev" ]] || continue
    found=1
    printf '\n--- %s SMART ---\n' "$dev"
    output="$(root nvme smart-log "$dev" 2>&1)" || { printf '%s\nUNKNOWN: NVMe SMART unavailable\n' "$output"; continue; }
    printf '%s\n' "$output"
    warning="$(awk -F: 'tolower($1) ~ /^critical_warning/ {gsub(/[[:space:]]/, "", $2); print $2; exit}' <<<"$output")"
    errors="$(awk -F: 'tolower($1) ~ /^media_errors/ {gsub(/[[:space:],]/, "", $2); print $2; exit}' <<<"$output")"
    used="$(awk -F: 'tolower($1) ~ /^percentage_used/ {gsub(/[[:space:]%]/, "", $2); print $2; exit}' <<<"$output")"
    if [[ "$warning" =~ ^(0|0x0+)$ && "$errors" =~ ^0+$ ]]; then
      printf '  SMART guideline     PASS (warning=%s; media_errors=%s; used=%s%%)\n' "$warning" "$errors" "${used:-?}"
    elif [[ -z "$warning" || -z "$errors" ]]; then
      echo '  SMART guideline     UNKNOWN (check raw output above)'
    else
      printf '  SMART guideline     INVESTIGATE (warning=%s; media_errors=%s)\n' "$warning" "$errors"
    fi
  done
  (( found )) || echo 'UNKNOWN: No NVMe controller detected'
}

panel() {
  heading DISPLAY
  reference 'X1 Carbon G9 panels are 16:10; this listing is expected to be 1920x1200. EDID identifies the panel, not defects: inspect white/black/colors, marks, flicker and lid movement yourself.'
  local e found=0
  for e in /sys/class/drm/card*-eDP-*/edid; do
    [[ -s "$e" ]] || continue
    found=1
    edid-decode "$e" 2>&1 | awk '/Manufacturer:|Model:|Display Product Name:|DTD|1920x1200|2560x1600/{print; n++; if (n>=14) exit}'
  done
  (( found )) || echo 'UNKNOWN: No active eDP EDID found'
  xrandr --current 2>/dev/null | awk '/ connected /{print; getline; print}' || true
}

thermal() {
  heading THERMALS
  reference 'Idle often tens of Celsius; no strict pass threshold. Under stress, brief 90s Celsius may occur; persistent ~100 C, shutdown, fan grinding or hardware errors warrant investigation.'
  sensors 2>&1 || true
}

errors() {
  heading 'KERNEL ERRORS'
  reference 'No recurring NVMe I/O errors, machine checks, GPU hangs, or repeated PCIe errors. Generic ACPI/firmware warnings require context.'
  root journalctl -k -p err..alert --no-pager -n 80 2>&1 || true
}

quick() { machine; battery; storage; panel; thermal; errors; heading 'NEXT STEPS'; reference 'Check BIOS passwords/Absolute manually, then stress, memory, display/input/camera/audio/network/ports. Run laptop-check help. Save reports to a writable USB before shutdown.'; }

inventory() {
  heading INVENTORY
  reference 'Expected X1 Carbon G9, i7-1165G7, 16 GB, 256 GB advertised SSD, internal eDP display, Intel Wi-Fi. Device inventory cannot prove each device works.'
  inxi -Fxxxz 2>&1 || true
  lspci -nnk 2>&1 || true
  lsusb 2>&1 || true
  root lshw -short 2>&1 || true
}

firmware() {
  heading FIRMWARE
  reference 'BIOS: Supervisor/Power-On/System Management/drive passwords unset; Absolute not activated. Linux cannot conclusively verify these; enter F1 BIOS. Secure Boot may be off for this live USB.'
  field /sys/class/dmi/id/bios_vendor Vendor
  field /sys/class/dmi/id/bios_version Version
  field /sys/class/dmi/id/bios_date Date
  root dmidecode -t system 2>&1 || true
  reference 'fwupd HSI is informational on live media; failed enumeration is not by itself a hardware defect.'
  fwupdmgr security 2>&1 || true
  reference 'Thunderbolt listing may be empty if nothing is connected; test both USB-C ports physically.'
  boltctl list 2>&1 || true
}

stress() {
  heading STRESS
  reference '3 min CPU + memory verification; zero verification failures, no freezes/shutdowns, no machine checks. Brief 90s C can be normal; sustained ~100 C or fan grinding needs investigation. Ctrl+C cancels.'
  stress-ng --cpu 8 --vm 2 --vm-bytes 30% --verify --timeout 180s --metrics-brief
  local rc=$?
  thermal; errors
  printf 'Stress exit status: %s (0 expected)\n' "$rc"
  return "$rc"
}

memory() {
  heading MEMORY
  reference 'One 4 GiB pass; zero errors expected. This is a quick screen, not a full RAM qualification. X1 Carbon G9 RAM is soldered.'
  root memtester 4G 1
  local rc=$?
  printf 'Memtester exit status: %s (0 expected)\n' "$rc"
  return "$rc"
}

display() {
  heading 'DISPLAY PATTERNS'
  reference 'Use Left/Right to cycle, Esc to exit. White: marks/scratches; black: bleed; RGB: stuck pixels; gray/gradient: uneven tint/banding. Move lid gently; image must remain stable.'
  reference 'Test brightness from minimum to maximum with Fn keys or brightnessctl set 10% / 50% / 100%; no flicker or jumps.'
  brightnessctl -m 2>&1 || true
  if [[ -z "${DISPLAY:-}" ]]; then echo 'Start the graphical session first; DISPLAY is unset.'; return 1; fi
  feh --fullscreen --hide-pointer --auto-zoom "$PATTERNS"/{white,black,red,green,blue,gray,gradient}.png
}

input() {
  heading INPUT
  reference 'Each key should emit once per press/release; TrackPoint moves in all directions, buttons click; touchpad moves/clicks/scrolls; keyboard backlight Fn+Space. Ctrl+C exits.'
  root libinput debug-events --show-keycodes
}

camera() {
  heading CAMERA
  reference 'Image visible and stable; ThinkShutter covers image when closed. Close mpv to finish; try another /dev/video* if the first is metadata-only.'
  local dev
  v4l2-ctl --list-devices 2>&1 || true
  for dev in /dev/video*; do
    [[ -e "$dev" ]] || continue
    if v4l2-ctl -d "$dev" --all 2>/dev/null | grep -q 'Video Capture'; then
      mpv --profile=low-latency "av://v4l2:$dev"; return $?
    fi
  done
  echo 'UNKNOWN: No capture camera found'; return 1
}

audio() {
  heading AUDIO
  reference 'Left/right speakers clear without crackle; microphone recording audible; headphone jack switches output. Ctrl+C ends speaker test if needed.'
  speaker-test -c 2 -t wav -l 1 || true
  local sample
  sample="$(mktemp --suffix=.wav)"
  echo 'Speak into the microphone for five seconds...'
  if arecord -q -d 5 -f cd "$sample"; then aplay -q "$sample"; else echo 'UNKNOWN: microphone recording failed'; fi
  rm -f "$sample"
}

network() {
  heading NETWORK
  reference 'Wi-Fi sees your hotspot and connects via nmcli; Bluetooth controller lists and scans nearby devices. Listing alone does not prove connectivity.'
  nmcli device status 2>&1 || true
  nmcli device wifi list 2>&1 || true
  bluetoothctl list 2>&1 || true
  echo 'Use nmcli device wifi connect SSID --ask; bluetoothctl scan on (Ctrl+C).'
}

ports() {
  heading PORTS
  reference 'Two USB-C ports: both should charge AND transfer data without intermittent disconnects. Test two USB-A ports, HDMI, headphones. Use a known-good charger and peripheral. Ctrl+C exits.'
  echo 'Plug devices one at a time; check each USB-C charging state in a second terminal with laptop-check battery.'
  lsusb 2>&1 || true
  root udevadm monitor --kernel --subsystem-match=usb
}

save() {
  local dest="${1:-}"
  heading 'SAVE REPORTS'
  reference 'Use an already mounted writable destination, preferably a second USB or writable partition. Reports contain serial numbers; /tmp disappears at shutdown.'
  if [[ -z "$dest" || ! -d "$dest" || ! -w "$dest" ]]; then
    echo 'Usage: laptop-check save /path/to/already-mounted/writable/USB'; return 2
  fi
  if [[ ! -d "$REPORT_DIR" ]]; then echo 'No reports found; run laptop-check quick first.'; return 1; fi
  local target="$dest/laptop-check-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$target" || return 1
  cp -v "$REPORT_DIR"/*.txt "$target"/ || return 1
  echo "Saved to $target"
}

main() {
  local command="${1:-help}" status
  case "$command" in
    help|-h|--help) help; return 0 ;;
    save) save "${2:-}"; return $? ;;
    quick|battery|storage|inventory|firmware|stress|memory|display|input|camera|audio|network|ports) ;;
    *) printf 'Unknown command: %s\n\n' "$command" >&2; help >&2; return 2 ;;
  esac
  mkdir -p "$REPORT_DIR" || return 1
  local report="$REPORT_DIR/$(date +%Y%m%d-%H%M%S)-${command}.txt"
  ( "$command" ) 2>&1 | tee "$report"
  status=${PIPESTATUS[0]}
  printf '\nReport: %s\n' "$report"
  return "$status"
}

main "$@"
