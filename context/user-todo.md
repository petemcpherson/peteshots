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

- [ ] **Text and crop tools (Phase 5).**
  1. Press T and click the image. Type two lines (Return adds a line). Check the cursor shows and the text has a soft dark shadow.
  2. Press Esc. Editing ends, the editor stays open, and the text is selected with 4 corner handles.
  3. Drag the text to move it. Drag a corner handle: the text scales and the opposite corner stays still.
  4. Double-click the text, change it, then click outside. Press Cmd-Z: the old text returns. Cmd-Shift-Z: the new text returns.
  5. Click with T, type nothing, click outside. No empty box remains.
  6. While typing, press V, A, B, Delete. They go into the text, not the tools.
  7. Press C. The full image shows with a dimmed outside and 8 handles. Drag handles and the inside. Press Return: only the crop area shows.
  8. Press C again, change the crop, press Esc: the previous crop stays. Press Cmd-Z after an applied crop: the crop is undone.


- [ ] **Save and export (Phase 6).**
  1. Capture a region, add an arrow, a blur, and text, then press Cmd-S. The editor closes and a file `Screenshot - MM-dd-yy HH.mm.png` appears in Downloads.
  2. Open the file. It matches the editor (crop, arrow, blur, text), and the long side is at most 2000 px.
  3. Save twice in the same minute. The second file ends in ` (2)`.
  4. After a save, paste into Preview (File → New from Clipboard) or Slack: the image pastes. Paste into a Finder window: the file is copied.
  5. Capture, then Cancel. No file is written.
  6. Make a folder read-only, set it as the destination (`defaults write com.peteshots.peteshots destinationPath /path/to/folder` until Phase 7 adds the setting), and save. The editor stays open and Save works again.
