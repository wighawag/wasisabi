# The agent layer

A local model, private search, and agents that use them, for the machine's owner and for anonymous accounts whose every packet is forced through Tor. Written 2026-09-26.

## What a wasisabi machine gets

With the defaults (every option below is `true` unless stated), a fresh install has:

| Piece | What it is | Where |
|---|---|---|
| Local model | llama.cpp on the CPU, Gemma 4 E4B QAT (Apache-2.0, 4.2 GB), no network of its own | `/run/wasisabi-llm/llm.sock`, plus `127.0.0.1:11435` |
| Search | SearXNG, socket-activated; `webveil` CLI | `/run/wasisabi-search/search.sock` |
| The owner's agent | pi with three store extensions: the local model, web search/fetch, recall over past sessions; memonaut CLI | `~/.pi/agent/settings.json` (seeded) |
| The owner's web UI | wherever, loopback only, token minted on the machine | `wherever-link` prints the URL |
| Anonymous accounts | `anon`, `anon-john`, `anon-jane`: every connection forced through Tor by anonctl, fail-closed, each proven with `anonctl verify` | `sudo anonctl use anon` |
| Their agent | pi on the local model (over the socket), web search through the account's own SearXNG and Tor circuit | per-account `~/.pi/agent` |
| Their web UI | a wherever per account, as that account, on a socket; routed by a loopback-only Caddy | `sudo anon-reconcile links` |

The distro-level switches are in `modules/options.nix` (`wasisabi.user`, `llm.enable`, `search.enable`, `search.viaTor` (off), `agents.enable`, `anon.enable`, `anon.autoEnroll`, `anon.accounts`), and the installer asks about each of them under "AI and privacy". They turn on building blocks in `modules/services/`, each an ordinary module with its own `enable` under `wasisabi.services.*`, wired together by `modules/agents.nix`. A machine can take the arrangement or use the blocks on their own.

## The one decision everything follows from: the model is on a unix socket

An anonctl account cannot open ANY TCP connection that is not forced into its Tor shim, loopback included, unless root punches an exemption (`anonctl update --allow 127.0.0.1:<port>`). A unix socket is not IP traffic and no nftables rule sees it. So serving the model on a socket gives the anon accounts a local model with no hole in their jail, gated by the socket's group instead. It also means:

- the model server runs with `PrivateNetwork = true`: the process holding every prompt on the machine cannot open a connection anywhere;
- access is a file permission, not "any local uid" as a loopback port would be.

pi only speaks HTTP to a host:port, so `pkgs/pi-wasisabi-local` teaches it the socket: a dependency-free extension that registers provider `local` from `/etc/wasisabi/llm.json` (written by the module from the same values that start the server, so pi cannot drift from what is served) and wraps `globalThis.fetch` for one sentinel origin, serving those requests with `node:http` over the socket. The OpenAI SDK pi uses resolves the global fetch per client and pi builds a client per request, so the wrap is enough; it is installed once per process because wherever hosts many sessions in one. An account outside the socket's group falls back to the TCP port if one is configured.

The TCP port (`wasisabi.services.llm.tcpPort`, 11435) is a socket-activated `systemd-socket-proxyd` in front of the socket, for clients that cannot speak to a socket. Null disables it.

## Provenance: most of this ran on telemaque first

The anon stack (`anon-accounts`, `anonctl-units`, `anon-dns`, `anon-home`, `anon-search`, `wherever-anon`, `wherever-anon-reconcile`, and the `anon-reconcile.sh` / `caddy-routes-guard.sh` scripts) and the packages (anonctl, webveil, pi-webveil, memonaut, memonaut-pi, pi) were carried over from the my-boxes fleet repo, where they run on a real machine. They were copied with a mechanical rename (`my.anonHome` to `wasisabi.services.anonHome`, and so on) so they stay diffable against their tested originals, and kept their comments; references in those comments to `work/notes/...`, `hosts/...` and ADR numbers point into github.com/wighawag/my-boxes.

What was changed in the carried-over code, and why:

- **No fleet coupling.** `self.packages.*` defaults became `config.wasisabi.pkgs.*`, an attrset of mkDefault packages built against the importing system's pkgs, so a consumer can substitute one (`wasisabi.pkgs.wherever = ...`).
- **anon-search lost its two private engines.** The fleet's challenge-answering engines and the searchcast browser depend on packages that are private to that repo by design (site-specific scrapers). The plain keyless engines remain.
- **anon-home's `endpoint` became optional.** With none, the provider comes from the extension (`provider`, default `local`) and models.json carries no provider. A loopback endpoint is also accepted now, for a machine that uses the exemption route instead.
- **The dispatcher is loopback-only.** The fleet's lives in its reverse-proxy module and serves a wildcard certificate on a real domain for a phone on a mesh. Here `modules/services/anon-dispatcher.nix` serves `http://<handle>.localhost:8480`: `*.localhost` resolves to loopback by RFC 6761 in browsers and in glibc, so there is no DNS, domain or certificate, and the bind keeps it local. The routing half is unchanged: the store config holds a wildcard site and a glob import, and reconcile writes one fragment per account outside the store. `anon-reconcile.sh` gained `--link-scheme` and `--link-port` so `links` prints a URL that works.
- **A fix to reconcile** (see "Found" below).

Written new for wasisabi: `llm.nix`, `searxng.nix` (the owner's instance, on anon-search's proven uWSGI-on-inherited-socket recipe), `pi-user.nix` and `wherever.nix` (laptop-shaped counterparts of the fleet's sops-bound modules), `anon-dispatcher.nix`, `agents.nix`, the extension.

## Owner vs fleet shapes

The fleet's `services.piUser` DECLARES settings.json (a read-only store symlink: on a fleet the file is policy). Here it is SEEDED, since pi writes to it in normal use and the file belongs to the owner. The trap a seed has is that settings.json names extensions by path and outlives the generation that wrote it, so a store path in it would be garbage-collected out from under it and pi would skip the extension silently. So the seed names `/etc/wasisabi/pi-extensions/<name>`, a symlink every activation repoints. `declareSettings = true` restores the fleet behaviour.

The owner's wherever has no secret manager to lean on, so its token is minted at first start into `/var/lib/wherever/token` (0400, the owner's) and never exists in the store, the flake or git; `wherever-link` prints the URL with the token in the fragment, which browsers never send.

## Enrolment

`wasisabi.anon.autoEnroll` runs `wasisabi-anon-enroll` from a timer (1 minute after boot, then every 15 minutes), never from `multi-user.target`, because `verify` waits on Tor and a boot must not. Per declared account it is idempotent and self-healing:

- proven (anonctl's marker exists): nothing to do;
- managed with forcing loaded: `anonctl verify`, which writes the marker on green;
- managed with forcing NOT loaded, i.e. a failed `add` (anonctl records the account before installing its rules): `rm`, then `add` again. Safe because an account that was never proven was never given an interface, so there is no handle or token to lose;
- not managed: `anonctl add --endpoint socks5h://127.0.0.1:9050`, which adopts the declared account.

It never passes `--allow`. The fleet keeps enrolment an operator verb on the principle that a deploy must not be able to punch a hole in a jail; this automation respects that principle because it only ever CREATES jails, and the model's socket means no hole is needed.

## Verified, and how

On a booted demo VM (the demo config, headless with a real render node, 8 GB), not just evaluated:

- `nix flake check` passes, including a new `agent-layer` check pinning the load-bearing claims (no network for the model server, socket serving, pinned uids, anon accounts in the socket's group, anon sessions starting on the local model with the extension from the store, loopback-only dispatcher, Tor on, no firewall port opened, enrolment not on the boot path) and new `emit-roundtrip` expectations for the installer's answers.
- **From a fresh disk with no manual step, the system reaches `running` with zero failed units, and within a few minutes all three accounts are enrolled, proven through Tor (all 14 of `anonctl verify`'s assertions, including DNS confinement and a confirmed Tor exit) and given their web interfaces.** That DNS confinement passes is worth noting: the carried-over `anon-dns` was only ever measured on telemaque, and wasisabi's stack (NetworkManager, avahi for printing) is different.
- After a reboot, every account's forcing is reloaded by anonctl's own boot loader (`anonctl probe` green), the interface links are unchanged, and an anon account's egress works (through Tor).
- `pi` run AS the jailed `anon` account answered through the local model over the socket, including a tool call. A TCP attempt would have been forced into the account's Tor shim and failed, so this is the socket route working.
- The dispatcher serves a claimed handle (200) and 404s an unclaimed one.
- The owner: `webveil search` returns results over the socket; settings.json is seeded, writable and owned by the owner, naming the `/etc` extension paths; `wherever-link` prints the loopback URL.
- The extension, on this build machine against a real llama-server on a socket: pi listed the model and completed a tool call through it.
- **From the ISO**: `./scripts/test-install-vm.sh` installed unattended from the netinstall autotest ISO (with the new "AI and privacy" questions answered by default), and the installed disk, booted on its own, reached its login screen. Logged in on a text VT: `running` with no failed units, the model, Tor, Caddy, wherever and search active, the owner (the installer's username, substituted into `wasisabi.user`) in both socket groups, pi seeded on the local model, and all three anon accounts enrolled, proven, jailed after that boot (`anonctl probe`) and given their interface links, with no manual step.
- my-boxes' nono, importing all of this on its 26.05 pin: evaluates, and its full system closure builds.

## Found while building this

- **anonctl's first `add` on a fresh machine failed in a unit** because anonctl runs `nft`, `setpriv` and `nologin` by name and a unit's PATH holds none of them, and NixOS does not put `nft` on the system PATH at all unless the firewall uses nftables. The enrol unit now has them on its path, and the anon layer installs nftables so `sudo anonctl ...` works interactively too.
- **Reconcile refused every boot on a machine anonctl had never run on**, and this is a latent bug in the fleet original too. It treats "the ledger directory is missing while provisioned state exists" as a refusal, rightly, but detected provisioned state as ANY directory under `/var/lib/wherever-anon`, and the wherever-anon module's own tmpfiles rules create one per declared slot at boot. So the check fired on every fresh machine. Fixed here by testing for a `state.json`, which is what reconcile actually writes. telemaque never hit it because its ledger existed before the slots were declared; a rebirth of telemaque would. Fixed in my-boxes too (db6d75e), with a fixture scenario.
- **The VM install test's stage 2 cannot screenshot on a host with GL.** Its GL branch (`virtio-vga-gl` under `egl-headless`) had never run before (the machine it was written on has no host GL), and QEMU answers `screendump` there with `Error: no surface`, so the stage reports "no screenshot produced" for a machine that booted fine. The installed disk was booted by hand on the `-vga std` branch instead. Unfixed in the harness.
- **The offline medium did not cover the agent layer, twice over.** An offline install set out to build 1042 derivations from source, bootstrapping compilers. (1) No payload system had an owner: `wasisabi.user` is a string, which the payload generator does not enumerate, so the owner's pi, wherever and memonaut were on no payload and the target had to build them and their toolchains. The payloads now set one. (2) The owner's SearXNG settings were generated with `pkgs.formats.yaml`, which runs remarshal (a Python toolchain), and their content depends on an answer (Tor or not), so the file is built on the target. They are now JSON written with `writeText` (JSON is valid YAML). An attempt to cover the false side of every bool by alternating them across payloads made it worse: the bools flip in lockstep, so enum values got paired only with a disabled parent (tuigreet only where greetd was off). What is left to build on the target is the ~130 small per-machine files an offline install always builds. Verified: an install with no network device at all, then a boot where the model answers from the weights the medium carried and search returns results. `iso-offline` is 8.5 GB.
- **A networked install can die on one dropped download.** The agent layer's packages are in no public binary cache, so every install builds them and fetches hundreds of npm tarballs; the VM install test failed once on `Stream error in the HTTP/2 framing layer`, after the disk was wiped. The installer now retries the networked build up to three times; what was already fetched stays in the target's store, so a retry resumes. Carrying those packages prebuilt on the netinstall medium would remove the exposure entirely, and is not done yet.
- **A failed `add` leaves a ledger record behind**, so "skip `add` when the account is managed" alone loops forever on `verify`. Hence the `forcing.state` branch above.

## Why this default model

Measured 2026-09-26 with the module's own server flags (8 threads to approximate a laptop, `--jinja`, reasoning off, 32k context) and pi through the extension, on five agentic tasks (run a command, create and read back a file, count a file's lines, edit a file with the edit tool, find which of three files contains a word), each model run once:

| Model | Passed | Per task | Download | Resident | Prompt / generation speed | Prompt tokens processed |
|---|---|---|---|---|---|---|
| **Gemma 4 E4B QAT UD-Q4_K_XL** (the default) | 5/5 | 3 to 4 s (11 s cold) | 4.2 GB | 5.2 GB | 237 / 18.0 tok/s | 1690 |
| Gemma 4 E4B Q4_K_M | 5/5 | 2 to 15 s | 5.0 GB | | | 1849 |
| Qwen3.5 4B Q4_K_M (the first default) | 5/5 | 8 to 17 s | 2.7 GB | 4.5 GB | 122 / 16.7 tok/s | 3926 |
| Phi-4-mini-instruct Q4_K_M | 1/4 | | 2.5 GB | | | |

Phi-4-mini's one pass was not real: it never issued a tool call through pi, it wrote the command as markdown and invented the output, so no file was ever created. At this size the first question is whether a model drives tools at all.

Between the two that do, Gemma wins on the cost an agent actually pays, which is reading prompts: twice the prompt throughput, and less than half the prompt tokens processed over the same tasks. The second number is architectural: Qwen3.5 is a hybrid with recurrent layers, whose state llama.cpp cannot roll back to a shared prefix, so it reuses its prompt cache across requests less often and keeps re-reading pi's system prompt. Gemma 4 E4B costs 1.5 GB more download and ~0.75 GB more memory, which a 16 GB machine absorbs. Gemma 4 is Apache-2.0 (earlier Gemma releases were under Google's own terms and would have failed the libre rule), and it takes images with its mmproj (`wasisabi.services.llm.mmproj`). Five tasks run once is a small sample.

## Not verified

- **Real hardware**, including how fast the default model answers on a laptop CPU. With the first default (Qwen3.5 4B) a cold tool-calling turn took about 28 s on this build machine (Zen 5, 8 threads) and about 1m40s in the VM (6 vCPUs); the VM runs above were all on that model. Gemma 4 E4B measured roughly twice as fast on this machine (see "Why this default model"), but no laptop and no VM run has used it yet. Most of a cold turn is processing pi's system prompt.
- **An anon account's wherever interface in a browser.** The route answers 200 with the UI's HTML through Caddy and the socket; no browser session was driven through it, and no agent session was run inside it.
- **The installer's interactive TUI** with the new group (only the unattended route was run).

## Next

- Converge the my-boxes fleet onto these building blocks, so telemaque and nono run one copy (see the note in that repo). The rename is mechanical; what needs care is the fleet-only halves (the challenge engines, the mesh dispatcher).
- A larger default model where the machine has the memory (a mixture-of-experts model with few active parameters runs at small-model speed on a CPU).
- Offer reaching an anon interface from another device as an explicit, separate choice rather than by widening the loopback bind.
