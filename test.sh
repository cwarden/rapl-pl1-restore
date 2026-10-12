#!/bin/sh
# Run rapl-pl1-restore against fake sysfs files and a fake powerprofilesctl.
# The fake powerprofilesctl writes 157 W to the limit file when the profile is
# set back to performance, as the firmware does, unless setup is given
# "ignore" as its third argument. The fake current_uuid file starts with the
# passive policy selected unless setup is given "INVALID" as its fourth
# argument.
set -u

dir=$(dirname "$(readlink -f "$0")")
fail=0
passive=42A441D6-AE6A-462b-A84B-4A8CE79027D3

run() {
	RAPL_ZONE=$tmp RAPL_AC_ONLINE=$tmp/ac RAPL_POLICY=$tmp/current_uuid \
		RAPL_INTERVAL=1 PATH=$tmp/bin:$PATH \
		timeout 2 "$dir/rapl-pl1-restore" > "$tmp/out" 2>&1
}

setup() {
	tmp=$(mktemp -d)
	mkdir "$tmp/bin"
	echo "$1" > "$tmp/constraint_0_power_limit_uw"
	echo "$2" > "$tmp/ac"
	echo "${4:-$passive}" > "$tmp/current_uuid"
	restore=true
	[ "${3:-}" = ignore ] && restore=false
	cat > "$tmp/bin/powerprofilesctl" <<-EOF
	#!/bin/sh
	echo "\$*" >> "$tmp/calls"
	[ "\$1" = get ] && echo performance
	[ "\$*" = "set performance" ] && $restore && echo 157000000 > "$tmp/constraint_0_power_limit_uw"
	exit 0
	EOF
	chmod +x "$tmp/bin/powerprofilesctl"
}

check() {
	if [ "$2" = "$3" ]; then
		echo "ok: $1"
	else
		echo "FAIL: $1: expected '$3', got '$2'"
		fail=1
	fi
}

setup 55000000 1
run
check "switches_profile_away_and_back_when_pl1_is_lowered" "$(cat "$tmp/calls")" "get
set balanced
set performance"
check "restores_pl1_on_ac" "$(cat "$tmp/constraint_0_power_limit_uw")" 157000000
check "logs_the_lowered_and_restored_values" "$(cat "$tmp/out")" "Selecting DPTF passive policy
PL1 is 55000000 uW; switching power profile
PL1 is now 157000000 uW"
rm -rf "$tmp"

setup 55000000 1 ignore
run
check "writes_pl1_directly_when_profile_switch_does_not_restore_it" "$(cat "$tmp/constraint_0_power_limit_uw")" 157000000
check "logs_the_direct_write" "$(cat "$tmp/out")" "Selecting DPTF passive policy
PL1 is 55000000 uW; switching power profile
PL1 is still 55000000 uW; writing 157000000 uW
PL1 is now 157000000 uW"
rm -rf "$tmp"

setup 55000000 0
run
check "leaves_pl1_alone_on_battery" "$(cat "$tmp/calls" 2>/dev/null)" ""
rm -rf "$tmp"

setup 157000000 1
run
check "does_nothing_when_pl1_is_at_target" "$(cat "$tmp/calls" 2>/dev/null)" ""
rm -rf "$tmp"

setup 157000000 1 restore INVALID
run
check "selects_passive_policy_at_start" "$(cat "$tmp/current_uuid")" "$passive"
check "logs_the_policy_selection" "$(cat "$tmp/out")" "Selecting DPTF passive policy"
rm -rf "$tmp"

setup 157000000 1
run
check "leaves_selected_policy_alone_when_pl1_is_at_target" "$(cat "$tmp/out")" ""
rm -rf "$tmp"

setup 157000000 1
rm "$tmp/current_uuid"
run
check "runs_without_the_int3400_device" "$(cat "$tmp/out")" ""
rm -rf "$tmp"

exit $fail
