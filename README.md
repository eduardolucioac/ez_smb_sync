# ez_smb_sync

![ezsmbsync](./images/ezsmbsync.png)

Mounts a **Samba/CIFS** share and keeps a local folder in sync with it using
**Unison**, driven by a small interactive prompt. Perfect for software
development against virtualized environments (VMWare, VirtualBox, KVM,
QEMU...), where the code lives on your host and has to reach a guest — or the
other way around.

**IMPORTANT:** My life, my work and my passion is free software. Corrections, tweaks and improvements are very welcome (**pull requests** 😉)! Please consider giving us a ⭐, fork, support this project or even visit our professional profile (see [About](#about)). **Thanks!** 🤗

**Support free software and my work!** ❤️🐧

## Table of Contents

- [Layout](#layout)
- [How it works](#how-it-works)
- [Installation](#installation)
   * [1. Prerequisites](#1-prerequisites)
   * [2. Create your setup](#2-create-your-setup)
   * [3. Give permissions](#3-give-permissions)
   * [4. Run it](#4-run-it)
   * [5. Optional: turn it into a command](#5-optional-turn-it-into-a-command)
- [Choosing a setup](#choosing-a-setup)
- [Commands](#commands)
- [Configuration parameters](#configuration-parameters)
- [Configuration check](#configuration-check)
- [One way sync (mirroring)](#one-way-sync-mirroring)
- [Safety measures](#safety-measures)
- [When the share is busy](#when-the-share-is-busy)
- [Troubleshooting](#troubleshooting)
   * [My setup is not listed](#my-setup-is-not-listed)
   * [Crap! The directory can not be mounted!](#crap-the-directory-can-not-be-mounted)
   * [Nothing is synchronized](#nothing-is-synchronized)
   * [Sudo asks for a password on every run](#sudo-asks-for-a-password-on-every-run)
- [Security note](#security-note)
- [About](#about)

## Layout

```
ez_smb_sync/
├── ezsmbsync.bash          # run this — lists your setups, mounts, syncs and prompts
├── configs/
│   ├── my_config_model.bash    # setup template (copy it, don't fill it in)
│   └── my_project.bash         # your setups, one file per target
├── images/
├── .gitignore              # keeps your setups (with passwords) out of git
├── LICENSE
└── README.md               # this file
```

---

## How it works

You run **`ezsmbsync.bash`**. It reads the setups in `configs/`, shows you the
ones whose target is actually answering, and loads the one you pick.

One file per target keeps different settings apart, and the file name — without
the `.bash` extension — is what you see in the list. It also becomes the prefix
of every log line, so you can tell your terminals apart:

```
--- [[ my_project ]] Trying to mount the network path!
```

The run goes like this:

1. The setups are listed and you pick one (see [Choosing a setup](#choosing-a-setup));
2. The configuration is validated (see [Configuration check](#configuration-check));
3. The share is mounted with `mount -t cifs` — via `sudo`;
4. An **initial** synchronization runs;
5. The interactive prompt opens, and stays open;
6. On `quit`, a **final** synchronization runs and the share is unmounted.

Because of steps 4 and 6, changes made while the script was running are never
left behind.

---

## Installation

### 1. Prerequisites

`unison` performs the synchronization and `cifs-utils` allows mounting the
share (Debian based example):

```sh
sudo apt-get install unison cifs-utils
```

Arch based example:

```sh
sudo pacman -S --needed unison cifs-utils
```

**NOTE:** `sudo` rights are required, since mounting and unmounting a share
is a privileged operation.

### 2. Create your setup

Copy `configs/my_config_model.bash` and give it a name that identifies the
target. Use one copy per target — that way you keep different settings for
different targets easily.

EXAMPLE

```sh
cp configs/my_config_model.bash configs/my_project.bash
```

**IMPORTANT:** The copy must stay in the **`configs`** folder, which is where
the setups are looked for. The name you choose, without the `.bash` extension,
is what shows up in the list.

Now fill in the parameters. Every one of them is documented inline in the
file itself, so it's worth reading it before your first run. See
[Configuration parameters](#configuration-parameters) for the summary.

### 3. Give permissions

```sh
chmod a+x ezsmbsync.bash
chmod 600 configs/my_project.bash
```

**TIP:** Your setup does **not** need execute permission — it is loaded, not
run. What it does need is `600`, which drops the read permission of everybody
else, and that matters because it holds a password.

### 4. Run it

```sh
./ezsmbsync.bash
```

Pick your setup from the list and let the magic happen!

### 5. Optional: turn it into a command

Link it into a folder that is in your `PATH` and you can call it from anywhere,
without typing the path:

```sh
mkdir -p ~/.local/bin
ln -s "$(pwd)/ezsmbsync.bash" ~/.local/bin/ezsmbsync
```

Then, from any folder:

```sh
ezsmbsync
```

**NOTE:** `~/.local/bin` is the usual place for a user's own commands, but not
every distribution puts it in the `PATH` by default. Check with
`echo "$PATH" | tr ':' '\n' | grep local/bin` and, if nothing comes out, add
this to your `~/.bashrc`:

```sh
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) PATH="$HOME/.local/bin:$PATH" ;; esac
```

**TIP:** Linking is better than copying. The script resolves the link before
looking for `configs/`, so it always finds the setups beside the **real** file —
and a copy would go stale the moment you update the project.

---

## Choosing a setup

Running `ezsmbsync.bash` lists what is in `configs/`, one line per file, and
asks which one to use:

```
Setups with a reachable host and Samba available:
   1) my_project                              192.168.122.59
   2) my_client_name                          fileserver.local
number:
```

**Only setups whose host is answering are listed.** The host is taken from the
`NET_SHARE_REMOTE` of each file (`//HOST/SHARE` → `HOST`) and probed on the
Samba ports, `445` first and `139` after it. A target that is switched off,
unreachable or not running Samba is left out on purpose — picking it could only
end in a failed mount.

**A setup whose share is already mounted is left out too.** Its
`DIR_MOUNT_REMOTE` is checked with `mountpoint`, and there is nothing left for a
run to do there, so it is not offered rather than offered and then refused.

When nothing is answering you get told so, instead of an empty list:

```
No setup found with a reachable host answering on Samba.
Looked in ".../configs".
```

Two details worth knowing:

- The files are **parsed**, not loaded, while the list is being built. Listing
  your setups never runs the code inside them. A `DIR_MOUNT_REMOTE` written with
  `$HOME` or `~` is still resolved, since those two are common enough to be worth
  it;
- `my_config_model.bash` is the template, so it is never listed.

The messages of this stage carry no prefix, since no setup has been chosen yet.
From the moment you pick one, every line is prefixed with its name.

**TIP:** The probe is a TCP connection with a short timeout, so a long list
stays quick. It is not a `ping` — a host may well answer ICMP with no Samba
running on it, and that would be of no use here.

---

## Commands

Type these at the terminal while your profile is running:

| Command | Purpose |
|---|---|
| `sync` | Synchronize according to the `ONE_WAY_SYNC_FROM_REMOTE` parameter |
| `owsfr` | Force a one way sync (mirroring, **CAUTION!**) **from remote** |
| `owsfl` | Force a one way sync (mirroring, **CAUTION!**) **from local** |
| `help` | List the commands above |
| `quit` | Run a final synchronization, unmount the share and exit |

**TIP:** Pressing **Ctrl+D** does exactly what `quit` does, final
synchronization and unmount included.

---

## Configuration parameters

| Parameter | Required | Purpose |
|---|---|---|
| `NET_SHARE_DOMAIN` | Optional | Domain name. Leave it empty when the share does not require one |
| `NET_SHARE_USER` | **Required** | Remote share user name |
| `NET_SHARE_PSW` | **Required** | Remote share password |
| `NET_SHARE_REMOTE` | **Required** | Remote share path, as `//IP_OR_NAME/SHARE_NAME` |
| `DIR_MOUNT_REMOTE` | **Required** | Local folder where the share gets mounted |
| `SYNC_ENABLED` | Optional, default `0` | `1` enables the synchronization, `0` only mounts the share |
| `DIR_MOUNT_SYNC_REMOTE` | Optional | Folder inside the mounted share to sync. Assumes `DIR_MOUNT_REMOTE` when empty |
| `DIR_MOUNT_SYNC_LOCAL` | Required if `SYNC_ENABLED=1` | Local folder to synchronize |
| `ONE_WAY_SYNC_FROM_REMOTE` | Optional, default `1` | `1` mirrors from the share, `0` synchronizes both ways |
| `I_SUPPORT_FREE_SOFTWARE_N_THIS_WORK` | Optional, default `0` | `1` hides the donation notice |

**IMPORTANT:** There must be **no spaces** around the `=` sign. In Bash
`VAR = value` is not an assignment, it is an attempt to run a command
named `VAR`.

---

## Configuration check

The configuration is validated when the script starts, **before anything is
mounted**. Problems are reported all at once, prefixed with `CONFIG ERROR`,
instead of failing later in a way that is hard to diagnose.

Cleaned up automatically:

- Surrounding whitespace of the paths, a common leftover of copying and pasting;
- Trailing slashes of the paths.

The user name, the domain and the password are **never** modified — changing
them would only turn an authentication failure into a confusing one. They are
validated instead.

Reported as errors:

- A comma or a line break in `NET_SHARE_DOMAIN`, `NET_SHARE_USER` or
  `NET_SHARE_PSW`, which would corrupt the option list of `mount`;
- `SYNC_ENABLED` or `ONE_WAY_SYNC_FROM_REMOTE` set to anything other than `0` or `1`;
- A missing `NET_SHARE_USER`, `NET_SHARE_REMOTE` or `DIR_MOUNT_REMOTE`;
- A `NET_SHARE_REMOTE` that is not in the `//IP_OR_NAME/SHARE_NAME` form;
- A `DIR_MOUNT_REMOTE` or `DIR_MOUNT_SYNC_LOCAL` that is not an existing directory;
- A `DIR_MOUNT_SYNC_REMOTE` outside of `DIR_MOUNT_REMOTE`, which would leave it
  out of the share;
- A `DIR_MOUNT_SYNC_LOCAL` inside `DIR_MOUNT_REMOTE`, which would make Unison
  fight against its own changes;
- A missing `unison` (when `SYNC_ENABLED=1`) or a missing `mount.cifs`.

---

## One way sync (mirroring)

A one way sync is a **mirroring**, not a copy. Files that exist **only** on
the destination side are **deleted**, so that it becomes identical to the
source.

| Mode | Source of truth | What happens to files that exist only on the other side |
|---|---|---|
| `ONE_WAY_SYNC_FROM_REMOTE=1` (default) | The share | Deleted from the local folder |
| `ONE_WAY_SYNC_FROM_REMOTE=0` | Both | Kept — new files propagate in both directions |
| `owsfr` command | The share | Deleted from the local folder |
| `owsfl` command | The local folder | Deleted from the share |

**IMPORTANT:** `owsfr` and `owsfl` ignore `ONE_WAY_SYNC_FROM_REMOTE` and
mirror right away. Be sure of the direction before typing them.

---

## Safety measures

- A synchronization only runs when the mount point is **really mounted** and
  **not empty**. That prevents a dropped share — which turns the mount point
  back into an ordinary empty folder — from being mirrored as a mass deletion;
- Permissions are ignored (`-perms 0`), which is required on CIFS;
- The share is unmounted on exit, so nothing is left hanging;
- A **busy** share is never force-detached behind your back. When the regular
  unmount fails, what is holding it is listed and you are asked before a lazy
  unmount is attempted (see [When the share is busy](#when-the-share-is-busy)).

---

## When the share is busy

On `quit` the share is unmounted with `umount -f`. That fails when something is
still using it — a terminal sitting inside the folder, an editor with an open
file, a running build. Instead of giving up silently or forcing it, the script
shows you what is holding the share and asks:

```
--- [[ my_project ]] The share could not be unmounted. It is busy: something is
 still using "/my/mount/folder".
--- [[ my_project ]] What is holding it:
                         USER    PID ACCESS COMMAND
    /my/mount/folder:    eduardo 4242 ..c.. bash
Force the unmount anyway? [y/N]:
```

**Answer `N`, close whatever is listed, and quit again.** That is the safe path,
and it is the default.

Answering `y` runs `umount -l`, a **lazy** unmount: the folder is detached right
away and only really released once nothing uses it any more. Whatever is still
writing at that moment may never reach the server, so **data can be lost**. It
exists for when you cannot close the offender — not as a shortcut.

**NOTE:** Listing the culprits needs `fuser`, from the `psmisc` package. Without
it the question is still asked, only without the list.

---

## Troubleshooting

### My setup is not listed

The list only shows setups whose host answers on a Samba port, so:

1. The target is switched off or unreachable. Check it with
   `ping HOST`, keeping in mind that a host may drop ICMP and still serve Samba;
2. Samba is not running on the target. Check the port straight away:

   ```sh
   timeout 2 bash -c '</dev/tcp/HOST/445' && echo open || echo closed
   ```

3. Its share is **already mounted**. Check with
   `mountpoint /your/mount/folder`, and unmount it if the previous run left it
   behind;
4. The file is not in `configs/`, or does not end in `.bash`;
5. `NET_SHARE_REMOTE` is missing or malformed. It must be `//IP_OR_NAME/SHARE_NAME`
   — the host is taken from between the leading `//` and the next `/`;
6. The file is named `my_config_model.bash`, which is the template and is never
   listed.

### Crap! The directory can not be mounted!

The `mount` command failed. In order of likelihood:

1. Wrong user name, password or domain;
2. The guest is unreachable — check the IP with `ping`, and check the
   firewall of the remote machine;
3. The share name is wrong. List what the server offers:

   ```sh
   smbclient -L //IP_OR_NAME -U user_name
   ```

4. The SMB protocol version is too old for your kernel. Some old guests need
   an explicit `vers=1.0`, which this script does not set.

### Nothing is synchronized

Check, in this order:

1. `SYNC_ENABLED` is `1`;
2. The share is really mounted — `mountpoint /your/mount/folder`;
3. The folder being synchronized is **not empty**, since an empty source
   aborts the synchronization on purpose (see [Safety measures](#safety-measures)).

### Sudo asks for a password on every run

That's expected — mounting is privileged. The message below is not an error,
it just means a previous run left the share mounted:

```
--- [[ my_project.bash ]] Hey! The remote directory is already mounted! ;)
```

---

## Security note

Your setup holds the share password **in plain text**. Keep it out of version
control and restrict its permissions with `chmod 600 configs/my_project.bash`.

The provided `.gitignore` already ignores every `*.bash` file except
`ezsmbsync.bash` and `my_config_model.bash`, so the setups in `configs/` are
not committed by accident.

## About

ez_smb_sync 🄯 BSD-3-Clause  
Eduardo Lúcio Amorim Costa  
Brazil-ES  
https://www.linkedin.com/in/eduardo-software-livre/

![Brazil](./images/brazil.png)
