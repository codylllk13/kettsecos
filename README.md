# KettsecOS

KettsecOS is a Matrix inspired AI security workstation based on Parrot Security Edition 7.3. Its `lllK` logo uses three vertical strokes and a K in the green and black desktop theme. It keeps Parrot's `parrot-tools-full` metapackage for both the live desktop and installed system, and adds KDE Plasma, fixed window decorations, NetworkManager, the four requested browsers, the Aegis assistant and opt-in hardening.

The Parrot 7.3, Tor Browser and AI payload downloads are checked and pinned. The Parrot source image is verified against its signed SHA256 manifest. Software from Mullvad's signed Debian repository and Ungoogled Chromium from Flathub are installed into the image during the build. No API keys, VPN credentials, task history or personal data are stored in the source or ISO. The locked public Huihui Qwen3.5 9B model is deliberately bundled for offline use; its build cache remains ignored and out of Git.

## Build

The builder needs an amd64 Debian family host with root access, internet connectivity, and at least 80 GB of free disk space. Install `curl`, `gpg`, `xorriso`, `squashfs-tools`, `python3`, `grub-pc-bin`, `grub-efi-amd64-bin`, `mtools`, and `dosfstools`, then run:

```bash
bash tests/test-remix.sh
PYTHONPATH=assets/agent python3 -m unittest discover -s tests -p 'test_*.py' -v
python3 tools/fetch-parrot.py
python3 tools/fetch-browsers.py
python3 tools/fetch-ai.py
sudo ./build-iso.sh
```

The Parrot source ISO downloads resumably into the ignored `cache/` directory. The build verifies Parrot's signed release manifest before using it and verifies the Tor Browser and AI payload hashes before bundling them. A successful preview.3 build writes `out/kettsec-os-3.0-preview.3-amd64.iso`. Older ISO files and previously flashed USB drives do not gain source changes automatically.

Run the ISO in a VM before using it. Test both BIOS and UEFI boot, Plasma login, Ethernet and Wi-Fi, all browser launchers, the full tool metapackage, the live installer, and encrypted and unencrypted installations. Do not install to a disk until you have identified its model and size and verified a backup.

## Desktop, network, and browsers

KDE Plasma uses KWin with Breeze window decorations. The default title bar includes close, minimize, and maximize buttons. NetworkManager manages Ethernet and Wi-Fi, including Realtek Ethernet through `firmware-realtek`; the image contains no copied network profiles.

The Internet menu includes:

- Firefox ESR from Parrot's Debian package archive.
- Mullvad Browser and Mullvad VPN from Mullvad's signed APT repository. Connecting the VPN requires the owner's Mullvad account.
- Ungoogled Chromium installed from Flathub as a system Flatpak.
- Tor Browser from a Tor signed archive. Its first launch copies the verified bundle to that user's home so its built-in updater can update it.

Mullvad Browser uses a direct connection unless a VPN is connected. Tor Browser uses the Tor network. These browsers have separate purposes; installing the VPN does not silently route the entire system over Mullvad. Tor routing for the whole workstation remains an explicit opt-in through `sudo aegisos-privacy enable`.

## Security and installation

The live image retains Parrot's full security toolkit. Calamares is configured to remove only transient live and installer packages; VM testing must verify that `parrot-tools-full`, `firmware-realtek`, and the browsers remain installed. KWin, Plasma and SDDM are included. KettsecOS keeps UFW, AppArmor, unattended upgrades, SSH hardening, AIDE initialization and the forensic boot mode. Tor routing, SSH server access and USBGuard stay disabled unless explicitly enabled.

The installer hides manual partitioning, starts with no disk selected, and offers LUKS2 encryption. In the patched installer, whole-disk erase stays blocked until the user types the exact model, byte capacity and device path shown for the selected disk. Calamares rechecks the live block device and available sysfs model/serial immediately before partition writes. Image customization builds the patched Parrot-matched Calamares 3.3.14-1 plugin. Confirm its installer behavior in a VM before installing to a physical disk.

Use the penetration testing tools only against systems you own or have explicit authorization to assess.

## Portable USB with persistence

The ordinary live boot is temporary. The boot menus include opt-in unencrypted and LUKS2-encrypted persistence entries. Live-boot reads a `persistence.conf` file from a partition labeled `persistence`; `/ union` requests a writable overlay for system changes and the user's home. Persistence probing is restricted to removable USB media, and forensic mode does not enable persistence.

After building and checking the preview.3 ISO, identify the target USB by model, size and serial with `lsblk`. Prepare it with:

```bash
sudo ./tools/prepare-persistent-usb.sh out/kettsec-os-3.0-preview.3-amd64.iso /dev/sdX
```

Replace `/dev/sdX` with the **whole USB device**, never a partition or internal disk. The tool requires a removable USB with at least 8 GiB left after the ISO, displays model, serial and byte capacity, and requires typing all three before it erases the drive. It writes the ISO and creates encrypted persistence by default, asking for a new LUKS2 passphrase in the local terminal. Add `plain` as the third argument only if you want unencrypted persistence. Choose the matching persistence entry under Advanced Modes when booting. A normal live boot will not load saved changes.

This is a fresh-media preparation workflow. It rechecks model, serial, transport, capacity and mount state after confirmation and around partition changes, and unmounts target partitions if the desktop auto-mounts them. It erases **all** USB contents, including any existing persistence, so back up data first. There is no update workflow that refreshes the ISO while preserving a persistence partition. Cross-PC cold-boot tests, including firmware, graphics, networking and persistence recovery, remain beta gates. Keep the USB inserted during shutdown so live-boot can flush changes. Secure Boot signing is outside this release.

## Aegis agent

`aegis-agent run "..."` and the Qt desktop app share a user level task service and private SQLite history under the user data directory. The image includes the official Codex CLI, the official ChatGPT Linux preview and a user-level Ollama service with `huihui_ai/qwen3.5-abliterated:9b` available offline. Local Ollama and an OpenAI-compatible LAN endpoint can be configured with `AEGIS_OLLAMA_URL`, `AEGIS_LOCAL_MODEL`, `AEGIS_LAN_URL`, and `AEGIS_LAN_MODEL`; LAN inference is expected through an SSH tunnel bound to loopback. `aegis-agent status` reports local model readiness. Sign in to Codex or ChatGPT on first use; no credentials are embedded.

Active scans require approval of the target and task. The initial tool allowlist limits scan modes and checks targets against the approved scope. Tools run as the logged in user. The agent does not expose root or arbitrary shell access. Cloud tasks using Sign in with ChatGPT display the exact content and require per task approval; if cloud access is unavailable the task stays on local/LAN models.

## Flash a USB installer

After the image is built and checked, identify the removable USB by model, size, and serial with `lsblk`. Flash the whole disk with:

```bash
sudo ./tools/flash-iso-to-usb.sh out/kettsec-os-3.0-preview.3-amd64.iso /dev/sdX
```

The script refuses fixed disks and mounted filesystems, checks the selected model, size and serial, and compares the USB read back against the complete ISO. It replaces all data on that USB and creates an installer without persistence. To boot and save changes on the USB, use the persistent USB command above. Neither command installs the OS to an internal drive.

## License

KettsecOS code is GPL-3.0-or-later; see [LICENSE](LICENSE). Parrot OS, Mullvad, Tor Browser, Flathub and their trademarks and packages retain their respective upstream licenses.
