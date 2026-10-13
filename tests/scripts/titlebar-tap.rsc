# a click posted at a titlebar button while the pointer rests elsewhere: no frame sees the pointer
# over the button, and the press is still the button's, not a window move
move 900 20
tap 1276 20
print-window
print-state
# resting on the welcome page's Settings, which must not take the press too
cmd close_tab
move 700 400
tap 1276 20
print-window
print-state
# the other way round: a press on the empty title area moves the window whatever the pointer hovers,
# and a second one there maximizes it
move 1276 20
tap 900 20
print-window
tap 900 20
print-window
print-state
quit
