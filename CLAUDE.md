# Voices

## Logging

All logs go to the shared Claw Control log server via WebSocket. Every app across all devices and branches writes to the same file.

| What | Where |
|------|-------|
| Log server | `ws://felixs-macbook-pro.tailcfdca5.ts.net:9998` |
| Log file | `~/clawcontraw.log` (JSONL, shared across all apps) |

**Finding your logs:** Filter by `device` name to isolate logs from a specific phone/branch.
```bash
# Logs from Felix's iPhone
grep '"device":"Felix'"'"'s iPhone"' ~/clawcontraw.log

# Logs from the device named "iPhone"
grep '"device":"iPhone"' ~/clawcontraw.log

# Live tail for a specific device
tail -f ~/clawcontraw.log | grep --line-buffered '"device":"iPhone"'
```

**API:** `log("message")` and `logError("message")` — sends device name, file, function, message as JSONL.

**Rule:** All logs and error messages in this app MUST go through `log()` and `logError()`. Never use `print()`, `debugPrint()`, or `NSLog()` — they are invisible on device. The WebSocket log is the only way to see what the app is doing.

**Requires:** Tailscale VPN on the iPhone and `NSAllowsArbitraryLoads` in `Info.plist` for `ws://` connections.
