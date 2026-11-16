# Known issues

Problems found while running Denial on the Xiaomi Pad 5 that are not
shell-side bugs, recorded with the evidence gathered so they can be picked up
later.

## Android's adbd logs a failed connection every two seconds

- Found: 2026-11-16
- Component: `droidloom-image 0.1.0-35`, not this repository.

### Symptom

`droidloomctl logs` is flooded with two lines every two seconds; anything
else the Android side logs is pushed out of the buffer:

```
11-16 11:21:32.962 235 11069 I adbd: host-16: connection terminated: read failed
11-16 11:21:34.967 235 11071 I adbd: host-15: connection terminated: read failed
```

`host-15` and `host-16` alternate and the thread id grows each time, so every
line is a fresh connection that is closed straight away.

### Evidence

- The host's adb server (`adb -L tcp:5037 fork-server server`, one persistent
  socket to `10.177.0.2:5555`) issues a new `connect()` every two seconds:
  `strace -f -p <adb> -e connect` shows four of them in eight seconds.
- `strace -e read` on the same server shows the request that drives it:
  `host:connect:10.177.0.2:5555`.
- No host-side droidloom process asks for it: `strace -f -e connect` on
  `droidloomctl`, `droidloomd`, `droidloom-wayland`,
  `droidloom-applications` and `droidloom-supervisor` never touches 5555.
- Stopping `droidloom-applications` does not stop the lines.
- The Android image carries the caller: `services.jar` contains
  `host:connect`.
- It is not ADB over Wi-Fi: `settings get global adb_wifi_enabled` is `0`.
- There is no switch for it in `/etc/droidloom` (`runtime.env`, `cell.json`).

### Impact

Log noise and one TCP handshake every two seconds. CPU use is 0.0% and
nothing in the UI misbehaves.

### Next step

Find the component inside the droidloom image that reconnects on a two-second
timer and either reuse the existing transport or back the timer off. Needs the
droidloom sources; nothing to change in this repository.
