# dmgbuild settings for the release disk image, used by 20_package_dmg_notarize_staple.sh as
#   dmgbuild -s dmg-settings.py -D app=<path to Afino.app> -D background=dmg-background.tiff <name> <dmg>
# The window and icon positions match the background drawn by design/render-dmg-background.swift.
import os

app = defines.get("app")
background_path = defines.get("background")
app_name = os.path.basename(app)

format = "UDZO"
size = None
files = [app]
symlinks = {"Applications": "/Applications"}
hide_extensions = [app_name]
badge_icon = app

background = background_path
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
# Matches the background (660 × 420) plus the title bar.
window_rect = ((200, 200), (660, 448))
default_view = "icon-view"
show_icon_preview = False
include_icon_view_settings = "auto"
include_list_view_settings = False
icon_size = 128
text_size = 14
label_pos = "bottom"

icon_locations = {
    app_name: (175, 175),
    "Applications": (485, 175),
}
