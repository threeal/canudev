#!/usr/bin/env bash
set -euo pipefail

RULES_FILE="${RULES_FILE:-/etc/udev/rules.d/99-canbus.rules}"
CONFIG_VERSION=1
BITRATE=1000000

declare -g -A KERNELS_TO_NAME=()

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "error: must be run as root (needed to write ${RULES_FILE} and reload udev)" >&2
    exit 1
  fi
}

# Parses a v1 config body (version line already consumed) into KERNELS_TO_NAME.
parse_config_v1() {
  local body="$1" line kernels name
  while IFS= read -r line; do
    case "$line" in
      "#"*) ;;
      *) break ;;
    esac
    line=${line#"# "}
    read -r kernels name <<<"$line"
    KERNELS_TO_NAME["$kernels"]="$name"
  done < <(printf '%s\n' "$body" | tail -n +2)
}

# Reads and verifies $RULES_FILE, populating KERNELS_TO_NAME.
# Warns and starts with an empty mapping if the file is missing its expected
# hash, has a config version this script doesn't know how to parse, or
# doesn't exist yet.
read_rules_file() {
  KERNELS_TO_NAME=()

  if [ ! -f "$RULES_FILE" ]; then
    return
  fi

  local hash_line body expected_hash actual_hash
  hash_line=$(head -n 1 "$RULES_FILE")
  body=$(tail -n +2 "$RULES_FILE")
  expected_hash=${hash_line#"# canudev:sha256:"}
  actual_hash=$(printf '%s\n' "$body" | sha256sum | cut -d' ' -f1)

  if [ "$hash_line" != "# canudev:sha256:${expected_hash}" ] || [ "$expected_hash" != "$actual_hash" ]; then
    echo "warning: ${RULES_FILE} was modified outside canudev; existing entries will be ignored and replaced" >&2
    return
  fi

  local version_line version
  version_line=$(printf '%s\n' "$body" | head -n 1)
  if [[ "$version_line" =~ ^#\ canudev-config\ v([0-9]+)$ ]]; then
    version="${BASH_REMATCH[1]}"
  else
    echo "warning: ${RULES_FILE} has no recognizable config version marker; existing entries will be ignored and replaced" >&2
    return
  fi

  case "$version" in
    1) parse_config_v1 "$body" ;;
    *)
      echo "warning: ${RULES_FILE} has config version ${version}, which this version of canudev doesn't know how to read; existing entries will be ignored and replaced" >&2
      ;;
  esac
}

# Regenerates $RULES_FILE in full from KERNELS_TO_NAME, then reloads udev.
write_rules_file() {
  local body kernels name
  body="# canudev-config v${CONFIG_VERSION}"$'\n'
  for kernels in "${!KERNELS_TO_NAME[@]}"; do
    body+="# ${kernels} ${KERNELS_TO_NAME[$kernels]}"$'\n'
  done
  body+=$'\n'
  for kernels in "${!KERNELS_TO_NAME[@]}"; do
    name="${KERNELS_TO_NAME[$kernels]}"
    body+="SUBSYSTEM==\"net\", ACTION==\"add\", KERNELS==\"${kernels}\", ATTR{type}==\"280\", NAME=\"${name}\", \\"$'\n'
    body+="  RUN+=\"/sbin/ip link set ${name} up type can bitrate ${BITRATE}\""$'\n'
  done

  local hash tmp_file
  hash=$(printf '%s' "$body" | sha256sum | cut -d' ' -f1)
  tmp_file="${RULES_FILE}.tmp.$$"

  {
    printf '# canudev:sha256:%s\n' "$hash"
    printf '%s' "$body"
  } >"$tmp_file"
  mv "$tmp_file" "$RULES_FILE"

  udevadm control --reload-rules
  udevadm trigger
}

# Manually applies a rename (if needed) plus bitrate and bring-up, since
# udevadm trigger won't re-fire an add event for an interface that already
# exists — the rule only takes effect on its own after a replug or reboot.
# Each step guards its own failure explicitly and returns early, since `set
# -e` is suppressed for the whole function while it runs as an `if`
# condition at the call site.
apply_interface_state() {
  local old_name="$1" new_name="$2"
  if [ "$old_name" != "$new_name" ]; then
    ip link set "$old_name" down || return 1
    ip link set "$old_name" name "$new_name" || return 1
  else
    ip link set "$new_name" down || return 1
  fi
  ip link set "$new_name" up type can bitrate "$BITRATE" || return 1
}

list_can_interfaces() {
  ip -d -o link show type can | awk -F': ' '{print $2}'
}

# Resolves the KERNELS value (physical bus location) for one interface.
# Prints it on success; prints nothing and returns non-zero on failure.
resolve_kernels() {
  local iface="$1" line parentdev
  line=$(ip -d link show "$iface")
  parentdev=$(printf '%s\n' "$line" | grep -oP 'parentdev \K\S+' || true)
  if [ -z "$parentdev" ]; then
    return 1
  fi
  printf '%s\n' "$parentdev"
}

# Reads one line of input from the controlling terminal, so this still works
# when the script itself is being read from stdin (e.g. curl | bash).
prompt() {
  local text="$1" reply
  read -r -p "$text" reply </dev/tty >/dev/tty
  printf '%s\n' "$reply"
}

is_valid_name() {
  local name="$1"
  [ -n "$name" ] && [ "${#name}" -le 15 ] && [[ "$name" =~ ^[A-Za-z0-9_-]+$ ]]
}

# Checks whether $name is already assigned to a KERNELS entry other than
# $exclude_kernels.
is_name_taken() {
  local name="$1" exclude_kernels="$2" kernels
  for kernels in "${!KERNELS_TO_NAME[@]}"; do
    [ "$kernels" = "$exclude_kernels" ] && continue
    [ "${KERNELS_TO_NAME[$kernels]}" = "$name" ] && return 0
  done
  return 1
}

# Checks whether $name is currently in use by an interface other than
# $exclude_iface (the interface keeping its own current name isn't a
# collision).
is_name_in_use() {
  local name="$1" exclude_iface="$2"
  [ "$name" = "$exclude_iface" ] && return 1
  ip link show "$name" >/dev/null 2>&1
}

main() {
  require_root
  read_rules_file

  while true; do
    local ifaces=() iface_kernels=() iface_labels=()
    local iface
    while IFS= read -r iface; do
      [ -n "$iface" ] || continue

      local kernels label mapped_name
      if kernels=$(resolve_kernels "$iface"); then
        if [ -n "${KERNELS_TO_NAME[$kernels]+set}" ]; then
          mapped_name="${KERNELS_TO_NAME[$kernels]}"
          if [ "$mapped_name" = "$iface" ]; then
            label="$iface (static)"
          else
            label="$iface (static, expected name: ${mapped_name} — not yet applied)"
          fi
        else
          label="$iface (unnamed)"
        fi
      else
        kernels=""
        label="$iface (location unknown)"
      fi

      ifaces+=("$iface")
      iface_kernels+=("$kernels")
      iface_labels+=("$label")
    done < <(list_can_interfaces)

    if [ "${#ifaces[@]}" -eq 0 ]; then
      echo "no CAN interfaces found"
    else
      echo "CAN interfaces:"
      local i=1
      for label in "${iface_labels[@]}"; do
        echo "  [$i] $label"
        i=$((i + 1))
      done
    fi

    echo "  [r] refresh"
    echo "  [q] quit"

    local choice
    choice=$(prompt "select an interface, r to refresh, or q to quit: ")

    case "$choice" in
      q | Q) break ;;
      r | R) continue ;;
      '' | *[!0-9]*)
        echo "invalid selection" >&2
        continue
        ;;
    esac

    if [ "$choice" -lt 1 ] || [ "$choice" -gt "${#ifaces[@]}" ]; then
      echo "invalid selection" >&2
      continue
    fi

    local selected="${ifaces[$((choice - 1))]}"
    local kernels="${iface_kernels[$((choice - 1))]}"
    if [ -z "$kernels" ]; then
      echo "error: could not determine the physical location of ${selected}; skipping" >&2
      continue
    fi

    local new_name
    new_name=$(prompt "enter static name for ${selected}: ")
    if ! is_valid_name "$new_name"; then
      echo "error: invalid interface name" >&2
      continue
    fi
    if is_name_taken "$new_name" "$kernels" || is_name_in_use "$new_name" "$selected"; then
      echo "error: name already in use by another interface" >&2
      continue
    fi

    KERNELS_TO_NAME["$kernels"]="$new_name"
    write_rules_file
    if ! apply_interface_state "$selected" "$new_name"; then
      echo "error: failed to apply new name to ${selected}; the rule was saved and will take effect after a replug or reboot" >&2
    fi
  done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
