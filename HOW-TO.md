# HOW-TO — pq-ssh

Operational guide for day-to-day use of `pq-ssh` on macOS.

---

## 1. First-time setup (new machine)

### Option A — EPM install (recommended)

```bash
git clone https://github.com/token71/pq-ssh-github
bash pq-ssh-github/install.sh --apply
```

This creates `~/.bin/pq-ssh` (wrapper to `setup_pq_ssh.sh`) and sources `ep-integration.sh`
into your `~/.zshrc` / `~/.bashrc`, enabling the `ep ssh*` subcommands.

Then finish key setup:
```bash
ep ssh-setup                          # generate key + write PQ KEX config block
gh ssh-key add ~/.ssh/id_ed25519_pq.pub --title pq-$(hostname -s)
ep ssh-store keychain                 # store passphrase in macOS Keychain (prompted once)
ep ssh                                # verify status
ep ssh-verify                         # test GitHub auth + confirm PQ KEX active
```

### Option B — manual

```bash
# Clone the repo
git clone https://github.com/token71/pq-ssh-github
cd pq-ssh-github

# Generate Ed25519 key + write PQ KEX block to ~/.ssh/config
bash setup_pq_ssh.sh --apply

# Upload public key to GitHub (requires gh CLI, already authenticated)
gh ssh-key add ~/.ssh/id_ed25519_pq.pub --title pq-$(hostname -s)

# Store passphrase in macOS Keychain (you'll be prompted once)
bash setup_pq_ssh.sh --store-passphrase keychain

# Inject autoload snippet into ~/.zshrc / ~/.bashrc
bash setup_pq_ssh.sh --install-autoload

# Verify everything is working
bash setup_pq_ssh.sh --verify
```

Expected output:
```
  ✓  Authenticated as: <your-username>
  ✓  KEX algorithm: mlkem768x25519-sha256 ✨ post-quantum active
```

---

## 2. `ep` subcommands reference

After EPM install, these are available in any shell:

| Command | Equivalent | Description |
|---------|-----------|-------------|
| `ep ssh` | `--status` | Full status: key, agent, GitHub, KEX |
| `ep ssh-load` | `--load` | Load key into ssh-agent (auto-detects passphrase manager) |
| `ep ssh-unload` | `--unload` | Remove key from ssh-agent |
| `ep ssh-verify` | `--verify` | Authenticate to GitHub and report KEX algorithm |
| `ep ssh-setup` | `--apply` | Generate key + write PQ KEX config block |
| `ep ssh-store <mgr>` | `--store-passphrase <mgr>` | Store passphrase (keychain/bitwarden/pass) |

---

## 3. Daily use (existing machine)

Nothing to do. The autoload snippet (written by `--install-autoload` / `install.sh --apply`) silently loads the key from Keychain on every new shell session.

Run `ep ssh` (or `bash setup_pq_ssh.sh --status`) at any time to check:
- Key file present and permissions correct
- Key loaded in ssh-agent
- GitHub connectivity
- PQ KEX algorithm active

---

## 4. Add passphrase to Bitwarden

**Prerequisites:** `brew install bitwarden-cli` and an active Bitwarden account.

```bash
# Log in and unlock (saves session token to BW_SESSION)
bw login
export BW_SESSION="$(bw unlock --raw)"

# Store passphrase as a Bitwarden secure note named "pq-ssh-passphrase"
bash setup_pq_ssh.sh --store-passphrase bitwarden
```

On subsequent `--load` calls, the script checks `BW_SESSION` and retrieves the passphrase automatically. Add `export BW_SESSION=...` to your shell rc or use a session-unlock alias.

---

## 5. Add passphrase to pass store

**Prerequisites:** `brew install pass` and a GPG key for encryption.

```bash
# Initialise pass store with your GPG key ID (skip if already initialised)
pass init <your-gpg-key-id>

# Store passphrase at ssh/pq-key-passphrase
bash setup_pq_ssh.sh --store-passphrase pass
```

The script writes to `ssh/pq-key-passphrase` by default (override with `PQ_PASS_ENTRY`). Auto-detected on `--load` when pass is installed.

---

## 6. NordPass / ProtonPass (manual)

Neither NordPass nor ProtonPass exposes a CLI, so automated storage is not possible.

When you run `--store-passphrase nordpass` or `--store-passphrase protonpass`, the script prints your passphrase and manual instructions:

1. Open NordPass / ProtonPass
2. Create a new **Secure Note** named `pq-ssh-passphrase`
3. Paste the printed passphrase
4. Save and close

To load the key manually when needed:
```bash
ssh-add ~/.ssh/id_ed25519_pq   # enter passphrase from vault when prompted
```

---

## 7. Rotate the SSH key

```bash
# 1. Unload + wipe existing key (overwrites bytes, removes from config)
bash setup_pq_ssh.sh --delete

# 2. Generate a fresh key + rewrite config block
bash setup_pq_ssh.sh --apply

# 3. Upload new public key to GitHub
gh ssh-key add ~/.ssh/id_ed25519_pq.pub --title pq-$(hostname -s)-rotated

# 4. Store new passphrase
bash setup_pq_ssh.sh --store-passphrase keychain   # or bitwarden / pass

# 5. Verify
bash setup_pq_ssh.sh --verify
```

> Remove the old key from [GitHub Settings → SSH keys](https://github.com/settings/keys) after the new one is verified.

---

## 8. Transfer to new machine

**Option A — copy private key securely (fastest):**

```bash
# On old machine: copy key to new machine over SSH
scp ~/.ssh/id_ed25519_pq ~/.ssh/id_ed25519_pq.pub user@newmachine:~/.ssh/

# On new machine: clone repo and re-apply (patches config, sets permissions)
git clone https://github.com/token71/pq-ssh-github
cd pq_ssh_github_regen
bash setup_pq_ssh.sh --apply       # detects existing key, skips keygen

# Store passphrase on new machine
bash setup_pq_ssh.sh --store-passphrase keychain

# Verify
bash setup_pq_ssh.sh --verify
```

**Option B — generate a new key on the new machine** and follow the [First-time setup](#1-first-time-setup-new-machine) steps.

---

## 9. Revoke access (offboarding)

```bash
# 1. Unload key, remove config block, overwrite + delete key files
bash setup_pq_ssh.sh --delete
```

Then remove the public key from GitHub:
- Go to **Settings → SSH and GPG keys**
- Find the `pq-<hostname>` key and click **Delete**

The machine can no longer authenticate to GitHub via this key.

---

## 10. Verify post-quantum KEX is active

```bash
bash setup_pq_ssh.sh --verify
```

**Post-quantum active:**
```
  ✓  Authenticated as: your-username
  ✓  KEX algorithm: mlkem768x25519-sha256 ✨ post-quantum active
```

**Classical fallback:**
```
  ✓  Authenticated as: your-username
  ⚠  KEX algorithm: curve25519-sha256 (classical fallback)
```

A `curve25519-sha256` result means the remote side (GitHub) did not negotiate a PQ algorithm for this handshake. The connection is still cryptographically secure — just not post-quantum. This can happen transiently; re-run `--verify` to confirm.

To check directly via OpenSSH verbose output:
```bash
ssh -vT git@github.com 2>&1 | grep "kex: algorithm"
```

---

## 11. Troubleshooting

**Key not loaded in agent after shell restart**
- Run `bash setup_pq_ssh.sh --status` — check autoload line is present in `~/.zshrc` / `~/.bashrc`
- Re-run `--install-autoload` if the snippet is missing, then open a new shell

**`Permission denied (publickey)`**
1. Confirm key is in agent: `ssh-add -l | grep id_ed25519_pq`
2. Confirm key is uploaded to GitHub: `gh ssh-key list`
3. Check `~/.ssh/config` has the `github.com` block: `grep -A10 'github.com' ~/.ssh/config`
4. Re-run `--verify` for a full diagnostic

**`BW_SESSION not set` when using Bitwarden**
```bash
export BW_SESSION="$(bw unlock --raw)"
```
Add this to a shell alias or session initialisation. The script cannot unlock Bitwarden on your behalf.

**PQ KEX falls back to `curve25519-sha256`**
- Check your OpenSSH version: `ssh -V` (needs ≥ 9.0 for `mlkem768x25519`, ≥ 8.5 for `sntrup761x25519`)
- Confirm the `KexAlgorithms` line is present in `~/.ssh/config`: `grep KexAlgorithms ~/.ssh/config`
- GitHub supports PQ KEX — if fallback persists, re-run `--apply` to refresh the config block

**`--delete` fails / key files already gone**
Safe to ignore — `--delete` is idempotent. Run `--clean` to remove the stale config block:
```bash
bash setup_pq_ssh.sh --clean
```
