#!/bin/bash
# ============================================
# Photo Organizer (Safe Mode, Humane Narration)
# Author: Jonathan (Exorobourii LLC)
# License: MIT (Free & Open Source)
# Version: 1.0-beta
# ============================================


# This script helps you safely understand and organize your photo collection.
# It never deletes your originals. It explains every step in plain language.
# If you choose to organize, it makes a copied library by Year/Month.


# -----------------------------
# Friendly intro and path tips
# -----------------------------
echo "Hello. This tool will help you understand and gently organize your photos."
echo "It will NOT delete or change your originals. It will only report or make copies."
echo
echo "Tip: To find your folder path..."
echo " - Windows: open File Explorer, click the address bar, copy the path (e.g., C:\\Users\\Mary\\Pictures)"
echo " - Mac: right-click the folder in Finder, choose 'Get Info', copy the 'Where:' path"
echo " - Linux: right-click the folder in your file manager, 'Properties' -> copy the path"
echo "You can also drag a folder into a Terminal window to paste its full path."
echo


# -----------------------------
# Ask for target folder
# -----------------------------
read -r -p "Please type or paste the path to the folder with your photos: " TARGET


# Basic validation
if [ -z "$TARGET" ]; then
  echo "I didn't receive a folder path. Please run the script again and paste a path."
  exit 1
fi
if [ ! -d "$TARGET" ]; then
  echo "I'm sorry, but that folder does not exist: $TARGET"
  echo "Please check the path and try again."
  exit 1
fi


echo
echo "Thank you. I found the folder:"
echo "  $TARGET"
echo "Now I'll take a look inside. This will take a moment if the folder is large."
echo


# -----------------------------
# Utility helpers (portable)
# -----------------------------


# Choose a checksum program (sha256 preferred for correctness; falls back if needed)
choose_hasher() {
  if command -v sha256sum >/dev/null 2>&1; then
    echo "sha256sum"
  elif command -v shasum >/dev/null 2>&1; then
    echo "shasum -a 256"
  elif command -v openssl >/dev/null 2>&1; then
    echo "openssl dgst -sha256"
  else
    echo ""  # none found
  fi
}


# Get free space (KB) on the filesystem containing TARGET (portable df -k parsing)
get_free_kb() {
  df -k "$TARGET" | tail -n 1 | awk '{print $4}'
}


# Get required space (KB) approximated by size of TARGET (du -sk)
get_required_kb() {
  du -sk "$TARGET" 2>/dev/null | awk '{print $1}'
}


# Get CPU core count (portable across Linux/Mac)
get_core_count() {
  if command -v nproc >/dev/null 2>&1; then
    nproc
  elif command -v sysctl >/dev/null 2>&1; then
    sysctl -n hw.ncpu
  else
    echo 1
  fi
}


# Get 1-minute load average as a float
get_load_avg() {
  # uptime output contains "load average: x.xx, y.yy, z.zz"
  uptime | awk -F'load average: ' '{print $2}' | awk -F',' '{print $1}' | xargs
}


# Float comparison using awk (returns 0/1)
# Usage: float_gt "2.5" "2.0" -> 1 means left > right
float_gt() {
  awk "BEGIN{if ($1 > $2) print 1; else print 0}"
}


# Safe mkdir (makes directory if missing)
ensure_dir() {
  [ -d "$1" ] || mkdir -p "$1"
}


# -----------------------------
# Scan for photos
# -----------------------------
echo "Step 1: Scanning for photos (JPG, JPEG, PNG, TIF, HEIC)..."
# Use -iname for case-insensitive extension matching
# shellcheck disable=SC2039
IFS=$'\n' read -r -d '' -a PHOTOS < <(find "$TARGET" -type f \( \
  -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.tif" -o -iname "*.heic" \
\) -print && printf '\0')


PHOTO_COUNT=${#PHOTOS[@]}
echo "  → I found $PHOTO_COUNT photo files."


if [ "$PHOTO_COUNT" -eq 0 ]; then
  echo "I didn't find any photos with those extensions. Nothing will be changed."
  exit 0
fi
echo


# -----------------------------
# Checksum duplicate detection
# -----------------------------
echo "Step 2: Checking for true duplicates (identical content)."
HASHER=$(choose_hasher)
if [ -z "$HASHER" ]; then
  echo "  ⚠️ I couldn't find a checksum tool on this system."
  echo "     Duplicate detection will be skipped. (sha256sum, shasum, or openssl is recommended.)"
  DUPLICATE_LIST=()
else
  declare -A SEEN
  DUPLICATE_LIST=()
  # Compute checksums; explain progress every N files
  TOTAL="$PHOTO_COUNT"
  COUNT=0
  for FILE in "${PHOTOS[@]}"; do
    COUNT=$((COUNT + 1))
    if [ $((COUNT % 500)) -eq 0 ]; then
      echo "  ...processed $COUNT of $TOTAL photos"
    fi
    # Compute checksum via chosen hasher
    if [[ "$HASHER" == "sha256sum" ]]; then
      CHECKSUM=$(sha256sum "$FILE" | awk '{print $1}')
    elif [[ "$HASHER" == "shasum -a 256" ]]; then
      CHECKSUM=$(shasum -a 256 "$FILE" | awk '{print $1}')
    else
      # openssl dgst -sha256 outputs "SHA256(file)= hash" or "SHA256(hash)"
      CHECKSUM=$(openssl dgst -sha256 "$FILE" | awk -F'= ' '{print $2}')
    fi


    if [[ -n "${SEEN[$CHECKSUM]}" ]]; then
      DUPLICATE_LIST+=("$FILE <<< duplicate of >>> ${SEEN[$CHECKSUM]}")
    else
      SEEN[$CHECKSUM]="$FILE"
    fi
  done
fi


DUP_COUNT=${#DUPLICATE_LIST[@]}
if [ "$DUP_COUNT" -gt 0 ]; then
  echo "  → I found $DUP_COUNT duplicate photos (same content, possibly different names)."
else
  echo "  → No true duplicates detected."
fi
echo


# -----------------------------
# Summary report to screen
# -----------------------------
echo "=== Photo Summary ==="
echo "Total photos: $PHOTO_COUNT"
echo "Duplicates (by checksum): $DUP_COUNT"
# Oldest and newest by modification time
OLDEST=$(find "$TARGET" -type f -printf "%T@ %p\n" 2>/dev/null | sort -n | head -n 1 | cut -d' ' -f2-)
NEWEST=$(find "$TARGET" -type f -printf "%T@ %p\n" 2>/dev/null | sort -nr | head -n 1 | cut -d' ' -f2-)
if [ -n "$OLDEST" ] && [ -n "$NEWEST" ]; then
  echo "Oldest file seen: $OLDEST"
  echo "Newest file seen: $NEWEST"
fi
echo


# -----------------------------
# Offer next steps
# -----------------------------
echo "What would you like to do next?"
echo "1) Create a simple report file (photos + duplicates list)"
echo "2) Make a safe, organized copy by Year/Month into a new folder"
echo "3) Exit without changes"
read -r -p "Please choose (1-3): " CHOICE
echo


case "$CHOICE" in
  1)
    REPORT="photo_report_$(date +%Y%m%d_%H%M%S).txt"
    echo "Creating a report: $REPORT"
    {
      echo "Photo Organizer Report"
      echo "Date: $(date)"
      echo "Folder: $TARGET"
      echo "Total photos: $PHOTO_COUNT"
      echo "Duplicates (by checksum): $DUP_COUNT"
      echo
      echo "First 100 photo paths:"
      for FILE in "${PHOTOS[@]:0:100}"; do
        echo "$FILE"
      done
      echo
      echo "Duplicate pairs (up to first 200 lines):"
      for LINE in "${DUPLICATE_LIST[@]:0:200}"; do
        echo "$LINE"
      done
    } > "$REPORT"
    echo "Report created safely. Your originals were not changed."
    ;;


  2)
    echo "You chose to make an organized copy by Year/Month."
    echo "Before we begin copying, let’s make sure there’s enough free space."
    AVAIL_KB=$(get_free_kb)
    REQ_KB=$(get_required_kb)
    AVAIL_MB=$((AVAIL_KB / 1024))
    REQ_MB=$((REQ_KB / 1024))


    echo "  → Estimated space needed (size of the source folder): ~${REQ_MB} MB"
    echo "  → Free space on this drive: ~${AVAIL_MB} MB"
    echo


    if [ "$AVAIL_KB" -lt "$REQ_KB" ]; then
      echo "⚠️ Warning: There may not be enough free space to safely make a full copy."
      echo "No files will be copied. Please free up space or choose a different drive."
      exit 1
    else
      echo "✅ Good news: There appears to be enough free space to proceed."
    fi
    echo


    echo "Now I’ll check your system’s current workload to avoid overloading it..."
    LOAD=$(get_load_avg)
    CORES=$(get_core_count)
    echo "  → Current 1-minute load: $LOAD on $CORES CPU cores"


    # Proceed if load <= cores; otherwise prompt
    TOO_BUSY=$(float_gt "$LOAD" "$CORES")
    if [ "$TOO_BUSY" -eq 1 ]; then
      echo "⚠️ Your system is already quite busy."
      read -r -p "Would you like to wait and try again later? (y/n): " ANSWER
      if [[ "$ANSWER" =~ ^[Yy]$ ]]; then
        echo "Okay. Exiting safely. Please run the script again when your system is less busy."
        exit 1
      else
        echo "Proceeding carefully. Performance may be affected during copying."
      fi
    else
      echo "✅ System load looks safe. Proceeding."
    fi
    echo


    # Perform organized copy into a sibling folder (default: ./Organized_Photos under current directory)
    DEST_DIR="./Organized_Photos_$(date +%Y%m%d_%H%M%S)"
    echo "I will copy photos into: $DEST_DIR"
    echo "Your originals remain in place. This is a separate, organized library."
    ensure_dir "$DEST_DIR"


    # Copy with Year/Month by file modification time
    COUNT=0
    for FILE in "${PHOTOS[@]}"; do
      COUNT=$((COUNT + 1))
      YEAR=$(date -r "$FILE" +%Y 2>/dev/null || stat -f "%Sm" -t "%Y" "$FILE" 2>/dev/null)
      MONTH=$(date -r "$FILE" +%m 2>/dev/null || stat -f "%Sm" -t "%m" "$FILE" 2>/dev/null)
      [ -z "$YEAR" ] && YEAR="unknown"
      [ -z "$MONTH" ] && MONTH="unknown"
      ensure_dir "$DEST_DIR/$YEAR/$MONTH"
      cp -p "$FILE" "$DEST_DIR/$YEAR/$MONTH/"


      # Gentle progress updates
      if [ $((COUNT % 500)) -eq 0 ]; then
        echo "  ...copied $COUNT of $PHOTO_COUNT photos"
      fi
    done


    echo
    echo "✅ Finished copying $PHOTO_COUNT photos into:"
    echo "   $DEST_DIR"
    echo "Folders are organized by Year/Month based on file dates."
    echo "Your originals were not changed."
    ;;


  3)
    echo "Okay. Nothing more will be done. Your files remain untouched."
    ;;


  *)
    echo "Invalid choice. Exiting safely. No changes were made."
    ;;
esac


echo
echo "All done. If you have ideas to improve this tool, feel free to share."
echo "Exorobourii LLC builds to enrich, not extract. Thank you for trusting this script.”