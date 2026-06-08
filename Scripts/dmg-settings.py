application = defines["app"]
background = defines["background"]

format = "UDZO"
size = "64M"
files = [(application, "PastePilot.app")]
symlinks = {"Applications": "/Applications"}

icon_locations = {
    "PastePilot.app": (155, 210),
    "Applications": (445, 210),
}

window_rect = ((120, 120), (600, 360))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
include_icon_view_settings = True

arrange_by = None
label_pos = "bottom"
text_size = 13
icon_size = 112
