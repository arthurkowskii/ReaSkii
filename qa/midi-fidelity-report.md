# Interactive MIDI fidelity milestone QA

Result: working first vertical slice, not full panel acceptance. REFERENCE_PARITY = NOT_MEASURED.

Final commands and actual results:

- `python /home/randomaccessmemories/.hermes/cache/scratch/lua54_run.py tests/midi_fidelity_unit.lua`: exit 0, DONE 11, all new Lua entrypoints/helpers compile with loadfile.
- Same runner on `tests/midi_recovery_safety.lua`: exit 0, DONE 72.
- Same runner on `tests/midi_adapter_unit.lua`: exit 0 (silent success).
- `python -m py_compile tests/run_midi_fidelity_gui.py`: exit 0.
- `xvfb-run -a -s '-screen 0 1400x1000x24' python tests/run_midi_fidelity_gui.py --reaper /home/randomaccessmemories/.hermes/cache/scratch/reaskii-native/reaper_linux_x86_64/REAPER/reaper`: exit 0, DONE 21. Exact checks and tested hashes: `qa/midi-fidelity-host.tsv`.
- Independently parsed host report: every declared SHA256 matches disk and DONE exactly matches 21 enumerated PASS lines.

UI evidence: `midi-fidelity-panel.png`, `midi-fidelity-collapsed.png`, `midi-fidelity-small.png`; all viewed with vision. Real rotary/fine drags, inline editing and graph/tension changes read back from native MIDI; Auto off restores, Transform commits, Reset preserves commit, Cancel/native close restore pending preview only, and native Undo restores original after commit. The native piano roll remains open.

Comparison image: `qa/midi-fidelity-comparison.png` (static supplied reference crop beside actual native-host panel crop, original sizes). SHA256 65c1d8bfbb97ed78a11d061c2487a33d95605c67723c2c2dd41b7b4a7c6739d0. This is QA-only evidence, not an application asset. Official Strum image was also viewed directly, not copied into the application.

Implementation/safety/reference distinctions and all disabled functionality: `docs/MIDI-PANEL-MILESTONE.md`, SHA256 ad8dac3266bde3e962c8230fd28bc89015e576224b29611a9a225bf16576b5fb. The exact-onset chord grouping, fixed ends, nonlinear curve, inversion pivot, reverse range and gesture sensitivities are provisional local semantics. Static appearance and manual documentation do not establish Live behaviour equivalence. Windows/runtime/embedding, Docker transition and native adversarial/restart coverage remain open.

Earlier host failures were real: startup Panel missing with no visible UI; inline release/keyboard ordering; synthetic empty source terminator caused strict readback refusal. Final full host scenario passed after fixes, with 90-second wait to accommodate intermittent startup delay. `host-partial`, `last`, `commit` files are diagnostic snapshots, not separate parity results.

No existing engine/Tools/LAB1/theme/build/deployment files were changed; no installation, commit, push or remote machine access occurred.
