#!/usr/bin/env python3
"""Brand Parrot's boot menus for KettsecOS and keep forensic mode available."""

from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
version = sys.argv[2]
grub_path = root / "boot/grub/grub.cfg"
grub = grub_path.read_text().replace("Kettco OS", "KettsecOS").replace("hostname=kettco", "hostname=kettsecos")
live_label = f'menuentry "KettsecOS {version} (live)"'
if 'menuentry "Try / Install"' not in grub and not re.search(
    r'menuentry "KettsecOS [^"]+ \(live\)"', grub
):
    raise RuntimeError("Unexpected Parrot GRUB menu")
grub = re.sub(
    r'menuentry "(?:Try / Install|KettsecOS [^"]+ \(live\))"',
    live_label,
    grub,
    count=1,
)
# Keep persistent boots opt-in so a normal live session remains ephemeral.
# Only probe USB media: persistence-labeled internal disks must never be used.
grub = grub.replace(
    'menuentry "Persistence (needs configuration)"',
    'menuentry "KettsecOS (persistent storage, unencrypted)"',
    1,
)
grub = grub.replace(
    'components noautomount persistence\n',
    'components noautomount persistence persistence-encryption=none persistence-media=removable-usb\n',
    1,
)
grub = grub.replace(
    'menuentry "Encrypted persistence (needs configuration)"',
    'menuentry "KettsecOS (persistent storage, encrypted)"',
    1,
)
grub = grub.replace(
    'components noautomount persistent=cryptsetup persistence-encryption=luks persistence\n',
    'components noautomount persistence persistence-encryption=lukslabel persistence-media=removable-usb\n',
    1,
)
for label in (
    'menuentry "KettsecOS (persistent storage, unencrypted)"',
    'menuentry "KettsecOS (persistent storage, encrypted)"',
):
    if label not in grub:
        raise RuntimeError(f"Missing persistent GRUB entry: {label}")
if grub.count("persistence-media=removable-usb") != 2:
    raise RuntimeError("Both GRUB persistence entries must be restricted to USB media")
# The forensic entry is first in GRUB, so select the regular live session by
# default. Keep forensic mode available as an explicit menu choice.
grub, default_count = re.subn(r"(?m)^set default=\d+$", "set default=1", grub, count=1)
if default_count != 1:
    raise RuntimeError("Could not set the normal live boot as the default")
grub = grub.replace("hostname=parrot", "hostname=kettsecos")
kernel = "/live/vmlinuz-7.0.9+parrot7-amd64"
initrd = "/live/initrd.img-7.0.9+parrot7-amd64"
if kernel not in grub or initrd not in grub:
    raise RuntimeError("Unexpected Parrot live kernel paths")
forensic = f'''menuentry "KettsecOS {version} (forensic mode)" --class iso {{
        set gfxpayload=keep
        linux {kernel} boot=live hostname=kettsecos components noautomount noswap aegisos.forensic=1 systemd.gpt_auto=no rd.systemd.gpt_auto=no fsck.mode=skip
        initrd {initrd}
}}

'''
forensic_label = f'menuentry "KettsecOS {version} (forensic mode)"'
if forensic_label not in grub:
    prior_forensic = re.search(r'menuentry "KettsecOS [^"]+ \(forensic mode\)"', grub)
    if prior_forensic:
        start = prior_forensic.start()
        end = grub.find("\n", start)
        grub = grub[:start] + forensic_label + grub[end:]
    else:
        grub = grub.replace("# Live boot\n", "# Live boot\n" + forensic, 1)
grub_path.write_text(grub)

theme_path = root / "boot/grub/live-theme/theme.txt"
theme = theme_path.read_text().replace("Kettco OS", "KettsecOS")
old_title = 'text = "Parrot security Live Boot Menu - 7.3 amd64"'
new_title = f'text = "KettsecOS {version}"'
if old_title in theme:
    theme = theme.replace(old_title, new_title, 1)
elif re.search(r'text = "KettsecOS [^"]+"', theme):
    theme = re.sub(r'text = "KettsecOS [^"]+"', new_title, theme, count=1)
else:
    raise RuntimeError("Unexpected Parrot GRUB theme title")
theme_path.write_text(theme)

bios_path = root / "isolinux/menu.cfg"
bios = bios_path.read_text().replace("Kettco OS", "KettsecOS").replace("hostname=kettco", "hostname=kettsecos")
if "label ^live" not in bios:
    raise RuntimeError("Unexpected Parrot ISOLINUX menu")
if "menu title Parrot security - 7.3 amd64" in bios:
    bios = bios.replace("menu title Parrot security - 7.3 amd64", f"menu title KettsecOS {version}", 1)
elif re.search(r"menu title KettsecOS [^\n]+", bios):
    bios = re.sub(r"menu title KettsecOS [^\n]+", f"menu title KettsecOS {version}", bios, count=1)
else:
    raise RuntimeError("Unexpected Parrot ISOLINUX title")
if "^Try / Install" in bios:
    bios = bios.replace("^Try / Install", f"^KettsecOS {version} (live)", 1)
elif re.search(r"\^KettsecOS [^\n]+ \(live\)", bios):
    bios = re.sub(r"\^KettsecOS [^\n]+ \(live\)", f"^KettsecOS {version} (live)", bios, count=1)
else:
    raise RuntimeError("Unexpected Parrot ISOLINUX label")
bios = bios.replace("hostname=parrot", "hostname=kettsecos")
# Keep persistence opt-in and restrict probing to the boot USB.
bios = bios.replace(
    "menu label Persistence\n",
    "menu label KettsecOS (persistent storage, unencrypted)\n",
    1,
)
bios = bios.replace(
    "append boot=live hostname=kettsecos quiet persistence components",
    "append boot=live hostname=kettsecos quiet persistence persistence-encryption=none persistence-media=removable-usb components",
    1,
)
bios = bios.replace(
    "menu label Encrypted Persistence\n",
    "menu label KettsecOS (persistent storage, encrypted)\n",
    1,
)
bios = bios.replace(
    "append boot=live persistent=cryptsetup persistence-encryption=luks hostname=kettsecos quiet persistence components",
    "append boot=live persistence persistence-encryption=lukslabel persistence-media=removable-usb hostname=kettsecos quiet components",
    1,
)
if "menu label Forensics" in bios:
    bios = bios.replace("menu label Forensics", f"menu label KettsecOS {version} (forensic mode)", 1)
    bios = bios.replace(
        "append boot=live hostname=kettsecos noswap noautomount components",
        "append boot=live hostname=kettsecos noswap noautomount components aegisos.forensic=1 systemd.gpt_auto=no rd.systemd.gpt_auto=no fsck.mode=skip",
        1,
    )
elif re.search(r"menu label KettsecOS [^\n]+ \(forensic mode\)", bios):
    bios = re.sub(
        r"menu label KettsecOS [^\n]+ \(forensic mode\)",
        f"menu label KettsecOS {version} (forensic mode)",
        bios,
        count=1,
    )
else:
    raise RuntimeError("Unexpected Parrot ISOLINUX forensic entry")
if bios.count("persistence-media=removable-usb") != 2:
    raise RuntimeError("Both BIOS persistence entries must be restricted to USB media")
bios_path.write_text(bios)
