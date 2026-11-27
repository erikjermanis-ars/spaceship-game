#!/usr/bin/env bash
# Runs every headless check (the list in README "Test harness and checks") and prints one line per check.
#
#   tools/run_checks.sh                # all headless checks (~20 s)
#   tools/run_checks.sh ship onfoot    # only checks whose name contains one of these words
#   tools/run_checks.sh --audio        # also the windowed ship_audio_test (opens a window, needs audio)
#   GODOT=/path/to/Godot tools/run_checks.sh
#
# A check passes only if Godot exits 0, the output has the check's success line, and nothing printed
# an ERROR or WARNING. The success line matters: some checks print FAIL but still exit 0.
# Failing output is saved in $TMPDIR/meridian_checks/<name>.log. Exit status is 0 only if every check passed.

set -u
cd "$(dirname "$0")/.."

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
if [[ ! -x "$GODOT" ]]; then
	GODOT="$(command -v godot || command -v godot4 || true)"
fi
if [[ -z "$GODOT" ]]; then
	echo "Godot not found: set GODOT=/path/to/Godot" >&2
	exit 2
fi

TIMEOUT_S=180
LOG_DIR="${TMPDIR:-/tmp}"
LOG_DIR="${LOG_DIR%/}/meridian_checks"
mkdir -p "$LOG_DIR"

# name | scene | extra Godot args | success regex (extended grep)
CHECKS=(
	"smoke_main|res://scenes/main.tscn|--headless --quit-after 600|Godot Engine"
	"ship_physics|res://scenes/test/ship_physics_test.tscn|--headless --fixed-fps 120|^RESULT: PASS"
	"level_validate|res://scenes/test/level_validate.tscn|--headless --fixed-fps 120|^RESULT: OK"
	"gate_clearance|res://scenes/test/gate_clearance_check.tscn|--headless --fixed-fps 120|^RESULT: OK"
	"gameplay_race|res://scenes/test/gameplay_race_test.tscn|--headless --fixed-fps 120|^\[race-test\] PASS"
	"onfoot_flow|res://scenes/test/onfoot_flow_test.tscn|--headless --fixed-fps 120|^onfoot_flow_test: OK"
	"vehicles_flow|res://scenes/test/vehicles_flow_test.tscn|--headless --fixed-fps 120|^vehicles_flow_test: OK"
	"shuttle_flight|res://scenes/test/shuttle_flight_test.tscn|--headless --fixed-fps 120|^shuttle_flight_test: OK"
	"cargo_hold|res://scenes/test/cargo_hold_test.tscn|--headless --fixed-fps 120|^cargo_hold_test: OK"
	"frigate|res://scenes/test/frigate_test.tscn|--headless --fixed-fps 120|^frigate_test: OK"
	"frigate_flow|res://scenes/test/frigate_flow_test.tscn|--headless --fixed-fps 120|^frigate_flow_test: OK"
	"weapons|res://scenes/test/weapons_test.tscn|--headless --fixed-fps 120|^weapons_test: OK"
	"outpost|res://scenes/test/outpost_test.tscn|--headless --fixed-fps 120|^outpost_test: OK"
	"carrier_jump|res://scenes/test/carrier_jump_test.tscn|--headless --fixed-fps 120|^carrier_jump_test: OK"
)
AUDIO_CHECK="ship_audio|res://scenes/test/ship_audio_test.tscn|--fixed-fps 120|^ship_audio_test: OK"

filters=()
for arg in "$@"; do
	case "$arg" in
		--audio) CHECKS+=("$AUDIO_CHECK") ;;
		-h|--help) sed -n '2,11p' "$0"; exit 0 ;;
		*) filters+=("$arg") ;;
	esac
done

passed=0
failed=0
for entry in "${CHECKS[@]}"; do
	IFS='|' read -r name scene args ok_re <<<"$entry"
	if ((${#filters[@]})); then
		match=0
		for f in "${filters[@]}"; do [[ "$name" == *"$f"* ]] && match=1; done
		((match)) || continue
	fi
	log="$LOG_DIR/$name.log"
	start=$SECONDS
	# perl's alarm is a portable timeout (macOS has no `timeout`), in case a check hangs.
	# shellcheck disable=SC2086
	perl -e 'alarm shift; exec @ARGV' "$TIMEOUT_S" "$GODOT" --path . $args "$scene" >"$log" 2>&1
	rc=$?
	secs=$((SECONDS - start))
	why=""
	if ((rc != 0)); then
		why="exit code $rc"
		((rc == 142)) && why="timed out after ${TIMEOUT_S}s"
	elif grep -qE 'ERROR|WARNING' "$log"; then
		why="errors or warnings in output"
	elif ! grep -qE "$ok_re" "$log"; then
		why="no success line"
	fi
	if [[ -z "$why" ]]; then
		printf 'PASS  %-15s %3ds\n' "$name" "$secs"
		passed=$((passed + 1))
		rm -f "$log"
	else
		printf 'FAIL  %-15s %3ds  %s  (log: %s)\n' "$name" "$secs" "$why" "$log"
		grep -E 'FAIL|ERROR|WARNING' "$log" | head -8 | sed 's/^/        /'
		failed=$((failed + 1))
	fi
done

echo "$passed passed, $failed failed"
((failed == 0))
