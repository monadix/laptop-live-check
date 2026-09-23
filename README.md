# Laptop Live Check

A NixOS live USB for inspecting a used laptop in person. The initial reference profile is the **ThinkPad X1 Carbon Gen 9, MTM 20XXS02700**, offered with an i7-1165G7, 16 GB RAM, 256 GB SSD and 57 Wh battery. The reference values are purchase guidelines for this specific listing; the raw measurements remain useful on other laptops.

It boots into a small Openbox desktop and automatically opens an `xterm` with `laptop-check quick`. All diagnostic dependencies and seven display patterns are included in the ISO. Inspection does not require Internet access. The script only reads the laptop's internal storage; stress and memtester work in RAM.

## Build and put it on USB

On an x86_64 NixOS/Linux machine with Nix flakes enabled:

```bash
nix build .#iso
ls -lh result/iso/*.iso
```

Alternatively, use the **ISO build** GitHub Actions workflow. Download the `laptop-inspection-iso` artifact from a successful run. A build on GitHub's hosted runner may take a while and can fail if the runner runs out of disk space; a local build is the fallback.

Identify the **whole USB device**, carefully distinguishing it from your system disk:

```bash
lsblk -o NAME,SIZE,MODEL,MOUNTPOINTS
iso_file=$(find result/iso -maxdepth 1 -name '*.iso' -print -quit)
test -n "$iso_file" && sudo dd if="$iso_file" of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

Replace `/dev/sdX` with the correct whole device (for example, `/dev/sdb`, **not** `/dev/sdb1`). `dd` destroys existing contents of the destination USB. Do not run it until you have verified the device identity. A tool such as GNOME Disks can write the ISO instead.

UEFI boot via F12 on the ThinkPad. Secure Boot may need to be disabled for this unsigned ISO. Enter BIOS with F1 separately to check passwords and Absolute status. The image is read-only and its `/tmp` is ephemeral: bring a second writable USB, or make a writable partition elsewhere, if you want to keep reports. `laptop-check save /run/media/nixos/YOUR_USB` copies them to an already mounted writable directory; the script never mounts or formats a disk.

## Inspection sequence

1. F1 BIOS: check Supervisor, Power-On, System Management and drive passwords are unset; Absolute is not activated. Confirm MTM.
2. F12 boot: read the `quick` report in the automatically opened terminal. Run `laptop-check help` at any time.
3. Unplug the charger, wait a few minutes, run `laptop-check battery`; reconnect it to **both USB-C ports**, one after the other. Test data with a USB-C device in each port too.
4. Run `laptop-check stress` (3 minutes), `laptop-check memory` (one pass), and `laptop-check firmware`. `inventory` provides an optional full hardware listing.
5. Run `display`, `input`, `camera`, `audio`, `network` and `ports` with the actual screen and peripherals. Move the lid gently and check that the display and system remain stable.
6. Run `laptop-check save /path/to/mounted/writable/USB` before shutting down. Reports include serial numbers: redact them before posting publicly.

All subcommands print their expected values or behavior directly above the measurements/events. `quick` reports raw values and a limited guideline for the battery and SSD. It intentionally does **not** call a whole laptop “PASS” without the BIOS and manual checks.

| Measurement | Reference for this listing | Interpretation |
|---|---:|---|
| Battery design | about 57 Wh | Reported full capacity / design gives controller-estimated health. |
| Battery full | ≥54 Wh excellent; 51–54 very good; 48.5–51 good; below 45.5 negotiate/replace | Earlier AIDA screenshot reported 56.99 Wh and 203 cycles; check this actual unit. |
| NVMe SMART | critical warning 0; media errors 0; percentage used under 20% ordinarily fine | SSD can be replaced; use the drive's raw SMART as evidence. |
| CPU stress | no verification failure, shutdown, machine check, or fan grinding | Brief temperatures in the 90s °C can occur; persistent ~100 °C merits investigation. |
| Memory | zero memtester errors | One pass is a quick screen; this model's RAM is soldered. |
| Screen, ports, input | visible image without defects; both USB-C ports charge and transfer data; all controls respond | These require manual inspection. |

If `quick` reports `UNKNOWN`, read its raw tool output and run the specific subcommand; `UNKNOWN` is not a hardware failure.

## Why these parts

The minimal NixOS installer supplies broad hardware support. Openbox and xterm provide a small GUI needed for screen, camera and pointer checks. `nvme-cli` reads drive health; sysfs reports the battery's learned capacity; `stress-ng` and `memtester` test stability; `feh` shows pixel patterns. `fwupd` and `bolt` provide firmware and Thunderbolt context, but cannot replace opening BIOS or physically testing both sockets. Gzip level 1 trades a larger ISO for fast decompression at the seller's desk.

The system is intentionally offline-capable and does not automatically update firmware, write to internal disks, or upload reports. `save` is the explicit exception: it copies reports to the directory you provide.

## Sources

- [Lenovo ThinkPad X1 Carbon Gen 9 PSREF](https://psref.lenovo.com/syspool/Sys/PDF/ThinkPad/ThinkPad_X1_Carbon_Gen_9/ThinkPad_X1_Carbon_Gen_9_Spec.html): battery, memory and I/O specifications.
- [Linux power supply class](https://docs.kernel.org/power/power_supply_class.html): meaning of reported battery energy values.
- [NixOS ISO guide](https://wiki.nixos.org/wiki/Creating_a_NixOS_live_CD): build and imaging approach.
- [NixOS X11 manual](https://nixos.org/manual/nixos/stable/#sec-x11): auto-login and window manager setup.

## Development

`bash -n scripts/laptop-check.sh` checks shell syntax. `python3 scripts/patterns.py /tmp/patterns` generates the seven PNGs. The GitHub workflow evaluates and builds the actual NixOS ISO; a script syntax check alone does not verify that NixOS options or package attributes exist. Keep `flake.lock` after the first `nix flake lock` to pin nixpkgs for reproducible rebuilds.
