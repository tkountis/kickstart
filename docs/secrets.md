# Secrets and keys — design

**Status: designed, not implemented.** The `sshkey` / `sshcp` helpers and
`~/.config/kickstart/env` exist today. Everything under "Proposed" below is a
plan to review, not shipped code.

---

## Three problems that get confused

It is worth separating them, because the right answer is different for each.

1. **SSH private keys.** Should never be copied between machines at all.
2. **Shared secrets that genuinely need to exist on several hosts** — a signing
   key, an internal registry token, a licence file.
3. **Short-lived credentials** — cloud STS tokens, SSO sessions, kerberos
   tickets. Not kickstart's job; a tool already owns each of these.

kickstart should solve (1) and (2), and stay out of (3).

---

## 1. SSH keys: generate per host, never sync

A private key that exists on four machines is four times as likely to leak and
cannot be revoked without disrupting all four. The alternative costs nothing:

- Every host generates its own `ed25519` key on first apply.
- Only **public** keys travel. They are not secret and can live in the repo.
- Revoking a laptop is deleting one line from `authorized_keys` / GitHub.

Already available:

```sh
sshkey                 # create this host's key if absent, print the public half
sshcp <host>           # copy it to a remote authorized_keys
sshfp <host>           # show a remote host's fingerprints before trusting it
```

`modules/ssh` already sets `IdentitiesOnly yes`, `AddKeysToAgent yes`,
`ForwardAgent no`, and connection multiplexing.

### Proposed additions

```sh
kickstart keys status          # every key on this host, type, age, where it is used
kickstart keys new [name]      # generate, with a host-and-date comment
kickstart keys publish         # push the public key to GitHub via `gh`
kickstart keys authorized      # rebuild ~/.ssh/authorized_keys from keys/*.pub in the repo
```

`keys/` in the repo (or overlay) holds one `.pub` per machine. `authorized`
rebuilds `authorized_keys` from it, which makes "this laptop is gone" a commit.

For work, if the org runs an SSH CA, certificates beat all of this — short
lived, centrally revocable, no `authorized_keys` sprawl. That belongs in the
work overlay, since the CA endpoint is internal.

Hardware keys (`ssh-keygen -t ed25519-sk`, YubiKey) work with everything above
and are worth it for the identity that guards the secret vault below.

---

## 2. Shared secrets: `age` vault in the repo

### Recommendation

[`age`](https://github.com/FiloSottile/age) — a single static binary, no
daemon, no keyring, no agent. Encrypted files are committed; plaintext never
touches the repo.

The reason it fits here specifically: **age accepts SSH keys as recipients.**

```sh
age -R ~/.ssh/id_ed25519.pub -o secret.age secret.txt   # encrypt
age -d -i ~/.ssh/id_ed25519 secret.age                  # decrypt
```

So there is no new key material to manage. The per-host SSH key from part 1
*is* the decryption identity. A new machine is onboarded by generating its ssh
key and adding the public half to the recipients list — exactly the workflow
that already exists for git access.

### Alternatives considered

| | Why not |
|---|---|
| **sops** | Solves a bigger problem (structured, partially-encrypted YAML). More machinery than a handful of files needs. `age` is sops' own preferred backend. |
| **git-crypt** | Transparent, which is nice, but revocation requires rewriting history, and it is GPG-bound. |
| **1Password CLI** | Excellent, but needs an authenticated `op` session on every box. On an air-gapped remote that is a non-starter, which is exactly where you most want your config to work. |
| **pass / GPG** | Well understood, but GPG agent and key handling across macOS and Linux is the reliability problem this whole repo exists to avoid. |
| **Vault / cloud KMS** | Needs a reachable server. Same air-gap problem, plus operational weight. |

`age` can be layered *under* 1Password later — store the age identity in
1Password and fetch it once per machine — without changing anything else.

### Proposed layout

```
secrets/
  recipients.txt      one age/ssh public key per line, commented with the host
  <name>.age          encrypted blobs
```

**Put this in the private overlay, not the public repo.** Ciphertext in a
public repo is public forever; if a key is ever compromised, every secret that
was ever committed must be rotated. Keeping the vault private makes that a
defence-in-depth problem rather than a certainty.

### Proposed commands

```sh
kickstart secrets init           # register this host's ssh pubkey as a recipient
kickstart secrets add <name>     # read stdin (or $EDITOR), encrypt to all recipients
kickstart secrets edit <name>    # decrypt to a temp file, edit, re-encrypt, shred
kickstart secrets cat <name>     # decrypt to stdout
kickstart secrets ls             # names, recipients, last modified
kickstart secrets rekey          # re-encrypt everything to the current recipient list
kickstart secrets sync           # materialise declared secrets onto this host
```

### Proposed module integration

Declarative, in the same style as everything else:

```sh
# modules/npm-work/module.sh
SECRETS="npm-token:~/.npmrc:0600"
```

`<vault name>:<destination>:<mode>`. During apply, `sync` decrypts to the
destination with the given mode. Decryption goes straight to the final path,
never into the repo and never into `/tmp` unencrypted.

A host that cannot decrypt (no identity, or not a recipient) **skips** the
secret with a warning rather than failing the run — the same rule as every
other gate. A build box should not need the vault to get its dotfiles.

### Onboarding and offboarding

```
new machine   -> sshkey -> add pubkey to recipients.txt -> secrets rekey -> commit
lost machine  -> remove from recipients.txt -> secrets rekey -> ROTATE the secrets
```

That last step is not optional. Removing a recipient stops them decrypting
*future* ciphertext; anything they already had a copy of is compromised.

### What must never go in the vault

- Anything with a real secrets manager behind it (cloud creds, SSO tokens)
- Anything with a short TTL — you will not rekey often enough
- Work secrets, in the public repo. Overlay only.

---

## Rollout

| Phase | Scope |
|---|---|
| 1 (done) | Per-host ssh keys, hardened ssh config, `~/.config/kickstart/env` for machine-local values |
| 2 | `kickstart keys` — status, publish, `authorized_keys` from the repo |
| 3 | `kickstart secrets` — age vault, add/edit/cat/rekey, in the overlay |
| 4 | `SECRETS=` declaration in modules, wired into apply |
| 5 | Optional: age identity held on a YubiKey via `age-plugin-yubikey` |

Nothing before phase 3 requires a decision. Phase 3 is the one worth a
conversation, mainly about where the vault lives.

## Open questions

- Vault in the work overlay only, or a second personal-but-private repo too?
- Is a YubiKey in the picture? It changes the identity story for the better,
  but means every host needs the plugin binary.
- Should `apply` decrypt secrets by default, or only on explicit
  `kickstart secrets sync`? Default-on is convenient; default-off means an
  `apply` on a shared box never materialises plaintext by accident.
