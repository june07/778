#!/bin/bash

# Check if --no-sleep or -n was passed as an argument
SKIP_SLEEP=false
for arg in "$@"; do
    if [ "$arg" = "--no-sleep" ] || [ "$arg" = "-n" ]; then
        SKIP_SLEEP=true
        break
    fi
done

REPO_SETUP=false
for arg in "$@"; do
    if [ "$arg" = "--repo-setup" ] || [ "$arg" = "-s" ]; then
        REPO_SETUP=true
        break
    fi
done

# Apply sleep delay unless skipped
if [ "$SKIP_SLEEP" = false ]; then
    sleep $((RANDOM % 30))
fi

SCRIPT_PATH="$(readlink -f "$0")"
HOSTNAME=`hostname`
# Define paths and repo details
YEAR=`date +%Y`
MONTH=`date +%m`
DAY=`date +%d`
REPO_DIR="/home/adrian/778-repo"
REPO_DIR_DAY="${REPO_DIR}/${YEAR}/${MONTH}/${DAY}"
IMAGE_DEST_PREFIX="$REPO_DIR_DAY/snapshot"
BRANCH="main" # Change to 'master' if your default branch is master
TIMESTAMP=`date +%s`
DATETIMESTAMP=$(TZ="America/Chicago" date +"%Y-%m-%d %H:%M:%S")
CACHE_FILE="/tmp/camera_devices.cache"
IMAGE1="${IMAGE_DEST_PREFIX}-${HOSTNAME}-${TIMESTAMP}-1.jpg"
IMAGE2="${IMAGE_DEST_PREFIX}-${HOSTNAME}-${TIMESTAMP}-2.jpg"
IMAGE3="${IMAGE_DEST_PREFIX}-${HOSTNAME}-${TIMESTAMP}-3.jpg"
IMAGE4="${IMAGE_DEST_PREFIX}-${HOSTNAME}-${TIMESTAMP}-4.jpg"
IMAGE5="${IMAGE_DEST_PREFIX}-${HOSTNAME}-${TIMESTAMP}-5.jpg"
IMAGE6="${IMAGE_DEST_PREFIX}-${HOSTNAME}-${TIMESTAMP}-6.jpg"
IMAGE7="${IMAGE_DEST_PREFIX}-${HOSTNAME}-${TIMESTAMP}-7.jpg"
IMAGE8="${IMAGE_DEST_PREFIX}-${HOSTNAME}-${TIMESTAMP}-8.jpg"

FLIP_ARG1=""
FLIP_ARG2=""
if [ "$HOSTNAME" = "art" ]; then
    FLIP_ARG1="--flip v,h"
    FLIP_ARG2="--flip v,h"
elif [ "$HOSTNAME" = "library" ]; then
    FLIP_ARG1="--flip v,h"
    FLIP_ARG2=""
elif [ "$HOSTNAME" = "aaliyah" ]; then
    FLIP_ARG1=""
    FLIP_ARG2=""
fi


# If the cache already exists, skip scanning and use it
if [ -f "$CACHE_FILE" ]; then
    echo "Cache found. Using existing device map:"
    cat "$CACHE_FILE"
else
    echo "Cache not found. Scanning USB bus for cameras..."
    rm -f "$CACHE_FILE"

    # Iterate through all USB devices in sysfs
    for d in /sys/bus/usb/devices/*; do
        # Ensure it's a valid USB device node containing vendor/product IDs
        [ -f "$d/idVendor" ] && [ -f "$d/idProduct" ] || continue
        
        vid=$(cat "$d/idVendor" 2>/dev/null)
        pid=$(cat "$d/idProduct" 2>/dev/null)
        vid_pid="${vid}:${pid}"
        
        # Get product string from sysfs
        prod_name=$(cat "$d/product" 2>/dev/null)
        [ -z "$prod_name" ] && prod_name="Unknown Camera"
        
        # Search for video4linux nodes nested under this device's interfaces (e.g., 1-1.2:1.0/video4linux/video0)
        for vnode in "$d"/*/video4linux/video* "$d"/video4linux/video*; do
            [ -e "$vnode" ] || continue
            v_base=$(basename "$vnode")
            dev_path="/dev/$v_base"
            
            # Write out in format: /dev/video0|Product Name|vid:pid|sysfs_path
            echo "$dev_path|$prod_name|$vid_pid|$d" >> "$CACHE_FILE"
        done
    done

    echo "Scan complete. Saved to $CACHE_FILE:"
    cat "$CACHE_FILE"
fi

git config --global init.defaultBranch $BRANCH
git config --global user.name "adrian@${HOSTNAME}"
git config --global user.email "778@onezerohosting.com"

if [ "$HOSTNAME" == "art" ]; then
		SPARSE_FILE_LIST="/upload.sh /snapshot-1.jpg /snapshot-2.jpg ${IMAGE1#${REPO_DIR}/} ${IMAGE2#${REPO_DIR}/}"
elif [ "$HOSTNAME" == "library" ]; then
    SPARSE_FILE_LIST="/upload.sh /snapshot-3.jpg /snapshot-4.jpg ${IMAGE1#${REPO_DIR}/} ${IMAGE2#${REPO_DIR}/}"
elif [ "$HOSTNAME" == "aaliyah" ]; then
    SPARSE_FILE_LIST="/upload.sh /snapshot-*.jpg ${IMAGE1#${REPO_DIR}/} ${IMAGE2#${REPO_DIR}/} ${IMAGE3#${REPO_DIR}/} ${IMAGE4#${REPO_DIR}/} ${IMAGE5#${REPO_DIR}/} ${IMAGE6#${REPO_DIR}/} ${IMAGE7#${REPO_DIR}/} ${IMAGE8#${REPO_DIR}/}"
fi

# 2. Clone the repo if it doesn't exist locally yet (run this setup once beforehand)
if [ ! -d "$REPO_DIR/.git" ]; then
	if [ "$REPO_SETUP" == true ]; then
		mkdir $REPO_DIR
		cd "$REPO_DIR"
		git init

	else
		# 2. Enable sparse checkout and target ONLY the snapshot file
		git clone --filter=blob:none --depth 1 --no-checkout --branch main git@github.com:june07/778.git $REPO_DIR
		cd $REPO_DIR
		git sparse-checkout init
	fi

	git sparse-checkout set --no-cone true
	git sparse-checkout set $SPARSE_FILE_LIST
	git pull origin "$BRANCH"
else
	cd $REPO_DIR

	git sparse-checkout set --no-cone true
fi

if [ ! -d $REPO_DIR_DAY ]; then
	mkdir -p $REPO_DIR_DAY
fi

# Define location (Fluvanna, TX coordinates)
LAT=32.8856
LON=-101.1487

# Use Python to determine the lighting mode based on system time and solar context,
# or simply output optimized fswebcam arguments.
# (Alternatively, you can compute sun position, or use a time-window approximation)

# Let's determine exposure profile based on hour/twilight logic evaluated via Python:
eval $(python3 - <<EOF
import datetime
# Simple time-window or sun calculation logic
now = datetime.datetime.now()
hour = now.hour + now.minute / 60.0

# Define rough thresholds for Fluvanna twilight/day (adjust as seasons shift)
# Winter/Summer twilight shifts can also be calculated via libraries if needed, 
# but fixed seasonal windows or a quick solar calc work great.
if 7.0 <= hour <= 18.5:
    # Daytime: Fast shutter, low exposure, skip fewer frames
    print("EXPOSURE=1")
    print("EXP_TIME=10")
    print("SKIP_FRAMES=10")
elif (6.0 <= hour < 7.0) or (18.5 < hour <= 19.5):
    # Sunrise / Sunset Twilight: Slower shutter, higher skip count for AWB settling
    print("EXPOSURE=1")
    print("EXP_TIME=100")
    print("SKIP_FRAMES=40")
else:
    # Night: Max manual exposure or fallback
    print("EXPOSURE=1")
    print("EXP_TIME=200")
    print("SKIP_FRAMES=20")
EOF
)

echo "Selected profile -> Exposure Mode: $EXPOSURE, Time: $EXP_TIME, Skip Frames: $SKIP_FRAMES"

# Define your camera pairs (Device, Flip argument, Image filename)
cameras=(
    "/dev/video0|$FLIP_ARG1|$IMAGE1"
    "/dev/video2|$FLIP_ARG2|$IMAGE2"
)

capture_image() {
    local dev="$1"
    local flip="$2"
    local TEMP_IMAGE="$3"
    local CACHE_FILE="/tmp/camera_devices.cache"

    # Run the capture command
    fswebcam --set auto_exposure="$EXPOSURE" \
             --set exposure_time_absolute="$EXP_TIME" \
             --set focus_absolute=0 \
             -S "$SKIP_FRAMES" \
             $flip -d "$dev" -r 1280x720 --no-banner "$TEMP_IMAGE"

    # Check if capture failed (non-zero exit code or missing output image)
    if [ $? -ne 0 ] || [ ! -f "$TEMP_IMAGE" ]; then
        echo "$(date): Capture failed on $dev. Attempting hardware recovery..."
        
        if [ -f "$CACHE_FILE" ]; then
            # Look up the specific sysfs path for this exact video device node from the cache
            sys_path=$(awk -F'|' -v target="$dev" '$1 == target {print $4}' "$CACHE_FILE")
            
            if [ -n "$sys_path" ] && [ -d "$sys_path" ]; then
                echo "$(date): Resetting USB port at $sys_path..."
                
                # Cut power to the port[cite: 1]
                echo 0 > "$sys_path/authorized" 2>/dev/null
                sleep 2
                
                # Restore power to force re-enumeration[cite: 1]
                echo 1 > "$sys_path/authorized" 2>/dev/null
                sleep 4 # Give the camera time to reinitialize
                
                if [ -f "$CACHE_FILE" ]; then
                    #retry capture
                    capture_image "$dev" "$flip" "$TEMP_IMAGE"
                fi
                # Remove cache so it rebuilds fresh paths/nodes on next check
                rm -f "$CACHE_FILE"
            else
                echo "$(date): Error: Could not find matching sysfs path for $dev in cache."
            fi
        else
            echo "$(date): Error: Cache file $CACHE_FILE does not exist."
        fi
    fi
}

# 1. Overlay timestamp and save as the "live" pointer
for cam in "${cameras[@]}"; do
    IFS='|' read -r dev flip img <<< "$cam"
    IMAGE_NAME=$(basename $img)
    TEMP_IMAGE="/tmp/$IMAGE_NAME"
 
    capture_image "$dev" "$flip" "$TEMP_IMAGE"

    # 2. Overlay timestamp and save to final destination
    convert "$TEMP_IMAGE" \
      -gravity SouthEast \
      -background 'rgba(0, 0, 0, 0.5)' \
      -fill white \
      -font Helvetica \
      -pointsize 18 \
      -splice 0x28 \
      -annotate +10+5 " $DATETIMESTAMP " \
      "$img"

    rm $TEMP_IMAGE
done


# 3. Enter repo, commit, and push
cd "$REPO_DIR" || exit 1
git fetch origin "$BRANCH"
git reset --hard "origin/$BRANCH"

cp "$SCRIPT_PATH" "${REPO_DIR}"

if [ "$HOSTNAME" == "art" ]; then
	cp $IMAGE1 "${REPO_DIR}/snapshot-1.jpg"
	cp $IMAGE2 "${REPO_DIR}/snapshot-2.jpg"
elif [ "$HOSTNAME" == "library" ]; then
	cp $IMAGE1 "${REPO_DIR}/snapshot-3.jpg"
	cp $IMAGE2 "${REPO_DIR}/snapshot-4.jpg"
elif [ "$HOSTNAME" == "aaliyah" ]; then
	cp $IMAGE1 "${REPO_DIR}/snapshot-5.jpg"
	cp $IMAGE2 "${REPO_DIR}/snapshot-6.jpg"

    extra_cam_images=(
	    "storefront-corner.jpg|$IMAGE3|snapshot-7.jpg"
	    "storefront-edge.jpg|$IMAGE4|snapshot-8.jpg"
	    "storefront-front.jpg|$IMAGE5|snapshot-9.jpg"
	    "storefront-tower.jpg|$IMAGE6|snapshot-10.jpg"
	    "storefront-kitchen.jpg|$IMAGE7|snapshot-11.jpg"
        "garage-north.jpg|$IMAGE8|snapshot-12.jpg"
    )

    for extra in "${extra_cam_images[@]}"; do
        IFS='|' read -r image_name image_var snapshot_name <<< "$extra"
            
        cp ~/ha-storage/${image_name} $TEMP_IMAGE
        # 2. Overlay timestamp and save to final destination
        convert "$TEMP_IMAGE" \
            -gravity SouthEast \
            -background 'rgba(0, 0, 0, 0.5)' \
            -fill white \
            -font Helvetica \
            -pointsize 18 \
            -splice 0x28 \
            -annotate +10+5 " $DATETIMESTAMP " \
            "$image_var"
	    cp $image_var "${REPO_DIR}/${snapshot_name}"
    done
fi

arr=($SPARSE_FILE_LIST); SPARSE_FILE_LIST="${arr[@]#/}"
git add $SPARSE_FILE_LIST
git status
git commit -m "Auto-update snapshot: $(date -u)"
git push origin "$BRANCH"

# cleanup
rm -fR $REPO_DIR
