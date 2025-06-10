#!/bin/bash

set -e
set -u

usage() {
  echo "Usage: $0 <markdown_file> <video_file.mp4> [time_offset_seconds]"
  echo ""
  echo "Arguments:"
  echo "  markdown_file         Path to the Markdown file containing image tags with timestamps."
  echo "  video_file.mp4        Path to the MP4 video from which to extract frames."
  echo "  time_offset_seconds   (Optional) A positive or negative number (e.g., 2.5, -5)"
  echo "                        to add to each timestamp. Defaults to 0."
  echo ""
  echo "Examples:"
  echo "  # No offset"
  echo "  $0 notes.md video.mp4"
  echo ""
  echo "  # Add 1.5 seconds to every timestamp"
  echo "  $0 notes.md video.mp4 1.5"
  echo ""
  echo "  # Subtract 5 seconds from every timestamp"
  echo "  $0 notes.md video.mp4 -5"
  exit 1
}

calculate_new_timestamp() {
  local timestamp=$1
  local offset=$2

  # parse time offset
  awk -v ts="$timestamp" -v offset="$offset" 'BEGIN {
    # 1. Convert HH:MM:SS.ms timestamp to total seconds
    split(ts, parts, /[:.]/);
    total_seconds = parts[1]*3600 + parts[2]*60 + parts[3] + parts[4]/1000;

    # 2. Apply the offset
    new_total_seconds = total_seconds + offset;

    # 3. Clamp at zero to prevent errors
    if (new_total_seconds < 0) {
      new_total_seconds = 0;
      # Exit with a special code to indicate clamping happened
      exit 2;
    }

    # 4. Convert back to HH:MM:SS.ms format
    ss_frac = new_total_seconds - int(new_total_seconds);
    ms = int(ss_frac * 1000);

    total_int_seconds = int(new_total_seconds);
    ss = total_int_seconds % 60;
    mm = int(total_int_seconds / 60) % 60;
    hh = int(total_int_seconds / 3600);

    # 5. Print the formatted string
    printf("%02d:%02d:%02d.%03d\n", hh, mm, ss, ms);
  }'
}

if [[ "$#" -lt 2 || "$#" -gt 3 ]]; then
  echo "Error: Incorrect number of arguments."
  usage
fi

MARKDOWN_FILE="$1"
VIDEO_FILE="$2"
TIME_OFFSET="${3:-0}"

# Validate TIME_OFFSET
OFFSET_REGEX='^[+-]?[0-9]+([.][0-9]+)?$'
if ! [[ $TIME_OFFSET =~ $OFFSET_REGEX ]]; then
  echo "Error: Invalid time offset '$TIME_OFFSET'. Please provide a number like '1.5' or '-5'."
  exit 1
fi

if [ ! -f "$MARKDOWN_FILE" ]; then
  echo "Error: Markdown file not found at '$MARKDOWN_FILE'"
  exit 1
fi
if [ ! -f "$VIDEO_FILE" ]; then
  echo "Error: Video file not found at '$VIDEO_FILE'"
  exit 1
fi

# Check ffmpeg
if ! command -v ffmpeg &> /dev/null; then
    echo "Error: ffmpeg not installed"
    exit 1
fi

VIDEO_DIR=$(dirname "$VIDEO_FILE")
VIDEO_BASENAME=$(basename "$VIDEO_FILE" .mp4)
OUTPUT_DIR="$VIDEO_DIR/$VIDEO_BASENAME"

mkdir -p "$OUTPUT_DIR"
echo "Outputs will be saved in: $OUTPUT_DIR"
if [ "$(echo "$TIME_OFFSET != 0" | bc)" -eq 1 ]; then
    echo "Applying time offset of ${TIME_OFFSET}s to all timestamps."
fi

echo "  Processing '$MARKDOWN_FILE'.."

REGEX='!\[([0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3})\]\(([^)]+\.jpg)\)'
COUNT_TOTAL=0
COUNT_EXTRACTED=0
COUNT_SKIPPED=0

while IFS= read -r line; do
  if [[ $line =~ $REGEX ]]; then
    TIMESTAMP="${BASH_REMATCH[1]}"
    FILENAME="${BASH_REMATCH[2]}"
    OUTPUT_PATH="$OUTPUT_DIR/$FILENAME"
    ((COUNT_TOTAL++))

    ADJUSTED_TIMESTAMP_RESULT=$(calculate_new_timestamp "$TIMESTAMP" "$TIME_OFFSET")
    CALC_EXIT_CODE=$?
    ADJUSTED_TIMESTAMP=$ADJUSTED_TIMESTAMP_RESULT

    if [ -f "$OUTPUT_PATH" ]; then
      echo " Skipping, file already exists: $FILENAME"
      ((COUNT_SKIPPED++))
    else
      echo " Found timestamp $TIMESTAMP for -> $FILENAME"
      if [ "$(echo "$TIME_OFFSET != 0" | bc)" -eq 1 ]; then
          echo "     Applying offset: $TIMESTAMP -> $ADJUSTED_TIMESTAMP"
          if [ $CALC_EXIT_CODE -eq 2 ]; then
              echo "       Warning: Adjusted time was negative, clamped to 00:00:00.000"
          fi
      fi

      echo "     Extracting frame..."
      ffmpeg -hide_banner -loglevel error -ss "$ADJUSTED_TIMESTAMP" -i "$VIDEO_FILE" -frames:v 1 -q:v 2 "$OUTPUT_PATH"
      ((COUNT_EXTRACTED++))
    fi
  fi
done < "$MARKDOWN_FILE"

echo ""
echo "-------------------------------------"
echo "Done!"
echo "Total timestamps found: $COUNT_TOTAL"
echo "Frames extracted: $COUNT_EXTRACTED"
echo "Frames skipped: $COUNT_SKIPPED"
echo "-------------------------------------"
