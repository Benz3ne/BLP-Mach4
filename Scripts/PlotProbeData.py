"""
Plot Probe Data - Visualize probed points and calculated keytop outlines
Compatible with current ProbeKeys CSV format and KeytopParametricUpdate calculations
"""

import numpy as np
import matplotlib.pyplot as plt
import csv
import os
import glob
import math

# Configuration - matches KeytopParametricUpdate.py
CONFIG = {
    'plastic_thickness': 0.09,
    'max_rotation': 2.0,
    'angle_step': 0.01,
    'tail_weight': 3,
    'band_split_y': 0.75,
    'front_overhang': 0.005,
    'tail_overhang': 0.01,
}

KEY_LENGTH = 6.1  # inches (approximate full key length for visualization)
LOGS_DIR = r"C:\Mach4Hobby\Profiles\BLP\Logs"


def find_most_recent_csv():
    """Find the most recent probe CSV in the Logs directory"""
    csv_files = []

    for folder in os.listdir(LOGS_DIR):
        folder_path = os.path.join(LOGS_DIR, folder)
        if os.path.isdir(folder_path):
            # Look for CSV files matching the folder name
            csv_path = os.path.join(folder_path, f"{folder}.csv")
            if os.path.exists(csv_path):
                csv_files.append(csv_path)

    if not csv_files:
        print(f"No probe CSV files found in {LOGS_DIR}")
        return None

    # Return the most recently modified
    return max(csv_files, key=os.path.getmtime)


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


def median(values):
    """Calculate median of a list"""
    if not values:
        return 0
    sorted_vals = sorted(values)
    n = len(sorted_vals)
    if n % 2:
        return sorted_vals[n // 2]
    return (sorted_vals[n // 2 - 1] + sorted_vals[n // 2]) / 2.0


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
    note = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'][midi % 12]
    return note in ['C', 'D', 'E', 'F', 'G', 'A', 'B']


def key_shoulders(key_num):
    """Determine shoulder type for a key"""
    if key_num == 1:
        return "right"
    if key_num == 88:
        return "none"
    midi = key_num + 20
    note = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'][midi % 12]
    if note in ('B', 'E'):
        return "left"
    if note in ('F', 'C'):
        return "right"
    if note in ('D', 'G', 'A'):
        return "both"
    return "none"


def calculate_global_params(probe_data):
    """Calculate shoulder length and key height from all keys"""
    y_front_values = []
    y_back_values = []
    z_values = []

    for key_data in probe_data.values():
        if key_data['3']:
            y_front_values.extend([p['Y'] for p in key_data['3']])
        if key_data['4']:
            y_back_values.extend([p['Y'] for p in key_data['4']])
        if key_data['5']:
            z_values.extend([p['Z'] for p in key_data['5']])

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

    left_front = [p for p in left_points if p[1] <= CONFIG['band_split_y']]
    left_tail = [p for p in left_points if p[1] > CONFIG['band_split_y']]
    right_front = [p for p in right_points if p[1] <= CONFIG['band_split_y']]
    right_tail = [p for p in right_points if p[1] > CONFIG['band_split_y']]

    for angle_int in range(int(-CONFIG['max_rotation'] / CONFIG['angle_step']),
                           int(CONFIG['max_rotation'] / CONFIG['angle_step']) + 1):
        angle = angle_int * CONFIG['angle_step']

        lf_rot = [rotate_point(p, angle, center) for p in left_front]
        lt_rot = [rotate_point(p, angle, center) for p in left_tail]
        rf_rot = [rotate_point(p, angle, center) for p in right_front]
        rt_rot = [rotate_point(p, angle, center) for p in right_tail]

        xl_outer = min(
            min((p[0] for p in lf_rot), default=float('inf')),
            min((p[0] for p in lt_rot), default=float('inf'))
        )
        xr_outer = max(
            max((p[0] for p in rf_rot), default=float('-inf')),
            max((p[0] for p in rt_rot), default=float('-inf'))
        )

        front_slack = (
            max((p[0] - xl_outer for p in lf_rot), default=0) +
            max((xr_outer - p[0] for p in rf_rot), default=0)
        )
        tail_slack = (
            max((p[0] - xl_outer for p in lt_rot), default=0) +
            max((xr_outer - p[0] for p in rt_rot), default=0)
        )

        metric = front_slack + CONFIG['tail_weight'] * tail_slack

        if metric < best_metric:
            best_metric = metric
            best_angle = angle

    return best_angle


def calculate_key_params(left_points, right_points, front_points, center, angle, key_num):
    """Calculate final parameters for a key"""
    left_rot = [rotate_point(p, angle, center) for p in left_points]
    right_rot = [rotate_point(p, angle, center) for p in right_points]
    front_rot = [rotate_point(p, angle, center) for p in front_points]

    left_front = [p for p in left_rot if rotate_point(p, -angle, center)[1] <= CONFIG['band_split_y']]
    left_tail = [p for p in left_rot if rotate_point(p, -angle, center)[1] > CONFIG['band_split_y']]
    right_front = [p for p in right_rot if rotate_point(p, -angle, center)[1] <= CONFIG['band_split_y']]
    right_tail = [p for p in right_rot if rotate_point(p, -angle, center)[1] > CONFIG['band_split_y']]

    # Calculate walls with overhangs applied
    xl_front = min((p[0] for p in left_front), default=0) - CONFIG['front_overhang']
    xl_tail = min((p[0] for p in left_tail), default=0) - CONFIG['tail_overhang']
    xr_front = max((p[0] for p in right_front), default=0) + CONFIG['front_overhang']
    xr_tail = max((p[0] for p in right_tail), default=0) + CONFIG['tail_overhang']

    xl_outer = min(xl_front, xl_tail)
    xl_inner = max(xl_front, xl_tail)
    xr_outer = max(xr_front, xr_tail)
    xr_inner = min(xr_front, xr_tail)

    y_front = median([p[1] for p in front_rot])
    front_left = rotate_point([xl_outer, y_front], -angle, center)
    front_right = rotate_point([xr_outer, y_front], -angle, center)
    center_x = (front_left[0] + front_right[0]) / 2.0

    width = xr_outer - xl_outer
    left_step = xl_inner - xl_outer if key_shoulders(key_num) in ['left', 'both'] else 0
    right_step = xr_outer - xr_inner if key_shoulders(key_num) in ['right', 'both'] else 0

    return {
        'X': center_x,
        'Angle': -angle,
        'Width': width,
        'LStep': left_step,
        'RStep': right_step,
        'y_front': y_front,  # Store for plotting
        'xl_outer': xl_outer,
        'xr_outer': xr_outer,
    }


def process_key(key_num, key_data):
    """Process a single key: optimize angle and calculate parameters"""
    left_points = [[p['X'], p['Y']] for p in key_data.get('1', [])]
    right_points = [[p['X'], p['Y']] for p in key_data.get('2', [])]
    front_points = [[p['X'], p['Y']] for p in key_data.get('3', [])]

    if not (left_points and right_points):
        return None

    if not front_points:
        default_front_y = -1.2
        left_front_x = min(p[0] for p in left_points)
        right_front_x = max(p[0] for p in right_points)
        front_points = [[left_front_x, default_front_y], [right_front_x, default_front_y]]

    all_points = left_points + right_points + front_points
    center = [
        sum(p[0] for p in all_points) / len(all_points),
        sum(p[1] for p in all_points) / len(all_points)
    ]

    best_angle = optimize_angle(left_points, right_points, center)
    params = calculate_key_params(left_points, right_points, front_points, center, best_angle, key_num)
    params['center'] = center
    params['raw_angle'] = best_angle

    return params


def plot_key_outline(ax, params, key_num, shoulder_length, y_front_median):
    """Plot the calculated keytop outline for a key"""
    # Get the actual rotated-frame coordinates
    xl_outer = params['xl_outer']
    xr_outer = params['xr_outer']
    y_front = params.get('y_front', y_front_median)
    center = params['center']
    angle = params['raw_angle']  # The actual rotation angle used

    left_step = params['LStep']
    right_step = params['RStep']
    stype = key_shoulders(key_num)

    y_shoulder = y_front + shoulder_length
    y_tail = y_front + KEY_LENGTH

    # Build corners in the ROTATED frame using actual coordinates
    # These are the coordinates after rotating the probe points
    corners_rot = []

    # Front edge (using actual xl_outer and xr_outer)
    corners_rot.append([xl_outer, y_front])
    corners_rot.append([xr_outer, y_front])

    # Right side
    if stype in ['right', 'both']:
        corners_rot.append([xr_outer, y_shoulder])
        corners_rot.append([xr_outer - right_step, y_shoulder])
        corners_rot.append([xr_outer - right_step, y_tail])
    else:
        corners_rot.append([xr_outer, y_tail])

    # Back edge and left side
    if stype in ['left', 'both']:
        corners_rot.append([xl_outer + left_step, y_tail])
        corners_rot.append([xl_outer + left_step, y_shoulder])
        corners_rot.append([xl_outer, y_shoulder])
    else:
        corners_rot.append([xl_outer, y_tail])

    # Rotate corners BACK to world coordinates using the actual center
    # We rotated by +angle to align, so rotate by -angle to get back
    corners_world = []
    for corner in corners_rot:
        world_pt = rotate_point(corner, -angle, center)
        corners_world.append(world_pt)

    # Close the polygon
    corners_world.append(corners_world[0])

    # Plot
    xs = [c[0] for c in corners_world]
    ys = [c[1] for c in corners_world]
    ax.plot(xs, ys, 'k-', linewidth=1.2, alpha=0.8)

    # Add key number label at center of outline
    cx = sum(c[0] for c in corners_world[:-1]) / len(corners_world[:-1])
    cy = sum(c[1] for c in corners_world[:-1]) / len(corners_world[:-1])
    ax.text(cx, cy, str(key_num), fontsize=7, ha='center', va='center',
            bbox=dict(boxstyle='circle,pad=0.1', facecolor='white', alpha=0.7, edgecolor='none'))


def main():
    # Find most recent CSV
    csv_path = find_most_recent_csv()
    if not csv_path:
        return

    print(f"Using: {csv_path}")

    # Parse data
    probe_data = parse_csv(csv_path)
    print(f"Found data for {len(probe_data)} keys")

    # Calculate global parameters
    shoulder_length, key_height = calculate_global_params(probe_data)
    print(f"Shoulder Length: {shoulder_length:.4f} in")
    print(f"Key Height: {key_height:.4f} in")

    # Get median front Y for fallback
    all_front_y = []
    for key_data in probe_data.values():
        if key_data['3']:
            all_front_y.extend([p['Y'] for p in key_data['3']])
    y_front_median = median(all_front_y) if all_front_y else 0

    # Process each white key
    white_keys = [k for k in sorted(probe_data.keys()) if is_white_key(k)]
    key_params = {}
    for key_num in white_keys:
        params = process_key(key_num, probe_data[key_num])
        if params:
            key_params[key_num] = params

    print(f"Calculated parameters for {len(key_params)} keys")

    # Create plot
    fig, ax = plt.subplots(figsize=(16, 9))
    fig.subplots_adjust(left=0.05, right=0.98, top=0.95, bottom=0.05)

    # Collect all probe points for plotting
    all_points = {'X': [], 'Y': [], 'Direction': [], 'Key': []}
    for key_num, key_data in probe_data.items():
        for direction in range(1, 6):
            for point in key_data.get(str(direction), []):
                all_points['X'].append(point['X'])
                all_points['Y'].append(point['Y'])
                all_points['Direction'].append(direction)
                all_points['Key'].append(key_num)

    # Plot probe points by direction
    direction_styles = [
        (1, 'blue', 'o', 'Left (+X)', 0.5),
        (2, 'orange', 'o', 'Right (-X)', 0.5),
        (3, 'green', '^', 'Front (+Y)', 0.7),
        (4, 'red', 'v', 'Shoulder (-Y)', 0.7),
        (5, 'purple', 's', 'Z Height', 0.8)
    ]

    for direction, color, marker, label, alpha in direction_styles:
        xs = [all_points['X'][i] for i in range(len(all_points['X']))
              if all_points['Direction'][i] == direction]
        ys = [all_points['Y'][i] for i in range(len(all_points['Y']))
              if all_points['Direction'][i] == direction]
        if xs:
            ax.scatter(xs, ys, c=color, marker=marker, s=25, alpha=alpha, label=label)

    # Plot calculated outlines
    for key_num, params in key_params.items():
        plot_key_outline(ax, params, key_num, shoulder_length, y_front_median)

    # Configure plot
    ax.set_xlabel('X (inches)')
    ax.set_ylabel('Y (inches)')

    # Extract piano name from path
    piano_name = os.path.basename(os.path.dirname(csv_path))
    ax.set_title(f'Probe Data Visualization - {piano_name} ({len(key_params)} keys)')

    ax.set_aspect('equal')
    ax.grid(True, alpha=0.3)
    ax.legend(loc='upper right')

    # Adjust view to show full data
    ax.autoscale()

    # Try to maximize window
    try:
        manager = plt.get_current_fig_manager()
        manager.window.state('zoomed')
    except:
        pass

    plt.show()


if __name__ == '__main__':
    main()
