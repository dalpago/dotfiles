# iPhone remote access to tmux sessions — design

**Date:** 2026-08-02
**Author:** Daniele Alpago
**Status:** Approved (pending written-spec review)

## Context

Long-running work on this machine lives in tmux (currently the `data-generation`
session, 6 windows). The goal is to reach those sessions from an iPhone —
checking on a run, restarting something, reading output — without the phone
becoming a second full workstation.

The starting premise was to install "Termux" from the iOS App Store. That app
exists under that name (id `6738933789`) but is **not** Termux, and the
distinction is load-bearing for a credential-handling app:

| Field | Value |
| --- | --- |
| Display name | Termux |
| Developer | FREE AI UTILS COMPANY LIMITED |
| Bundle ID | `com.fau.sshterminal` |
| Name used in its own description | "TermuxUS" |
| Privacy policy URL | `mcanswers.ai/termux/privacy-policy` — returns **HTTP 404** |

The same publisher ships 18 unrelated apps (`com.fau.*`), four of which squat
recognisable open-source names — Jupyter Notebook, NFC Tools, Goblin Tools,
Termux — alongside blood-pressure trackers, Block Blast, and a Myanmar news app.
Real Termux is Android-only by construction: it unpacks a Linux userland and
`exec`s arbitrary ELF binaries, which iOS forbids (no `fork`/`exec` of
downloaded binaries, no W^X, no JIT without entitlement). No iOS build exists or
can exist without a jailbreak; anything shipping under that name on the App
Store is necessarily just an SSH client.

**Termius** was chosen instead — an established cross-platform SSH client, and
almost certainly the app originally intended given the one-letter name
difference.

Relevant existing state, verified rather than assumed:

- Tailscale 1.98.8 is up; `daniele-personal-iphone` (`100.64.0.8`) and this Mac
  (`daniele-personal-laptop`, `100.64.0.18`) are already on the same tailnet.
- `sshd` is **not** running: nothing on `:22`, `ssh.plist` shows `Disabled => 1`,
  no `~/.ssh/authorized_keys`, and `com.apple.access_ssh` is empty.
- tmux 3.7 with oh-my-tmux, chezmoi-managed.
- `mosh` and `mosh-server` are installed (unused by this design — see non-goals).
- `pmset` shows `sleep 1` on both AC and battery, masked in practice by
  `displaysleep 0` keeping a `powerd` assertion alive plus two ad-hoc
  `caffeinate` processes.
- Two DELL S2721QS displays attached (relevant to clamshell behaviour).
- Existing `~/.ssh` keys (`github-personal`, `github-work`, `csi-data`,
  `laptop-macbook-signing`) are all **outbound** client keys; nothing inbound.

## Decisions that shape this work

- **`ListenAddress` cannot be used to bind sshd to the Tailscale interface.**
  macOS `sshd` is socket-activated by launchd (`ssh.plist` declares
  `inetdCompatibility` with `Wait => 0` and a `Sockets` block), so launchd owns
  the listening socket and spawns a fresh `sshd` per connection.
  `ListenAddress` is silently ignored. Interface restriction is therefore done
  at the auth layer with `AllowUsers work@100.64.0.0/10`, the Tailscale CGNAT
  range. Guides recommending `ListenAddress` on macOS are wrong on this point.
- **Per-connection spawn also means config changes need no daemon reload** and
  cannot disrupt an established session. This makes iterating on `sshd_config`
  materially lower-risk than on a long-lived daemon, and removes lockout as a
  practical concern.
- **The drop-in is written before Remote Login is enabled.** Ordering matters:
  enabling first would open a window where password authentication is live.
  Written-then-enabled means `sshd` is hardened from its first connection.
- **Host keys must be generated before validation can run.** macOS ships with
  no `/etc/ssh/ssh_host_*` at all — key generation is deferred to the first
  time Remote Login is enabled, which is why `ssh.plist` launches
  `sshd-keygen-wrapper` rather than `sshd`. `sshd -t` loads host keys as part
  of validation and exits with `no hostkeys available` without them, so
  validate-before-enable is impossible unless keys are created first.
  `ssh-keygen -A` creates the missing keys without starting or enabling any
  service, preserving the ordering guarantee above.
- **`systemsetup -setremotelogin` requires Full Disk Access** and fails from a
  terminal that lacks it. `launchctl enable system/com.openssh.sshd` plus
  `launchctl bootstrap` is the equivalent path and needs no special privilege.
  It does not populate `com.apple.access_ssh`, so the `dseditgroup` call that
  scopes access to a single user is not optional on this path — it is the only
  thing applying the restriction.
- **The private key is generated on the iPhone and never leaves it.** Only the
  public half reaches this machine. A lost phone costs one deleted line in
  `authorized_keys`, not rotation of the four existing outbound keys.
- **Regular `sshd` over Tailscale, not Tailscale SSH.** `tailscale set --ssh`
  is exposed on this build and would remove key management entirely in favour of
  tailnet ACLs, but its server side is first-class on Linux and less proven on
  macOS. The path that must work when away from the machine should not be the
  experimental one.
- **`pmset -a sleep 0` disables only the idle timer, not forced sleep.** Apple
  menu → Sleep, the power button (`Sleep On Power Button 1`), and `pmset
  sleepnow` continue to work. The setting that *would* suppress manual sleep is
  `disablesleep`, which `pmset -g cap` does not list on this machine, so it is
  not reachable even by accident.
- **The phone attaches to a grouped session, never the desktop's session.**
  `tmux new-session -t <target>` creates a session in the same session group:
  same windows, independent current-window, so moving around on the phone does
  not drag the desktop client along. **It does not give independent sizing** —
  see the 2026-08-04 revision below, which corrects an incorrect claim made
  here originally.
- **The grouped session must be destroyed when the phone detaches.** While a
  session group exists, `choose-tree` (`prefix s` / `prefix w`) fails to render
  for other attached clients, so a lingering mobile view breaks session and
  window switching on the desktop indefinitely. A `client-detached` hook set at
  creation confines the group to the time it is actually in use.
  `destroy-unattached` cannot be used: setting it on a not-yet-attached session
  destroys that session immediately.
- **`authorized_keys` stays out of chezmoi.** It is machine-specific, and
  syncing it would propagate the phone's access to every machine in the tailnet.
  Config that *is* portable (tmux settings, the helper script) goes through
  chezmoi as usual.

## Goals

- Reach any tmux session on this Mac from Termius on the iPhone, over Tailscale
  only, with no port forwarding and no public internet exposure.
- Key-only authentication, with the private key confined to the phone.
- Connecting drops straight into a phone-sized view of a chosen session without
  altering how that session renders on the Mac.
- The Mac stays reachable when idle, while manual sleep keeps working normally.
- Persistent configuration lands in the chezmoi source, not in stray edits to
  `~/.config`.

## Non-goals

- **No mosh**, despite `mosh-server` being installed. Termius's mosh support is
  not its strength; revisit only if plain SSH proves too fragile on cell.
- **No Tailscale SSH** this round — deferred, not rejected. It can be layered on
  later once the sshd baseline is proven.
- **No LAN-reachable SSH.** `AllowUsers` is restricted to the Tailscale range;
  adding `work@192.168.1.0/24` is a one-token change if a fallback is later
  wanted.
- **No password authentication**, and no fallback to it under any condition.
- **No always-on guarantee when away from AC on battery** beyond disabling the
  idle timer; wake-on-network is AC-only on this hardware.
- **No file-sync / Files.app integration** (the Secure ShellFish use case).
- **No changes to the four existing outbound SSH keys** or `~/.ssh/config`.

## Architecture

### Network path

```
iPhone (Termius)                    MacBook Air
daniele-personal-iphone   ──WG──▶   daniele-personal-laptop
100.64.0.8                          100.64.0.18  :22
```

No port forwarding, no dynamic DNS, no public listener. MagicDNS names are used
in the Termius host entry rather than raw addresses so the config survives an
address change.

### Server configuration

`/etc/ssh/sshd_config.d/200-iphone-tailscale.conf` — included via the existing
`Include /etc/ssh/sshd_config.d/*` at line 19 of `sshd_config`. The only other
drop-in, `100-macos.conf`, sets `UsePAM yes`, `AcceptEnv`, and a crypto include;
there are no conflicting keys, so OpenSSH's first-value-wins ordering is not in
play.

```sshdconfig
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
AllowUsers work@100.64.0.0/10
```

`PasswordAuthentication no` alone is insufficient under `UsePAM yes`;
`KbdInteractiveAuthentication no` is what closes the PAM password path.

Remote Login is scoped to a single user rather than All Users:

```bash
sudo systemsetup -setremotelogin on
sudo dseditgroup -o edit -a work -t user com.apple.access_ssh
```

### Authentication

ED25519 keypair generated inside Termius on the iPhone. Public half only is
appended to `~/.ssh/authorized_keys` (`0600`; `~/.ssh` at `0700`).

### tmux attach path

`~/.local/bin/tmux-mobile`:

```bash
#!/usr/bin/env bash
# Attach to a phone-sized view of a session without resizing the desktop client.
set -euo pipefail
TARGET="${1:-data-generation}"
VIEW="mobile-${TARGET}"
tmux has-session -t "=${VIEW}" 2>/dev/null && exec tmux attach-session -t "=${VIEW}"
exec tmux new-session -s "${VIEW}" -t "${TARGET}"
```

Paired with `setw -g aggressive-resize on` in the oh-my-tmux local config, so
windows size to the smallest client *actually viewing that window* rather than
the smallest client attached to the session. Invoked from Termius's per-host
startup snippet.

### Power policy

```bash
sudo pmset -a sleep 0
```

Applies to AC and battery. At the desk, two attached displays on AC mean lid
close enters clamshell and the machine stays awake regardless. Away from the
displays, this covers the idle case; lid close still sleeps, by design.

### chezmoi integration

The tmux setting and `tmux-mobile` go into the chezmoi source at
`~/.local/share/chezmoi` via `chezmoi edit` / `chezmoi re-add`, per the
symlink-tree staging model — never by editing `~/.config` directly. Whether
`~/.tmux.conf.local` is a real file or a symlink into the oh-my-tmux tree is
verified before editing, since that determines the correct chezmoi target.

`~/.ssh/authorized_keys` is deliberately excluded.

## Implementation sequence

1. Write the hardened drop-in while Remote Login is still off.
2. Generate host keys with `ssh-keygen -A` — required before step 3 can run,
   and exposes nothing on its own.
3. Validate with `sudo sshd -t`; on failure, delete the drop-in and abort
   without touching Remote Login.
4. Enable Remote Login (`systemsetup`, falling back to `launchctl` when Full
   Disk Access is unavailable) and scope it to `work` via `dseditgroup`.
5. **Blocking on the user:** install Termius on the iPhone, generate an ED25519
   key, and supply the public half.
6. Install the public key into `authorized_keys` with correct permissions.
7. Apply the power policy.
8. Add the tmux helper and `aggressive-resize`; route both through chezmoi.
9. Verify end-to-end from the phone.

Steps 1–4, 7 and 8 are independent of step 5 and proceed in parallel with it.

## Verification

- `sudo sshd -t` exits clean before Remote Login is enabled.
- `lsof -nP -iTCP:22 -sTCP:LISTEN` shows a listener after enabling.
- `ssh -o BatchMode=yes work@100.64.0.18 true` from a tailnet host succeeds by
  key; the same with `-o PreferredAuthentications=password` is refused.
- A connection attempt sourced from outside `100.64.0.0/10` is refused by
  `AllowUsers`.
- `pmset -g` reports `sleep 0`; Apple menu → Sleep still sleeps the machine.
- From Termius: connecting lands in `mobile-data-generation`, and the Mac's own
  view of `data-generation` retains its full width while the phone is attached.
- `chezmoi diff` is empty after `re-add`, confirming source and target agree.

### Observed on 2026-08-02

Server side confirmed working. `sshd -T` reports the hardening live:

```
permitrootlogin no
pubkeyauthentication yes
passwordauthentication no
kbdinteractiveauthentication no
allowusers work@100.64.0.0/10
```

A real client connection over the Tailscale IP negotiates
`Authentications that can continue: publickey` and nothing else — stronger
evidence than reading the config back, since it is the server's actual
behaviour. `dseditgroup -o checkmember -m work com.apple.access_ssh` returns
`yes`, and `/etc/pam.d/sshd` enforces it via
`account required pam_sacl.so sacl_service=ssh`.

Host key fingerprints, for verification on first connect from the phone:

```
ED25519  SHA256:OFlbMoZwP6Lh2jDjof+Y+PsZPBxhtO3py2u6rCM95Wg
ECDSA    SHA256:hbMlHQRJUMfxnLMD6lRnSYhjh4nF/VwGLtcr/mgRVHc
RSA      SHA256:Z1aBSp2V0Ejr9a2yLqTYibDMoceyAdoOlHB+PIbvGlw
```

## Revision — 2026-08-04

First real phone use exposed two defects in the tmux half of this design. The
SSH half needed no changes.

### `aggressive-resize` was inert, and the resize problem is not fixable

`aggressive-resize` only modulates the smallest/largest computation, and
oh-my-tmux sets `window-size latest`, which performs no such computation —
it simply follows whichever client was most recently active. The setting was
therefore a no-op and has been commented out with the reasoning in place.

More fundamentally, **a tmux window has exactly one size.** Two clients
displaying the same window must share it; no configuration escapes this.
Grouped sessions buy an independent *current-window*, not independent sizing.
The original design overstated what they provide. The remaining options are to
view different windows on each client, to accept the resize, or to give the
phone a fully independent ungrouped session and lose the shared view.

### A lingering grouped session breaks `choose-tree`

While `mobile-data-generation` existed — even detached, even with the phone
long disconnected — `prefix s` and `prefix w` produced nothing on the desktop.
Killing the session restored both immediately.

The mode itself engages correctly: issuing `choose-tree` against a detached
test session moves it to `in_mode=1, mode=tree-mode`. The failure is in the
draw path for an *attached* client, which a detached test never exercises —
an isolation test that initially produced a false negative here.

Fix: `tmux-mobile` now sets a `client-detached` hook that destroys the mobile
view as soon as the phone drops, so the group never outlives the connection.

Not explained: window 1 held a size (`212x52`) matching no attached client, and
kept it after the group was removed. Cosmetic, and separate from the
`choose-tree` failure rather than its cause.

## Risks and rollback

- **Bonjour advertising.** Enabling Remote Login also advertises `ssh` and
  `sftp-ssh` over mDNS on whatever LAN the Mac joins, café networks included.
  Authentication is unaffected, but it is unnecessary disclosure; suppressing it
  is an open follow-up.
- **Tailscale as a single point of failure.** With `AllowUsers` restricted to
  the CGNAT range, a Tailscale outage means no SSH at all, including from the
  same LAN. Accepted deliberately; the LAN fallback is one token away.
- **Rollback is complete and local.** `sudo systemsetup -setremotelogin off`,
  delete the drop-in, delete `authorized_keys`, `sudo pmset -a sleep 1`. Nothing
  here is destructive and physical access to the machine is never lost.
