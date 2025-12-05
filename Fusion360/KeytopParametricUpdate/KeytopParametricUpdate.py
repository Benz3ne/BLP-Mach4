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

WATCH_DIR = r"C:\Users\benja\Downloads"
current_piano_id = None  # Track current piano being processed

def log(msg):
    """Write debug info to debug log file"""
    if current_piano_id:
        gcode_folder = os.path.join(WATCH_DIR, f"GCode_{current_piano_id}")
        os.makedirs(gcode_folder, exist_ok=True)
        debug_log_path = os.path.join(gcode_folder, f"DEBUG_{current_piano_id}.txt")

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

    if not (left_points and right_points and front_points):
        return None

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
            input_data = {}
            if args.additionalInfo:
                try:
                    input_data = json.loads(args.additionalInfo)
                    csv_path = input_data.get('csv_path', '')
                    piano_id = input_data.get('piano_id', 'Unknown')

                    # Determine section from CSV filename
                    if '_Upper.csv' in csv_path:
                        section = 'Upper'
                    elif '_Lower.csv' in csv_path:
                        section = 'Lower'

                    # Set global piano ID for logging
                    global current_piano_id
                    current_piano_id = piano_id

                    # Now we have piano_id, start logging
                    log(f"Processing probe data event - {piano_id} {section} section")
                    result.append(f"Processing: {piano_id} - {section} section")
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
                    # Create output folder
                    gcode_folder = os.path.join(WATCH_DIR, f"GCode_{piano_id}")
                    os.makedirs(gcode_folder, exist_ok=True)

                    # Check for existing parameters file
                    params_file = os.path.join(gcode_folder, f"PARAMETERS_{piano_id}.txt")
                    existing_params = {}
                    sections_processed = set()

                    if os.path.exists(params_file):
                        log(f"Found existing parameters file for {piano_id}")
                        with open(params_file, 'r') as f:
                            for line in f:
                                if '=' in line and not line.startswith('#'):
                                    key, value = line.strip().split('=', 1)
                                    # Only convert numeric values to float
                                    if key in ['ShoulderLength', 'KeyHeight']:
                                        existing_params[key] = float(value)
                                    else:
                                        existing_params[key] = value
                                elif line.startswith('# Upper Section') or line.startswith('# Lower Section'):
                                    # Track which sections have been processed
                                    if 'Upper' in line:
                                        sections_processed.add('Upper')
                                    elif 'Lower' in line:
                                        sections_processed.add('Lower')

                    # Check if this section was already processed
                    if section in sections_processed:
                        log(f"WARNING: {section} section already processed for {piano_id}")
                        result.append(f"WARNING: {section} section already processed")
                        result.append("Re-processing with same parameters...")

                        # Clean up old G-code files for this section
                        if os.path.exists(gcode_folder):
                            for file in os.listdir(gcode_folder):
                                if file.endswith('.tap') or file.endswith('.nc') or file.endswith('.cnc'):
                                    file_lower = file.lower()
                                    # Remove old files for this section
                                    if section == 'Upper' and 'upper' in file_lower:
                                        os.remove(os.path.join(gcode_folder, file))
                                        log(f"Removed old file: {file}")
                                    elif section == 'Lower' and 'lower' in file_lower:
                                        os.remove(os.path.join(gcode_folder, file))
                                        log(f"Removed old file: {file}")

                    # Parse CSV and calculate parameters
                    if csv_path and os.path.exists(csv_path):
                        log(f"Parsing CSV: {csv_path}")
                        probe_data = parse_csv(csv_path)
                        log(f"Found data for {len(probe_data)} keys")

                        # Use existing global params if available, else calculate new ones
                        if 'ShoulderLength' in existing_params and 'KeyHeight' in existing_params:
                            shoulder_length = existing_params['ShoulderLength']
                            key_height = existing_params['KeyHeight']
                            log(f"Using existing global params: ShoulderLength={shoulder_length:.4f}, KeyHeight={key_height:.4f}")
                            result.append(f"Using existing global parameters from previous {piano_id} probe")
                        else:
                            shoulder_length, key_height = calculate_global_params(probe_data)
                            log(f"Calculated new global params: ShoulderLength={shoulder_length:.4f}, KeyHeight={key_height:.4f}")

                            # Save parameters for future use
                            with open(params_file, 'w') as f:
                                f.write(f"ShoulderLength={shoulder_length}\n")
                                f.write(f"KeyHeight={key_height}\n")
                                f.write(f"FirstSection={section}\n")
                            log(f"Saved global parameters to {params_file}")

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

                            # Log progress every 5 keys
                            if (idx + 1) % 5 == 0:
                                log(f"Updated parameters for {idx + 1}/{len(key_params)} keys. Total params: {updated_count}")

                        result.append(f"Updated {updated_count} parameters")
                        log(f"All parameters updated. Count: {updated_count}")

                        # Save all key parameters to file for reference
                        if section not in sections_processed:
                            # Section not processed before
                            if not os.path.exists(params_file):
                                # First section ever, create new file
                                with open(params_file, 'w') as f:
                                    f.write(f"ShoulderLength={shoulder_length}\n")
                                    f.write(f"KeyHeight={key_height}\n")
                                    f.write(f"FirstSection={section}\n")
                                    f.write(f"\n# {section} Section Parameters\n")
                                    for key_num, params in sorted(key_params.items()):
                                        f.write(f"\nKey{key_num}:\n")
                                        for param, value in params.items():
                                            f.write(f"  {param}={value}\n")
                            else:
                                # Append this new section's parameters
                                with open(params_file, 'a') as f:
                                    f.write(f"\n# {section} Section Parameters\n")
                                    for key_num, params in sorted(key_params.items()):
                                        f.write(f"\nKey{key_num}:\n")
                                        for param, value in params.items():
                                            f.write(f"  {param}={value}\n")
                        # else: Section already processed, parameters already in file

                        # Resume computation - this triggers ONE geometry rebuild
                        design.isComputeDeferred = False
                        log("Resuming geometry computation (this may take a few minutes)...")
                        adsk.doEvents()  # Let Fusion recalculate

                        # Switch to Manufacturing workspace for CAM operations
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

                        # Regenerate only relevant toolpaths
                        cam = adsk.cam.CAM.cast(doc.products.itemByProductType('CAMProductType'))
                        if cam and cam.setups.count > 0:
                            # Determine which toolpaths to regenerate based on section
                            relevant_setups = []
                            for i in range(cam.setups.count):
                                setup = cam.setups.item(i)
                                setup_name = setup.name.lower()

                                # Always include Initial Trim (but only export once)
                                if 'initial' in setup_name or 'trim' in setup_name:
                                    relevant_setups.append(setup)
                                # Include Upper setups only for Upper section
                                elif section == 'Upper' and 'upper' in setup_name:
                                    relevant_setups.append(setup)
                                # Include Lower setups only for Lower section
                                elif section == 'Lower' and 'lower' in setup_name:
                                    relevant_setups.append(setup)

                            result.append(f"Regenerating {len(relevant_setups)} relevant toolpaths for {section} section")
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
                                    if elapsed % 30 == 0:  # Log progress every 30 seconds
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

                            # Export G-code only for relevant programs
                            if hasattr(cam, 'ncPrograms'):
                                # Check if Initial Trim already exists
                                initial_trim_exists = any(
                                    os.path.exists(os.path.join(gcode_folder, f))
                                    for f in os.listdir(gcode_folder)
                                    if 'initial' in f.lower() or 'trim' in f.lower()
                                ) if os.path.exists(gcode_folder) else False

                                exported_count = 0
                                for i in range(cam.ncPrograms.count):
                                    prog = cam.ncPrograms.item(i)
                                    prog_name_lower = prog.name.lower()

                                    # Skip if not relevant to this section
                                    if section == 'Upper':
                                        # For Upper: export Upper programs and Initial Trim (if not exists)
                                        if 'lower' in prog_name_lower:
                                            continue
                                        if ('initial' in prog_name_lower or 'trim' in prog_name_lower) and initial_trim_exists:
                                            log(f"Skipping {prog.name} - already exported")
                                            continue
                                    elif section == 'Lower':
                                        # For Lower: export Lower programs and Initial Trim (if not exists)
                                        if 'upper' in prog_name_lower:
                                            continue
                                        if ('initial' in prog_name_lower or 'trim' in prog_name_lower) and initial_trim_exists:
                                            log(f"Skipping {prog.name} - already exported")
                                            continue

                                    if prog.postConfiguration:
                                        try:
                                            # Export with original name (Fusion ignores our programName)
                                            opts = adsk.cam.NCProgramPostProcessOptions.create()
                                            opts.postConfiguration = prog.postConfiguration
                                            opts.outputFolder = WATCH_DIR
                                            opts.programName = prog.name  # This gets ignored anyway
                                            prog.postProcess(opts)

                                            # Find and move the exported file
                                            # Look for file with just the program name (no piano ID)
                                            for ext in ['.tap', '.nc', '.cnc']:
                                                source_file = os.path.join(WATCH_DIR, f"{prog.name}{ext}")
                                                if os.path.exists(source_file):
                                                    # Rename with piano ID and move to folder
                                                    dest_name = f"{prog.name}_{piano_id}{ext}"
                                                    dest_file = os.path.join(gcode_folder, dest_name)

                                                    if os.path.exists(dest_file):
                                                        os.remove(dest_file)
                                                    os.rename(source_file, dest_file)

                                                    exported_count += 1
                                                    result.append(f"Exported: {dest_name}")
                                                    log(f"Moved {prog.name}{ext} to {dest_name}")
                                                    break
                                            else:
                                                log(f"Warning: Could not find exported file {prog.name}.*")

                                        except Exception as e:
                                            result.append(f"ERROR exporting {prog.name}: {e}")
                                            log(f"Export error: {e}")

                                result.append(f"Complete! Exported {exported_count} files to: {gcode_folder}")

                                result.append(f"Complete! Files in: {gcode_folder}")
                        else:
                            result.append("ERROR: No CAM setups found")
                    else:
                        result.append(f"ERROR: CSV file not found: {csv_path}")

            # Write summary to log file (not the debug details)
            if piano_id != 'Unknown':
                gcode_folder = os.path.join(WATCH_DIR, f"GCode_{piano_id}")
                os.makedirs(gcode_folder, exist_ok=True)

                log_file = os.path.join(gcode_folder, f"LOG_{piano_id}.txt")
                timestamp = time.strftime("%Y-%m-%d %H:%M:%S")

                # Write clean summary to log file
                with open(log_file, 'a') as f:
                    f.write(f"\n{timestamp} - {section} Section\n")
                    for line in result:
                        if line.startswith("ERROR") or line.startswith("WARNING"):
                            f.write(f"  {line}\n")
                        elif "Complete!" in line or "Exported" in line or "Updated" in line:
                            f.write(f"  {line}\n")
                    f.write("\n")

            # Write simple completion marker for external script
            response_path = os.path.join(WATCH_DIR, f"COMPLETE_{piano_id}.txt")
            with open(response_path, 'w') as f:
                if any("ERROR" in line for line in result):
                    f.write("ERROR\n")
                else:
                    f.write("SUCCESS\n")

        except:
            error_msg = traceback.format_exc()
            log(f"Error: {error_msg}")
            error_path = os.path.join(WATCH_DIR, "ERROR.txt")
            with open(error_path, 'w') as f:
                f.write(error_msg)


class WatchThread(threading.Thread):
    def __init__(self):
        super().__init__()
        self.daemon = True

    def run(self):
        trigger_pattern = "PROBE_COMPLETE_"

        while not stop_flag.is_set():
            try:
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

        ui.messageBox("Keytop Parametric Update started!\nWatching for probe data...")

    except:
        error = traceback.format_exc()
        if ui:
            ui.messageBox(f'Failed:\n{error}')


def stop(context):
    global watch_thread, custom_event, _handlers
    try:
        stop_flag.set()
        if watch_thread:
            watch_thread.join(timeout=5)

        if custom_event:
            app.unregisterCustomEvent(custom_event_id)

        _handlers.clear()
    except:
        pass  # Silently fail on stop