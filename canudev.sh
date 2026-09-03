#!/usr/bin/env bash
set -euo pipefail

RULES_FILE="/etc/udev/rules.d/99-canbus.rules"
CONFIG_VERSION_LINE="# canudev-config v1"

declare -A KERNELS_TO_NAME=()

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "error: must be run as root (needed to write ${RULES_FILE} and reload udev)" >&2
    exit 1
  fi
}

# Reads and verifies $RULES_FILE, populating KERNELS_TO_NAME.
# Warns and starts with an empty mapping if the file is missing its expected
# hash, has an unsupported config version, or doesn't exist yet.
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

  local version_line
  version_line=$(printf '%s\n' "$body" | head -n 1)
  if [ "$version_line" != "$CONFIG_VERSION_LINE" ]; then
    echo "warning: ${RULES_FILE} has an unsupported config version; existing entries will be ignored and replaced" >&2
    return
  fi

  local line kernels name
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

# Regenerates $RULES_FILE in full from KERNELS_TO_NAME, then reloads udev.
write_rules_file() {
  local body kernels name
  body="${CONFIG_VERSION_LINE}"$'\n'
  for kernels in "${!KERNELS_TO_NAME[@]}"; do
    body+="# ${kernels} ${KERNELS_TO_NAME[$kernels]}"$'\n'
  done
  body+=$'\n'
  for kernels in "${!KERNELS_TO_NAME[@]}"; do
    name="${KERNELS_TO_NAME[$kernels]}"
    body+="SUBSYSTEM==\"net\", ACTION==\"add\", KERNELS==\"${kernels}\", ATTR{type}==\"280\", NAME=\"${name}\""$'\n'
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

main() {
  require_root
  read_rules_file

  while true; do
    local ifaces=()
    while IFS= read -r iface; do
      [ -n "$iface" ] && ifaces+=("$iface")
    done < <(list_can_interfaces)

    if [ "${#ifaces[@]}" -eq 0 ]; then
      echo "no CAN interfaces found"
    else
      echo "CAN interfaces:"
      local i=1 iface is_static name
      for iface in "${ifaces[@]}"; do
        is_static=0
        for name in "${KERNELS_TO_NAME[@]}"; do
          if [ "$name" = "$iface" ]; then
            is_static=1
            break
          fi
        done
        if [ "$is_static" -eq 1 ]; then
          echo "  [$i] $iface (static)"
        else
          echo "  [$i] $iface (unnamed)"
        fi
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
    local kernels
    if ! kernels=$(resolve_kernels "$selected"); then
      echo "error: could not determine the physical location of ${selected}; skipping" >&2
      continue
    fi

    local new_name
    new_name=$(prompt "enter static name for ${selected}: ")
    if ! is_valid_name "$new_name"; then
      echo "error: invalid interface name" >&2
      continue
    fi

    KERNELS_TO_NAME["$kernels"]="$new_name"
    write_rules_file
  done
}

main
