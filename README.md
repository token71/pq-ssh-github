# Post-Quantum SSH (Hybrid KEX) — macOS + GitHub

Enable hybrid post-quantum SSH key exchange for GitHub on macOS.

- **Authentication**: Ed25519 (unchanged)
- **Key exchange**: PQ hybrid — `mlkem768x25519-sha256` → `sntrup761x25519-sha512` → `curve25519-sha256` (fallback)

---

## Quick Start

```bash
# 1. Generate key + patch ~/.ssh/config
bash setup_pq_ssh.sh --apply

# 2. Upload public key to GitHub
gh ssh-key add ~/.ssh/id_ed25519_pq.pub --title pq-$(hostname -s)

# 3. Store passphrase in macOS Keychain (asked once, never again)
bash setup_pq_ssh.sh --store-passphrase keychain

# 4. Auto-load key on every new shell session
bash setup_pq_ssh.sh --install-autoload

# 5. Verify connectivity + PQ KEX active
bash setup_pq_ssh.sh --verify
```

---

## All Commands

| Command | Description |
|---------|-------------|
| `setup_pq_ssh.sh` | Dry-run: full status report, no changes |
| `--apply` | Generate key (if missing) + write `~/.ssh/config` PQ KEX block |
| `--load [--manager <mgr>]` | Load key into ssh-agent (auto-detects passphrase manager) |
| `--unload` | Remove key from ssh-agent |
| `--verify` | Test GitHub auth + confirm PQ KEX algorithm negotiated |
| `--status` | Full health report: key / permissions / agent / config / managers / GitHub |
| `--store-passphrase <mgr>` | Store passphrase in a manager (see below) |
| `--install-autoload` | Inject autoload snippet into `~/.zshrc`, `~/.bashrc`, etc. |
| `--clean` | Remove PQ KEX block from `~/.ssh/config` |
| `--delete` | Unload + clean config + overwrite + delete key files |
| `--help` | Full usage |

---

## Passphrase Managers

| Manager | `--store-passphrase` | `--load` auto-detect | Notes |
|---------|---------------------|----------------------|-------|
| **macOS Keychain** | `keychain` | ✅ automatic | Best option on macOS — no prompt after first time |
| **Bitwarden** | `bitwarden` | ✅ if `BW_SESSION` set | `brew install bitwarden-cli` |
| **pass** | `pass` | ✅ automatic | `brew install pass` |
| **NordPass** | `nordpass` | ❌ no CLI | Manual steps printed |
| **ProtonPass** | `protonpass` | ❌ no CLI | Manual steps printed |

**Passphrase auto-detection order** (for `--load`):
1. macOS Keychain
2. Bitwarden (if `BW_SESSION` set)
3. pass store
4. Interactive prompt (fallback)

---

## Autoload (Shell Integration)

`--install-autoload` writes a fenced snippet to all detected rc files (`~/.zshrc`, `~/.bashrc`, `~/.bash_profile`, `~/.profile`):

```bash
# BEGIN pq-ssh autoload
_pq_ssh_autoload() {
  [[ -f ~/.ssh/id_ed25519_pq ]] || return 0
  ssh-add -l 2>/dev/null | grep -qF id_ed25519_pq && return 0
  ssh-add --apple-use-keychain ~/.ssh/id_ed25519_pq 2>/dev/null || true
}
_pq_ssh_autoload; unset -f _pq_ssh_autoload
# END pq-ssh autoload
```

If Keychain has the passphrase, this runs silently. No prompt, ever.

---

## Key Safety

- Private key stored with permissions `600` — script enforces and auto-fixes this
- `--delete` overwrites key bytes with random data before removal (shred-like)
- Key is scoped to `github.com` only (`IdentitiesOnly yes`)
- PQ KEX means session traffic is protected against "harvest now, decrypt later" attacks

---

## Environment Overrides

| Variable | Default | Description |
|----------|---------|-------------|
| `PQ_KEY_PATH` | `~/.ssh/id_ed25519_pq` | Key file path |
| `PQ_KEX_ALGOS` | `mlkem768x25519-sha256,...` | KEX algorithm preference list |
| `PQ_BW_ITEM` | `pq-ssh-passphrase` | Bitwarden item name |
| `PQ_PASS_ENTRY` | `ssh/pq-key-passphrase` | pass store entry path |

---

## Expected `--verify` Output

```
  ✓  Authenticated as: token71
  ✓  KEX algorithm: mlkem768x25519-sha256 ✨ post-quantum active
```


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

