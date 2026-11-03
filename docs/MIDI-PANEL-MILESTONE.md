# MIDI companion panel: first interactive milestone

Entry point: `scripts/midi/ReaSkii_MIDI_Panel.lua`. Load in the MIDI Editor action section. Standalone narrow gfx window with Docker toggle; native piano roll is unchanged. Nothing was installed or deployed. Existing Tools/LAB1 and engine modules were not edited.

## Working subset

Clip / Launch / Pitch & Time / Transform / Generate hierarchy; independent collapse, vertically scrolling content and fixed safety/status footer. Clip scale root and Major/Minor/Dorian/Chromatic selectors feed Fit to Scale. Pitch actions use the safe adapter: Fit to Scale, melodic Invert (integer midpoint of selected pitch extremes), Reverse (selected-note bounding range), Legato. These are local engine semantics, not proven Live semantics.

Stretch is a rotary arc: upward drag +0.01 per pixel, Shift drag +0.001 per pixel (rounded to 0.01), wheel +0.01/notch, Shift wheel +0.001 before rounding; range 0.01–100, default 1. x2 and /2 use the same clamping. Click the number to type inline; Enter commits the field, Escape cancels text. Vertical number drag, wheel and double-click default are available. Knob double-click resets default. Auto on previews Stretch; Keep pitch commits its pending preview. Auto off only changes parameters; there is not yet a separate explicit Stretch application action while Auto is off.

Transform has one chooser, Strum, with unavailable inventory entries in reference order. Low/High readouts -100..100%, horizontal endpoint drags (upper High, lower Low), visible nonlinear graph and inline Tension -100..100%. Shift graph drag is 10x finer. Numeric drags/wheel use one percentage point per pixel/notch; Shift uses 0.1 before integer rounding. Defaults Low=High=Tension=0. Parameter limits and wheel dispatch are tested in Lua; native tests exercise knob, graph and numeric editing.

Strum uses the existing adapter algorithm: exact-onset selected-note chords, pitch-sorted, starts move and ends stay fixed, offsets in native grid ticks. Curve is `1-(1-t)^(2^(2*tension))`, where tension is -1..1. The displayed curve uses the same mapping. Single-note groups do not move. Reapplying to a previously strummed chord will generally do nothing unless it still has coincident onsets. This is explicitly provisional, NOT Ableton parity.

Auto starts on. Adjustments preview from the original snapshot, not the current preview. Auto off safely cancels the preview. Turning Auto on arms the next adjustment without silently transforming. Transform explicitly previews and commits Strum with a named REAPER undo point, independent of Auto. Reset changes Strum parameters only: it does not write MIDI or discard committed MIDI; the next adjustment/Transform uses those parameters. Switching tools cancels a pending preview rather than silently committing it. Fit/Invert/Reverse/Legato commit immediately.

## Disabled / unavailable

Clip/loop editing, Launch, Add Interval, Set Length, Humanize, every other transformation, Generate and MPE. Interval/Humanize values are inline-editable parameter placeholders but their unavailable actions never write MIDI. Grid displays native-source information, not a fake working grid editor. Unsupported expression data, malformed selected notes and unsafe collisions are refused by the existing adapter. No GetUserInputs forms are used.

## Safety boundary

Private Core/Adapter instances reuse journal-before-write, byte readback, identity checks, noncumulative preview, cancel, apply and Undo. Poll detects external edits or target/project changes and refuses overwrites. It does not activate projects. Close/atexit attempts safe cancellation; a refused restore retains the recovery file. Right-click offers explicit interrupted-original recovery. No take leaves the panel running with actionable status.

A private wrapper handles REAPER's final unselected channel-0 CC123 value-0 source boundary: only that exact final nonempty marker is removed from adapter analysis, then restored at its exact position. Results crossing the marker are refused; all other CC/pressure/bend refusals remain. No engine patch is needed for this milestone. A future shared-engine change, if desired, should move this exact bounded-marker classification into Adapter analysis, not broadly exempt CC123 or weaken readback checks.

## Evidence and limits

TDD: `midi_fidelity_unit.lua` initially failed because the new Controller did not exist; implementation followed. Final suite passes 11 groups, including controller lifecycle, original-based updates, parameter mapping, inline keyboard/wheel dispatch, exact marker preservation, expression refusal and boundary refusal. All three scripts compile with `loadfile`. Existing recovery safety suite passes 72 checks; adapter unit script exits 0.

Real REAPER 7.84 on Linux/Xvfb: `tests/run_midi_fidelity_gui.py` passes 21 checks with real X11 input and fixture MIDI readback, including native Undo after Transform. The host fixture selects C/E/G at PPQ 960–1920 plus C5 at 2880–3360. Native grid is 1/4; measured PPQ resolution comes from REAPER. `qa/midi-fidelity-host.tsv` hashes the exact tested code/tests/screenshots. `qa/midi-fidelity-panel.png` shows an actual curved Strum preview with Tension 50%; collapsed and 224x400 small-window screenshots show navigation.

Viewed both user references and official Strum image before drawing, and viewed actual full/collapsed/small captures after testing. Preserved narrow hierarchy, paired Pitch & Time controls, single chooser, graph endpoint orientation and Auto/Transform placement. Fixed the full-circle knob to an arc and made Auto visibly active. Remaining visual differences are explicit: Clip content is abbreviated/unavailable rather than simulated, the safety footer is additional, percentages are integer instead of tenths, reset uses a compact R, and this is a separate companion window, not native embedding. Test counts do not establish visual equivalence.

Reference evidence: user screenshots are static; official Live 12 manual documents Auto and Reset. Prior remote Live capture is PARTIAL and contains no successful parameter edit or exported fixture. All gesture sensitivities/defaults/curve/selection/reapplication rules here are locally specified, not observed from Live. REFERENCE_PARITY = NOT_MEASURED.

Not exercised in the final native host suite: Docker transitions, no-take/lost-target/project-switch scenarios, real external edits, crash/restart recovery, Windows placement/runtime, and native Fit/Invert/Reverse/Legato clicks. These retain engine/controller coverage or wiring only, not native acceptance. Parent owns further integration and final acceptance.

## Reproduce

From the repo root:

    python /home/randomaccessmemories/.hermes/cache/scratch/lua54_run.py tests/midi_fidelity_unit.lua
    python /home/randomaccessmemories/.hermes/cache/scratch/lua54_run.py tests/midi_recovery_safety.lua
    python /home/randomaccessmemories/.hermes/cache/scratch/lua54_run.py tests/midi_adapter_unit.lua
    xvfb-run -a -s '-screen 0 1400x1000x24' python tests/run_midi_fidelity_gui.py --reaper /home/randomaccessmemories/.hermes/cache/scratch/reaskii-native/reaper_linux_x86_64/REAPER/reaper

The runner uses a dedicated scratch configuration and terminates only its own child host. Intermittent startup timeouts with no panel/window occurred; increasing the wait from 18s to 90s allowed the final complete run. Earlier implementation failures exposed key-release ordering and a synthetic empty terminal event; both were fixed and the full scenario rerun. Diagnostic `last`, `commit`, `host-partial` files are not substitutes for the final hash-bound passing report.

Next: native adversarial/project-switch/restart tests; expose an explicit non-Auto Stretch application; measure Live fixtures and control gestures before changing the provisional mapping; then expand disabled panels through the same gates. This milestone does not complete transformations, generators or MPE.
