# Handoff: debugging on the target Mac

You're picking this up on the Mac it's actually meant for (Apple M4, macOS 26). The installer ran
through; the VM boots; Quartus crashes on startup. Your job: make Quartus start, then push the fix
so `curl … | bash` delivers it.

## What this is

A one-line installer (`setup` → `install.sh`) for a non-technical user that gives her Quartus Prime
Lite 25.1 + Questa for a DE0-Nano (Cyclone IV E, EP4CE22F17C6) on an Apple Silicon Mac:

- `install.sh`: installs Rosetta, upstream Nix (NixOS/nix-installer), nix-darwin; copies the repo to
  `~/.config/quartus-mac`, writes `local.nix` (user, uid, memory, keyboard, screen size, VM MAC,
  `builder` flag); switches nix-darwin with the Linux builder on; builds the VM; switches the builder
  off again; creates two apps in `~/Applications` and Dock icons.
- `darwin.nix`: nix-darwin. `nix.linux-builder` with `pkgs.darwin.linux-builder-vz` (Virtualization.framework
  + Rosetta, so x86_64-linux builds run translated). `de0-program` wraps openFPGALoader.
- `quartus-vm.nix`: NixOS aarch64 guest via microvm.nix, hypervisor vfkit, Rosetta enabled. Shares the
  host `/nix/store` (virtiofs), `~/FPGA`, and a logs dir. `/home` on `~/.local/share/quartus-vm/home.img`.
  No display manager: getty autologin → `startx` → Openbox + Quartus maximized; quitting Quartus powers
  off. A user service converts each `.sof` in `~/FPGA` to `.rbf`.
- `vfkit-stop-on-close.patch`: vfkit hangs forever after its window is closed; this stops the VM.

## Paths on this Mac

| Path | What |
|---|---|
| `~/quartus-for-mac` | last downloaded copy of the repo (tarball, **not** a git checkout) |
| `~/.config/quartus-mac` | what's actually built from; contains the generated `local.nix` (keep its `mac`, the Questa license depends on it) |
| `~/.local/share/quartus-vm/runner` | built VM runner; `runner/bin/microvm-run` starts it |
| `~/.local/share/quartus-vm/logs/` | `console.log` (guest console/systemd), `x.log`, `quartus.log`, `vm.log` (vfkit) |
| `~/Applications/Quartus.app` | runs `microvm-run` from `~/.local/share/quartus-vm` |

`nix` may not be on PATH in an old shell: use `/run/current-system/sw/bin/nix` or open a new Terminal.
There's no git (Command Line Tools aren't installed and shouldn't be); use `nix shell nixpkgs#git nixpkgs#gh`.

## The current bug

`quartus.log` after clicking the Quartus app:

```
*** Fatal Error: Illegal Instruction
Module: quartus
Stack Trace:
    0x1af8f: hasHighPrecisionDouble + 0x42 (ccl_sqlite3)
    0x53b55: altr_sqlite3_initialize + 0xd8 (ccl_sqlite3)
    0x5451e: altr_sqlite3_malloc + 0x8 (ccl_sqlite3)
    0x53cea: altr_sqlite3_initialize + 0x26d (ccl_sqlite3)
    0x40425: msg_exe_init(int, char const**) + 0x56 (ccl_msg)
    0x4048c: msg_exe_main(int, char const**, int (*)(int, char const**)) + 0x2a (ccl_msg)
     0x39d5: main + 0x26 (quartus)
quartus exited with 2
```

Everything else in the logs is fine (Rosetta share mounted, X and Openbox start; `/dev/fb0` and
`menu.xml` messages are harmless).

What's known:
- On the dev Mac (A18 Pro, macOS 27) the same Quartus build ran under Rosetta inside the
  `linux-builder-vz` VM: `quartus_sh --version`, a full `quartus_sh --flow compile` for EP4CE22F17C6, and
  `quartus_cpf`. Those go through the same `msg_exe_main` → SQLite init, so this should have crashed too.
- AVX isn't the explanation (macOS 26 Rosetta has it). M4 vs A18 Pro have the same relevant CPU features.
- `hasHighPrecisionDouble` is SQLite's check whether `long double` (x87, 80-bit) is more precise than
  `double`, so the faulting instruction is probably x87.

Open differences between the working and the failing case:
1. macOS 26 vs 27 Rosetta.
2. vfkit VM vs the vzvm builder VM (e.g. Rosetta caching options on the share).
3. The `quartus` GUI executable vs `quartus_sh` (unlikely, same init path).

The dev Mac is reproducing with the `quartus` executable inside the builder VM right now; check
`git log` / this file for a result before going too far.

## Suggested first steps

1. See the faulting instruction:
   ```bash
   lib=$(ls -d /nix/store/*-quartus-prime-lite-unwrapped-*/quartus/linux64/libccl_sqlite3.so | head -1)
   nix shell nixpkgs#llvm -c llvm-objdump -d --disassemble-symbols=hasHighPrecisionDouble "$lib"
   ```
2. Get a shell in the VM to test directly instead of guessing: add `services.openssh` with a key to
   `quartus-vm.nix` (the VM has vfkit NAT networking; the Mac can reach its 192.168.64.x address), or
   temporarily make the session script run tests and write to `/mnt/logs`.
3. Likely fix if it's just this check: make `hasHighPrecisionDouble` return 0 (`31 c0 c3`, i.e.
   `xor eax,eax; ret`); SQLite then avoids `long double` entirely. Patching the 9 GB unwrapped package
   means a full reinstall build, so a small derivation with a patched copy of `libccl_sqlite3.so` that
   wins over `quartus/linux64` on the library path is cheaper (mind that the package notes `LD_PRELOAD`
   breaks Questa). If x87 is broken more widely under this Rosetta, other code will crash next; check
   before declaring victory.

## Fast iteration loop

Edit in `~/.config/quartus-mac`, then:

```bash
cd ~/.config/quartus-mac
# Linux-side changes need the builder; enable it while you work
sed -i '' 's/builder = false/builder = true/' local.nix
sudo /run/current-system/sw/bin/darwin-rebuild switch --flake "path:$PWD#quartus"
nix build "path:$PWD#quartus-vm" -o ~/.local/share/quartus-vm/runner
cd ~/.local/share/quartus-vm && ./runner/bin/microvm-run    # or click the Quartus app
```

When done, port the change to the repo, set `builder = false` again and switch, so the builder stops
using memory and its disk image (`/var/lib/linux-builder`) is removed.

## Constraints and preferences

- Everything has to keep working through `curl -fsSL https://raw.githubusercontent.com/any-0/quartus-for-mac/main/setup | bash`
  on a fresh Mac, and must be safe to rerun. The user is not technical.
- Don't change the Linux builder's NixOS system (e.g. adding swap): it must stay a cache hit, or a fresh
  Mac would need a Linux builder to build the builder. Runner-side settings like memory are fine.
- README is German, short, no defensive explanations of problems she hasn't hit.
- Commits: plain messages, authored as the repo owner, **no AI attribution lines** of any kind.
- `git push` needs auth on this Mac (`gh auth login`); otherwise leave commits for the owner to push.
