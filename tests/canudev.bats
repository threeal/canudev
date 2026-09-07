#!/usr/bin/env bats

setup() {
  RULES_FILE="${BATS_TEST_TMPDIR}/99-canbus.rules"
  source "${BATS_TEST_DIRNAME}/../canudev.sh"
  set +euo pipefail
}

# parse_config_v1

@test "parse_config_v1 populates KERNELS_TO_NAME from the comment header" {
  local body="# canudev-config v1
# 1-2:1.0 can0
# 1-3:1.0 can1

SUBSYSTEM==\"net\""

  KERNELS_TO_NAME=()
  parse_config_v1 "$body"

  [ "${KERNELS_TO_NAME[1-2:1.0]}" = "can0" ]
  [ "${KERNELS_TO_NAME[1-3:1.0]}" = "can1" ]
}

@test "parse_config_v1 stops at the first non-comment line" {
  local body="# canudev-config v1
# 1-2:1.0 can0
SUBSYSTEM==\"net\"
# 1-3:1.0 can1"

  KERNELS_TO_NAME=()
  parse_config_v1 "$body"

  [ "${KERNELS_TO_NAME[1-2:1.0]}" = "can0" ]
  [ -z "${KERNELS_TO_NAME[1-3:1.0]+set}" ]
}

# read_rules_file

@test "read_rules_file returns an empty mapping when the rules file does not exist" {
  [ ! -f "$RULES_FILE" ]

  read_rules_file

  [ "${#KERNELS_TO_NAME[@]}" -eq 0 ]
}

@test "read_rules_file round-trips entries written by write_rules_file" {
  udevadm() { :; }

  KERNELS_TO_NAME=()
  KERNELS_TO_NAME["1-2:1.0"]="can0"
  KERNELS_TO_NAME["1-3:1.0"]="can1"
  write_rules_file

  KERNELS_TO_NAME=()
  read_rules_file

  [ "${KERNELS_TO_NAME[1-2:1.0]}" = "can0" ]
  [ "${KERNELS_TO_NAME[1-3:1.0]}" = "can1" ]
}

@test "read_rules_file discards entries when the hash has been tampered with" {
  udevadm() { :; }

  KERNELS_TO_NAME=()
  KERNELS_TO_NAME["1-2:1.0"]="can0"
  write_rules_file

  echo "# tampered" >>"$RULES_FILE"

  read_rules_file 2>"${BATS_TEST_TMPDIR}/stderr.log"

  grep -q "was modified outside canudev" "${BATS_TEST_TMPDIR}/stderr.log"
  [ "${#KERNELS_TO_NAME[@]}" -eq 0 ]
}

@test "read_rules_file discards entries when the version marker is missing" {
  local body="not a version marker"$'\n'
  local hash
  hash=$(printf '%s' "$body" | sha256sum | cut -d' ' -f1)
  {
    printf '# canudev:sha256:%s\n' "$hash"
    printf '%s' "$body"
  } >"$RULES_FILE"

  read_rules_file 2>"${BATS_TEST_TMPDIR}/stderr.log"

  grep -q "no recognizable config version marker" "${BATS_TEST_TMPDIR}/stderr.log"
  [ "${#KERNELS_TO_NAME[@]}" -eq 0 ]
}

@test "read_rules_file discards entries for an unrecognized config version" {
  local body="# canudev-config v99"$'\n'
  local hash
  hash=$(printf '%s' "$body" | sha256sum | cut -d' ' -f1)
  {
    printf '# canudev:sha256:%s\n' "$hash"
    printf '%s' "$body"
  } >"$RULES_FILE"

  read_rules_file 2>"${BATS_TEST_TMPDIR}/stderr.log"

  grep -q "config version 99" "${BATS_TEST_TMPDIR}/stderr.log"
  [ "${#KERNELS_TO_NAME[@]}" -eq 0 ]
}

# write_rules_file

@test "write_rules_file writes a self-verifying hash header and reloads udev" {
  udevadm() { echo "udevadm $*" >>"${BATS_TEST_TMPDIR}/udevadm.log"; }

  KERNELS_TO_NAME=()
  KERNELS_TO_NAME["1-2:1.0"]="can0"
  write_rules_file

  [ -f "$RULES_FILE" ]

  local hash_line body expected_hash actual_hash
  hash_line=$(head -n 1 "$RULES_FILE")
  body=$(tail -n +2 "$RULES_FILE")
  expected_hash=${hash_line#"# canudev:sha256:"}
  actual_hash=$(printf '%s\n' "$body" | sha256sum | cut -d' ' -f1)
  [ "$expected_hash" = "$actual_hash" ]

  grep -q '# 1-2:1.0 can0' "$RULES_FILE"
  grep -q 'KERNELS=="1-2:1.0"' "$RULES_FILE"
  grep -q 'NAME="can0"' "$RULES_FILE"

  grep -q '^udevadm control --reload-rules$' "${BATS_TEST_TMPDIR}/udevadm.log"
  grep -q '^udevadm trigger$' "${BATS_TEST_TMPDIR}/udevadm.log"
}

# apply_interface_state

@test "apply_interface_state renames, brings the interface down, then up with the bitrate" {
  ip() { echo "ip $*" >>"${BATS_TEST_TMPDIR}/ip.log"; }
  BITRATE=500000

  apply_interface_state "can0" "front-can"

  cat <<EOF >"${BATS_TEST_TMPDIR}/ip.expected"
ip link set can0 down
ip link set can0 name front-can
ip link set front-can up type can bitrate 500000
EOF

  diff "${BATS_TEST_TMPDIR}/ip.expected" "${BATS_TEST_TMPDIR}/ip.log"
}

@test "apply_interface_state skips the rename when the name is unchanged" {
  ip() { echo "ip $*" >>"${BATS_TEST_TMPDIR}/ip.log"; }
  BITRATE=500000

  apply_interface_state "can0" "can0"

  cat <<EOF >"${BATS_TEST_TMPDIR}/ip.expected"
ip link set can0 down
ip link set can0 up type can bitrate 500000
EOF

  diff "${BATS_TEST_TMPDIR}/ip.expected" "${BATS_TEST_TMPDIR}/ip.log"
}

# list_can_interfaces

@test "list_can_interfaces prints just the interface names" {
  ip() {
    printf '%s\n' \
      '3: can0: <NOARP,UP,LOWER_UP> mtu 16 qdisc pfifo_fast state UP mode DEFAULT group default qlen 10' \
      '5: can1: <NOARP> mtu 16 qdisc noop state DOWN mode DEFAULT group default qlen 10'
  }

  run list_can_interfaces
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "can0" ]
  [ "${lines[1]}" = "can1" ]
}

@test "list_can_interfaces prints nothing when there are no CAN interfaces" {
  ip() { :; }

  run list_can_interfaces
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 0 ]
}

# resolve_kernels

@test "resolve_kernels prints the parentdev from ip link show" {
  ip() { echo "3: can0: <NOARP> mtu 16 qdisc noqueue state UNKNOWN mode DEFAULT group default qlen 10  link/can  promiscuity 0 allmulti 0 minmtu 0 maxmtu 0 parentdev 1-2:1.0 parentbus usb"; }

  run resolve_kernels "can0"
  [ "$status" -eq 0 ]
  [ "$output" = "1-2:1.0" ]
}

@test "resolve_kernels fails when parentdev is absent" {
  ip() { echo "3: can0: <NOARP> mtu 16 qdisc noqueue state UNKNOWN mode DEFAULT group default qlen 10  link/can"; }

  run resolve_kernels "can0"
  [ "$status" -ne 0 ]
}

# is_valid_name

@test "is_valid_name accepts a plain alphanumeric name" {
  run is_valid_name "can0"
  [ "$status" -eq 0 ]
}

@test "is_valid_name accepts underscores and hyphens" {
  run is_valid_name "can_bus-0"
  [ "$status" -eq 0 ]
}

@test "is_valid_name rejects an empty name" {
  run is_valid_name ""
  [ "$status" -ne 0 ]
}

@test "is_valid_name rejects a name longer than 15 characters" {
  run is_valid_name "this-name-is-too-long"
  [ "$status" -ne 0 ]
}

@test "is_valid_name rejects names with disallowed characters" {
  run is_valid_name "can0/eth0"
  [ "$status" -ne 0 ]
}

# is_name_taken

@test "is_name_taken finds a name assigned to a different kernels entry" {
  KERNELS_TO_NAME=()
  KERNELS_TO_NAME["1-2:1.0"]="can0"

  run is_name_taken "can0" "1-3:1.0"
  [ "$status" -eq 0 ]
}

@test "is_name_taken ignores the excluded kernels entry" {
  KERNELS_TO_NAME=()
  KERNELS_TO_NAME["1-2:1.0"]="can0"

  run is_name_taken "can0" "1-2:1.0"
  [ "$status" -ne 0 ]
}

@test "is_name_taken succeeds when no other entry uses the name" {
  KERNELS_TO_NAME=()
  KERNELS_TO_NAME["1-2:1.0"]="can0"

  run is_name_taken "can1" "1-3:1.0"
  [ "$status" -ne 0 ]
}
