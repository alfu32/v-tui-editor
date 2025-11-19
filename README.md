<div align="center">

# V Reactive Renderer

Terminal-first UI experiments powered by a lightweight virtual DOM and a headless text-buffer editor.

</div>

![Workspace overview](doc/assets/Screenshot%20from%202025-11-19%2001-39-06.png)

> ⚡ Compiles in under a second and produces ~900 KB static binaries on Linux thanks to V’s lean runtime.

## Objectives

- **Composable primitives** – drive the entire UI from three reactive primitives (`<rect>`, `<text>`, `<relative>`) that can be nested, styled, and wired with events like a mini JSX for the terminal.
- **Headless editor core** – keep editing logic (cursor, selection, clipboard, viewport slicing) independent of rendering so it can later plug into different front-ends (Tree-sitter, syntax themes, etc.).
- **Interactive workspace** – provide a split-pane layout with open files, a navigable file tree, resizable dividers, and a scrollable, editable buffer that behaves like a modern code editor.
- **Deterministic event routing** – bubble events through the component tree while respecting hit-testing so drag/resize gestures feel predictable even inside a terminal UI.

## Installation

1. **Install V**
   - Follow the official instructions at <https://github.com/vlang/v> to install the latest V compiler.
   - Ensure `v` is available on your `PATH`.
2. **Clone this repository**
   ```bash
   git clone https://github.com/your-user/v-editor.git
   cd v-editor/v-renderer
   ```
3. **Run the app (sub-second builds)**
   ```bash
   v run .
   ```
   The application launches inside the terminal using `term.ui`. Resize the terminal to explore how the layout adapts.
4. **Run the editor unit tests**
   ```bash
   v test ./editor
   ```
   This suite covers the headless buffer (cursor movement, selection, clipboard, viewport slicing).

## Features

### Virtual DOM + Templates

- Author components using string templates with embedded event handlers and styles.
- Only three primitives are required to build the entire layout, encouraging composable components and straightforward reasoning about hit boxes.

![Template-driven explorer](doc/assets/Screenshot%20from%202025-11-19%2001-37-53.png)

### File explorer & open-file stack

- File tree flattens directories into a sorted list with toggleable folders and graceful error handling for unreadable entries.
- Open-file list shows MRU ordering and allows instant focus switching. Both sections are separated by a draggable splitter.

### Headless text buffer + editor view

- Editor supports insertion, deletion, selections (including word-wise navigation with Ctrl/Shift modifiers), clipboard operations, and scrollable viewports.
- View rendering consumes the buffer’s viewport slice, paints gutters, highlights selections, and inverts the character under the caret for a VT-friendly cursor.

![Inverted cursor in editor](doc/assets/Screenshot%20from%202025-11-19%2001-24-56.png)

### Mouse-friendly layout

- Vertical and horizontal dividers can be drag-resized; gestures are constrained to their hit regions to avoid accidental resizing.
- Status bar surfaces mouse coordinates and the currently hovered component tag, helping reason about event targeting.

### Media

- [Workspace overview (webm)](doc/assets/Screencast%20from%2019-11-25%2001:41:04.webm)
- [Editing & resizing demo (webm)](doc/assets/Screencast%20from%2019-11-25%2001:43:13.webm)

## Roadmap Ideas

- Integrate Tree-sitter for syntax-aware segments within the headless buffer.
- Expand the component library with reusable widgets built atop the three primitives (status widgets, dialogs, etc.).
- Add persistence for workspace state (open files, cursor positions) and plug in file-watchers for live reloads.

---

Enjoy hacking on the terminal-reactive stack! PRs and experiments are encouraged.
