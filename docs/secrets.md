# Secrets and keys

Three problems that get confused, and are worth separating because the right
answer differs for each:

1. **SSH private keys.** Should never be copied between machines at all.
2. **Shared secrets that genuinely need to exist on several hosts** — a signing
   key, an internal registry token, a licence file.
3. **Short-lived credentials** — cloud STS tokens, SSO sessions, kerberos
   tickets. Not kickstart's job; a tool already owns each of these.

kickstart solves (1) and (2), and stays out of (3).

---

## 1. SSH keys: generate per host, never sync

A private key that exists on four machines is four times as likely to leak and
cannot be revoked without disrupting all four. The alternative costs nothing:
every host generates its own `ed25519` key, only public keys travel, and
revoking a laptop is deleting one line.

```sh
kickstart keys status        # every key here, its fingerprint, agent state, file modes
kickstart keys new           # generate, commented with host and date
kickstart keys track         # copy the PUBLIC key into keys/<host>.pub for commit
kickstart keys publish       # register it with GitHub via gh
kickstart keys authorized    # rebuild ~/.ssh/authorized_keys from keys/*.pub
```

`keys/` lives in the repo, or in an overlay if one has that directory (overlay
wins, as everywhere else). It holds one `.pub` per machine, so "this laptop is
gone" becomes a commit rather than an archaeology exercise across every
`authorized_keys` you have ever touched.

`keys authorized` only manages its own marked block, so an entry your host
provider or work tooling put there survives a rebuild.

`modules/ssh` sets `IdentitiesOnly yes`, `AddKeysToAgent yes`,
`ForwardAgent no`, and connection multiplexing. From the shell: `keys`,
`sshkey`, `sshcp <host>`, `sshfp <host>`, `sshforget <host>`.

If your org runs an SSH CA, certificates beat all of this — short lived,
centrally revocable, no `authorized_keys` sprawl. That belongs in the work
overlay, since the CA endpoint is internal.

---

## 2. Shared secrets: the age vault

[`age`](https://github.com/FiloSottile/age): one static binary, no daemon, no
keyring, no agent to debug at 11pm.

The reason it fits here specifically is that **age accepts ssh keys as
recipients**. There is no new key material to manage — the per-host ssh key
from part 1 *is* the decryption identity. Onboarding a machine is generating
its ssh key and adding the public half to the recipients list, which is
already the workflow for git access.

```
<vault>/recipients.txt    one ssh public key per line, one per host
<vault>/<name>.age        ciphertext, safe to commit
```

### Setting it up

Put the vault in a **private** repo — normally your work overlay:

```sh
kickstart apply age
kickstart secrets init --in ~/.local/share/kickstart/overlays/work/secrets
```

`init` registers this host's public key as a recipient and pins the vault path
in `~/.config/kickstart/config`. Pointing a vault at the public kickstart repo
prompts for confirmation first, because ciphertext in a public repo is public
forever: if a key is ever compromised, every secret ever committed must be
rotated.

### Using it

```sh
kickstart secrets ls                     # what is in the vault, and how many recipients
kickstart secrets add npm-token          # opens $EDITOR
echo "$TOKEN" | kickstart secrets add ci-token   # or pipe it, never touching disk
kickstart secrets cat npm-token
kickstart secrets edit npm-token         # decrypt to a 0700 tmpdir, edit, re-encrypt
kickstart secrets rm npm-token
kickstart secrets recipients             # who can decrypt
kickstart secrets rekey                  # re-encrypt everything to the current list
```

From the shell: `secrets`, `secret <name>`, `secedit <name>`, and
`secenv <name>` which exports a secret's `KEY=value` lines into the current
shell without the plaintext ever reaching disk.

### Module integration

A module declares what it needs, in the same style as everything else:

```sh
# modules/npm-work/module.sh
DESC="npm against the internal registry"
SECRETS="npm-token:~/.npmrc:0600"
```

`<vault name>:<destination>:<mode>`, space separated for several. `kickstart
apply` materialises them after linking files: decryption writes to a temp file
next to the destination, gets the declared mode, and is moved into place only
if the content changed. It never lands in the repo and never in a world
readable `/tmp`.

A host that cannot decrypt — no identity, or not a recipient — **skips** the
secret with a warning rather than failing the run. A build box should not need
the vault to get its dotfiles. That behaviour is covered by the test suite.

You can also run it on its own: `kickstart secrets sync [module...]`.

### Onboarding and offboarding

```
new machine   kickstart keys new
              add the pubkey to recipients.txt   (or: secrets recipient-add <file>)
              kickstart secrets rekey && commit

lost machine  remove its line from recipients.txt
              kickstart secrets rekey && commit
              ROTATE every secret it could read
```

That last step is not optional. Removing a recipient stops them decrypting
*future* ciphertext; anything they already had a copy of is compromised.

### What must never go in the vault

- Anything with a real secrets manager behind it (cloud creds, SSO tokens)
- Anything with a short TTL — you will not rekey often enough
- Work secrets, in the public repo. Overlay only.

### Known limits

- `rm` on an SSD is not a secure erase. The 0700 temp directory used by
  `secrets edit` defends against other users and stray backups, not against
  forensic recovery.
- age does not talk to `ssh-agent`. A passphrase-protected ssh key means age
  prompts for the passphrase on every decrypt, including during `apply`.
- `secrets rekey` rewrites files in place; git history keeps the old
  ciphertext, which is the point of rotating rather than just rekeying.

---

## Alternatives considered

| | Why not |
|---|---|
| **sops** | Solves a bigger problem (structured, partially-encrypted YAML). More machinery than a handful of files needs. `age` is sops' own preferred backend. |
| **git-crypt** | Transparent, which is nice, but revocation requires rewriting history, and it is GPG-bound. |
| **1Password CLI** | Excellent, but needs an authenticated `op` session on every box. On an air-gapped remote that is a non-starter, which is exactly where you most want your config to work. |
| **pass / GPG** | Well understood, but GPG agent and key handling across macOS and Linux is the reliability problem this whole repo exists to avoid. |
| **Vault / cloud KMS** | Needs a reachable server. Same air-gap problem, plus operational weight. |

`age` can be layered *under* 1Password later — store the age identity in
1Password and fetch it once per machine — without changing anything else.

## Still open

- **YubiKey.** `age-plugin-yubikey` would move the identity onto hardware,
  which is the right answer for the key that guards everything else. It means
  every host needs the plugin binary, so it is a deliberate decision rather
  than a default.
- **Should `apply` decrypt by default?** It does today, which is convenient.
  Default-off would mean an `apply` on a shared box never materialises
  plaintext by accident. Easy to flip if you want it.
