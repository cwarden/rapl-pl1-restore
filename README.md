# rapl-pl1-restore

On the ThinkPad P16 Gen 2 (21FA), the firmware lowers the CPU package
long-term power limit (PL1) from 157 W to 55 W after the package stays above
about 92 °C for roughly 30 seconds. It does not raise the limit again, even
after the CPU cools down.

At startup, `rapl-pl1-restore` writes the DPTF passive policy UUID
(`42A441D6-AE6A-462b-A84B-4A8CE79027D3`) to
`/sys/bus/platform/devices/INTC10A0:00/uuids/current_uuid`. The int3400
driver then calls `_OSC` to tell the firmware that the OS handles passive
cooling. With the policy selected, the firmware left PL1 at 157 W while the
package stayed at 98–100 °C for about 50 seconds (tested on 2026-10-12); the
CPU's own thermal limit at about 100 °C reduced clock speed instead. With no
policy selected, `current_uuid` reads `INVALID`. Disabling the INT3400 thermal
zone, or exiting thermald, clears the policy.

The script then reads
`/sys/class/powercap/intel-rapl-mmio:0/constraint_0_power_limit_uw` every 5
seconds. When AC power is connected and the value is below the target, it
selects the passive policy again, because the driver does not call `_OSC`
again after resume and `current_uuid` shows the driver's saved value rather
than the firmware's. It then switches the power profile to another one and
back with `powerprofilesctl`, which makes the firmware re-apply the limits for
the current profile. If PL1 is still below the target after the switch, it
writes the target to the limit file directly. On battery it does nothing.

The firmware behaves in one of two ways after it lowers PL1:

- It re-applies the profile's limits on a profile switch, and it writes its
  own value back within about 7 seconds of a direct write to the limit file.
- It ignores profile switches, and it keeps a value written directly to the
  limit file. On 2026-10-11 the firmware (BIOS N3TET64W) behaved this way
  from 14:21 onward, with the CPU at 77–97 °C.

## Install

```
sudo install -m 755 rapl-pl1-restore /usr/local/sbin/
sudo install -m 644 rapl-pl1-restore.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now rapl-pl1-restore
```

## Configuration

Set these environment variables in the unit (`systemctl edit rapl-pl1-restore`):

| Variable | Default |
|---|---|
| `RAPL_PL1_UW` | `157000000` (a lower value triggers a profile switch) |
| `RAPL_INTERVAL` | `5` (seconds) |
| `RAPL_ZONE` | `/sys/class/powercap/intel-rapl-mmio:0` |
| `RAPL_AC_ONLINE` | `/sys/class/power_supply/AC/online` |
| `RAPL_POLICY` | `/sys/bus/platform/devices/INTC10A0:00/uuids/current_uuid` (skipped if missing) |

## Logs

```
journalctl -u rapl-pl1-restore
```

Each policy selection logs `Selecting DPTF passive policy`. Each restore logs
the lowered value, whether it wrote the limit directly, and the value
afterward.

## Tests

Run `./test.sh`. It runs the script against fake sysfs files, including a fake
`current_uuid`, and a fake `powerprofilesctl`.
