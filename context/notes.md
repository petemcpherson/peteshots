# "Peteshots" app notes

The following notes are in no particular order of importance, etc, just "brainstorming & braindumping"

## tech

MacOS app.

## the gist

A very simple screenshot tool for MacOS, but with an instant "editing & annotation popup" and compression feature. For Pete's personal use only, not going to be publicly available.

## features

* local ONLY--no uploading screenshots to the web for cloud storage, etc. No data/info leaves my macbook!
* hotkey customization (usually use 'command-shit-a' personally, so that'll be the default)
* folder destination customization (default to Downloads folder)
* file type & size customization (can save as .png or .jpg/jpeg??). AND if (and only if) the image dimensions are above the chosen size threshold, the image can be auto-resized to a "long side in pixels." I.e. the user selects 1,000px, then takes a screenshot with the longest side of the image LONGER than that, say 2,354px wide. The image resolution/dimensions get automatically scaled down
* compression customization - can be enabled (default) or disabled. I'd love a very simple image compression to happen AFTER the editing & resizing process, etc. I want YOU to find the simplest & optimal way to do this.
* name customization - screenshot images will be "{custom_text} - {timestamp}". defaults to "Screenshot - MM/DD/YY HH:MM"
* on hotkey press, starts the "select a portion of the screen" experience. cursor changes. user clicks and drags. flexible rectange, etc.
* on release, the screenshot is taken, "editor" opens
* NOTE: It's up to YOU when we actually "save" the image file to the destination...before & during editing? Afterward?
* VERY simple editor, with a menu bar with a few options:
    * color picker (hex color, etc, this saves and persists between sessions, etc)
    * arrow tool (user clicks the arrow button, then drags an arrow with 2 re-positionable dots on the ends, i.e. to move or change the arrow shape) the arrow can be draggable to move
    * blur (user selects, then can drag a flexible rectangle of "blur") the blur "box" can be draggable to move
    * text field (also uses chosen hex color). just uses system font I suppose? whatever is cleanest, easiest!! NOTE: the textbox should be draggable to move....AND resizing the textbox increases/decreases the font size
    * image crop (simple, basic)
* command-s will save, or the 'save' button
* a VERY small popup notification will appear for about 2-3 seconds summarizing any resizes and/or compression that happened (for compression, a simple {original size in mb, kb, etc,} 👉 {compressed file size in mb, kb, etc}.)