cat > disk_extend.sh <<'EOF'
#!/bin/bash
set -euo pipefail

echo
echo "Available filesystems"
df -h | awk 'NR==1 || $NF ~ /^\//'

echo
read -r -p "Enter mount point to extend: " MOUNT

if ! mountpoint -q "$MOUNT"; then
  echo "Invalid mount point"
  exit 1
fi

echo
echo "Detecting source and filesystem type"
SOURCE=$(findmnt -no SOURCE "$MOUNT")
FSTYPE=$(findmnt -no FSTYPE "$MOUNT")

echo "Mount: $MOUNT"
echo "Source: $SOURCE"
echo "Filesystem: $FSTYPE"
echo

echo "Rescanning disk(s)"
for d in /sys/class/block/*/device/rescan; do
  echo 1 >"$d" 2>/dev/null || true
done

echo
if [[ "$SOURCE" == /dev/mapper/* || "$SOURCE" == /dev/*/* ]]; then
  echo "LVM detected"
  echo
  lsblk -f

  LV_PATH="$SOURCE"
  VG_NAME=$(lvs --noheadings -o vg_name "$LV_PATH" | awk '{print $1}')
  if [[ -z "$VG_NAME" ]]; then
    echo "Failed to detect VG name"
    exit 1
  fi

  echo
  echo "Detected VG: $VG_NAME"

  echo
  echo "Detecting PVs for VG $VG_NAME"
  mapfile -t PVS < <(pvs --noheadings -o pv_name,vg_name | awk -v vg="$VG_NAME" '$2==vg{print $1}')
  if [[ "${#PVS[@]}" -eq 0 ]]; then
    echo "No PVs found for VG $VG_NAME"
    exit 1
  fi

  echo
  echo "Attempting to grow PV partitions if needed"
  for pv in "${PVS[@]}"; do
    echo "PV: $pv"

    DISK_NAME=$(lsblk -no PKNAME "$pv" 2>/dev/null | head -n1 || true)
    PARTNUM=$(lsblk -no PARTNUM "$pv" 2>/dev/null | head -n1 || true)

    if [[ -z "${PARTNUM:-}" ]]; then
      PARTNUM=$(echo "$pv" | grep -o '[0-9]*$' | head -n1 || true)
    fi

    if [[ -n "${DISK_NAME:-}" && -n "${PARTNUM:-}" ]]; then
      DISK="/dev/$DISK_NAME"
      echo "growpart $DISK $PARTNUM"
      growpart "$DISK" "$PARTNUM" || true
    fi

    echo "pvresize $pv"
    pvresize "$pv"
  done

  VG_SIZE_H=$(vgs --noheadings -o vg_size --units h --nosuffix "$VG_NAME" | awk '{print $1}')
  VG_FREE_H=$(vgs --noheadings -o vg_free --units h --nosuffix "$VG_NAME" | awk '{print $1}')

  echo
  echo "VG total size: $VG_SIZE_H"
  echo "VG free space: $VG_FREE_H"

  VG_FREE_BYTES=$(vgs --noheadings -o vg_free --units b --nosuffix "$VG_NAME" | awk '{print $1}')
  VG_FREE_BYTES=${VG_FREE_BYTES%%.*}

  if [[ -z "$VG_FREE_BYTES" || "$VG_FREE_BYTES" -le 0 ]]; then
    echo "No free space available in VG"
    exit 1
  fi

  echo
  read -r -p "Enter percentage of VG free space to add (1-100): " PERCENT
  if ! [[ "$PERCENT" =~ ^[0-9]+$ ]]; then
    echo "Invalid percentage"
    exit 1
  fi
  if [[ "$PERCENT" -lt 1 || "$PERCENT" -gt 100 ]]; then
    echo "Percentage must be between 1 and 100"
    exit 1
  fi

  ADD_BYTES=$(( VG_FREE_BYTES * PERCENT / 100 ))
  ADD_GIB=$(( ADD_BYTES / 1024 / 1024 / 1024 ))

  echo
  echo "Planned increase: ${PERCENT}% of VG free space"
  echo "Estimated add: ${ADD_GIB}GiB"

  echo
  echo "Extending LV"
  lvextend -l +"$PERCENT"%FREE "$LV_PATH"

  echo
  echo "Growing filesystem"
  if [[ "$FSTYPE" == "xfs" ]]; then
    xfs_growfs "$MOUNT"
  elif [[ "$FSTYPE" == "ext4" ]]; then
    resize2fs "$LV_PATH"
  else
    echo "Unsupported filesystem type: $FSTYPE"
    exit 1
  fi

elif [[ "$SOURCE" =~ [0-9]$ ]]; then
  echo "Partition detected"
  echo

  DISK="/dev/$(lsblk -no PKNAME "$SOURCE" 2>/dev/null | head -n1)"
  PARTNUM=$(lsblk -no PARTNUM "$SOURCE" 2>/dev/null | head -n1)

  if [[ -z "${DISK:-}" || "$DISK" == "/dev/" || -z "${PARTNUM:-}" ]]; then
    DISK_NAME=$(lsblk -no PKNAME "$SOURCE" 2>/dev/null | head -n1 || true)
    PARTNUM=$(echo "$SOURCE" | grep -o '[0-9]*$' | head -n1 || true)
    DISK="/dev/$DISK_NAME"
  fi

  if [[ -z "${DISK_NAME:-}" && ( -z "${DISK:-}" || "$DISK" == "/dev/" ) ]]; then
    echo "Failed to detect disk"
    exit 1
  fi
  if [[ -z "${PARTNUM:-}" ]]; then
    echo "Failed to detect partition number"
    exit 1
  fi

  echo "Disk: $DISK"
  echo "Partition: $SOURCE"
  echo "Partition number: $PARTNUM"

  echo
  echo "Growing partition with growpart"
  growpart "$DISK" "$PARTNUM"

  echo
  echo "Growing filesystem"
  if [[ "$FSTYPE" == "xfs" ]]; then
    xfs_growfs "$MOUNT"
  elif [[ "$FSTYPE" == "ext4" ]]; then
    resize2fs "$SOURCE"
  else
    echo "Unsupported filesystem type: $FSTYPE"
    exit 1
  fi

else
  echo "Direct disk detected"
  echo

  echo "Growing filesystem"
  if [[ "$FSTYPE" == "xfs" ]]; then
    xfs_growfs "$MOUNT"
  elif [[ "$FSTYPE" == "ext4" ]]; then
    resize2fs "$SOURCE"
  else
    echo "Unsupported filesystem type: $FSTYPE"
    exit 1
  fi
fi

echo
echo "Final filesystem status"
df -h "$MOUNT"
EOF

chmod +x disk_extend.sh
