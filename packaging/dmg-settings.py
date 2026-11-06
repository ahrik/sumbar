from pathlib import Path

app = Path(defines['app']).resolve()
assets = Path(defines['assets']).resolve()
format = 'UDZO'
filesystem = 'HFS+'
files = [str(app)]
symlinks = {'Программы': '/Applications'}
icon = str(assets / 'Sumbar.icns')
background = str(assets / 'dmg-background.png')
window_rect = ((180, 120), (640, 420))
default_view = 'icon-view'
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
include_icon_view_settings = True
include_list_view_settings = False
icon_size = 88
text_size = 14
arrange_by = None
icon_locations = {'Sumbar.app': (160, 245), 'Программы': (480, 245)}
