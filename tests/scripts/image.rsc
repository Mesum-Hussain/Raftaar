# image tabs: fit, zoom by command, keys and ctrl+wheel, double click, a cut short file, a text file named .png
open tests/data/images/rgba.png
print-state
cmd zoom_in
print-state
key =
print-state
key -
key -
print-state
move 630 455
scroll -120 ctrl
print-state
scroll 60
key 0
print-state
click 630 455
click 630 455
print-state
cmd zoom_reset
print-state
key Right
key ctrl+w
print-state
open tests/data/images/truncated.png
print-state
open tests/data/images/exif-rotated.jpg
print-state
open tests/data/images/not-an-image.png
print-state
quit
