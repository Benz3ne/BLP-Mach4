"""
Plot Key Parameters - Visualize probe points and parameter-generated outlines
"""

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import csv
import os
import glob

# Configuration
KEY_LENGTH = 6.1  # inches

# Find the most recent probe CSV in Downloads
downloads_path = os.path.join(os.environ.get('USERPROFILE', ''), 'Downloads')
probe_files = glob.glob(os.path.join(downloads_path, '*_Lower.csv')) + \
              glob.glob(os.path.join(downloads_path, '*_Upper.csv'))
if not probe_files:
    print("No probe CSV files (*_Lower.csv or *_Upper.csv) found in Downloads")
    exit(1)
PROBE_CSV = max(probe_files, key=os.path.getmtime)
print(f"Using probe file: {os.path.basename(PROBE_CSV)}")

# Find the most recent KeyParameters CSV in Documents
documents_path = os.path.join(os.environ.get('USERPROFILE', ''), 'Documents')
params_files = glob.glob(os.path.join(documents_path, 'KeyParameters_*.csv'))
if not params_files:
    print("No KeyParameters CSV files found in Documents")
    exit(1)
PARAMS_CSV = max(params_files, key=os.path.getmtime)
print(f"Using parameters file: {os.path.basename(PARAMS_CSV)}")

def rotate_point(point, angle_deg, center):
    """Rotate a point around center by angle (in degrees)."""
    angle_rad = np.deg2rad(angle_deg)
    c, s = np.cos(angle_rad), np.sin(angle_rad)
    dx = point[0] - center[0]
    dy = point[1] - center[1]
    x_rot = dx * c - dy * s + center[0]
    y_rot = dx * s + dy * c + center[1]
    return np.array([x_rot, y_rot])

def main():
    # Read probe data
    probe_df = pd.read_csv(PROBE_CSV)

    # Read parameter data
    params_data = []
    global_params = {}

    # First pass - read data rows
    with open(PARAMS_CSV, 'r') as f:
        reader = csv.reader(f)
        headers = next(reader)  # Get headers

        for row in reader:
            if row and row[0] and not row[0].startswith('#'):
                # Regular data row
                params_data.append({
                    'Key': int(row[0]),
                    'ShoulderType': row[1],
                    'CenterX': float(row[2]),
                    'Angle': float(row[3]),
                    'Width': float(row[4]),
                    'LeftStep': float(row[5]) if row[5] else 0,
                    'RightStep': float(row[6]) if row[6] else 0
                })

    # Second pass - read global parameters (they're after the data)
    with open(PARAMS_CSV, 'r') as f:
        lines = f.readlines()
        for line in lines:
            if line.startswith('# '):
                parts = line.replace('# ', '').strip().split(',')
                if len(parts) == 2:
                    param_name = parts[0]
                    param_value = float(parts[1])
                    global_params[param_name] = param_value
                    print(f"Found global param: {param_name} = {param_value}")

    # Extract global parameters
    shoulder_len = global_params.get('ShoulderLength', 1.0)  # Better default
    print(f"\nGlobal parameters loaded:")
    print(f"  ShoulderLength: {shoulder_len:.4f} inches")
    print(f"  KeyHeight: {global_params.get('KeyHeight', 0):.4f} inches")
    print(f"  SlackWeight: {global_params.get('SlackWeight', 0.5):.2f}")
    print(f"  OptimizationPreference: {global_params.get('OptimizationPreference', 0.5):.2f}")
    print(f"  Key Length (hardcoded): {KEY_LENGTH} inches\n")

    # Create figure with same style as RotatedKeyCorners.py
    fig = plt.figure(figsize=(16, 9))
    ax = fig.add_subplot(111)

    # Maximize window
    manager = plt.get_current_fig_manager()
    if hasattr(manager, 'window'):
        if hasattr(manager.window, 'state'):
            try:
                manager.window.state('zoomed')  # For TkAgg backend
            except:
                pass

    # Adjust subplot to fill the figure
    fig.subplots_adjust(left=0.05, right=0.98, top=0.95, bottom=0.05)

    # Plot probe points by direction
    for direction, color, marker, label, alpha in [
        (1, 'blue', 'o', 'Left (+X)', 0.4),
        (2, 'orange', 'o', 'Right (-X)', 0.4),
        (3, 'green', '^', 'Front (+Y)', 0.6),
        (4, 'red', 'v', 'Shoulder (-Y)', 0.6),
        (5, 'purple', 's', 'Z probe', 0.8)
    ]:
        dir_data = probe_df[probe_df['Direction'] == direction]
        if not dir_data.empty:
            ax.scatter(dir_data['X'], dir_data['Y'], c=color, marker=marker,
                      s=30, alpha=alpha, label=label)

    # Plot parameter-generated outlines
    for param in params_data:
        key = param['Key']
        center_x = param['CenterX']
        angle = param['Angle']
        width = param['Width']
        stype = param['ShoulderType']
        left_step = param['LeftStep']
        right_step = param['RightStep']

        # Calculate half width
        half_width = width / 2.0

        # Find Y position from probe data (median of front points)
        key_front = probe_df[(probe_df['PianoKey#'] == key) & (probe_df['Direction'] == 3)]
        if not key_front.empty:
            y_front = key_front['Y'].median()
        else:
            y_front = 0  # fallback

        # Y levels
        y_shoulder = y_front + shoulder_len
        y_tail = y_front + KEY_LENGTH  # Use hardcoded key length

        # Build corners in rotated frame
        # Front corners
        corners_rot = [
            [-half_width, y_front],  # Front left
            [half_width, y_front]    # Front right
        ]

        # Right side
        if stype in ['right', 'both']:
            corners_rot.extend([
                [half_width, y_shoulder],           # Right shoulder outer
                [half_width - right_step, y_shoulder],  # Right shoulder inner
                [half_width - right_step, y_tail]       # Right tail inner
            ])
        else:
            corners_rot.append([half_width, y_tail])  # Right tail outer

        # Back edge
        if stype in ['left', 'both']:
            corners_rot.extend([
                [-half_width + left_step, y_tail],       # Left tail inner
                [-half_width + left_step, y_shoulder],   # Left shoulder inner
                [-half_width, y_shoulder]                # Left shoulder outer
            ])
        else:
            corners_rot.append([-half_width, y_tail])  # Left tail outer

        # Close the polygon
        corners_rot.append(corners_rot[0])

        # Convert to numpy array for rotation
        corners_rot = np.array(corners_rot)

        # The corners are in the rotated frame where the key is aligned
        # We need to rotate them back to the original frame
        # The center of rotation in the rotated frame is at (0, y_front)
        center_rot = np.array([0, y_front])

        # Rotate each corner back to original frame
        corners_orig = []
        for corner in corners_rot[:-1]:  # Exclude the duplicate closing point
            # The angle in CSV is the F360 angle (inverted), so we need to negate it again
            # to get back to the original rotation that matches probe points
            corner_orig = rotate_point(corner, angle, center_rot)  # Use angle directly (it's already negative)
            # Translate to actual center position
            corner_orig[0] += center_x
            corners_orig.append(corner_orig)

        # Plot the outline
        corners_orig = np.array(corners_orig)
        xs = np.append(corners_orig[:, 0], corners_orig[0, 0])  # Close polygon
        ys = np.append(corners_orig[:, 1], corners_orig[0, 1])

        ax.plot(xs, ys, 'k-', linewidth=1.5, alpha=0.8)

        # Add key number at center
        cx = center_x
        cy = (y_front + y_tail) / 2
        ax.text(cx, cy, str(key), fontsize=8, ha='center', va='center',
                bbox=dict(boxstyle='circle,pad=0.1', facecolor='white', alpha=0.7))

    ax.set_xlabel('X (inches)')
    ax.set_ylabel('Y (inches)')
    ax.set_title(f'Key Parameters Visualization - {len(params_data)} keys')
    ax.set_aspect('equal')
    ax.grid(True, alpha=0.3)
    ax.legend(loc='upper right')

    # Force the view to show more vertical space (same as RotatedKeyCorners.py)
    x_min, x_max = ax.get_xlim()
    y_min, y_max = ax.get_ylim()
    x_center = (x_min + x_max) / 2
    y_center = (y_min + y_max) / 2
    x_range = x_max - x_min
    y_range = y_max - y_min

    # Make the Y range match the aspect ratio of the figure
    fig_width, fig_height = fig.get_size_inches()
    aspect_ratio = fig_height / fig_width

    # Set Y range to use full height given the X range
    new_y_range = x_range * aspect_ratio
    if new_y_range > y_range:
        ax.set_ylim(y_center - new_y_range/2, y_center + new_y_range/2)
    else:
        # If data is already taller, adjust X instead
        new_x_range = y_range / aspect_ratio
        ax.set_xlim(x_center - new_x_range/2, x_center + new_x_range/2)

    plt.show()

if __name__ == '__main__':
    main()