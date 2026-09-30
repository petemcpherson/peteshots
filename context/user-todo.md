The AI Agent can give Pete (the dev) manual to-do items here (clear, CONCISE, step by step instructions as well).
## Final testing (after all phases)

- [ ] **Capture flow (Phase 2): grant Screen Recording and test capture.**
  1. Run the app from Xcode (Cmd-R).
  2. Press Cmd-Shift-A. If the permission window appears, click **Open System Settings**, turn on **peteshots**, then quit and rerun the app.
  3. Press Cmd-Shift-A. Check that every display dims.
  4. Drag a region (hold Shift for a square). Check the `W × H` label shows real pixels.
  5. Release. The editor opens. Check the region matches and the dim overlay is not in the image.
  6. Check cancel: Esc, right-click, and a plain click each dismiss the overlay with no editor.

- [ ] **Editor window (Phase 3).**
  1. Capture a region. The editor opens centered on that display, with the image at its on-screen size (or scaled to fit about 85% of the screen).
  2. Capture a tiny region (about 50×50). The window keeps its minimum size and the image is centered.
  3. Press V, A, B, T, C and click the toolbar buttons. The highlighted tool changes each time.
  4. Press Cmd-Shift-A while the editor is open: the editor comes to the front, no overlay.
  5. Close with Esc, then with Cancel, then with the red close button. Each closes with no prompt, and the next Cmd-Shift-A shows the overlay again.
