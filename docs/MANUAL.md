# Claude Network Lock — Manual

> **A macOS tool that ensures Claude Code connects to the internet exclusively through a single, verified proxy port — providing a stable, consistent network exit.**

---

## Table of Contents

- [Overview](#overview)
- [Why This Exists](#why-this-exists)
- [Quick Start](#quick-start)
- [How It Works](#how-it-works)
  - [Architecture Diagram](#architecture-diagram)
  - [Layer 1: Pre-flight Launcher](#layer-1-pre-flight-launcher-claude-locked)
  - [Layer 2: Seatbelt Process Sandbox](#layer-2-seatbelt-process-sandbox)
  - [Layer 3: Proxy Chain + LuLu Firewall](#layer-3-proxy-chain--lulu-firewall)
- [Configuration](#configuration)
  - [Config File Reference](#config-file-reference)
  - [Local Development Ports](#local-development-ports)
  - [Environment Variables](#environment-variables)
- [Self-Test](#self-test)
- [OAuth Login](#oauth-login)
- [Updating Claude Code](#updating-claude-code)
- [Proxy Client Setup](#proxy-client-setup)
- [Uninstallation](#uninstallation)
- [Troubleshooting](#troubleshooting)
- [FAQ](#faq)
- [Limitations](#limitations)
- [Disclaimer](#disclaimer)

---

## Overview

Claude Network Lock is a **fail-closed network constraint system** for macOS. It wraps the official Claude Code CLI in three independent layers of enforcement so that every outbound connection from Claude (and all of its child processes) must traverse a single, pre-verified local proxy port — or the process is not allowed to start at all.

**What it does:**
- Pins the Claude binary by path, SHA-256 hash, and macOS code signature
- Verifies the exit IP matches a pre-recorded fingerprint before every launch
- Sandboxes Claude and all child processes so they can only reach `localhost:<port>`
- Blocks `open`, `osascript`, and LaunchServices to prevent browser auto-open
- Injects proxy environment variables and disables auto-update and telemetry
- Provides a built-in self-test to actively verify all restrictions are working

**What it does NOT do:**
- Modify Claude Code itself
- Guarantee that an account will never be flagged
- Control browsers, IDE plugins, or other entry points to Claude services

---

## Why This Exists

If you access Claude Code from a network environment where your public exit IP can change unexpectedly — due to proxy rotation, ISP reassignment, VPN reconnects, or load-balanced proxy pools — you risk presenting inconsistent network fingerprints to the service. This tool ensures that Claude Code **always** exits through the same fixed IP, or refuses to run.

> **Note:** This project is about network stability and consistency. It is not a tool for bypassing bans, evading detection, or violating any terms of service. Users are responsible for complying with Anthropic's Terms of Service, local laws, and their organization's security policies.

---

## Quick Start

### Prerequisites

| Requirement | Details |
|---|---|
| **OS** | macOS (must have `/usr/bin/sandbox-exec` available) |
| **Claude Code** | Official CLI, installed and working |
| **Proxy client** | A local proxy client with a dedicated listener on a fixed port |
| **Fixed exit** | A stable, compliant upstream proxy or node that you control |
| **LuLu** (recommended) | [LuLu firewall](https://objective-see.org/products/lulu.html) as an insurance layer |
| **Shell tools** | `zsh`, `curl`, `nc`, `codesign`, `shasum` (all ship with macOS) |

### Step 1: Configure Your Proxy Client

Using your own proxy tool, set up a **dedicated** proxy listener on port `7899` (or your chosen port) that is hard-wired to a single fixed upstream node. The critical requirements:

- Listens on `127.0.0.1` only (never `0.0.0.0`)
- Bound directly to a fixed node — does not follow global selection
- No `DIRECT`, no auto-select, no load-balancing, no failover
- If the upstream dies, the port must fail closed (refuse connections, not fall back)

Please refer to your proxy tool's own documentation for how to configure a dedicated listener port.

Verify the port and exit IP:

```zsh
# Confirm the port is listening
lsof -nP -iTCP:7899 -sTCP:LISTEN

# Query exit IP through the dedicated port (both must return the same IP)
curl --fail --proxy http://127.0.0.1:7899 https://api.ipify.org
curl --fail --proxy http://127.0.0.1:7899 https://ifconfig.me/ip
```

### Step 2: Install the Network Lock

```zsh
chmod +x scripts/install.zsh
./scripts/install.zsh --proxy-port 7899
```

The installer will:

1. Locate the real `claude` binary (resolving symlinks)
2. Read and pin its code signature (Identifier + TeamIdentifier) and SHA-256 hash
3. Perform dual-source exit IP verification through your proxy
4. Store only the SHA-256 of the exit IP (never the plaintext IP)
5. Install the launcher to `~/.local/bin/claude-locked`
6. Write a config file at `~/.config/claude-network-lock/config` with mode `600`

For fully automated / non-interactive installation:

```zsh
./scripts/install.zsh \
  --proxy-port 7899 \
  --claude-bin /path/to/real/claude \
  --expected-ip 203.0.113.10 \
  --yes
```

> **Note:** `203.0.113.10` is an [RFC 5737](https://datatracker.ietf.org/doc/html/rfc5737) documentation address. Replace it with your actual exit IP.

### Step 3: Self-Test and Launch

If `~/.local/bin` is not in your `PATH`:

```zsh
export PATH="$HOME/.local/bin:$PATH"
```

Run the full self-test:

```zsh
claude-locked --lock-self-test
```

If the self-test passes, start Claude Code normally:

```zsh
claude-locked
```

Optionally, create a convenience alias (do not shadow the real `claude` command):

```zsh
# Add to ~/.zshrc
alias claude-safe="$HOME/.local/bin/claude-locked"
```

---

## How It Works

### Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│                     claude-locked launcher                       │
│                                                                  │
│  ┌─ Pre-flight checks (Layer 1) ───────────────────────────┐    │
│  │  1. Binary path + SHA-256 hash                          │    │
│  │  2. macOS code signature (Identifier + TeamIdentifier)  │    │
│  │  3. Proxy port 7899 is listening                        │    │
│  │  4. Dual-source exit IP query (ipify + ifconfig.me)     │    │
│  │  5. Exit IP SHA-256 matches stored fingerprint          │    │
│  │  ANY check fails ──> REFUSE TO LAUNCH                   │    │
│  └──────────────────────────────────────────────────────────┘    │
│                              │                                   │
│                         All passed                               │
│                              │                                   │
│  ┌─ Inject environment ─────┴──────────────────────────────┐    │
│  │  http_proxy / HTTP_PROXY = http://127.0.0.1:7899        │    │
│  │  DISABLE_AUTOUPDATER = 1                                │    │
│  │  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = 1           │    │
│  │  DISABLE_TELEMETRY = 1                                  │    │
│  └──────────────────────────────────────────────────────────┘    │
│                              │                                   │
│  ┌─ Seatbelt sandbox (Layer 2) ────────────────────────────┐    │
│  │  (deny  network-outbound)           ← default deny all  │    │
│  │  (allow network-outbound localhost:7899)  ← proxy only   │    │
│  │  (deny  process-exec "/usr/bin/open")                    │    │
│  │  (deny  process-exec "/usr/bin/osascript")               │    │
│  │  (deny  mach-lookup "com.apple.lsd.open*")              │    │
│  │  + optional local dev port allowlist                     │    │
│  └──────────────────────────────────────────────────────────┘    │
│                              │                                   │
│                     exec claude "$@"                             │
└──────────────────────────────┬───────────────────────────────────┘
                               │
              ┌────────────────▼─────────────────┐
              │  Claude Code (sandboxed process)  │
              │  + all child processes            │
              │  can ONLY reach localhost:7899    │
              └────────────────┬─────────────────┘
                               │
              ┌────────────────▼─────────────────┐
              │  Proxy client (Layer 3)           │
              │  127.0.0.1:7899                   │
              │  Fixed node ─── no fallback       │
              │  Upstream dies ──> connection fail │
              └────────────────┬─────────────────┘
                               │
              ┌────────────────▼─────────────────┐
              │  LuLu firewall (insurance)        │
              │  Only allows Claude ──> 7899      │
              │  + whitelisted local dev ports    │
              └────────────────┬─────────────────┘
                               │
                         Fixed exit IP
```

### Layer 1: Pre-flight Launcher (`claude-locked`)

Before Claude Code starts, the launcher performs a strict sequence of checks. If **any** check fails, launch is refused (fail-closed).

| # | Check | What It Verifies |
|---|---|---|
| 1 | **Binary path** | `PINNED_CLAUDE_BIN` exists and is executable |
| 2 | **SHA-256 hash** | File hash matches the value recorded at install time |
| 3 | **Code signature** | `codesign` output contains the expected `Identifier` and `TeamIdentifier` |
| 4 | **Proxy port** | `nc -z 127.0.0.1:7899` confirms the port is listening |
| 5 | **Dual-source exit IP** | Two independent IP services (`api.ipify.org` and `ifconfig.me`) queried through the proxy; results must match |
| 6 | **Exit fingerprint** | SHA-256 of the actual exit IP must equal the stored `EXPECTED_IP_SHA256` |

> **Warning:** The exit IP is **never** stored in plaintext. Only its SHA-256 hash is saved in the config file. This means the config file alone cannot reveal your exit IP.

After all checks pass, the launcher:

1. Injects proxy environment variables in both cases (`http_proxy` + `HTTP_PROXY`, etc.)
2. Sets `no_proxy=localhost,127.0.0.1,::1`
3. Sets `DISABLE_AUTOUPDATER=1` to prevent binary self-modification
4. Sets `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` and `DISABLE_TELEMETRY=1`
5. Launches Claude under the Seatbelt sandbox via `exec`

### Layer 2: Seatbelt Process Sandbox

macOS `sandbox-exec` enforces a kernel-level policy on Claude and **all of its child processes**:

```scheme
(version 1)
(allow default)

; Block ALL outbound network by default
(deny network-outbound)

; Allow ONLY the dedicated proxy port
(allow network-outbound (remote ip "localhost:7899"))

; Prevent auto-opening browser (OAuth, links, etc.)
(deny process-exec (literal "/usr/bin/open"))
(deny process-exec (literal "/usr/bin/osascript"))
(deny mach-lookup (global-name "com.apple.lsd.open"))
(deny mach-lookup (global-name "com.apple.lsd.openurl"))
```

Key properties of this sandbox:

- **Default deny for network** — even if Claude discovers another proxy or tries a direct connection, the kernel blocks it
- **Child process inheritance** — subprocesses spawned by Claude (Node.js workers, shell commands, etc.) inherit the same sandbox
- **Browser prevention** — blocking `open`, `osascript`, and LaunchServices `mach-lookup` prevents Claude from auto-opening URLs in the system browser
- **Additional local ports** — if configured in `local-ports`, corresponding `(allow network-outbound (remote ip "localhost:<port>"))` rules are appended

### Layer 3: Proxy Chain + LuLu Firewall

The third layer is your proxy client configuration and (optionally) the LuLu firewall:

**Proxy client requirements:**
- A dedicated listener on `127.0.0.1:7899` with a **fixed** upstream node
- No auto-select, no fallback, no load-balancing, no `DIRECT`
- If the upstream node goes down, port 7899 must **fail closed** — refuse connections rather than falling back to another route

**LuLu firewall (recommended insurance):**
- Configure LuLu to only allow the Claude process to connect to `127.0.0.1:7899`
- Optionally whitelist any local development ports you need
- This acts as a defense-in-depth layer — if the Seatbelt sandbox were somehow bypassed, LuLu would still block unauthorized connections

### Defense in Depth

```
   Threat                      Layer 1    Layer 2    Layer 3
   ─────────────────────────   ────────   ────────   ────────
   Binary tampered/swapped     BLOCKED      -          -
   Exit IP changed             BLOCKED      -          -
   Proxy port not running      BLOCKED      -          -
   Direct internet attempt       -        BLOCKED    BLOCKED
   Connect to wrong proxy        -        BLOCKED    BLOCKED
   Child process direct conn     -        BLOCKED    BLOCKED
   Auto-open browser (OAuth)     -        BLOCKED      -
   osascript abuse               -        BLOCKED      -
   Proxy fallback to DIRECT      -          -        BLOCKED*
```

_* "BLOCKED" for the proxy layer means the proxy itself must be configured to fail closed. The network lock cannot enforce this from outside the proxy — you must verify this during setup._

---

## Configuration

### Config File Reference

The config file lives at `~/.config/claude-network-lock/config` with permission mode `600`. It is generated by the installer and should not be edited manually under normal circumstances.

| Key | Description | Example |
|---|---|---|
| `CONFIG_VERSION` | Config format version (currently `1`) | `1` |
| `PROXY_HOST` | Proxy listen address (always `127.0.0.1`) | `127.0.0.1` |
| `PROXY_PORT` | Dedicated proxy port | `7899` |
| `EXPECTED_IP_SHA256` | SHA-256 hash of the expected exit IP | `a1b2c3d4...` (64 hex chars) |
| `PINNED_CLAUDE_BIN` | Absolute path to the pinned Claude binary | `~/.local/bin/claude` |
| `PINNED_IDENTIFIER` | `codesign` Identifier of the Claude binary | `com.anthropic.claude-code` |
| `PINNED_TEAM_ID` | `codesign` TeamIdentifier of the Claude binary | `ABCDE12345` |
| `PINNED_SHA256` | SHA-256 file hash of the Claude binary | `f6e5d4c3...` (64 hex chars) |

### Local Development Ports

By default, no localhost ports other than the proxy port are accessible to Claude. If Claude Code needs to reach a local development server (e.g., a web server on port 3000), add the port to:

```
~/.config/claude-network-lock/local-ports
```

Format: one port number per line. Comments (lines starting with `#`) and blank lines are ignored.

```text
# Local web dev server
3000
# API server
8080
```

> **Warning:** Never add HTTP/SOCKS proxy ports, arbitrary forwarders, or untrusted services to this whitelist. Any whitelisted port becomes a potential path around the fixed exit. After modifying this file, always re-run the self-test.

### Environment Variables

The following environment variables can override default paths:

| Variable | Default | Purpose |
|---|---|---|
| `CLAUDE_NETWORK_LOCK_CONFIG_DIR` | `~/.config/claude-network-lock` | Config directory location |
| `CLAUDE_NETWORK_LOCK_BIN_DIR` | `~/.local/bin` | Launcher install directory |
| `IP_CHECK_URL_ONE` | `https://api.ipify.org` | First IP check service |
| `IP_CHECK_URL_TWO` | `https://ifconfig.me/ip` | Second IP check service |

---

## Self-Test

The `--lock-self-test` flag runs an active verification suite that confirms all three layers are working:

```zsh
claude-locked --lock-self-test
```

The self-test performs all Layer 1 pre-flight checks, then additionally verifies:

| Test | Expected Result |
|---|---|
| Proxy port reachable through sandbox | Connection succeeds |
| Direct internet (1.1.1.1:443) from sandbox | Connection **blocked** |
| Child process direct internet | Connection **blocked** |
| `/usr/bin/open` from sandbox | Execution **blocked** |
| `/usr/bin/osascript` from sandbox | Execution **blocked** |

If all tests pass:

```
[Claude Network Lock] Self-test passed: Claude identity, file, fixed exit, and Seatbelt all match expectations
```

> **Note:** Run the self-test after every installation, Claude Code update, proxy configuration change, or modification to `local-ports`.

---

## OAuth Login

Claude Code's OAuth flow normally auto-opens a browser. The network lock blocks this behavior (via Seatbelt denial of `open` and LaunchServices).

To log in:

```zsh
claude-locked auth login
```

1. Claude will display an OAuth URL in the terminal
2. **Manually copy** this URL
3. Open it in a browser that is **also configured to use the same fixed proxy exit** (port 7899 or equivalent)
4. Complete the login flow in the browser
5. Return to the terminal

> **Warning:** The browser is **not** covered by the network lock's Seatbelt sandbox. You must independently ensure that the browser you use for OAuth exits through the same IP as Claude Code. Configure your browser to use `http://127.0.0.1:7899` as its proxy, or use a browser profile dedicated to this purpose.

---

## Updating Claude Code

When Claude Code updates, its binary path, SHA-256 hash, or code signature may change. The network lock will **refuse to launch** (by design) because the pinned values no longer match.

To update the lock after a Claude Code update:

```zsh
# Verify the new version comes from a trusted source, then:
./scripts/install.zsh --proxy-port 7899

# Run the self-test with the new binary
claude-locked --lock-self-test
```

The installer automatically backs up the previous config before writing a new one. It will never silently trust a new binary.

> **Note:** `DISABLE_AUTOUPDATER=1` is set in the environment to prevent Claude from auto-updating while running under the lock. This ensures the binary does not change out from under a running session.

---

## Proxy Client Setup

Use your own proxy tool to configure a dedicated listener port for Claude Network Lock. Refer to your tool's documentation for specific setup instructions.

Regardless of which tool you use, the proxy configuration must satisfy these invariants:

1. **Dedicated listener** on `127.0.0.1:<port>` (never `0.0.0.0`)
2. **Fixed node binding** — the listener's upstream is a single, specific node; it does not follow "global selection"
3. **No fallback** — no `DIRECT`, no auto-speed-test, no load-balancing, no backup nodes
4. **Fail closed** — if the upstream node dies, connections through this port must fail, not reroute

### Verification Procedure

After setting up your proxy client, run these checks:

```zsh
# 1. Confirm port is listening on localhost only
lsof -nP -iTCP:7899 -sTCP:LISTEN
# Output should show 127.0.0.1:7899, NOT *:7899 or 0.0.0.0:7899

# 2. Query exit IP (both must return the same IP)
curl --fail --proxy http://127.0.0.1:7899 https://api.ipify.org
curl --fail --proxy http://127.0.0.1:7899 https://ifconfig.me/ip

# 3. Switch your daily/global proxy node, then re-query — 7899 must not change
curl --fail --proxy http://127.0.0.1:7899 https://api.ipify.org

# 4. Kill the fixed upstream node, then verify 7899 fails (not reroutes)
curl --fail --proxy http://127.0.0.1:7899 https://api.ipify.org
# Expected: connection failure, NOT a different IP

# 5. Restore the upstream node and confirm the original IP is back
curl --fail --proxy http://127.0.0.1:7899 https://api.ipify.org
```

---

## Uninstallation

Remove the launcher only (preserves config for easy reinstallation):

```zsh
./scripts/uninstall.zsh
```

Remove the launcher and all configuration:

```zsh
./scripts/uninstall.zsh --purge-config
```

After uninstalling, the original `claude` command continues to work as before — the network lock never modifies it.

---

## Troubleshooting

### Launch refuses: "proxy port not listening"

The proxy client is not running, or the dedicated listener on the expected port is not configured.

```zsh
# Check what is listening on the port
lsof -nP -iTCP:7899 -sTCP:LISTEN
```

Start your proxy client and ensure the dedicated listener is active.

### Launch refuses: "exit IP fingerprint mismatch"

Your exit IP has changed since installation. Possible causes:
- The proxy upstream node changed or was rotated
- The proxy client fell back to a different route
- The upstream server's public IP changed

Verify your current exit:

```zsh
curl --fail --proxy http://127.0.0.1:7899 https://api.ipify.org
```

If the IP intentionally changed (e.g., you switched to a new server), re-run the installer:

```zsh
./scripts/install.zsh --proxy-port 7899
```

### Launch refuses: "Claude file has changed"

Claude Code was updated, reinstalled, or the binary was otherwise modified. Re-run the installer after verifying the new binary is legitimate:

```zsh
./scripts/install.zsh --proxy-port 7899
claude-locked --lock-self-test
```

### Launch refuses: "code signature mismatch"

The Claude binary's code signature does not match what was recorded. This could indicate an update, a different build, or tampering. Verify the binary manually:

```zsh
codesign -dv --verbose=2 $(which claude)
```

If it looks legitimate, re-run the installer.

### Self-test fails: "Seatbelt incorrectly allowed direct connection"

The macOS sandbox is not enforcing network restrictions. Possible causes:
- SIP (System Integrity Protection) is disabled — `sandbox-exec` may not enforce properly
- The macOS version no longer supports `sandbox-exec`

Check SIP status:

```zsh
csrutil status
```

### Self-test fails: "Seatbelt incorrectly allowed open/osascript"

Similar to above — verify SIP is enabled and `sandbox-exec` is functional.

### Claude cannot reach local dev server

Add the port to `~/.config/claude-network-lock/local-ports`:

```text
3000
```

Then re-run the self-test:

```zsh
claude-locked --lock-self-test
```

### Two IP check services return different results

This usually means the proxy is not consistently routing through the same exit. Check your proxy configuration — the dedicated listener may be following global selection instead of being pinned to a fixed node.

---

## FAQ

**Q: Does this work on Linux or Windows?**
No. It relies on macOS-specific features: `sandbox-exec` (Seatbelt), `codesign`, and the macOS LaunchServices Mach interface. There is no Linux or Windows equivalent in this project.

**Q: Why port 7899 specifically?**
7899 is just the default used in examples. You can use any available port by passing `--proxy-port <port>` to the installer. The important thing is that this port is dedicated to Claude and not shared with your daily browsing proxy.

**Q: Why not just use the system proxy?**
A system-wide proxy (e.g., on port 7897) typically follows auto-select rules, has fallback to DIRECT, and may load-balance across nodes. None of these properties are acceptable for a fixed exit. The dedicated port ensures Claude's traffic is isolated from your daily proxy configuration changes.

**Q: Can Claude still function normally under the lock?**
Yes. Claude Code communicates with Anthropic's API servers over HTTPS. As long as the proxy is running and the upstream is healthy, Claude operates normally. The only behavioral change is that browser auto-open is blocked (you must copy OAuth URLs manually).

**Q: What happens if my proxy goes down while Claude is running?**
Claude's network requests will fail until the proxy recovers. This is the intended behavior — fail closed rather than fall back to an uncontrolled route.

**Q: Is the exit IP stored in plaintext anywhere?**
No. The installer computes `SHA-256(exit_ip)` and stores only the hash. The config file, the launcher script, and log output all avoid recording the plaintext IP. The launcher masks the IP in its startup message (e.g., `203.0.x.x`).

**Q: Does this prevent Anthropic from seeing my real IP?**
No. Anthropic sees whatever IP your proxy's upstream presents. This tool ensures that IP is always the **same** one — it does not anonymize or hide it.

**Q: Why block `open` and `osascript`?**
Claude Code may attempt to open URLs in the default browser (e.g., during OAuth). The browser is outside the Seatbelt sandbox and might use a different network route. Blocking these commands forces the user to manually open URLs in a browser that is also configured for the fixed exit.

**Q: What is LuLu and is it required?**
[LuLu](https://objective-see.org/products/lulu.html) is a free, open-source macOS firewall by Objective-See. It is recommended as a defense-in-depth layer but is not strictly required — the Seatbelt sandbox provides the primary network enforcement. LuLu adds insurance in case of edge cases or future macOS changes to sandbox behavior.

**Q: Will Apple remove `sandbox-exec` in a future macOS version?**
`sandbox-exec` has been marked as deprecated since macOS 10.15 but continues to function as of the latest macOS versions (including macOS Sequoia). If Apple removes it, this tool will cease to provide Layer 2 protection. Monitor macOS release notes and test after major OS upgrades.

---

## Limitations

1. **macOS only** — relies on `sandbox-exec`, `codesign`, and Mach IPC
2. **`sandbox-exec` is deprecated** — Apple may remove it in a future macOS version
3. **Cannot control the proxy client itself** — if the proxy client has a bug or misconfigured fallback, traffic could exit through an unintended route; the network lock cannot detect this from outside the proxy
4. **Does not cover browsers or other Claude entry points** — only the Claude Code CLI process tree is sandboxed
5. **IP check services are external dependencies** — if both `api.ipify.org` and `ifconfig.me` are down or return incorrect results, launch will fail
6. **Cannot undo server-side state** — if previous sessions used a different IP, the network lock cannot change what the platform has already recorded
7. **Local user account compromise** — malware running as your user can modify the config, proxy, or replace the launcher
8. **Whitelisted local ports** — any port in `local-ports` is a potential bypass path if an untrusted service runs on it

---

## Disclaimer

This project is **not affiliated with, endorsed by, or associated with Anthropic** in any way. It is an independent, open-source tool.

The authors make no guarantees about account safety, platform compliance, or fitness for any particular purpose. Users are solely responsible for:

- Complying with [Anthropic's Terms of Service](https://www.anthropic.com/terms)
- Complying with applicable local laws and regulations
- Ensuring their proxy infrastructure is legitimate and properly configured
- Understanding the security boundaries described in [SECURITY.md](../SECURITY.md)

Use at your own risk.

---

## License

MIT. See [LICENSE](../LICENSE).
