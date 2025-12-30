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
import shutil

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
    'plastic_thickness': 0.09,  # Added to shoulder length calculation
    'max_rotation': 2.0,
    'angle_step': 0.01,
    'tail_weight': 3,
    'band_split_y': 0.75,
    'max_points_per_band': 6,
    'min_points_per_band': 3,
    'front_overhang': 0.005,
    'tail_overhang': 0.01,
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


def update_progress(step, detail=""):
    """Log progress update with timestamp"""
    msg = f"[PROGRESS] {step}"
    if detail:
        msg += f" - {detail}"
    log(msg)


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


def percentile(values, p):
    """Calculate percentile of a list (p is 0-100)"""
    if not values:
        return 0
    sorted_vals = sorted(values)
    n = len(sorted_vals)
    k = (n - 1) * p / 100.0
    f = int(k)
    c = f + 1 if f + 1 < n else f
    return sorted_vals[f] + (k - f) * (sorted_vals[c] - sorted_vals[f])


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
    y_front_values = []  # Direction 3 (+Y front edge)
    y_back_values = []   # Direction 4 (-Y shoulder/back edge)
    z_values = []

    for key_data in probe_data.values():
        # Collect Y front values (Direction 3)
        if key_data['3']:
            y_front_values.extend([p['Y'] for p in key_data['3']])

        # Collect Y back/shoulder values (Direction 4)
        if key_data['4']:
            y_back_values.extend([p['Y'] for p in key_data['4']])

        # Collect Z values from direction 5
        if key_data['5']:
            z_values.extend([p['Z'] for p in key_data['5']])

    # Shoulder length: difference between median front Y and 75th percentile back Y
    # Using 75th percentile for back to skew shoulder width larger
    # Add plastic thickness to account for material on front edge
    if y_front_values and y_back_values:
        median_front_y = median(y_front_values)
        p75_back_y = percentile(y_back_values, 75)
        shoulder_length = abs(p75_back_y - median_front_y) + CONFIG['plastic_thickness']
    else:
        shoulder_length = 0

    key_height = median(z_values) if z_values else 0

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

    # Calculate walls with overhangs applied to each region
    # Left side: subtract overhang (move left/more negative)
    # Right side: add overhang (move right/more positive)
    xl_front = min((p[0] for p in left_front), default=0) - CONFIG['front_overhang']
    xl_tail = min((p[0] for p in left_tail), default=0) - CONFIG['tail_overhang']
    xr_front = max((p[0] for p in right_front), default=0) + CONFIG['front_overhang']
    xr_tail = max((p[0] for p in right_tail), default=0) + CONFIG['tail_overhang']

    xl_outer = min(xl_front, xl_tail)
    xl_inner = max(xl_front, xl_tail)
    xr_outer = max(xr_front, xr_tail)
    xr_inner = min(xr_front, xr_tail)

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
        piano_id = 'Unknown'
        section = 'Unknown'  # Upper or Lower
        success = False
        error_msg = None

        try:
            # Parse input data
            input_data = {}
            if args.additionalInfo:
                try:
                    input_data = json.loads(args.additionalInfo)
                    csv_path = input_data.get('csv_path', '')
                    piano_id = input_data.get('piano_id', 'Unknown')

                    # Determine section from piano_id
                    if piano_id.endswith('_Upper'):
                        section = 'Upper'
                    elif piano_id.endswith('_Lower'):
                        section = 'Lower'
                    elif '_Upper' in csv_path:
                        section = 'Upper'
                    elif '_Lower' in csv_path:
                        section = 'Lower'

                    # Set global piano ID and section for logging
                    global current_piano_id, current_section
                    current_piano_id = piano_id
                    current_section = section

                    log(f"=== STARTING PROCESSING: {piano_id} ===")
                    update_progress("Starting", f"Received trigger for {piano_id}")
                except:
                    log("ERROR: No valid input data in trigger")
                    csv_path = ''
            else:
                log("ERROR: No input data provided")
                csv_path = ''

            doc = app.activeDocument
            if not doc:
                log("ERROR: No active document")
            else:
                # Get design from document's products
                design = None
                for product in doc.products:
                    if product.objectType == 'adsk::fusion::Design':
                        design = adsk.fusion.Design.cast(product)
                        break

                if not design:
                    log("ERROR: No design found in document")
                else:
                    piano_folder = get_piano_folder(piano_id)
                    os.makedirs(piano_folder, exist_ok=True)

                    # Remove old shaping files for this section (files ending in _Upper.tap or _Lower.tap)
                    if os.path.exists(piano_folder):
                        for file in os.listdir(piano_folder):
                            file_lower = file.lower()
                            if (section == 'Upper' and file_lower.endswith('_upper.tap')) or \
                               (section == 'Lower' and file_lower.endswith('_lower.tap')):
                                os.remove(os.path.join(piano_folder, file))
                                log(f"Removed old file: {file}")

                    # Parse CSV and calculate parameters
                    if csv_path and os.path.exists(csv_path):
                        update_progress("Parsing CSV", csv_path)
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
                        update_progress("Switching to Design workspace")
                        log("Switching to Design workspace...")
                        design_ws = ui.workspaces.itemById('FusionSolidEnvironment')
                        if design_ws:
                            design_ws.activate()
                            adsk.doEvents()
                            time.sleep(1)  # Let workspace fully load
                            log("Switched to Design workspace")
                        else:
                            log("Warning: Could not find Design workspace")

                        # Update Fusion parameters using batch modifyParameters API
                        # This is ~50-70x faster than individual param.expression updates
                        user_params = design.userParameters
                        update_progress("Updating parameters", f"Building batch update for {len(key_params)} keys")
                        log("Using batch modifyParameters API for efficient updates")

                        # Build lists for batch update
                        params_list = []
                        values_list = []

                        # Add global parameters
                        param = user_params.itemByName('ShoulderLength')
                        if param:
                            params_list.append(param)
                            values_list.append(adsk.core.ValueInput.createByString(f"{shoulder_length} in"))

                        param = user_params.itemByName('KeyHeight')
                        if param:
                            params_list.append(param)
                            values_list.append(adsk.core.ValueInput.createByString(f"{key_height} in"))

                        # Add key parameters
                        for key_num, params in key_params.items():
                            prefix = f'Key{key_num}'
                            for suffix, value in params.items():
                                if value:  # Skip if value is None/0
                                    param_name = f'{prefix}{suffix}'
                                    param = user_params.itemByName(param_name)
                                    if param:
                                        if suffix == 'Angle':
                                            values_list.append(adsk.core.ValueInput.createByString(f"{value} deg"))
                                        else:
                                            values_list.append(adsk.core.ValueInput.createByString(f"{value} in"))
                                        params_list.append(param)

                        log(f"Built batch update with {len(params_list)} parameters")
                        update_progress("Updating parameters", f"Applying {len(params_list)} params + geometry rebuild")

                        # Execute batch update - single geometry rebuild for all params
                        batch_result = design.modifyParameters(params_list, values_list)
                        log(f"Batch modifyParameters result: {batch_result}")
                        adsk.doEvents()

                        # Switch to Manufacturing workspace for CAM operations
                        update_progress("Switching to Manufacturing workspace")
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
                            # Must use ObjectCollection, not Python list (API requirement)
                            relevant_setups = adsk.core.ObjectCollection.create()
                            setup_names = []
                            for i in range(cam.setups.count):
                                setup = cam.setups.item(i)
                                setup_name = setup.name.lower()

                                # Only include Shaping setups for this section
                                if 'shaping' in setup_name:
                                    if section == 'Upper' and 'upper' in setup_name:
                                        relevant_setups.add(setup)
                                        setup_names.append(setup.name)
                                    elif section == 'Lower' and 'lower' in setup_name:
                                        relevant_setups.add(setup)
                                        setup_names.append(setup.name)

                            update_progress("Generating toolpaths", f"{relevant_setups.count} setups for {section}")
                            log(f"Starting toolpath generation for {relevant_setups.count} setups: {setup_names}")

                            try:
                                # Generate only the relevant setups (not all toolpaths)
                                future = cam.generateToolpath(relevant_setups)

                                # Wait for completion
                                timeout = 1800  # 30 minutes
                                start = time.time()
                                last_log = 0
                                while not future.isGenerationCompleted:
                                    adsk.doEvents()
                                    time.sleep(2)
                                    elapsed = time.time() - start
                                    # Update progress every 10 seconds
                                    if elapsed - last_log >= 10:
                                        update_progress("Generating toolpaths", f"{elapsed:.0f}s elapsed")
                                        last_log = elapsed
                                    if int(elapsed) % 30 == 0:
                                        log(f"Still generating toolpaths... {elapsed:.0f} seconds elapsed")
                                    if elapsed > timeout:
                                        log(f"ERROR: Timeout after {elapsed:.0f} seconds")
                                        break
                                else:
                                    log("Toolpath generation complete")

                            except Exception as e:
                                log(f"ERROR generating toolpaths: {e}")

                            # Export G-code for this section's Shaping program
                            update_progress("Exporting G-code")
                            log(f"Starting G-code export...")
                            downloads_dir = os.path.join(os.environ['USERPROFILE'], 'Downloads')

                            if hasattr(cam, 'ncPrograms'):
                                log(f"Found {cam.ncPrograms.count} NC programs")

                                for i in range(cam.ncPrograms.count):
                                    prog = cam.ncPrograms.item(i)
                                    prog_name_lower = prog.name.lower()

                                    # Only export Shaping program for this section
                                    if 'shaping' not in prog_name_lower:
                                        continue
                                    if section == 'Upper' and 'upper' not in prog_name_lower:
                                        continue
                                    if section == 'Lower' and 'lower' not in prog_name_lower:
                                        continue

                                    log(f"Exporting NC program: '{prog.name}'")
                                    try:
                                        opts = adsk.cam.NCProgramPostProcessOptions.create()
                                        post_success = prog.postProcess(opts)
                                        if post_success:
                                            log(f"  Post process completed")
                                        else:
                                            log(f"  WARNING: postProcess returned False")
                                    except Exception as e:
                                        log(f"  Export error: {e}")
                                        log(f"  Traceback: {traceback.format_exc()}")

                            # Find and move the exported file from Downloads to piano folder
                            expected_filename = f"{section} Shaping.tap"
                            source_file = os.path.join(downloads_dir, expected_filename)
                            dest_name = f"{piano_id}.tap"
                            dest_file = os.path.join(piano_folder, dest_name)

                            log(f"Looking for exported file: {source_file}")

                            if os.path.exists(source_file):
                                log(f"Moving to {dest_file}")
                                if os.path.exists(dest_file):
                                    os.remove(dest_file)
                                shutil.move(source_file, dest_file)
                                log(f"File moved successfully")
                                success = True
                            else:
                                log(f"ERROR: Exported file not found: {source_file}")
                        else:
                            log("ERROR: No CAM setups found")
                    else:
                        log(f"ERROR: CSV file not found: {csv_path}")

            # Log final status with clear marker for FinalKeytopShaping to parse
            if piano_id != 'Unknown':
                if success:
                    log(f"=== PROCESSING COMPLETE: SUCCESS ===")
                    log(f"Output file: {dest_file if success else 'N/A'}")
                else:
                    log(f"=== PROCESSING COMPLETE: FAILED ===")

        except:
            error_msg = traceback.format_exc()
            log(f"ERROR: {error_msg}")
            log(f"=== PROCESSING COMPLETE: FAILED ===")


class HeartbeatChecker:
    """Validates Fusion 360 session state before sending heartbeat"""

    @staticmethod
    def check_ready():
        """
        Check if Fusion is ready to process requests.
        Returns (is_ready: bool, status: str, details: str)
        """
        try:
            # 1. Check startup complete
            if not app.isStartupComplete:
                return False, "STARTING", "Fusion still starting up"

            # 2. Check offline state
            if app.isOffLine:
                return False, "OFFLINE", "Fusion is offline"

            # 3. Check active document
            doc = app.activeDocument
            if not doc:
                return False, "NO_DOC", "No active document"

            # 4. Check correct document
            if not doc.dataFile or doc.dataFile.name != "Parametrized Keytop Toolpath":
                return False, "WRONG_DOC", f"Wrong document: {doc.dataFile.name if doc.dataFile else 'untitled'}"

            # 5. Check document not read-only (indicates session conflict, license issue, etc.)
            if doc.dataFile.isReadOnly:
                return False, "READ_ONLY", "Document is read-only (possible session conflict)"

            # 6. Write capability probe - attempt a tiny reversible write
            # This catches "Session Suspended" modal blocking state
            design = None
            for product in doc.products:
                if product.objectType == 'adsk::fusion::Design':
                    design = adsk.fusion.Design.cast(product)
                    break

            if not design:
                return False, "NO_DESIGN", "No design found in document"

            # Try to write and immediately delete a test attribute
            # This will fail if Fusion is blocked by modal dialog
            try:
                root_comp = design.rootComponent
                test_attr_group = "HeartbeatProbe"
                test_attr_name = "ping"

                # Write test attribute
                root_comp.attributes.add(test_attr_group, test_attr_name, str(time.time()))

                # Delete it immediately
                attr = root_comp.attributes.itemByName(test_attr_group, test_attr_name)
                if attr:
                    attr.deleteMe()

            except Exception as e:
                return False, "BLOCKED", f"Write probe failed: {str(e)[:50]}"

            # All checks passed
            return True, "READY", "All checks passed"

        except Exception as e:
            return False, "ERROR", f"Check failed: {str(e)[:50]}"


class WatchThread(threading.Thread):
    def __init__(self):
        super().__init__()
        self.daemon = True
        self.last_heartbeat = 0

    def write_heartbeat(self):
        """Write heartbeat status to file with session state validation"""
        try:
            is_ready, status, details = HeartbeatChecker.check_ready()

            if is_ready:
                # Write timestamp for READY state
                with open(HEARTBEAT_FILE, 'w') as f:
                    f.write(str(time.time()))
            else:
                # Write status info for NOT READY states
                # Format: STATUS|timestamp|details
                # This lets Mach4 know WHY Fusion isn't ready
                with open(HEARTBEAT_FILE, 'w') as f:
                    f.write(f"{status}|{time.time()}|{details}")

        except Exception as e:
            # Network/file error - try to write error status
            try:
                with open(HEARTBEAT_FILE, 'w') as f:
                    f.write(f"FILE_ERROR|{time.time()}|{str(e)[:50]}")
            except:
                pass  # Complete failure to write

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