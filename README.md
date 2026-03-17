# Post-Quantum SSH (Hybrid KEX) — macOS + GitHub

Enable hybrid post-quantum SSH key exchange for GitHub on macOS using stock OpenSSH.

- **Authentication**: Ed25519 (unchanged)
- **Key exchange**: PQ hybrid — `mlkem768x25519-sha256` → `sntrup761x25519-sha512` → `curve25519-sha256` (fallback)

---

## Quick Start

```bash
# 1. Generate key + patch ~/.ssh/config
bash setup_pq_ssh.sh --apply

# 2. Upload public key to GitHub
gh ssh-key add ~/.ssh/id_ed25519_pq.pub --title pq-$(hostname -s)

# 3. Load key into agent (macOS Keychain — asked once, remembered)
bash setup_pq_ssh.sh --load

# 4. Verify connectivity + PQ KEX active
bash setup_pq_ssh.sh --verify
```

---

## All Commands

| Command | Description |
|---------|-------------|
| `setup_pq_ssh.sh` | Dry-run: show current status, no changes |
| `setup_pq_ssh.sh --apply` | Generate key (if missing) + write `~/.ssh/config` block |
| `setup_pq_ssh.sh --load` | `ssh-add` key into agent (macOS Keychain aware — passphrase stored) |
| `setup_pq_ssh.sh --verify` | Test GitHub connectivity + confirm PQ KEX algorithm negotiated |
| `setup_pq_ssh.sh --status` | Show key / agent / config / GitHub status |
| `setup_pq_ssh.sh --help` | Full usage |

---

## Environment Overrides

| Variable | Default | Description |
|----------|---------|-------------|
| `PQ_KEY_PATH` | `~/.ssh/id_ed25519_pq` | Key file path |
| `PQ_KEX_ALGOS` | `mlkem768x25519-sha256,...` | KEX algorithm preference list |

---

## How It Works

- **`--apply`** writes a fenced block (`# BEGIN pq-ssh github.com` … `# END pq-ssh github.com`) into `~/.ssh/config`. Idempotent — won't duplicate.
- **`--load`** calls `ssh-add --apple-use-keychain` on macOS so the passphrase is stored in the macOS Keychain. Subsequent sessions load silently.
- **`--verify`** runs a live `ssh -T git@github.com` (BatchMode) and then a verbose handshake to confirm the negotiated KEX algorithm.

---

## Expected `--verify` Output

```
  ✓  Authenticated as: token71
  ✓  KEX algorithm: mlkem768x25519-sha256 ✨ post-quantum active
```

If you see `curve25519-sha256`: the remote side doesn't support PQ KEX (classical fallback — still secure, just not post-quantum).

