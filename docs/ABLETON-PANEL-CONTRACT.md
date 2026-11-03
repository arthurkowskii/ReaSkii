# Ableton-panel fidelity: binding acceptance contract

## User correction supersedes the generic toolbox direction

Arthur requires the same behaviour AND graphical interaction logic as the Ableton Live MIDI panel. A toolbox with similar tool names, buttons and modal GetUserInputs forms is not an acceptable substitute. The installed MIDI LAB1 is a temporary engine/debug prototype, not an implementation that meets this requirement. Do not publish or deploy the modal-form expansion as the finished panel.

Keep the native REAPER piano roll. Existing engine/recovery code may be reused only where its behaviour matches measured reference results. Native host window embedding is a separate, explicitly unproven boundary.

## Reference evidence inspected by parent

- User screenshot upload_bjmi03ke.png: narrow collapsible left column, Clip, Launch, Pitch & Time, Transform, Generate; inline scale selectors; Pitch & Time contains Fit to Scale, Invert, interval entry/Add Interval, Stretch rotary control with numeric value and x2,/2 buttons, grid/Set Length, Humanize amount/button, Reverse and Legato.
- User screenshot upload_03sl0kan.png: Transform contains one tool chooser, not a grid of tool-launch buttons. Visible choices include Arpeggiate, Chop, Connect, Glissando (MPE), LFO (MPE), Ornament, Quantize, Recombine, Span, Strum, Time Warp, Velocity Shaper. Preserve inventory/order for the exact reference version once confirmed.
- Official Live12 manual: https://www.ableton.com/en/live-manual/12/midi-tools/
- Official Strum reference inspected visually: https://ableton-production.imgix.net/live-manual/12/MIDIToolStrumL12.png?w=640 . Tool selector and reset at top; Low/High percentage readouts; large Strum Position display with upper/lower draggable endpoints and connecting curve, horizontal centre guide; Tension percentage below; Auto toggle and Transform button. The Strum display is NOT a pair of substitute rotary controls. Stretch uses a rotary control in the user reference. Recreate each actual control type rather than putting knobs everywhere.

A static image proves appearance, not drag sensitivity/default-reset gestures, fine modifiers, wheel handling or exact interpolation. Those must be observed in the reference application.

## Required interface

- Match reference section hierarchy, chooser placement, grouping, visual density, relative geometry and inline controls. No Edit/Transform/Generate dashboard invented as replacement for the reference clip-panel hierarchy.
- Implement the actual control types: rotary arcs, inline draggable numeric values, tool dropdowns, toggles, segmented choices, draggable graphs/endpoints and tool-specific previews.
- Normal parameter adjustment stays inside the panel, not pop-up parameter-entry forms.
- Parameter changes update the real MIDI through the safe snapshot/session mechanism. Observe Auto on/off, reapply, Reset and Undo semantics rather than substituting an Apply/Cancel-only workflow.
- Keep accessibility labels/numeric values; do not encode state only by colour.
- Draw original vector primitives; do not bundle copied proprietary application assets. Matching interaction structure does not require extracting Ableton code, fonts or icons.

## Required behaviour and reference measurements

- Pin actual installed Live version/build, theme/zoom, scale, grid, clip loop, selection, playrate/timebase and tool settings for every comparison.
- Capture deterministic input fixtures and export actual Live MIDI output; compare against REAPER in musical time. Include boundary notes, no/partial selection, loops, scale on/off, straight/triplet grid, chords, overlaps and MPE channel reuse.
- Measure ranges, units, defaults, quantisation/step sizes, nonlinear transfer curves, note grouping, boundary handling, tool reapplication and exact selection semantics.
- Treat random tools separately: repeatability in our own code does not prove Ableton's PRNG or seed equivalence.
- Manual describes Auto Apply on by default, immediate updates, disabling Auto restores original; Reset resets tool parameters rather than MIDI. Verify against actual reference version before acceptance.
- The manual's generator-overlap descriptions need empirical resolution; do not choose add/replace semantics merely for convenience.
- Current independent algorithms (three arp styles, simple Euclidean voice, locally chosen Strum curve, restricted CC handling) are NOT accepted as parity. Implemented/tested internally != compared with Live.

## Delivery gates

1. Reference inventory with control-level evidence and unknowns.
2. Faithful interactive vertical slice in REAPER (Pitch & Time plus selected Strum panel); it is a milestone, not a scope reduction. Reference and implementation screenshots side by side plus real drag tests.
3. Behaviour comparison fixtures for that slice. Any discrepancy remains explicitly open.
4. Expand across every reference transformation, generator and MPE panel using the same gates.
5. Windows host/runtime and placement verification before claiming the laptop matches the reference.

No further deployment of the modal-form interface as the requested result. Preserve the installed LAB1 and user projects until a replacement passes its gates.
