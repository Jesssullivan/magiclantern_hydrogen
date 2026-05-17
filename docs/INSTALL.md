# Installing magiclantern_hydrogen on a Canon DSLR

This guide covers the four in-scope cameras:

- Canon 5D Mark II (firmware 2.1.2) — tarball `magiclantern-hydrogen-<TAG>-5D2.212.tar.gz`
- Canon 5D Mark III (firmware 1.1.3) — `magiclantern-hydrogen-<TAG>-5D3.113.tar.gz`
- Canon 5D Mark III (firmware 1.2.3) — `magiclantern-hydrogen-<TAG>-5D3.123.tar.gz`
- Canon 5D Mark IV (firmware 1.3.3) — `magiclantern-hydrogen-<TAG>-5D4.133.tar.gz`

> [!CAUTION]
> Magic Lantern modifies the way your camera boots. Use a dedicated SD card.
> Backup any photos first. **This fork is for heavily-modified cameras**
> (AA filter and full filter stack removed) used in research contexts.
> Run it on an unmodified body at your own risk.

## 1. Verify your firmware version

On the camera:

```
Menu → Wrench → Firmware Ver.
```

The displayed version must match the platform name in the tarball
(e.g. `1.2.3` → `5D3.123`). If your camera reports a different version,
download the matching tarball from the
[releases page](https://github.com/Jesssullivan/magiclantern_hydrogen/releases)
or update / downgrade Canon firmware first.

## 2. Prep the SD card

Use an empty card (or one whose photos you have backed up):

```
Menu → Wrench → Format card → Low level format
```

The card must be FAT32 (≤ 32 GB) or exFAT (> 32 GB). The card must be
**bootable** — check `Menu → Wrench → Cards setup → Make EOS card
bootable` once Magic Lantern is on it.

## 3. Verify the tarball

Every release ships a `.sha256` sidecar:

```bash
TAG=v0.4.0                                    # or whichever
PLATFORM=5D3.123
URL=https://github.com/Jesssullivan/magiclantern_hydrogen/releases/download/${TAG}
curl -LO ${URL}/magiclantern-hydrogen-${TAG}-${PLATFORM}.tar.gz
curl -LO ${URL}/magiclantern-hydrogen-${TAG}-${PLATFORM}.tar.gz.sha256
shasum -a 256 -c magiclantern-hydrogen-${TAG}-${PLATFORM}.tar.gz.sha256
```

`OK` means the bytes match. If `FAILED`, re-download.

## 4. Copy to the SD card

```bash
tar xzf magiclantern-hydrogen-${TAG}-${PLATFORM}.tar.gz
# macOS:
cp -r magiclantern-hydrogen-${TAG}-${PLATFORM}/* /Volumes/EOS_DIGITAL/
# Linux:
cp -r magiclantern-hydrogen-${TAG}-${PLATFORM}/* /run/media/$USER/EOS_DIGITAL/
sync
```

The tarball lays down:

- `autoexec.bin` — ML bootloader, picked up by Canon's firmware at boot.
- `ML-SETUP.FIR` — the installer "firmware update" image (one-time use).
- `modules/` — ML modules (`.mo`) loaded at runtime.
- `MODULES.txt` — manifest of module names.
- `README.md` — per-platform notes (any platform-specific quirks).
- `INSTALL.md` — this guide.

Eject the card cleanly (`diskutil unmount` on macOS, `umount` on Linux).

## 5. First-time install — run the installer

> Once-per-camera. After this, only the `autoexec.bin` swap is needed for
> upgrades.

1. Insert the SD card. Set the camera's mode dial to `M` (manual).
2. `Menu → Wrench → Firm Ver.` → select.
3. Confirm the firmware update prompt. **Do not power-cycle during this
   step.**
4. The camera will reboot. Magic Lantern is now installed in flash.

## 6. Regular upgrades

For subsequent releases, you only need to overwrite `autoexec.bin` and
the `modules/` directory:

```bash
TAG=v0.5.0
PLATFORM=5D3.123
URL=https://github.com/Jesssullivan/magiclantern_hydrogen/releases/download/${TAG}
curl -L "${URL}/magiclantern-hydrogen-${TAG}-${PLATFORM}.tar.gz" | tar xz
cp magiclantern-hydrogen-${TAG}-${PLATFORM}/autoexec.bin /Volumes/EOS_DIGITAL/
cp -r magiclantern-hydrogen-${TAG}-${PLATFORM}/modules/* /Volumes/EOS_DIGITAL/ML/modules/
```

No firmware-update step is needed — Canon's flash is unchanged.

## 7. Recovery (camera won't boot)

ML cannot brick the camera as long as you stay on a matching Canon
firmware version. Remove the SD card; the camera boots stock Canon.

If the camera misbehaves while ML is loaded:

1. Power off, remove the SD card.
2. Power on without a card — confirm stock Canon comes up.
3. Reformat the card (in-camera `Low level format`).
4. Re-copy the tarball contents.

## 8. Uninstall

```
Menu → Wrench → Firm Ver. → run ML-SETUP.FIR with the "uninstall" prompt
```

Then either reformat the card or delete `autoexec.bin` and `ML/` from it.
Canon's flash is restored to its pre-ML state.

## 9. Troubleshooting

| Symptom | Likely cause |
|---|---|
| Camera ignores ML, boots stock Canon | Card not bootable (re-do `Make EOS card bootable`) or wrong firmware version |
| ML half-loads then hangs | Module `.mo` mismatch — wipe `ML/modules/` and re-copy from the tarball |
| Long card-write delays in raw video | Slow card — magic lantern's MLV path needs UHS-I U3 minimum, ideally U3/V60+ |
| `RAWX` / `AFLG` blocks missing from output | Modules `rawspect` / `aflogger` not enabled — turn them on in `ML menu → Modules` |

See `developer_guide/` in the source tree for deeper architecture notes.
