# Remote Share for reMarkable Paper Pro

Remote Share is a private, on-demand file-transfer tool for the reMarkable Paper Pro. It is an open-source reMarkable Connect alternative for one specific job: reaching the tablet's stock web interface from a phone or computer over Tailscale, without plugging in a USB cable every time.

After the one-time USB installation, a home-screen switch turns remote sharing on and off. While it is on, you can open the familiar reMarkable web interface in a browser and transfer documents from Windows, macOS, Linux, Android, or iOS. The connection shuts itself down after 30 minutes by default.

The project deliberately has a narrow compatibility target. It does not install or patch the mod framework, enable Wi-Fi SSH, alter xochitl's service, add a boot daemon, or expose the web interface to the public internet.

## What problem it solves

The built-in reMarkable USB web interface is useful, but normally requires a cable and a local USB connection. Remote Share makes that same interface available through your private Tailscale network when you ask for it.

- Transfer PDFs, EPUBs, and other files supported by the stock importer.
- Reach the Paper Pro from a laptop or phone away from the tablet's USB cable.
- Keep the service off when it is not being used.
- Avoid a permanent sync daemon, public port, Wi-Fi SSH server, or custom browser on the tablet.
- Keep using the native reMarkable document importer instead of writing directly into its document database.

This is remote browser-based file transfer, not continuous folder synchronization.

## Is this a reMarkable Connect alternative?

For remote file transfer, yes. Remote Share gives a modified Paper Pro an independent way to move files through a browser without using the reMarkable cloud for that transfer session. The software is open source and does not require a Remote Share subscription.

It is not a complete replacement for reMarkable Connect. It does not provide cloud library synchronization, automatic cloud backup, handwriting conversion, official desktop or mobile app integration, collaboration features, or reMarkable support. Connect and Remote Share can coexist; this project does not remove, disable, or bypass Connect.

## Exact compatibility

Version 0.1.0 supports only this combination:

| Component | Required value |
| --- | --- |
| Device | reMarkable Paper Pro (`Ferrari`) |
| Architecture | `aarch64` |
| reMarkable OS | `3.28.0.172` |
| XOVI | `0.3.3-r2` |
| qt-resource-rebuilder | `19.0.0-r4` |
| xovi-extensions | `19.0.0-r4` |
| Tailscale | `1.104.1` |

The installer fails closed on any other combination. There is no force or compatibility-override option. AppLoad is not used.

The existing Vellum installation must include `qt-command-executor`, and qt-resource-rebuilder must already have a valid hashtable generated specifically for OS 3.28.0.172. XOVI must be inactive during installation.

## What it installs

- `/home/root/remote-share`: controller, configuration, Tailscale executables, local state, and runtime files
- `/home/root/xovi/exthome/qt-resource-rebuilder/remoteShare.qmd`: home-screen button
- `/home/root/xovi/extensions.d/loopback-importer.so`: a small extension that lets xochitl's built-in importer answer on loopback

No service is enabled. Tailscale starts only when the button is turned on and stops on OFF, timeout, or startup failure. The Serve rule is removed during shutdown. The node uses userspace networking and refuses DNS, routes, exit-node behavior, Tailscale SSH, and firewall integration. Funnel is never configured.

## Install

Download the host installer from this repository and use the assets from the [latest release](https://github.com/MrSmaugerson05/remarkable-remote-share/releases/latest). The first installation still uses USB SSH because the tablet must not expose SSH over Wi-Fi. Supply your own USB host address and private-key path; neither is stored by this project.

Windows PowerShell:

```powershell
.\scripts\install.ps1 -DeviceHost $deviceHost -IdentityFile $identityFile
```

Linux or macOS:

```sh
./scripts/install.sh "$DEVICE_HOST" "$SSH_IDENTITY"
```

The host installer:

1. verifies the signed-transport release checksum;
2. downloads Tailscale 1.104.1 directly from Tailscale and checks the pinned SHA-256;
3. copies a temporary payload over USB SSH;
4. runs the exact compatibility checks on the tablet;
5. opens an interactive Tailscale login and leaves sharing OFF.

The Tailscale login URL is printed by Tailscale itself. Do not put an auth key in a script or configuration file. After installation, reboot and use the existing three-button XOVI startup gesture. This project neither installs nor changes that gesture.

## Daily use

First turn on the stock USB web interface under **Settings → General → Storage**. It remains bound to the tablet's loopback interface; Remote Share does not enable Wi-Fi SSH.

On the home screen, press the Remote Share icon:

- cloud with an X: OFF
- lightning: starting or stopping
- checked cloud: ON
- warning circle: startup failed

When ON, the controller prints and stores the usable URL derived from `tailscale ip -4`. Open that URL on another device signed into the same Tailscale network. The switch automatically returns to OFF after the configured timeout without a polling process.

Controller commands are available locally as:

```sh
/home/root/remote-share/remote-share-control auth
/home/root/remote-share/remote-share-control on
/home/root/remote-share/remote-share-control off
/home/root/remote-share/remote-share-control toggle
/home/root/remote-share/remote-share-control status
/home/root/remote-share/remote-share-control status-fast
```

## Configuration

Edit `/home/root/remote-share/config` as root while sharing is OFF:

```ini
REMOTE_SHARE_HOSTNAME=remarkable-paper-pro
REMOTE_SHARE_PORT=8080
AUTO_OFF_SECONDS=1800
```

The hostname accepts letters, digits, and hyphens. The port must be from 1024 through 65535. The timeout must be from 60 through 86400 seconds. The controller rejects invalid values.

## Recovery and uninstall

If the button reports an error, run `remote-share-control off`. If the native importer is unavailable, toggle the stock USB web interface OFF and ON once. See [Troubleshooting](docs/TROUBLESHOOTING.md) for diagnostics that do not weaken the device.

To uninstall, first reboot with XOVI inactive, then run:

```sh
/home/root/remote-share/uninstall
```

Uninstall stops sharing, removes only Remote Share's QMD, importer, application directory, and local node state, then reminds you to revoke the tablet in the Tailscale admin console. It does not remove XOVI, QTRR, xovi-extensions, Vellum, or the existing startup gesture.

The installer places copies of files it replaces under `/home/root/remote-share-backups`. To recover the prior version, keep XOVI inactive, uninstall the current version, and restore the desired dated copy to its original path. Reboot afterward.

## OS updates

Do not carry the QMD or importer across a reMarkable OS update.

1. Turn Remote Share OFF.
2. Reboot with XOVI inactive.
3. Run the uninstaller and confirm stock xochitl works.
4. Update reMarkable OS normally.
5. Wait for an explicitly compatible XOVI, QTRR, extensions package, and Remote Share release.
6. Generate the new QTRR hashtable through the documented upstream process and reinstall only after all versions match.

Never bypass a version check or reuse the included QMD against a different firmware resource table.

## Known limitations

- Support is intentionally limited to one device and firmware release.
- Uploads use the stock reMarkable web importer and inherit its behavior and file-type limits.
- The tablet must have working Wi-Fi and be able to reach the Tailscale coordination service while sharing is ON.
- Sharing consumes more battery while active. The default timeout limits that cost, but it is still best to turn the switch OFF when finished.
- Anyone authorized by your Tailscale access policy to reach this node and port can reach the importer while it is ON. Use restrictive Tailscale grants and revoke lost devices promptly.
- Tailscale is downloaded at install time and is not included in this repository or its releases.

## Frequently asked questions

### Can I transfer files to a reMarkable Paper Pro without USB?

Yes, after the initial USB SSH installation. Turn on Remote Share from the tablet, then open the URL reported by the controller from another device on the same Tailscale network. Normal use does not require the USB cable.

### Does this work without a reMarkable Connect subscription?

Remote Share does not depend on Connect for its file-transfer path. It uses the stock on-device web importer, XOVI, and Tailscale. It does not reproduce Connect's cloud sync or subscription features.

### Is this reMarkable cloud sync or Syncthing?

No. It is an on-demand gateway to the built-in web interface. It does not watch folders, synchronize in the background, or maintain another copy of your notebook library.

### Does it enable SSH over Wi-Fi?

No. Remote Share exposes only the stock importer through Tailscale while the switch is on. SSH remains limited to the existing USB connection.

### Is the reMarkable web interface public on the internet?

No. Tailscale Serve makes it reachable only inside the user's Tailscale network. The project does not configure Funnel or a public listening port.

### Does it work on reMarkable 2, Paper Pro Move, or newer firmware?

No. Version 0.1.0 intentionally supports only the original reMarkable Paper Pro running OS 3.28.0.172 with the exact dependency versions listed above. Unsupported devices and firmware are rejected by the installer.

## Building

The release binary is built in GitHub Actions from `src/loopback-importer` using XOVI v0.3.3 at commit `0c8d5269b55c851901d4e4a754dc2d7deab40b17` and the Paper Pro toolchain image pinned by digest in the workflows. Compiled binaries and firmware-derived hashtables are never committed.

## License and credits

The project is licensed under [GPL-3.0](LICENSE). It builds on existing reMarkable community work; see [NOTICE](NOTICE) for direct links and attribution. The underlying idea of remote access to the stock web interface is not claimed as original.
