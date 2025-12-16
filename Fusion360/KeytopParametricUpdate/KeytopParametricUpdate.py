"""
Keytop Parametric Update Add-in
Watches for probe completion, updates parameters, regenerates toolpaths, exports G-code
"""

import adsk.core
import adsk.fusion
import adsk.cam
import threading
import time
import os
import csv
import json
import math
import traceback

# Global variables
app = None
ui = None
watch_thread = None
stop_flag = threading.Event()
custom_event = None
custom_event_id = 'ProbeDataProcessEvent'
_handlers = []

# Configuration (from KeyParameterUpdate.py)
CONFIG = {
    'key_height_offset': 0.079,
    'max_rotation': 2.0,
    'angle_step': 0.01,
    'tail_weight': 3,
    'band_split_y': 0.75,
    'max_points_per_band': 6,
    'min_points_per_band': 3,
    'front_overhang': 0.005,
}

# Network path to Mach4 Logs folder on CNC machine (BLPCN)
# The add-in watches this folder for probe completion triggers and exports G-code here
MACH4_LOGS_DIR = r"\\BLPCNC\Mach4Hobby\Profiles\BLP\Logs"
# Local watch directory for trigger files (ProbeKeys writes triggers here)
WATCH_DIR = MACH4_LOGS_DIR
# Heartbeat file path - written every 5 seconds to indicate add-in is running
HEARTBEAT_FILE = os.path.join(MACH4_LOGS_DIR, "FUSION_HEARTBEAT.txt")
HEARTBEAT_INTERVAL = 5  # seconds between heartbeat writes

current_piano_id = None  # Track current piano being processed
current_section = None   # Track current section being processed


def update_progress(status, step, detail=""):
    """Log progress update (previously wrote to ACK file, now just logs)"""
    if current_piano_id:
        log(f"Progress: {status} - {step}" + (f" ({detail})" if detail else ""))


def get_piano_folder(piano_id):
    """Get the path to the piano's folder in Logs directory"""
    return os.path.join(MACH4_LOGS_DIR, piano_id)


def log(msg):
    """Write debug info to debug log file"""
    if current_piano_id:
        piano_folder = get_piano_folder(current_piano_id)
        os.makedirs(piano_folder, exist_ok=True)
        debug_log_path = os.path.join(piano_folder, f"DEBUG_{current_piano_id}.txt")

        with open(debug_log_path, 'a') as f:
            f.write(f"{time.strftime('%H:%M:%S')} - {msg}\n")


def median(values):
    """Calculate median of a list"""
    if not values:
        return 0
    sorted_vals = sorted(values)
    n = len(sorted_vals)
    if n % 2:
        return sorted_vals[n//2]
    return (sorted_vals[n//2-1] + sorted_vals[n//2]) / 2.0


def rotate_point(point, angle_deg, center):
    """Rotate a point around a center by angle in degrees"""
    angle_rad = math.radians(angle_deg)
    cos_a = math.cos(angle_rad)
    sin_a = math.sin(angle_rad)
    dx = point[0] - center[0]
    dy = point[1] - center[1]
    return [
        dx * cos_a - dy * sin_a + center[0],
        dx * sin_a + dy * cos_a + center[1]
    ]


def is_white_key(key_num):
    """Check if a piano key number is a white key"""
    midi = key_num + 20
    note = ['C','C#','D','D#','E','F','F#','G','G#','A','A#','B'][midi % 12]
    return note in ['C','D','E','F','G','A','B']


def key_shoulders(key_num):
    """Determine shoulder type for a key"""
    if key_num == 1:
        return "right"
    if key_num == 88:
        return "none"
    midi = key_num + 20
    note = ['C','C#','D','D#','E','F','F#','G','G#','A','A#','B'][midi % 12]
    if note in ('B','E'):
        return "left"
    if note in ('F','C'):
        return "right"
    if note in ('D','G','A'):
        return "both"
    return "none"


def parse_csv(csv_path):
    """Parse probe data from CSV into structured format"""
    data = {}
    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            key = int(row['PianoKey#'])
            if key not in data:
                data[key] = {str(i): [] for i in range(1, 6)}

            direction = int(row['Direction'])
            if direction <= 5:
                point = {
                    'X': float(row['X']),
                    'Y': float(row['Y']),
                    'Z': float(row.get('Z', 0))
                }
                data[key][str(direction)].append(point)
    return data


def calculate_global_params(probe_data):
    """Calculate shoulder length and key height from all keys"""
    shoulder_diffs = []
    z_values = []

    for key_data in probe_data.values():
        # Shoulder length: max difference between Y3 and Y4
        if key_data['3'] and key_data['4']:
            y3_median = median([p['Y'] for p in key_data['3']])
            y4_median = median([p['Y'] for p in key_data['4']])
            shoulder_diffs.append(abs(y4_median - y3_median))

        # Collect Z values from direction 5
        if key_data['5']:
            z_values.extend([p['Z'] for p in key_data['5']])

    shoulder_length = max(shoulder_diffs) if shoulder_diffs else 0
    key_height = median(z_values) - CONFIG['key_height_offset'] if z_values else 0

    return shoulder_length, key_height


def optimize_angle(left_points, right_points, center):
    """Find the optimal rotation angle to minimize slack"""
    if not left_points or not right_points:
        return 0

    best_angle = 0
    best_metric = float('inf')

    # Split points into bands for metric calculation
    left_front = [p for p in left_points if p[1] <= CONFIG['band_split_y']]
    left_tail = [p for p in left_points if p[1] > CONFIG['band_split_y']]
    right_front = [p for p in right_points if p[1] <= CONFIG['band_split_y']]
    right_tail = [p for p in right_points if p[1] > CONFIG['band_split_y']]

    # Search for best angle
    for angle_int in range(int(-CONFIG['max_rotation']/CONFIG['angle_step']),
                          int(CONFIG['max_rotation']/CONFIG['angle_step']) + 1):
        angle = angle_int * CONFIG['angle_step']

        # Rotate all bands
        lf_rot = [rotate_point(p, angle, center) for p in left_front]
        lt_rot = [rotate_point(p, angle, center) for p in left_tail]
        rf_rot = [rotate_point(p, angle, center) for p in right_front]
        rt_rot = [rotate_point(p, angle, center) for p in right_tail]

        # Calculate walls
        xl_outer = min(
            min((p[0] for p in lf_rot), default=float('inf')),
            min((p[0] for p in lt_rot), default=float('inf'))
        )
        xr_outer = max(
            max((p[0] for p in rf_rot), default=float('-inf')),
            max((p[0] for p in rt_rot), default=float('-inf'))
        )

        # Calculate slack for each band
        front_slack = (
            max((p[0] - xl_outer for p in lf_rot), default=0) +
            max((xr_outer - p[0] for p in rf_rot), default=0)
        )
        tail_slack = (
            max((p[0] - xl_outer for p in lt_rot), default=0) +
            max((xr_outer - p[0] for p in rt_rot), default=0)
        )

        # Weighted metric
        metric = front_slack + CONFIG['tail_weight'] * tail_slack

        if metric < best_metric:
            best_metric = metric
            best_angle = angle

    return best_angle


def calculate_key_params(left_points, right_points, front_points, center, angle, key_num):
    """Calculate final parameters for a key"""
    # Rotate all points
    left_rot = [rotate_point(p, angle, center) for p in left_points]
    right_rot = [rotate_point(p, angle, center) for p in right_points]
    front_rot = [rotate_point(p, angle, center) for p in front_points]

    # Split into bands
    left_front = [p for p in left_rot if rotate_point(p, -angle, center)[1] <= CONFIG['band_split_y']]
    left_tail = [p for p in left_rot if rotate_point(p, -angle, center)[1] > CONFIG['band_split_y']]
    right_front = [p for p in right_rot if rotate_point(p, -angle, center)[1] <= CONFIG['band_split_y']]
    right_tail = [p for p in right_rot if rotate_point(p, -angle, center)[1] > CONFIG['band_split_y']]

    # Calculate walls
    xl_front = min((p[0] for p in left_front), default=0)
    xl_tail = min((p[0] for p in left_tail), default=0)
    xr_front = max((p[0] for p in right_front), default=0)
    xr_tail = max((p[0] for p in right_tail), default=0)

    xl_outer = min(xl_front, xl_tail)
    xl_inner = max(xl_front, xl_tail)
    xr_outer = max(xr_front, xr_tail)
    xr_inner = min(xr_front, xr_tail)

    # Apply front overhang if needed
    if xl_front <= xl_tail:
        xl_outer -= CONFIG['front_overhang']
    if xr_front >= xr_tail:
        xr_outer += CONFIG['front_overhang']

    # Calculate center X
    y_front = median([p[1] for p in front_rot])
    front_left = rotate_point([xl_outer, y_front], -angle, center)
    front_right = rotate_point([xr_outer, y_front], -angle, center)
    center_x = (front_left[0] + front_right[0]) / 2.0

    # Calculate width and steps
    width = xr_outer - xl_outer
    left_step = xl_inner - xl_outer if key_shoulders(key_num) in ['left', 'both'] else 0
    right_step = xr_outer - xr_inner if key_shoulders(key_num) in ['right', 'both'] else 0

    return {
        'X': center_x,
        'Angle': -angle,  # Inverted for Fusion
        'Width': width,
        'LStep': left_step,
        'RStep': right_step
    }


def process_key(key_num, key_data):
    """Process a single key: optimize angle and calculate parameters"""
    # Get point sets
    left_points = [[p['X'], p['Y']] for p in key_data.get('1', [])]
    right_points = [[p['X'], p['Y']] for p in key_data.get('2', [])]
    front_points = [[p['X'], p['Y']] for p in key_data.get('3', [])]

    if not (left_points and right_points):
        return None

    # If no front probing data, synthesize front points at Y=-1.2 using leftmost/rightmost X values
    if not front_points:
        default_front_y = -1.2
        # Get the frontmost X measurements from left and right edges
        left_front_x = min(p[0] for p in left_points)
        right_front_x = max(p[0] for p in right_points)
        front_points = [[left_front_x, default_front_y], [right_front_x, default_front_y]]

    # Calculate center
    all_points = left_points + right_points + front_points
    center = [
        sum(p[0] for p in all_points) / len(all_points),
        sum(p[1] for p in all_points) / len(all_points)
    ]

    # Find optimal angle
    best_angle = optimize_angle(left_points, right_points, center)

    # Calculate final parameters
    params = calculate_key_params(
        left_points, right_points, front_points, center, best_angle, key_num
    )

    return params


class ProbeDataHandler(adsk.core.CustomEventHandler):
    def __init__(self):
        super().__init__()

    def notify(self, args):
        result = []
        piano_id = 'Unknown'
        section = 'Unknown'  # Upper or Lower

        try:
            # Parse input data
            # New folder structure: {Make}_{Serial}_{Section}/ with CSV: {Make}_{Serial}_{Section}.csv
            input_data = {}
            if args.additionalInfo:
                try:
                    input_data = json.loads(args.additionalInfo)
                    csv_path = input_data.get('csv_path', '')
                    # piano_id now includes section: {Make}_{Serial}_{Section}
                    piano_id = input_data.get('piano_id', 'Unknown')

                    # Determine section from piano_id (last part after underscore)
                    if piano_id.endswith('_Upper'):
                        section = 'Upper'
                    elif piano_id.endswith('_Lower'):
                        section = 'Lower'
                    else:
                        # Fallback: try to get from CSV filename
                        if '_Upper' in csv_path:
                            section = 'Upper'
                        elif '_Lower' in csv_path:
                            section = 'Lower'

                    # Set global piano ID and section for logging and progress updates
                    global current_piano_id, current_section
                    current_piano_id = piano_id
                    current_section = section

                    # Update acknowledgement file to show PROCESSING status
                    update_progress("PROCESSING", "Starting", f"Received trigger for {piano_id}")

                    # Now we have piano_id, start logging
                    log(f"Processing probe data event - {piano_id}")
                    result.append(f"Processing: {piano_id}")
                except:
                    result.append("ERROR: No valid input data")
                    csv_path = ''
            else:
                result.append("ERROR: No input data provided")
                csv_path = ''

            doc = app.activeDocument
            if not doc:
                result.append("ERROR: No active document")
            else:
                # Get design from document's products, not activeProduct
                # This works regardless of which workspace is active
                design = None
                for product in doc.products:
                    if product.objectType == 'adsk::fusion::Design':
                        design = adsk.fusion.Design.cast(product)
                        break

                if not design:
                    result.append("ERROR: No design found in document")
                else:
                    # Use the piano folder in Logs directory (same folder ProbeKeys uses)
                    piano_folder = get_piano_folder(piano_id)
                    os.makedirs(piano_folder, exist_ok=True)

                    # Check for existing shaping file for this section and remove it
                    if os.path.exists(piano_folder):
                        for file in os.listdir(piano_folder):
                            if file.endswith('.tap') or file.endswith('.nc') or file.endswith('.cnc'):
                                file_lower = file.lower()
                                # Remove old shaping files for this section
                                if section == 'Upper' and 'upper' in file_lower and 'shaping' in file_lower:
                                    os.remove(os.path.join(piano_folder, file))
                                    log(f"Removed old file: {file}")
                                elif section == 'Lower' and 'lower' in file_lower and 'shaping' in file_lower:
                                    os.remove(os.path.join(piano_folder, file))
                                    log(f"Removed old file: {file}")

                    # Parse CSV and calculate parameters
                    if csv_path and os.path.exists(csv_path):
                        update_progress("PROCESSING", "Parsing CSV", csv_path)
                        log(f"Parsing CSV: {csv_path}")
                        probe_data = parse_csv(csv_path)
                        log(f"Found data for {len(probe_data)} keys")

                        # Each section is treated independently - calculate params from this section's data only
                        shoulder_length, key_height = calculate_global_params(probe_data)
                        log(f"Calculated {section} section params: ShoulderLength={shoulder_length:.4f}, KeyHeight={key_height:.4f}")

                        # Process each white key in this section
                        # Upper section: keys 1-26, Lower section: keys 27-52
                        white_keys = [k for k in sorted(probe_data.keys()) if is_white_key(k)]
                        log(f"Processing {len(white_keys)} white keys in {section} section")
                        key_params = {}

                        for key_num in white_keys:
                            params = process_key(key_num, probe_data[key_num])
                            if params:
                                key_params[key_num] = params
                        log(f"Calculated parameters for {len(key_params)} keys")

                        # Switch to Design workspace for parameter updates
                        update_progress("PROCESSING", "Switching workspace", "Design workspace")
                        log("Switching to Design workspace...")
                        design_ws = ui.workspaces.itemById('FusionSolidEnvironment')
                        if design_ws:
                            design_ws.activate()
                            adsk.doEvents()
                            time.sleep(1)  # Let workspace fully load
                            log("Switched to Design workspace")
                        else:
                            log("Warning: Could not find Design workspace")

                        # Update Fusion parameters
                        user_params = design.userParameters
                        updated_count = 0

                        # Suspend computation during parameter updates for speed
                        design.isComputeDeferred = True
                        update_progress("PROCESSING", "Updating parameters", f"0/{len(key_params)} keys")
                        log("Suspending geometry updates for batch parameter changes")

                        # Update global parameters
                        param = user_params.itemByName('ShoulderLength')
                        if param:
                            param.expression = f"{shoulder_length} in"
                            updated_count += 1

                        param = user_params.itemByName('KeyHeight')
                        if param:
                            param.expression = f"{key_height} in"
                            updated_count += 1

                        log(f"Updated global parameters. Count: {updated_count}")

                        # Update key parameters
                        for idx, (key_num, params) in enumerate(key_params.items()):
                            prefix = f'Key{key_num}'
                            for suffix, value in params.items():
                                param_name = f'{prefix}{suffix}'
                                param = user_params.itemByName(param_name)
                                if param and value:
                                    if suffix == 'Angle':
                                        param.expression = f"{value} deg"
                                    else:
                                        param.expression = f"{value} in"
                                    updated_count += 1

                            # Log and report progress every 5 keys
                            if (idx + 1) % 5 == 0:
                                log(f"Updated parameters for {idx + 1}/{len(key_params)} keys. Total params: {updated_count}")
                                update_progress("PROCESSING", "Updating parameters", f"{idx + 1}/{len(key_params)} keys")

                        result.append(f"Updated {updated_count} parameters")
                        log(f"All parameters updated. Count: {updated_count}")

                        # Resume computation - this triggers ONE geometry rebuild
                        update_progress("PROCESSING", "Rebuilding geometry", "This may take several minutes...")
                        design.isComputeDeferred = False
                        log("Resuming geometry computation (this may take a few minutes)...")
                        adsk.doEvents()  # Let Fusion recalculate

                        # Switch to Manufacturing workspace for CAM operations
                        update_progress("PROCESSING", "Switching workspace", "Manufacturing workspace")
                        log("Switching to Manufacturing workspace...")
                        manufacture_ws = ui.workspaces.itemById('CAMEnvironment')
                        if not manufacture_ws:
                            # Try alternate ID
                            manufacture_ws = ui.workspaces.itemById('FusionManufactureEnvironment')

                        if manufacture_ws:
                            manufacture_ws.activate()
                            adsk.doEvents()
                            time.sleep(1)  # Let workspace fully load
                            log("Switched to Manufacturing workspace")
                        else:
                            log("Warning: Could not find Manufacturing workspace")

                        # Regenerate only relevant toolpaths (Shaping programs only, no Initial Trim)
                        cam = adsk.cam.CAM.cast(doc.products.itemByProductType('CAMProductType'))
                        if cam and cam.setups.count > 0:
                            # Determine which toolpaths to regenerate based on section
                            # Only include Shaping setups - Initial Trim is handled by Mach4 directly
                            relevant_setups = []
                            for i in range(cam.setups.count):
                                setup = cam.setups.item(i)
                                setup_name = setup.name.lower()

                                # Only include Shaping setups for this section
                                if 'shaping' in setup_name:
                                    if section == 'Upper' and 'upper' in setup_name:
                                        relevant_setups.append(setup)
                                    elif section == 'Lower' and 'lower' in setup_name:
                                        relevant_setups.append(setup)

                            result.append(f"Regenerating {len(relevant_setups)} Shaping toolpaths for {section} section")
                            update_progress("PROCESSING", "Generating toolpaths", f"{len(relevant_setups)} setups")
                            log(f"Starting toolpath generation for {len(relevant_setups)} setups: {[s.name for s in relevant_setups]}")

                            try:
                                # Generate all toolpaths in one operation
                                future = cam.generateAllToolpaths(False)  # False = don't skip valid toolpaths

                                # Wait for all to complete
                                timeout = 1800  # 30 minutes for all toolpaths
                                start = time.time()
                                while not future.isGenerationCompleted:
                                    adsk.doEvents()
                                    time.sleep(2)
                                    elapsed = time.time() - start
                                    # Update progress every 10 seconds
                                    if int(elapsed) % 10 == 0:
                                        update_progress("PROCESSING", "Generating toolpaths", f"{elapsed:.0f}s elapsed")
                                    if int(elapsed) % 30 == 0:  # Log every 30 seconds
                                        log(f"Still generating toolpaths... {elapsed:.0f} seconds elapsed")
                                    if elapsed > timeout:
                                        result.append(f"Timeout after {elapsed:.0f} seconds")
                                        break
                                else:
                                    result.append(f"All toolpaths generated successfully")
                                    log("Toolpath generation complete")

                            except Exception as e:
                                result.append(f"ERROR generating toolpaths: {e}")
                                log(f"Toolpath generation error: {e}")

                            # Export G-code only for Shaping programs (no Initial Trim)
                            update_progress("PROCESSING", "Exporting G-code", "Starting export...")
                            log(f"Starting G-code export...")
                            if hasattr(cam, 'ncPrograms'):
                                log(f"Found {cam.ncPrograms.count} NC programs")
                                exported_count = 0
                                downloads_dir = os.path.join(os.environ['USERPROFILE'], 'Downloads')

                                for i in range(cam.ncPrograms.count):
                                    prog = cam.ncPrograms.item(i)
                                    prog_name_lower = prog.name.lower()
                                    log(f"Checking NC program: '{prog.name}'")

                                    # Only export Shaping programs for this section
                                    if 'shaping' not in prog_name_lower:
                                        log(f"  Skipping: not a shaping program")
                                        continue
                                    if section == 'Upper' and 'upper' not in prog_name_lower:
                                        log(f"  Skipping: not Upper section")
                                        continue
                                    if section == 'Lower' and 'lower' not in prog_name_lower:
                                        log(f"  Skipping: not Lower section")
                                        continue

                                    log(f"  Matched! Checking post configuration...")
                                    if prog.postConfiguration:
                                        log(f"  Post config: {prog.postConfiguration.name if hasattr(prog.postConfiguration, 'name') else 'present'}")
                                        try:
                                            # Post process the NC program to Downloads
                                            post_input = adsk.cam.PostProcessInput.create(
                                                prog.name,  # program name
                                                prog.postConfiguration,  # post config
                                                downloads_dir,  # output folder
                                                adsk.cam.PostOutputUnitOptions.DocumentUnitsOutput  # units
                                            )
                                            cam.postProcess(prog, post_input)
                                            log(f"  Post process completed")
                                            exported_count += 1

                                        except Exception as e:
                                            result.append(f"ERROR exporting {prog.name}: {e}")
                                            log(f"  Export error: {e}")
                                            log(f"  Traceback: {traceback.format_exc()}")
                                    else:
                                        log(f"  No post configuration set for this program")

                                # After post-processing, find and move the shaping files from Downloads
                                # Fusion always exports as "Upper Shaping.tap" or "Lower Shaping.tap"
                                expected_filename = f"{section} Shaping.tap"
                                source_file = os.path.join(downloads_dir, expected_filename)

                                log(f"Looking for exported file: {source_file}")

                                if os.path.exists(source_file):
                                    # Move to piano folder with piano_id in the name
                                    dest_name = f"{section} Shaping_{piano_id}.tap"
                                    dest_file = os.path.join(piano_folder, dest_name)

                                    log(f"Moving {source_file} to {dest_file}")
                                    if os.path.exists(dest_file):
                                        os.remove(dest_file)
                                    os.rename(source_file, dest_file)

                                    result.append(f"Exported: {dest_name}")
                                    log(f"SUCCESS: Moved {expected_filename} to {dest_file}")
                                else:
                                    result.append(f"ERROR: Expected file not found: {expected_filename}")
                                    log(f"ERROR: File not found in Downloads: {source_file}")

                                result.append(f"Complete! Exported {exported_count} Shaping file(s) to: {piano_folder}")
                                log(f"Export complete. {exported_count} files exported.")
                        else:
                            result.append("ERROR: No CAM setups found")
                    else:
                        result.append(f"ERROR: CSV file not found: {csv_path}")

            # Log completion (marker files removed for simplicity)
            if piano_id != 'Unknown':
                has_error = any("ERROR" in line for line in result)
                log(f"Processing complete - {'ERROR' if has_error else 'SUCCESS'}")

        except:
            error_msg = traceback.format_exc()
            log(f"Error: {error_msg}")


class WatchThread(threading.Thread):
    def __init__(self):
        super().__init__()
        self.daemon = True
        self.last_heartbeat = 0

    def write_heartbeat(self):
        """Write current timestamp to heartbeat file, only if correct document is open"""
        try:
            # Only send heartbeat if the Keytop Toolpath document is open
            doc = app.activeDocument
            if doc and doc.dataFile and doc.dataFile.name == "Parametrized Keytop Toolpath":
                with open(HEARTBEAT_FILE, 'w') as f:
                    f.write(str(time.time()))
            else:
                # Wrong document or no document - remove heartbeat if it exists
                if os.path.exists(HEARTBEAT_FILE):
                    os.remove(HEARTBEAT_FILE)
        except:
            pass  # Ignore errors (network issues, etc.)

    def run(self):
        trigger_pattern = "PROBE_COMPLETE_"

        # Write initial heartbeat
        self.write_heartbeat()
        self.last_heartbeat = time.time()

        while not stop_flag.is_set():
            try:
                # Write heartbeat every HEARTBEAT_INTERVAL seconds
                if time.time() - self.last_heartbeat >= HEARTBEAT_INTERVAL:
                    self.write_heartbeat()
                    self.last_heartbeat = time.time()

                # Check for trigger files
                for filename in os.listdir(WATCH_DIR):
                    if filename.startswith(trigger_pattern) and filename.endswith(".txt"):
                        trigger_path = os.path.join(WATCH_DIR, filename)

                        # Read trigger data
                        data = ''
                        try:
                            with open(trigger_path, 'r') as f:
                                data = f.read()
                        except:
                            pass

                        # Delete trigger
                        os.remove(trigger_path)

                        # Fire event
                        app.fireCustomEvent(custom_event_id, data)

            except Exception as e:
                pass  # Ignore watch errors

            time.sleep(2)


def run(context):
    global app, ui, watch_thread, custom_event, _handlers

    try:
        app = adsk.core.Application.get()
        ui = app.userInterface

        # Register custom event
        custom_event = app.registerCustomEvent(custom_event_id)
        handler = ProbeDataHandler()
        custom_event.add(handler)
        _handlers.append(handler)  # Keep reference

        # Start watch thread
        stop_flag.clear()
        watch_thread = WatchThread()
        watch_thread.start()

    except:
        error = traceback.format_exc()
        # Log error to file instead of popup
        try:
            error_log_path = os.path.join(MACH4_LOGS_DIR, "FUSION_ERROR.txt")
            with open(error_log_path, 'w') as f:
                f.write(f"Startup error at {time.strftime('%Y-%m-%d %H:%M:%S')}\n")
                f.write(error)
        except:
            pass


def stop(context):
    global watch_thread, custom_event, _handlers
    try:
        stop_flag.set()
        if watch_thread:
            watch_thread.join(timeout=5)

        if custom_event:
            app.unregisterCustomEvent(custom_event_id)

        _handlers.clear()

        # Remove heartbeat file on clean shutdown
        try:
            if os.path.exists(HEARTBEAT_FILE):
                os.remove(HEARTBEAT_FILE)
        except:
            pass
    except:
        pass  # Silently fail on stop