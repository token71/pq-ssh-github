# pq-ssh — Post-Quantum SSH for GitHub

![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)
![Platform: macOS](https://img.shields.io/badge/platform-macOS-lightgrey.svg)
![Shell: bash](https://img.shields.io/badge/shell-bash-green.svg)

Hybrid post-quantum SSH key exchange for GitHub on macOS — Ed25519 auth + `mlkem768x25519` KEX, passphrase managers, shell autoload, and EPM integration.

---

## Install (EPM)

```bash
bash install.sh --apply      # installs pq-ssh to ~/.bin + ep ssh* subcommands
```

Or clone and run manually:

```bash
git clone https://github.com/akietler/pq_ssh_github_regen
cd pq_ssh_github_regen
bash setup_pq_ssh.sh --apply
```

---

## Quick Start (4 commands)

```bash
# 1. Generate Ed25519 key + patch ~/.ssh/config with PQ KEX block
bash setup_pq_ssh.sh --apply

# 2. Upload public key to GitHub
gh ssh-key add ~/.ssh/id_ed25519_pq.pub --title pq-$(hostname -s)

# 3. Store passphrase in macOS Keychain (asked once, silent forever after)
bash setup_pq_ssh.sh --store-passphrase keychain

# 4. Auto-load key on every new shell session
bash setup_pq_ssh.sh --install-autoload

# Verify connectivity + confirm PQ KEX is negotiated
bash setup_pq_ssh.sh --verify
```

---

## ep Command Integration

After `install.sh --apply`, the following `ep` subcommands are available:

| Command | Description |
|---------|-------------|
| `ep ssh` | Show current key / agent / config / GitHub status |
| `ep ssh-load` | Load key into ssh-agent (auto-detects passphrase manager) |
| `ep ssh-unload` | Remove key from ssh-agent |
| `ep ssh-verify` | Test GitHub auth + confirm PQ KEX algorithm negotiated |
| `ep ssh-setup` | Run full first-time setup interactively |
| `ep ssh-store keychain` | Store passphrase in macOS Keychain |

---

## All pq-ssh Commands

| Flag | Description |
|------|-------------|
| *(no flag)* | Dry-run: full status report, no changes made |
| `--apply` | Generate key (if missing) + write `~/.ssh/config` PQ KEX block |
| `--load [--manager <mgr>]` | Load key into ssh-agent (auto-detects passphrase manager) |
| `--unload` | Remove key from ssh-agent |
| `--verify` | Test GitHub auth + confirm PQ KEX algorithm negotiated |
| `--status` | Full health report: key / perms / agent / config / managers / GitHub |
| `--store-passphrase <mgr>` | Store passphrase in a manager (see table below) |
| `--install-autoload` | Inject autoload snippet into `~/.zshrc`, `~/.bashrc`, etc. |
| `--clean` | Remove PQ KEX block from `~/.ssh/config` |
| `--delete` | Unload + clean config + overwrite bytes + delete key files |
| `--help` | Full usage |

---

## Passphrase Managers

| Manager | `--store-passphrase` value | `--load` auto-detect | Notes |
|---------|---------------------------|----------------------|-------|
| **macOS Keychain** | `keychain` | ✅ automatic | Best option on macOS — no prompt after first store |
| **Bitwarden** | `bitwarden` | ✅ if `BW_SESSION` set | `brew install bitwarden-cli` required |
| **pass** | `pass` | ✅ automatic | `brew install pass` required |
| **NordPass** | `nordpass` | ❌ no CLI | Manual copy-paste steps printed |
| **ProtonPass** | `protonpass` | ❌ no CLI | Manual copy-paste steps printed |

**Auto-detection order** (for `--load`): Keychain → Bitwarden → pass → interactive prompt

---

## Key Safety

- Private key stored with permissions `600` — script enforces and auto-fixes on every run
- `--delete` overwrites key bytes with random data before `rm` (shred-like behaviour)
- `.gitignore` blocks `id_ed25519_pq` (private key) from accidental commits
- Key is scoped to `github.com` only via `IdentitiesOnly yes` in `~/.ssh/config`
- PQ KEX protects session traffic against "harvest now, decrypt later" attacks

---

## EPM Integration

This tool follows the EPM `toolkit_framework 1.0.0` convention:

| File | Purpose |
|------|---------|
| `meta/pq-ssh.json` | EPM manifest (name, version, commands, install targets) |
| `install.sh` | EPM-compatible installer — copies to `~/.bin`, registers `ep` subcommands |
| `lib/ep-integration.sh` | Sourced by EPM to register `ep ssh*` subcommand handlers |

---

## License

MIT — see [LICENSE](LICENSE)
