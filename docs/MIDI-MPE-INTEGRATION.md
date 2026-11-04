# MIDI MPE integration foundation (provisional)

## Status and scope

Independent Lua implementation. No proprietary assets bundled. This is a raw-event foundation, not a finished per-note UI, not an Ableton parity claim and not measured plugin sound. Main Panel, Controller, UI, Core, Adapter and Expression files are unchanged by this worker.

Pure tests exercise the existing Expression engine through this adapter. The requested native REAPER executable was absent at `/home/randomaccessmemories/.hermes/cache/scratch/reaskii-native/reaper_linux_x86_64/REAPER/reaper`. No existing executable was found in the targeted local cache, `.local`, `/opt`, `/usr/local` or Downloads searches. No install was attempted. Native fixtures and an isolated runner are supplied but native write/apply/cancel/undo proof is BLOCKED, not passed. `qa/midi-mpe-integration-results.tsv` is the hash-bound execution record. A missing executable returns status 2, pure/native failure status 1, completed tests status 0. A native safe-session rejection is logged separately and must not be interpreted as successful Apply/Undo proof.

## Reference inspected

Official Live 12 manual: https://www.ableton.com/en/live-manual/12/midi-tools/

Official images visually inspected, not copied into this repo:

- https://ableton-production.imgix.net/live-manual/12/MIDIToolGlissandoL12.png?w=344
- https://ableton-production.imgix.net/live-manual/12/MIDIToolLFOL12.png?w=344

Glissando manual: at least two selected notes; connects one pitch to a successive pitch; Start is percentage of note length; Curve changes the bend curve. Image shows endpoint/curve display, Start and Curve rotary controls, Start 50%, Curve 0.0%, Auto and Transform. Screenshot settings do not prove reset defaults.

LFO manual: Target Pitch Bend/Slide/Pressure; attack/decay relative envelope; Shape Type Sine/Square/Triangle/Random with Shape control, Random reseed; Rate 1..1/128 in musical time (1 = four quarter-note beats); positive Time Shift delays, negative changes phase; Amount pitch ±2 times range, Base pitch ±range; other dimensions Amount/Base -127..127. Image shows target chooser, waveform display, A/D values, Shape/Rate/Amount rotary controls, shape chooser and inline time-shift/base fields. Shown values: A/D 0.0%, Shape 0.00, Rate 1/4, Amount 1.00 st, shift 0.0%, base 0.00 st. These are image settings, not empirically verified defaults.

This adapter follows that control vocabulary only where implemented. Curve transfer, amplitude normalization, phase convention, envelope mapping, sampling and reset semantics are independently chosen and explicitly provisional. No actual Live MIDI fixtures were available. No inference of exact parity from these screenshots.

## Stable API, version 1

Load the module and inject the existing pure Expression dependency:

```lua
local E = dofile(directory .. 'ReaSkii_MIDI_Expression.lua')
local M = dofile(directory .. 'ReaSkii_MIDI_MPEAdapter.lua')
M.configure({ E = E }) -- returns M; required before transform
local schema = M.describe() -- fresh plain tables, schema.version == 1
local changed = M.transform(raw, 'lfo_mpe', options)
```

`M.transform(raw, tool, options)` returns one raw MIDI string or raises a Lua error. It never calls REAPER, writes a take, changes input strings or changes the supplied options. Supported tool identifiers are exactly `glissando_mpe` and `lfo_mpe`. Unknown options are errors, not ignored promises. `M.describe()` lists implementation controls/defaults/ranges/units, provenance and restrictions, with `provisional=true`. All defaults are ours unless subsequently measured in Live.

Shared options:

- `mpe=true` REQUIRED: caller confirms an already configured MPE receiver. Ordinary multichannel MIDI is not silently treated as MPE.
- `member_channels={1,2,...,N}` REQUIRED, no implicit zone/default. Dense contiguous lower zone only, zero-based channels 1..15 (= MIDI channels 2..16), master channel 0 (= MIDI channel 1). Arbitrary subsets and upper zones are refused. No channel allocation or note conversion occurs. Actual selected note channels must be inside this list.
- `dimension='pitch'` default; LFO also accepts `slide`, `pressure`. Glissando is pitch only.
- `pitchbend_range` REQUIRED for pitch: finite 1..96 semitones. Optional but validated if supplied for other dimensions. This is a caller-confirmed symmetric member bend range assumption, not discovery, RPN transmission or synth setup. Nondefault/fractional ranges are allowed within the bound; receiver agreement is the caller's responsibility.
- `mode='replace'` only. Add mode is deliberately not exposed.

Pitch emits channel pitchbend `0xEn`, center 8192, endpoints 0 and 16383. Physical semitone conversion uses separate negative/positive scales 8192/8191 to hit both endpoints. Slide emits CC74 `0xBn 74 value`. Pressure emits CHANNEL pressure `0xDn value`, not polyphonic key pressure. Slide/pressure values clamp to 0..127; there is no invented negative MIDI value.

Glissando options:

- `start_percent=50`, 0..100 percent of each edited note's attributable duration.
- `curve=0`, -100..100 percent. Zero is linear after Start. Positive is an ease-out power curve; negative is ease-in. Exponent `2^(abs(curve)/25)` is our provisional function, not Live's measured curve.
- `steps=32`, integer 2..1024 samples per edited note.

At least two successive selected notes are required. Selected chords/overlapping selected melody notes are refused; different-member notes may touch. Each selected note except the final one bends from zero to `(next selected pitch - this pitch)` semitones. Intervals outside the declared range are refused, not clipped. Notes are not lengthened/tied/reallocated; the final note is untouched. This restricted melody implementation does NOT implement Live's full tie/grouping/overlap behavior. Start=100 means only the final attributable tick receives the target (dense tick deduplication may collapse a very short note).

LFO options:

- `ppq` REQUIRED: finite 1..1000000 ticks per quarter note, measured from the actual take's musical mapping, not hardcoded from another take.
- `rate=1/4`, finite 1/128..1 whole notes per cycle; period is `4*ppq*rate` ticks. All finite rates in this interval are accepted, not only a discrete Live menu.
- `amount=1`, signed semitones for pitch (±2*range), signed MIDI-value amplitude for slide/pressure (±127). Independently implemented peak excursion, not proven equal to Live Amount's full-wave transfer.
- `base=0`, signed semitones for pitch (±range), signed MIDI value for slide/pressure (±127), clamped after modulation. A useful unipolar slide/pressure example is base 64, amount 40.
- `shape='sine'`; also `triangle`, `square`. Fixed analytic waves only. Random/reseed and Shape morph are unsupported and refused.
- `attack=0`, `decay=0`, each 0..100 percent of attributable note duration; sum must be <=100. Piecewise linear amplitude envelope. Unlike Live's coupled UI, this pure API rejects inconsistent sums rather than adjusting another control silently.
- `time_shift=0`, -100..100 percent of oscillator period. Positive delays the wave (holds base until start), negative advances phase. Envelope remains note-relative. Exact Live mapping unmeasured.
- `samples=64`, integer 2..1024 per selected note. Phase restarts at each note. Musical period rather than a fixed number of cycles per note.

Example LFO parameters:

```lua
local options = {
  mpe=true, member_channels={1,2,3}, pitchbend_range=48,
  dimension='pitch', ppq=960, rate=1/4,
  amount=1, base=0, shape='sine', samples=64,
  attack=0, decay=0, time_shift=0,
}
```

## Byte and attribution guarantees

The adapter uses bounded `Expression.decode` for raw parsing. It validates complete MIDI channel messages (length, data bytes), positive selected note durations, actual note channel membership and all same-channel notes that could share the selected lifetime. Overlap with selected OR unselected notes, touching same-channel notes and occupying unterminated notes are refused. No channel-wide bend is presented as per-note expression over shared-channel polyphony. Unmatched note-offs are conservatively refused even outside the selection.

For each attributable edited note the adapter invokes `Expression.transform` on synthetic note scaffolding, takes only its generated target-dimension events, then merges them into original raw events. This avoids the existing engine encoder's assumption of an empty terminator and its broad same-tick priority sorting. The existing Expression implementation is NOT modified.

Only chosen-dimension events inside selected `[on, off)` windows are replaced. Generated samples occupy `[on, off-1]`; rounded duplicate ticks use the last sample. Unrelated raw message bytes, flags, absolute positions, release velocities, selection and note messages are retained. Original unrelated order is stable, except an existing neutral bend at a release tick is moved after the same channel's note-off for safety. Generated note-start expression follows the note-on. Muted selected notes produce muted expression, not active channel automation.

At note-off, source expression state is restored when needed, after the note-off, to prevent leaking generated values into later unselected notes on a reused member channel. Source state means the last original unmuted dimension value through release, defaulting to neutral pitch/zero slide/zero pressure. An existing release-tick dimension event is retained instead of duplicating that transition. These safety restoration events are an explicit addition outside the replacement window; they are not unrelated source changes. They do not prevent a synth's long release tails from responding to a bend reset; actual synth response has NOT been measured.

A final empty event OR native `B0 7B 00` (channel-0 CC123=0) source marker is accepted and retained, at the exact source position, flags, message and final raw record bytes; no source-boundary extension. A marker coincident with release stays last after restoration. Nonterminal empty events/multiple terminators, negative deltas and truncation are refused. A nonterminal CC123 inside a selected lifetime is refused, including master-channel mode messages; terminal CC123 is not misclassified as selected expression.

Conservative unsupported states: upper zones; arbitrary member subsets; ordinary non-MPE takes; same-channel overlap/touching; malformed notes/channel messages; polyphonic key pressure on edited members; RPN/NRPN/data-entry setup anywhere; CC64/66/69 on master or edited members (even releases are refused); channel-mode messages inside edited lifetimes; CCBZ companions; shaped/CCBZ-flagged target expression. Opaque unrelated SysEx/text is retained, not interpreted as receiver configuration: externally configured receiver and absence of opaque setup side effects remain caller responsibilities. No selected note returns byte-identical input after config/raw validation.

Budgets: underlying decoder 64 MiB, 100000 events, 2^31-1 PPQ; adapter 4096 note-ons, samples 2..1024, projected original + samples + possible restoration <=100000, output <=64 MiB. Exceeding a budget raises before a caller can receive output/write it.

## Core safe-session caller wrapper (no main-panel edits)

Install after any existing Adapter/Tools transform wrapper, capture its final dispatch, once per locally loaded Core instance:

```lua
local E = dofile(directory .. 'ReaSkii_MIDI_Expression.lua')
local MPE = dofile(directory .. 'ReaSkii_MIDI_MPEAdapter.lua')
MPE.configure({E=E})
local previous_transform = Core.transform
Core.transform = function(raw, tool, options)
  if tool == 'glissando_mpe' or tool == 'lfo_mpe' then
    return MPE.transform(raw, tool, options)
  end
  return previous_transform(raw, tool, options)
end

local session = Core.session(take)
local ok, err = pcall(function()
  session:preview('lfo_mpe', options) -- recomputes from original snapshot
end)
if not ok then
  -- A host readback mismatch can follow a real write. Preserve the session:
  -- cancel verifies restoration, while abandon preserves genuine external edits.
  local restored, restore_err = pcall(function() session:cancel() end)
  if not restored then
    local left_changed, reason = session:abandon()
    -- Surface err, restore_err, left_changed and reason in caller UI/log.
    -- Do not claim restoration or delete recovery journals by hand.
  end
  -- Surface err and stop; never apply after a rejected preview.
else
  -- Keep session open while adjusting controls. Then choose ONE:
  -- session:cancel()                    -- Auto off / cancellation
  -- session:apply('ReaSkii MPE LFO')    -- confirmed commit + undo
end
```

Do not use `session:write` directly or a bare `MIDI_SetAllEvts` in the panel. Do not wrap on each slider event, or capture a dispatcher that later routes back into itself. Core handles identity/conflicts, verified journal before writes, strict readback, cancellation and named undo. The pure module itself cannot make host/session guarantees.

Core does not normalize expression itself: `session:write` calls native SetAllEvts, reads native GetAllEvts and tracks the actual bytes; `preview` rejects any mismatch. Native REAPER may normalize raw data. The supplied native fixture records first mismatch/lengths and cancellation if this occurs. Because the executable is missing, no actual normalization diagnosis or native outcome can currently be asserted.

## Reproduction and acceptance gates

```sh
python3 /home/randomaccessmemories/.hermes/cache/scratch/lua54_run.py tests/midi_expression_unit.lua
python3 /home/randomaccessmemories/.hermes/cache/scratch/lua54_run.py tests/midi_mpe_integration_unit.lua
python3 tests/run_midi_mpe_integration.py \
  --reaper /home/randomaccessmemories/.hermes/cache/scratch/reaskii-native/reaper_linux_x86_64/REAPER/reaper \
  --lua-runner /home/randomaccessmemories/.hermes/cache/scratch/lua54_run.py
```

Native runner uses a unique `TMPDIR/reaskii-native-mpe-integration-*` config, auto-allocated Xvfb, own process group, disabled plugin scan paths; never the parallel worker's display/config. It creates only scratch test takes. It tests all three dimensions through native raw writes and a Core caller wrapper, preview from snapshot, cancel, apply/undo when preview verifies, terminal source boundary, same-channel refusal and no partial writes on invalid configurations. The Lua fixture is compile-checked in the pure suite but has not executed in the absent host.

Remaining acceptance: restore the existing isolated executable (user/parent decision; no installation done here), run native tests, inspect any real mismatch without weakening Core, export actual Live MPE fixtures, measure curve/amplitude/phase/envelope/reset behavior, implement full note tying/grouping, Random/reseed/Shape morph, upper zones if required, actual receiver/plugin sound checks, parent per-note UI and Auto/Reset/Undo integration, then Windows runtime verification. None of those milestones are claimed by passing a pure library suite.
