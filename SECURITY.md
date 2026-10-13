# Security policy

## Supported version

Security fixes are provided for the current release on its exact documented firmware and dependency set. A firmware update makes that release unsupported until a newly tested release says otherwise.

## Reporting a vulnerability

Use GitHub's private vulnerability reporting feature for this repository. Do not open a public issue for a vulnerability that could expose a tablet, Tailscale network, credentials, or user documents.

Include the Remote Share version, reMarkable OS version, and enough reproduction detail to confirm the problem. Remove node names, addresses, login URLs, keys, document names, and logs containing personal data.

## Security boundaries

Remote Share is designed to remain tailnet-only and on demand. It does not configure Funnel, Tailscale SSH, accepted routes, DNS, an exit node, firewall rules, or a boot service. Turning it off resets the Serve rule, disconnects the node, and stops its userspace daemon.

The stock importer does not add its own Remote Share password. Access control therefore depends on the user's Tailscale identity and grants. Restrict access to the tablet's port, keep accounts protected with multi-factor authentication, and revoke machines that are no longer trusted.

Never submit authentication state, SSH keys, login URLs, device backups, QTRR hashtables, or stock firmware resources to this repository.
