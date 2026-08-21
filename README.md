# genos

Server setup and hardening scripts for a private development host.

## Ubuntu 26.04 hardening

[`scripts/harden-ubuntu-server.sh`](scripts/harden-ubuntu-server.sh) hardens an
Ubuntu 26.04 server while keeping SSH password login available for the chosen
administrator account.

Before running it, confirm you have console access or an active SSH session.
The script changes SSH and replaces all existing UFW rules.

```sh
ADMIN_USER=genos RESET_UFW=yes sudo ./scripts/harden-ubuntu-server.sh
```

Set `SSH_PORT` if SSH does not use port 22:

```sh
ADMIN_USER=genos SSH_PORT=2222 RESET_UFW=yes \
  sudo ./scripts/harden-ubuntu-server.sh
```

### What it configures

- automatic security updates;
- AppArmor and audit logging;
- conservative Linux network and kernel hardening settings;
- SSH root-login protection, while retaining password authentication for
  `ADMIN_USER`;
- Fail2Ban protection for SSH; and
- UFW firewall rules.

### Firewall rules

The script resets UFW, denies all incoming traffic by default, and allows all
outgoing traffic. It then permits:

- SSH over TCP on `22` (or the configured `SSH_PORT`), from any address;
- HTTPS over TCP on `443`, from any address.

Tailscale is not installed or configured by this script and can be added later.
