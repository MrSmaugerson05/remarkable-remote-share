# Troubleshooting

These checks do not require Wi-Fi SSH and do not change xochitl or the core mod stack. Connect over USB SSH when command-line access is needed.

## The button is missing

Confirm that XOVI was started with the existing startup gesture and that the exact versions in the compatibility table are installed. The QMD should be at:

```text
/home/root/xovi/exthome/qt-resource-rebuilder/remoteShare.qmd
```

Do not copy the QMD to another OS version. If xochitl is unstable, reboot without XOVI and uninstall Remote Share.

## The icon shows a warning circle

Check the controller without turning sharing on:

```sh
/home/root/remote-share/remote-share-control status
```

Then inspect the short runtime log:

```sh
tail -n 30 /home/root/remote-share/run/tailscaled.log
```

The log is local runtime data. Redact it before sharing because it may contain node information.

Common causes are an unauthenticated node, unavailable Wi-Fi, or the stock importer being off. Run `auth` over USB SSH if login has expired. Toggle **Settings → General → Storage → USB web interface** OFF and ON if the importer is unavailable.

## The URL worked over USB but not remotely

Make sure both devices are connected to the same Tailscale network and that its access policy permits the client to reach the tablet's configured port. Use the URL reported by the controller; do not substitute a tailnet DNS name.

Remote Share does not enable Wi-Fi SSH. An SSH failure over Wi-Fi is expected and is not evidence that file sharing is broken.

## Sharing remains on in the UI after timeout

The QMD uses a one-shot timer based on the controller's expiry timestamp. It does not poll. The controller still shuts down independently at the deadline. Leave and reopen the home screen, or press the button once; `status-fast` is the source of truth.

## Safe reset

```sh
/home/root/remote-share/remote-share-control off
```

That command removes the Serve rule, disconnects Tailscale, stops the userspace daemon, and clears runtime PID/socket files. If it cannot complete, rebooting clears the running process because Remote Share has no boot service.

## Collecting a useful bug report

Include:

- output of `remote-share-control status-fast`;
- the four version values from the compatibility table;
- which icon was displayed;
- whether the stock USB web interface worked locally.

Do not include logs or screenshots until node names, addresses, document names, login links, and account details have been removed.
