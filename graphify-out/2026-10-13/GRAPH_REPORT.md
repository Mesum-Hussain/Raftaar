# Graph Report - rhun  (2026-10-13)

## Corpus Check
- 133 files · ~317,227 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 432 file(s) not represented in the graph (top: .syn 133, .s 106, .expected 56)

## Summary
- 2312 nodes · 5153 edges · 163 communities (97 shown, 66 thin omitted)
- Extraction: 94% EXTRACTED · 6% INFERRED · 0% AMBIGUOUS · INFERRED: 321 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `6a642344`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- C
- windows.py
- distanceToPoint
- CommitAI
- Translator
- gp
- LiveReload
- arm64.py
- install.sh
- constructor
- wayland-launcher.c
- rn
- updateProjectionMatrix
- .render
- EditorMatrix
- SidebarSplit
- SettingsUI
- jt
- linux-appearance.py
- ReopenClosedTab
- EditorHScroll
- linux-scroll.py
- X11Auth
- fromBufferAttribute
- FileLaunch
- TerminalLinks
- file-icons.py
- startup-stats-x11.py
- ReadOnlySave
- Tooltips
- Appearance
- expandByObject
- _fromTexture
- LocalModel
- TerminalTabs
- applyMatrix4
- FieldBlink
- .err
- GitReset
- install.ps1
- hero.js
- ce
- FocusedZoom
- n
- StartupStats
- startup-stats-mac.py
- startup-stats-win.py
- PaletteScroll
- commit.sh
- .check_download
- ShiftWheel
- Clipboard
- LongPaths
- setStyle
- raftaar guide
- NewWindow
- ScrollSensitivity
- Bench
- startup-stats-hyprland.py
- tests/file-associations.py
- Stress
- TerminalKeys
- commit.ps1
- CommitWrap
- GitUntracked
- windows-update.py
- .analyze
- build-windows.py
- Id
- ct
- bind
- tests/install.sh
- mkfont.py
- mp
- multiplyScalar
- app.py
- build.py
- Shop.Notifier
- desktop-ux.py
- flatten
- Order
- blink.sh
- mac-launch.py
- windows-appearance.py
- .divide
- .layout
- icons.py
- gen-assets.sh script
- Jf
- explorer-create.py
- explorer-tabs.py
- session.sh
- build-mac.sh
- export.sh
- health
- detach.sh
- files.sh
- install-output.py
- update.sh
- casefold.py
- tools/file-associations.py
- verify-mac-release.sh
- providers/README.md
- docs.js
- shop
- App.tsx
- linux.sh
- explorer-delete.py
- inject
- fuzz.py
- mac-package.py
- run.sh
- ui.sh
- package-mac.sh
- dot
- release.sh
- SECURITY.md
- site/build.sh
- take.sh
- vendor/README.md
- compare-linux.sh
- prose.md
- mac-defaults.py
- extract-windows-llvm.py
- gen-keysyms.sh
- tools/install.sh
- package-windows.py
- gc
- normalize
- dispatchEvent
- subVectors
- getValueSize
- cc
- evaluate
- getBarycoord
- getObjectByProperty
- eo
- lf
- load
- getPoint
- setFromProjectionMatrix
- setFromCylindrical
- setFromSpherical
- copy
- Startup stats
- getObjectsByProperty
- social/README.md
- unbind

## God Nodes (most connected - your core abstractions)
1. `Translator` - 129 edges
2. `constructor()` - 89 edges
3. `copy()` - 65 edges
4. `mp()` - 55 edges
5. `CommitAI` - 50 edges
6. `LiveReload` - 44 edges
7. `update()` - 40 edges
8. `C()` - 40 edges
9. `gp()` - 39 edges
10. `applyMatrix4()` - 38 edges

## Surprising Connections (you probably didn't know these)
- `gsettings()` --indirect_call--> `session()`  [INFERRED]
  tests/linux-appearance.py → tests/windows.py
- `build.sh script` --calls--> `gen-assets.sh script`  [EXTRACTED]
  build.sh → tools/gen-assets.sh
- `draw()` --indirect_call--> `height()`  [INFERRED]
  site/hero.js → site/vendor/three-0.180.0.min.js
- `draw()` --indirect_call--> `width()`  [INFERRED]
  site/hero.js → site/vendor/three-0.180.0.min.js
- `shown()` --indirect_call--> `tree()`  [INFERRED]
  tests/linux-scroll.py → tests/linux-launch.py

## Import Cycles
- None detected.

## Communities (163 total, 66 thin omitted)

### Community 1 - "C"
Cohesion: 0.05
Nodes (66): $a(), add(), addEventListener(), clear(), u(), C(), Dd(), h() (+58 more)

### Community 2 - "windows.py"
Cohesion: 0.12
Nodes (42): cls_keeps_prompt(), command(), commit_ai(), control(), crlf_script(), environment(), equal(), file_becomes_symlink() (+34 more)

### Community 3 - "distanceToPoint"
Cohesion: 0.22
Nodes (15): clampPoint(), _computeIntersections(), containsPoint(), distanceSqToPoint(), distanceTo(), distanceToPoint(), distanceToSphere(), distanceToSquared() (+7 more)

### Community 4 - "CommitAI"
Cohesion: 0.06
Nodes (10): CommitAI, Hermetic provider and headless UI checks. Never contacts a provider or…, command(), expect(), pixel(), Follow system dark mode on macOS: a copy of the app follows the system's…, set_dark(), state() (+2 more)

### Community 6 - "gp"
Cohesion: 0.18
Nodes (21): clearLayerUpdates(), Bt(), decompose(), gp(), dt(), E(), ee(), et() (+13 more)

### Community 7 - "LiveReload"
Cohesion: 0.18
Nodes (5): LiveReload, write_stream(), skipIf, External writes reload open files, keep local edits, and briefly mark the…, Click the Animate changed text switch, then check that no other setting moved.

### Community 8 - "arm64.py"
Cohesion: 0.08
Nodes (26): Exception, char_value(), Error, evaluate(), expr(), peek(), primary(), guard() (+18 more)

### Community 9 - "install.sh"
Cohesion: 0.13
Nodes (41): add_block(), add_path(), add_posix(), banner(), bash_login(), choose_default_editor(), configure_files(), default_app_dir() (+33 more)

### Community 10 - "constructor"
Cohesion: 0.07
Nodes (40): constructor(), Eo(), es(), fe(), K(), Mo(), ns(), pt() (+32 more)

### Community 11 - "wayland-launcher.c"
Cohesion: 0.07
Nodes (20): HashMap, mode_t, Option, Self, main(), Order, Pricer, String (+12 more)

### Community 12 - "rn"
Cohesion: 0.12
Nodes (11): arith_imm(), logical_imm(), reg = v (bits 32 or 64), a register holding v; zero register for 0, emits setup (x9, x10) and returns the AArch64 address operand, d = address of m (64-bit register name), tmp (index) = zero-extended memory value; returns register name, register name holding operand o (bits); 8/16-bit registers may carry high… (+3 more)

### Community 13 - "updateProjectionMatrix"
Cohesion: 0.29
Nodes (7): clearViewOffset(), getFilmHeight(), getFilmWidth(), getFocalLength(), setFocalLength(), setViewOffset(), updateProjectionMatrix()

### Community 14 - ".render"
Cohesion: 0.14
Nodes (19): Bd(), a(), r(), clone(), dispose(), extractBasis(), fp(), R() (+11 more)

### Community 15 - "EditorMatrix"
Cohesion: 0.10
Nodes (3): EditorMatrix, skipIf, Editor controls, palette inventory, theme rendering and narrow-window safety.

### Community 16 - "SidebarSplit"
Cohesion: 0.11
Nodes (4): Panel dividers keep their presses and cursors, scrollbars hide when idle…, echo NAME= before a print command; returns {NAME: its output line}, shot{N} in actions takes screenshot N; returns their pixels, SidebarSplit

### Community 17 - "SettingsUI"
Cohesion: 0.13
Nodes (9): Click every settings control, verify saved values, cancellation and limits. Run…, SettingsUI, do_GET(), Handler, install(), install_while_stage_held(), Exercise the Windows installer against local, checksum-verified release…, install, with LICENSE in its staging folder held open from before the folder is… (+1 more)

### Community 18 - "jt"
Cohesion: 0.15
Nodes (15): jt(), disableAll(), enable(), T(), getParameter(), getViewport(), Jt(), Wt() (+7 more)

### Community 19 - "linux-appearance.py"
Cohesion: 0.10
Nodes (16): Bus, gsettings(), marshal(), message(), pad(), Raftaar, check(), Follow system dark mode on Linux, through the real X11 and Wayland backends,… (+8 more)

### Community 20 - "ReopenClosedTab"
Cohesion: 0.24
Nodes (3): skipIf, Reopen Closed Tab (Ctrl+Shift+T, Command+Shift+T on macOS) brings back the last…, ReopenClosedTab

### Community 21 - "EditorHScroll"
Cohesion: 0.19
Nodes (6): EditorHScroll, frame_time(), skipIf, The editor's horizontal scrollbar (issue 49): with word wrap off, lines wider…, the distinct colors along the bar's track: one while it is hidden, x, max and the track (x, y, w, h), or None without the bar

### Community 22 - "linux-scroll.py"
Cohesion: 0.10
Nodes (20): nodes(), output(), Native Linux launch focus with a competing window and focus prevention enabled., tree(), clicks(), scroll(), events(), scroll() (+12 more)

### Community 23 - "X11Auth"
Cohesion: 0.18
Nodes (5): skipUnless, Capture X11 setup requests using isolated authority files and a fake server., receive(), record(), X11Auth

### Community 24 - "fromBufferAttribute"
Cohesion: 0.11
Nodes (27): addGroup(), Ai(), applyMatrix3(), applyNormalMatrix(), computeTangents(), computeVertexNormals(), fromBufferAttribute(), getAttribute() (+19 more)

### Community 25 - "FileLaunch"
Cohesion: 0.14
Nodes (7): FileLaunch, FileLaunchReload, skipIf, A config file written while the window runs (another raftaar saving its…, A window started with files alone (raftaar notes.txt, --wait, Finder) is a…, The middle of a [ui] row in Settings, laid out as tests/settings-ui.py does…, settings_row_y()

### Community 26 - "TerminalLinks"
Cohesion: 0.24
Nodes (5): skipIf, The middle of a cell of text in the output (not on a prompt line): x, y., Links in the terminal: Cmd+click on macOS, Ctrl+click elsewhere. An http(s) URL…, Types a command into the shell and waits for its output: for a line only the…, TerminalLinks

### Community 27 - "file-icons.py"
Cohesion: 0.14
Nodes (22): arc(), area(), cubic(), ellipse(), evenodd(), glyph(), inside(), main() (+14 more)

### Community 28 - "startup-stats-x11.py"
Cohesion: 0.14
Nodes (15): check_platform(), ClientIdSpec, ClientIdValue, find_binary(), launch_environment(), main(), measure(), print_stats() (+7 more)

### Community 29 - "ReadOnlySave"
Cohesion: 0.23
Nodes (3): skipIf, Saving a read-only file asks first: Overwrite replaces it and it stays read-…, ReadOnlySave

### Community 30 - "Tooltips"
Cohesion: 0.22
Nodes (5): skipIf, The strip under the button before hovering, and after hovering for wait ms., Hover tooltips: the delay, what hides them, the setting, and no redraw while…, Generate's tooltip at x y, in the work tree's panel at its narrowest (260 of a…, Tooltips

### Community 33 - "expandByObject"
Cohesion: 0.18
Nodes (19): expandByObject(), expandByPoint(), expandByScalar(), getBoundingBox(), getBoundingSphere(), getCenter(), getSize(), getVertexPosition() (+11 more)

### Community 34 - "_fromTexture"
Cohesion: 0.14
Nodes (21): _allocateTargets(), _applyPMREM(), n(), Bl(), _blur(), _cleanup(), compileCubemapShader(), compileEquirectangularShader() (+13 more)

### Community 35 - "LocalModel"
Cohesion: 0.14
Nodes (4): LocalModel, do_POST(), skipUnless, Exercise the Windows download protocol against a loopback fixture, never real…

### Community 36 - "TerminalTabs"
Cohesion: 0.25
Nodes (3): Terminals are tabs among the files: Toggle Terminal goes to one and back, New…, A new terminal that sets its title and prints SESSION_index (the echo of what…, TerminalTabs

### Community 37 - "applyMatrix4"
Cohesion: 0.05
Nodes (55): addVectors(), applyMatrix4(), attach(), center(), computeBoundingBox(), computeBoundingSphere(), conjugate(), a() (+47 more)

### Community 38 - "FieldBlink"
Cohesion: 0.15
Nodes (7): FieldBlink, skipIf, The caret blinks in every text field as it does in the editor: the find bar and…, y of a setting's row in a 1400 px wide Settings tab (as tests/settings-ui.py…, the frames shown after actions, 300 ms apart, as (width, pixels), the x range where two frames differ, or None, settings_row_y()

### Community 41 - "install.ps1"
Cohesion: 0.18
Nodes (13): Choose-DefaultEditor(), Get-EditorValue(), Get-UserVariable(), Notify-FileAssociations(), Register-FileAssociations(), Remove-FileAssociations(), Remove-Folder(), Remove-StaleUpdates() (+5 more)

### Community 42 - "hero.js"
Cohesion: 0.16
Nodes (17): animate(), canvas, context, draw(), hero, narrow, paint(), pointer (+9 more)

### Community 43 - "ce"
Cohesion: 0.21
Nodes (17): af(), ce(), cf(), $d(), ef(), he(), hi(), If() (+9 more)

### Community 44 - "FocusedZoom"
Cohesion: 0.29
Nodes (3): FocusedZoom, skipUnless, Editor and terminal font zoom follows focus, persists independently, and leaves…

### Community 45 - "n"
Cohesion: 0.06
Nodes (35): clearUpdateRanges(), getHex(), getHexString(), getInterpolation(), getNormal(), getRGB(), hp(), Ka() (+27 more)

### Community 46 - "StartupStats"
Cohesion: 0.12
Nodes (3): load(), Standalone startup probes: PID filtering, timing, cleanup, and report…, StartupStats

### Community 47 - "startup-stats-mac.py"
Cohesion: 0.19
Nodes (10): check_platform(), find_binary(), launch_environment(), main(), measure(), print_stats(), Print a readable report; all durations are milliseconds., Raftaar startup stats on macOS. Requires Python 3 and Raftaar only. Usage:… (+2 more)

### Community 48 - "startup-stats-win.py"
Cohesion: 0.18
Nodes (10): check_platform(), find_binary(), launch_environment(), main(), measure(), print_stats(), Print a readable report; all durations are milliseconds., Raftaar startup stats on Windows. Requires Python 3 and Raftaar only. Usage: py… (+2 more)

### Community 50 - "commit.sh"
Cohesion: 0.29
Nodes (11): auth(), fail(), git_at(), NO_COLOR, commit.sh script, find_cli(), install_local(), local_server() (+3 more)

### Community 52 - "ShiftWheel"
Cohesion: 0.27
Nodes (4): skipIf, Shift turns the wheel sideways on Linux and Windows (discussion 67), in the…, the editor's x in pixels and y in 1/256 lines, ShiftWheel

### Community 53 - "Clipboard"
Cohesion: 0.26
Nodes (4): Clipboard, holder(), skipUnless, Native copy/paste must survive a short clipboard lock from another process.

### Community 54 - "LongPaths"
Cohesion: 0.24
Nodes (4): extended(), LongPaths, skipUnless, Native file operations beyond MAX_PATH without changing the system policy.

### Community 55 - "setStyle"
Cohesion: 0.21
Nodes (12): getHSL(), Kr(), lerpHSL(), ma(), mc(), offsetHSL(), set(), setColorName() (+4 more)

### Community 56 - "raftaar guide"
Cohesion: 0.06
Nodes (27): Explorer file icons, Build, Commit message AI, Configuration, Extensions (planned), Features, Folders and files, Git (+19 more)

### Community 57 - "NewWindow"
Cohesion: 0.24
Nodes (4): NewWindow, skipIf, Open Folder's "Open <folder> in a new window", and a recent folder in the…, A session of the folder, so the project menu lists it as a recent folder.

### Community 59 - "Bench"
Cohesion: 0.22
Nodes (8): Bench, fixtures(), main(), measure(), Headless performance baseline: times raftaar on fixed workloads, so a version…, seconds for one run of raftaar TARGET with the script's actions, then quit, ms per step: (setup + n steps) less setup alone, one sample of every workload

### Community 60 - "startup-stats-hyprland.py"
Cohesion: 0.39
Nodes (7): hyprctl(), main(), measure(), print_stats(), Raftaar startup stats on Hyprland. Requires Python 3 and hyprctl. Usage:…, Print a readable report; all durations are milliseconds., stop_process()

### Community 61 - "tests/file-associations.py"
Cohesion: 0.18
Nodes (7): check_shells(), editor_in(), quoted(), Verify installer choices and registration without changing the user's…, PATH as sh reads it in single quotes, VISUAL and EDITOR as SHELL exports them after reading RC, with EXTRA in its…, each shell reads EXPECTED (VALUE) where a window can open (DISPLAY), and keeps…

### Community 63 - "TerminalKeys"
Cohesion: 0.24
Nodes (4): skipIf, Runs the reader, presses keys, and returns its reply line and what each key…, Keys a program in the terminal receives (issue 54). A program that turns on the…, TerminalKeys

### Community 64 - "commit.ps1"
Cohesion: 0.33
Nodes (9): Download-Runtime(), Git(), Install-Local(), Local-Server(), Pull-Model(), Snapshot(), Quote-Arg(), Run() (+1 more)

### Community 67 - "windows-update.py"
Cohesion: 0.24
Nodes (6): Handler, Exercise the editor's embedded Windows updater and detached restart with local…, restarted_window(), run(), standalone_restart(), stop_restarted()

### Community 68 - ".analyze"
Cohesion: 0.24
Nodes (3): writes flags only sometimes: string compares with rcx 0, shifts by cl 0, flags that instructions after k read before they are written; inc/dec passed…, data labels: section base + offset, so differences in one section are constants

### Community 69 - "build-windows.py"
Cohesion: 0.29
Nodes (9): assets(), main(), assemble(), executable(), Build native x64 Windows PE files with LLVM, on Windows, Linux or macOS. Only…, PowerShell TEXT without its whole-line comments, here-strings as they are: the…, run(), tool() (+1 more)

### Community 70 - "Id"
Cohesion: 0.10
Nodes (22): ep(), F(), P(), R(), u(), v(), A(), F() (+14 more)

### Community 71 - "ct"
Cohesion: 0.15
Nodes (14): applyAxisAngle(), applyEuler(), applyQuaternion(), compose(), ct(), getWorldPosition(), makePerspective(), makeRotationFromQuaternion() (+6 more)

### Community 72 - "bind"
Cohesion: 0.50
Nodes (5): bind(), findNode(), getValue(), _getValue_unbound(), _setValue_unbound()

### Community 73 - "tests/install.sh"
Cohesion: 0.33
Nodes (7): begin(), end(), inode(), inst(), release(), install.sh script, t()

### Community 74 - "mkfont.py"
Cohesion: 0.31
Nodes (9): components(), main(), Copy a TrueType font keeping only the tables raftaar reads, optionally only…, code point -> glyph id, from the format 12 or format 4 subtable, offsets of the glyph index fields in a composite glyph, read_cmap(), subset(), tables_of() (+1 more)

### Community 75 - "mp"
Cohesion: 0.09
Nodes (15): it(), te(), oe(), v(), mp(), g(), gt(), h() (+7 more)

### Community 76 - "multiplyScalar"
Cohesion: 0.19
Nodes (14): angleTo(), clamp(), clampLength(), clampScalar(), coplanarPoint(), divideScalar(), Ft(), lengthSq() (+6 more)

### Community 77 - "app.py"
Cohesion: 0.38
Nodes (6): get, post, create_order(), get_order(), Order, HTTP API for the shop: orders and their status.

### Community 79 - "Shop.Notifier"
Cohesion: 0.33
Nodes (3): Shop.Notifier, handle_cast(), handle_info()

### Community 80 - "desktop-ux.py"
Cohesion: 0.33
Nodes (4): opens(), the output, and the opener's calls once there is one. raftaar starts the opener…, Startup project precedence and desktop actions, with isolated user state., run()

### Community 81 - "flatten"
Cohesion: 0.33
Nodes (4): contours(), flatten(), Subdivide a cubic until the control polygon is within 0.2 grid units of its…, Flatten provider SVGs to the icon grid. Regeneration needs reportlab; builds do…

### Community 83 - "blink.sh"
Cohesion: 0.53
Nodes (4): check(), frames(), run(), blink.sh script

### Community 84 - "mac-launch.py"
Cohesion: 0.40
Nodes (3): find_pid(), jxa(), Real Launch Services file events, ordinary tabs and foreground activation.

### Community 85 - "windows-appearance.py"
Cohesion: 0.40
Nodes (4): Follow system dark mode on Windows: the app mode under the Personalize key at…, print-appearance lines of a real window's script, with app mode changes made…, states(), write()

### Community 87 - ".layout"
Cohesion: 0.33
Nodes (3): bytes of a GNU as string literal, offsets of labels in data sections (the translation keeps data sizes); .quad…, string_bytes()

### Community 88 - "icons.py"
Cohesion: 0.16
Nodes (12): arc(), _arc_points(), huge(), line(), _path_lines(), poly(), a Hugeicons icon as a drawing program: its 24 units over the 128 grid, a closed rounded rectangle, clockwise from the top left corner's end (+4 more)

### Community 89 - "gen-assets.sh script"
Cohesion: 0.50
Nodes (3): build.sh script, emit(), gen-assets.sh script

### Community 90 - "Jf"
Cohesion: 0.17
Nodes (12): Jf(), ji(), jl(), kf(), Kl(), Qf(), Ql(), tc() (+4 more)

### Community 93 - "session.sh"
Cohesion: 0.80
Nodes (4): check(), fresh(), run(), session.sh script

### Community 94 - "build-mac.sh"
Cohesion: 0.70
Nodes (4): link(), name(), build-mac.sh script, stale()

### Community 95 - "export.sh"
Cohesion: 0.83
Nodes (3): render(), export.sh script, shot()

### Community 97 - "detach.sh"
Cohesion: 0.83
Nodes (3): check(), run(), detach.sh script

### Community 99 - "install-output.py"
Cohesion: 0.67
Nodes (3): main(), Check actual installer output with and without a terminal, using test releases., run_installer()

### Community 100 - "update.sh"
Cohesion: 0.83
Nodes (3): expect(), run(), update.sh script

### Community 102 - "casefold.py"
Cohesion: 0.67
Nodes (3): fold(), main(), Writes src/casefold.s: the simple case folding of every character whose folded…

### Community 103 - "tools/file-associations.py"
Cohesion: 0.67
Nodes (3): outputs(), Keep installer extension lists and desktop declarations aligned with the…, text_extensions()

### Community 118 - "dot"
Cohesion: 0.25
Nodes (11): addScaledVector(), at(), closestPointToPoint(), distanceSqToSegment(), distanceToPlane(), dot(), intersectBox(), intersectLine() (+3 more)

### Community 136 - "gc"
Cohesion: 0.18
Nodes (11): an(), convertLinearToSRGB(), convertSRGBToLinear(), copyLinearToSRGB(), copySRGBToLinear(), gc(), getDataURL(), Il() (+3 more)

### Community 141 - "normalize"
Cohesion: 0.22
Nodes (11): computeFrenetFrames(), P(), extractRotation(), getTangent(), getTangentAt(), length(), makeRotationAxis(), normalize() (+3 more)

### Community 142 - "dispatchEvent"
Cohesion: 0.27
Nodes (10): connect(), et(), W(), Z(), disable(), disconnect(), dispatchEvent(), dt() (+2 more)

### Community 143 - "subVectors"
Cohesion: 0.33
Nodes (9): cross(), crossVectors(), getArea(), getPlane(), intersectTriangle(), isFrontFacing(), setFromCoplanarPoints(), setFromNormalAndCoplanarPoint() (+1 more)

### Community 144 - "getValueSize"
Cohesion: 0.22
Nodes (9): getValueSize(), InterpolantFactoryMethodDiscrete(), InterpolantFactoryMethodLinear(), InterpolantFactoryMethodSmooth(), $l(), Oc(), optimize(), trim() (+1 more)

### Community 145 - "cc"
Cohesion: 0.38
Nodes (7): bo(), cc(), hc(), seqWithValue(), setOptional(), setValue(), upload()

### Community 146 - "evaluate"
Cohesion: 0.40
Nodes (6): copySampleValue_(), evaluate(), getSettings_(), interpolate_(), intervalChanged_(), slerpFlat()

### Community 147 - "getBarycoord"
Cohesion: 0.40
Nodes (5): getBarycoord(), getInterpolatedAttribute(), Rc(), setScalar(), xs()

### Community 148 - "getObjectByProperty"
Cohesion: 0.67
Nodes (3): getObjectById(), getObjectByName(), getObjectByProperty()

### Community 152 - "getPoint"
Cohesion: 0.29
Nodes (8): getLength(), getLengths(), getPoint(), getPointAt(), getPoints(), getSpacedPoints(), getUtoTmapping(), updateArcLengths()

### Community 156 - "copy"
Cohesion: 0.08
Nodes (35): ap(), r(), copy(), cp(), o(), Ei(), equals(), _f() (+27 more)

### Community 157 - "Startup stats"
Cohesion: 0.40
Nodes (4): Headless baseline, Interpret results, Run, Startup stats

## Knowledge Gaps
- **48 isolated node(s):** `NO_COLOR`, `TERM`, `build.sh script`, `stage`, `preview` (+43 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 594 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **66 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `constructor()` connect `constructor` to `three-0.180.0.min.js`, `C`, `gp`, `gc`, `updateProjectionMatrix`, `.render`, `dispatchEvent`, `cc`, `jt`, `fromBufferAttribute`, `setFromProjectionMatrix`, `copy`, `expandByObject`, `_fromTexture`, `applyMatrix4`, `ce`, `n`, `ct`, `bind`, `mp`, `multiplyScalar`?**
  _High betweenness centrality (0.011) - this node is a cross-community bridge._
- **Why does `mp()` connect `mp` to `three-0.180.0.min.js`, `C`, `applyMatrix4`, `gp`, `ct`, `constructor`, `n`, `.render`, `dispatchEvent`, `jt`, `dot`, `copy`?**
  _High betweenness centrality (0.010) - this node is a cross-community bridge._
- **Why does `gp()` connect `gp` to `three-0.180.0.min.js`, `C`, `Id`, `gc`, `constructor`, `mp`, `.render`, `jt`?**
  _High betweenness centrality (0.009) - this node is a cross-community bridge._
- **Are the 6 inferred relationships involving `constructor()` (e.g. with `it()` and `je()`) actually correct?**
  _`constructor()` has 6 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `copy()` (e.g. with `e()` and `l()`) actually correct?**
  _`copy()` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Are the 26 inferred relationships involving `mp()` (e.g. with `at()` and `Bt()`) actually correct?**
  _`mp()` has 26 INFERRED edges - model-reasoned connections that need verification._
- **What connects `NO_COLOR`, `TERM`, `build.sh script` to the rest of the system?**
  _48 weakly-connected nodes found - possible documentation gaps or missing edges._