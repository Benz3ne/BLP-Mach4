"""
Debug Add-in: Full Workflow Benchmark
Mirrors the real KeytopParametricUpdate workflow for accurate timing
Tests: Parameters, Geometry Rebuild, Toolpath Generation, Post-Processing
"""

import adsk.core
import adsk.fusion
import adsk.cam
import os
import time
import traceback
import shutil

app = None
ui = None

# Test parameter values derived from actual probe data (slightly modified)
# These are realistic values that won't break the geometry
# Upper section keys (45-88 range - white keys only)
TEST_PARAMS = {
    # Key parameters: (X, Angle, Width, LStep, RStep) - values in inches
    45: (1.73, 0.05, 0.87, 0.02, 0.01),
    47: (3.43, -0.03, 0.89, 0.03, 0.02),
    49: (5.13, 0.02, 0.88, 0.02, 0.02),
    51: (6.82, -0.01, 0.86, 0.03, 0.01),
    52: (8.53, 0.01, 0.89, 0.02, 0.02),
    54: (10.23, 0.03, 0.87, 0.02, 0.02),
    56: (11.93, -0.02, 0.88, 0.03, 0.01),
    57: (13.64, 0.01, 0.85, 0.02, 0.02),
    59: (15.35, -0.01, 0.89, 0.02, 0.02),
    61: (17.05, 0.02, 0.87, 0.03, 0.02),
    63: (18.75, 0.00, 0.85, 0.02, 0.01),
    64: (20.44, -0.02, 0.87, 0.02, 0.02),
    66: (22.15, 0.01, 0.89, 0.02, 0.02),
    68: (23.85, 0.03, 0.85, 0.03, 0.02),
    69: (25.55, -0.01, 0.87, 0.02, 0.01),
    71: (27.24, 0.02, 0.86, 0.02, 0.02),
    73: (28.93, 0.00, 0.86, 0.02, 0.02),
    75: (30.62, -0.02, 0.85, 0.03, 0.02),
    76: (32.30, 0.01, 0.88, 0.02, 0.02),
    78: (34.02, 0.02, 0.87, 0.02, 0.02),
    80: (35.72, -0.01, 0.86, 0.03, 0.02),
    81: (37.43, 0.00, 0.87, 0.02, 0.01),
    83: (39.14, 0.02, 0.89, 0.02, 0.02),
    85: (40.84, -0.01, 0.88, 0.02, 0.02),
    87: (42.53, 0.01, 0.85, 0.03, 0.02),
    88: (44.23, 0.00, 0.86, 0.02, 0.01),
}

# Global params (same as real add-in calculates)
TEST_SHOULDER_LENGTH = 0.635  # inches
TEST_KEY_HEIGHT = 0.245  # inches

# Section to test (matches real add-in Upper section workflow)
TEST_SECTION = "Upper"


def run(context):
    global app, ui

    try:
        app = adsk.core.Application.get()
        ui = app.userInterface

        downloads_dir = os.path.join(os.environ['USERPROFILE'], 'Downloads')
        output_path = os.path.join(downloads_dir, 'FullWorkflow_Benchmark.txt')

        results = []
        results.append(f"=== FULL WORKFLOW BENCHMARK - {time.strftime('%Y-%m-%d %H:%M:%S')} ===")
        results.append("Discovering API and comparing param methods")
        results.append("")

        doc = app.activeDocument
        if not doc:
            results.append("ERROR: No active document")
            write_results(output_path, results)
            return

        results.append(f"Document: {doc.name}")

        # Get design
        design = None
        for product in doc.products:
            if product.objectType == 'adsk::fusion::Design':
                design = adsk.fusion.Design.cast(product)
                break

        if not design:
            results.append("ERROR: No design found")
            write_results(output_path, results)
            return

        user_params = design.userParameters
        results.append(f"Total user parameters: {user_params.count}")
        results.append("")

        # ================================================================
        # API DISCOVERY: Find compute deferral methods
        # ================================================================
        results.append("=" * 70)
        results.append("API DISCOVERY: Design object attributes")
        results.append("=" * 70)
        results.append("")

        # Look for compute-related attributes
        compute_attrs = []
        for attr in dir(design):
            if not attr.startswith('_'):
                attr_lower = attr.lower()
                if any(kw in attr_lower for kw in ['compute', 'defer', 'update', 'refresh', 'rebuild', 'batch']):
                    try:
                        val = getattr(design, attr)
                        compute_attrs.append(f"  {attr} = {val} ({type(val).__name__})")
                    except:
                        compute_attrs.append(f"  {attr} (method/property)")

        if compute_attrs:
            results.append("Compute-related attributes found:")
            results.extend(compute_attrs)
        else:
            results.append("No compute-related attributes found with keywords: compute, defer, update, refresh, rebuild, batch")

        results.append("")

        # List all design attributes for reference
        results.append("All Design attributes (for reference):")
        all_attrs = [attr for attr in dir(design) if not attr.startswith('_')]
        for i in range(0, len(all_attrs), 5):
            results.append("  " + ", ".join(all_attrs[i:i+5]))
        results.append("")

        # Check for ParameterList methods
        results.append("UserParameters attributes:")
        param_attrs = [attr for attr in dir(user_params) if not attr.startswith('_')]
        results.append("  " + ", ".join(param_attrs[:20]))
        results.append("")

        # Count how many test parameters exist
        existing_params = []
        for key_num in TEST_PARAMS.keys():
            for suffix in ['X', 'Angle', 'Width', 'LStep', 'RStep']:
                param_name = f'Key{key_num}{suffix}'
                if user_params.itemByName(param_name):
                    existing_params.append(param_name)

        results.append(f"Found {len(existing_params)} matching key parameters")
        results.append(f"Testing {TEST_SECTION} section workflow")
        results.append("")

        # Unit conversions for param.value
        INCH_TO_CM = 2.54
        DEG_TO_RAD = 3.14159265359 / 180.0

        # ================================================================
        # TEST 1: Explore modifyParameters API
        # ================================================================
        results.append("=" * 70)
        results.append("TEST 1: Explore modifyParameters batch API")
        results.append("=" * 70)
        results.append("")

        design_ws = ui.workspaces.itemById('FusionSolidEnvironment')
        if design_ws:
            design_ws.activate()
            adsk.doEvents()
            time.sleep(1)

        # Explore modifyParameters
        results.append("Inspecting design.modifyParameters:")
        try:
            modify_method = design.modifyParameters
            results.append(f"  Type: {type(modify_method)}")
            results.append(f"  Docstring: {modify_method.__doc__[:500] if modify_method.__doc__ else 'None'}")
        except Exception as e:
            results.append(f"  ERROR: {e}")
        results.append("")

        # Explore computeAll
        results.append("Inspecting design.computeAll:")
        try:
            compute_method = design.computeAll
            results.append(f"  Type: {type(compute_method)}")
            results.append(f"  Docstring: {compute_method.__doc__[:500] if compute_method.__doc__ else 'None'}")
        except Exception as e:
            results.append(f"  ERROR: {e}")
        results.append("")

        # Unit conversions
        INCH_TO_CM = 2.54
        DEG_TO_RAD = 3.14159265359 / 180.0
        test_keys = list(TEST_PARAMS.keys())[:3]  # Only 3 key numbers for quick test

        # ================================================================
        # TEST 2: Try modifyParameters batch update
        # ================================================================
        results.append("=" * 70)
        results.append("TEST 2: modifyParameters batch update (3 keys)")
        results.append("=" * 70)
        results.append("")

        t_start = time.time()
        try:
            # Build list of parameter changes using ValueInput objects (required by API)
            params_list = []
            values_list = []

            for key_num in test_keys:
                for suffix in ['X', 'Width', 'LStep', 'RStep']:
                    param_name = f'Key{key_num}{suffix}'
                    param = user_params.itemByName(param_name)
                    if param:
                        # Read current value (in cm), convert to inches, add 0.01
                        current_in = param.value / INCH_TO_CM
                        new_val = current_in + 0.01
                        # Create ValueInput from string expression
                        value_input = adsk.core.ValueInput.createByString(f"{new_val} in")
                        params_list.append(param)
                        values_list.append(value_input)

                # Angle - read current, add 0.1 deg
                param_name = f'Key{key_num}Angle'
                param = user_params.itemByName(param_name)
                if param:
                    current_deg = param.value / DEG_TO_RAD
                    new_val = current_deg + 0.1
                    value_input = adsk.core.ValueInput.createByString(f"{new_val} deg")
                    params_list.append(param)
                    values_list.append(value_input)

            results.append(f"  Built {len(params_list)} parameter changes with ValueInput objects")

            # Call modifyParameters with proper types
            results.append(f"  Calling design.modifyParameters...")
            result = design.modifyParameters(params_list, values_list)
            results.append(f"  Result: {result}")

            t_batch = time.time() - t_start
            results.append(f"  Time: {t_batch:.3f}s for {len(params_list)} params")
            if len(params_list) > 0:
                results.append(f"  Per-param: {t_batch/len(params_list)*1000:.1f}ms")

        except Exception as e:
            t_batch = time.time() - t_start
            results.append(f"  ERROR: {e}")
            results.append(f"  Time before error: {t_batch:.3f}s")
            import inspect
            try:
                sig = inspect.signature(design.modifyParameters)
                results.append(f"  Signature: {sig}")
            except:
                pass
        results.append("")

        # ================================================================
        # TEST 3: Single param baseline (for comparison)
        # ================================================================
        results.append("=" * 70)
        results.append("TEST 3: Single param.expression update (baseline)")
        results.append("=" * 70)
        results.append("")

        t_start = time.time()
        first_key = test_keys[0]
        param = user_params.itemByName(f'Key{first_key}X')
        if param:
            try:
                # Read current and add small delta
                current_in = param.value / INCH_TO_CM
                param.expression = f"{current_in + 0.01} in"
                t_single = time.time() - t_start
                results.append(f"  Single param update: {t_single:.3f}s")
            except Exception as e:
                results.append(f"  ERROR: {e}")
        results.append("")

        # Set these for later comparison section
        t_expr_5 = 0
        t_val_5 = 0

        # ================================================================
        # TEST 4: Toolpath + Post-process only (skip slow param updates)
        # ================================================================
        results.append("=" * 70)
        results.append("TEST 4: Toolpath generation + Post-process")
        results.append("=" * 70)
        results.append("(Skipping full param updates - already tested above)")
        results.append("")

        timings = {}
        t_workflow_start = time.time()
        timings['design_ws'] = 0
        timings['param_update'] = 0

        # Switch to Manufacturing
        t_start = time.time()
        manufacture_ws = ui.workspaces.itemById('CAMEnvironment')
        if not manufacture_ws:
            manufacture_ws = ui.workspaces.itemById('FusionManufactureEnvironment')
        if manufacture_ws:
            manufacture_ws.activate()
            adsk.doEvents()
            time.sleep(1)
        timings['mfg_ws'] = time.time() - t_start
        results.append(f"  Switch to Mfg WS: {timings['mfg_ws']:.3f}s")

        # Toolpath generation - use ObjectCollection
        t_start = time.time()
        cam = adsk.cam.CAM.cast(doc.products.itemByProductType('CAMProductType'))

        if cam and cam.setups.count > 0:
            # Create ObjectCollection for setups
            setup_collection = adsk.core.ObjectCollection.create()
            for i in range(cam.setups.count):
                setup = cam.setups.item(i)
                setup_name = setup.name.lower()
                if 'shaping' in setup_name and TEST_SECTION.lower() in setup_name:
                    setup_collection.add(setup)
                    results.append(f"  Found setup: {setup.name}")

            if setup_collection.count > 0:
                results.append(f"  Generating toolpaths for {setup_collection.count} setups...")
                try:
                    future = cam.generateToolpath(setup_collection)
                    timeout = 1800
                    start = time.time()
                    while not future.isGenerationCompleted:
                        adsk.doEvents()
                        time.sleep(2)
                        elapsed = time.time() - start
                        if elapsed > timeout:
                            results.append(f"  ERROR: Timeout after {elapsed:.0f}s")
                            break
                    results.append(f"  Toolpath generation complete")
                except Exception as e:
                    results.append(f"  ERROR: {e}")

        timings['toolpath'] = time.time() - t_start
        results.append(f"  Toolpath time: {timings['toolpath']:.3f}s")

        # Post-process
        t_start = time.time()
        if cam and hasattr(cam, 'ncPrograms'):
            for i in range(cam.ncPrograms.count):
                prog = cam.ncPrograms.item(i)
                prog_name_lower = prog.name.lower()
                if 'shaping' in prog_name_lower and TEST_SECTION.lower() in prog_name_lower:
                    results.append(f"  Post-processing: {prog.name}")
                    try:
                        opts = adsk.cam.NCProgramPostProcessOptions.create()
                        success = prog.postProcess(opts)
                        results.append(f"    Success: {success}")
                    except Exception as e:
                        results.append(f"    ERROR: {e}")

        timings['postprocess'] = time.time() - t_start
        results.append(f"  Post-process time: {timings['postprocess']:.3f}s")

        # File check
        t_start = time.time()
        expected_filename = f"{TEST_SECTION} Shaping.tap"
        source_file = os.path.join(downloads_dir, expected_filename)
        if os.path.exists(source_file):
            file_size = os.path.getsize(source_file)
            file_time = os.path.getmtime(source_file)
            results.append(f"  Found: {expected_filename} ({file_size:,} bytes)")
            results.append(f"    Modified: {time.ctime(file_time)}")
        else:
            results.append(f"  File not found: {expected_filename}")
        timings['file_ops'] = time.time() - t_start

        t_workflow_total = time.time() - t_workflow_start
        timings['total'] = t_workflow_total
        results.append("")

        # ================================================================
        # SUMMARY
        # ================================================================
        results.append("=" * 70)
        results.append("TIMING SUMMARY (param.value method)")
        results.append("=" * 70)
        results.append("")
        results.append(f"{'Step':<35} {'Time':>10} {'Percent':>10}")
        results.append("-" * 55)

        for step, label in [
            ('design_ws', 'Switch to Design WS'),
            ('param_update', 'Parameter updates + geometry'),
            ('mfg_ws', 'Switch to Mfg WS'),
            ('toolpath', 'Toolpath generation'),
            ('postprocess', 'Post-processing'),
            ('file_ops', 'File operations'),
        ]:
            t = timings.get(step, 0)
            pct = (t / t_workflow_total * 100) if t_workflow_total > 0 else 0
            results.append(f"{label:<35} {t:>8.2f}s {pct:>9.1f}%")

        results.append("-" * 55)
        results.append(f"{'TOTAL':<35} {t_workflow_total:>8.2f}s {'100.0':>9}%")
        results.append("")

        # ================================================================
        # CONCLUSIONS
        # ================================================================
        results.append("=" * 70)
        results.append("CONCLUSIONS")
        results.append("=" * 70)
        results.append("")
        results.append("If modifyParameters worked:")
        results.append("  - This is the solution for batch parameter updates")
        results.append("  - Should dramatically reduce total time")
        results.append("")
        results.append("If modifyParameters failed:")
        results.append("  - No batch API exists in Fusion 360")
        results.append("  - Each param change = full geometry rebuild (~6s)")
        results.append("  - 116 params × 6s = 696s minimum (11+ minutes)")
        results.append("  - This is a fundamental Fusion 360 limitation")

        results.append("")

        # Write results
        write_results(output_path, results)
        ui.messageBox(f"Benchmark complete!\n\nResults: {output_path}\n\nTotal time: {t_workflow_total:.1f}s", "Done")

    except:
        error_msg = traceback.format_exc()
        try:
            with open(os.path.join(os.environ['USERPROFILE'], 'Downloads', 'FullWorkflow_Error.txt'), 'w') as f:
                f.write(error_msg)
        except:
            pass
        if ui:
            ui.messageBox(f"Error:\n{error_msg}", "Error")


def write_results(path, results):
    with open(path, 'w') as f:
        for line in results:
            f.write(line + '\n')


def stop(context):
    pass
