# rapl-pl1-restore

On the ThinkPad P16 Gen 2 (21FA), the firmware lowers the CPU package
long-term power limit (PL1) from 157 W to 55 W after the package stays above
about 92 °C for roughly 30 seconds. It does not raise the limit again, even
after the CPU cools down.

`rapl-pl1-restore` reads
`/sys/class/powercap/intel-rapl-mmio:0/constraint_0_power_limit_uw` every 5
seconds. When AC power is connected and the value is below the target, it
switches the power profile to another one and back with `powerprofilesctl`,
which makes the firmware re-apply the limits for the current profile. If PL1
is still below the target after the switch, it writes the target to the limit
file directly. On battery it does nothing.

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

## Logs

```
journalctl -u rapl-pl1-restore
```

Each restore logs the lowered value, whether it wrote the limit directly, and
the value afterward.

## Tests

Run `./test.sh`. It runs the script against fake sysfs files and a fake
`powerprofilesctl`.
