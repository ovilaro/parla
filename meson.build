# to release update version field below and:
# vim data/io.github.trufae.Parla.appdata.xml
project('parla', ['vala', 'c'],
  version: '0.7.0',
  meson_version: '>= 0.59.0',
)

# posix vapi provides Posix.getpid () for the StatusNotifierItem bus name.
# mingw-w64 ships pid_t/getpid but no kill()/SIGKILL, so Windows-only code
# paths are selected with the WINDOWS Vala define.
add_project_arguments(['--pkg', 'posix'], language: 'vala')
if host_machine.system() == 'windows'
  add_project_arguments(['--define=WINDOWS'], language: 'vala')
endif

# Silence warnings emitted by valac-generated C and lagging GTK/glib vapi
# bindings (unused temporaries, g_once_init_enter atomics, const mismatches).
# These are not fixable from the Vala source.
cc = meson.get_compiler('c')
add_project_arguments(
  cc.get_supported_arguments([
    '-Wno-unused-but-set-variable',
    '-Wno-unused-function',
    '-Wno-unused-variable',
    '-Wno-incompatible-pointer-types',
    '-Wno-discarded-qualifiers',
    '-Wno-address',
  ]),
  language: 'c',
)

deps = [
  dependency('glib-2.0'),
  dependency('gio-2.0'),
  dependency('gtk4'),
  dependency('libadwaita-1', version: '>= 1.5'),
  dependency('json-glib-1.0'),
]

config = configuration_data()
config.set('VERSION', meson.project_version())
config.set('RPC_SERVER_PATH', get_option('rpc_server_path'))
config_file = configure_file(
  input: 'src/config.vala.in',
  output: 'config.vala',
  configuration: config,
)

python = import('python').find_installation()
appdata_xml = files('data/io.github.trufae.Parla.appdata.xml')
appdata_vala = custom_target(
  'appdata-vala',
  input: appdata_xml,
  output: 'appdata.vala',
  command: [
    python,
    files('build-aux/gen-appdata.py'),
    '@INPUT@',
    '@OUTPUT@',
  ],
)
configure_file(
  input: appdata_xml,
  output: 'io.github.trufae.Parla.metainfo.xml',
  copy: true,
  install: true,
  install_dir: get_option('datadir') / 'metainfo',
)

gnome = import('gnome')
resources = gnome.compile_resources(
  'parla-resources',
  'data/parla.gresource.xml',
  source_dir: 'data/icons/hicolor',
)

src_inc = include_directories('src')
sources = files(
  'src/main.vala',
  'src/platform.vala',
  'src/platform.c',
  'src/application.vala',
  'src/window.vala',
  'src/rpc_transport.vala',
  'src/rpc_params.vala',
  'src/attachment_types.vala',
  'src/rpc_parsers.vala',
  'src/rpc_client.vala',
  'src/account_finder.vala',
  'src/rpc_installer.vala',
  'src/models.vala',
  'src/message_history.vala',
  'src/chat_row.vala',
  'src/markdown.vala',
  'src/mentions.vala',
  'src/image_utils.vala',
  'src/message_row.vala',
  'src/image_viewer.vala',
  'src/video_player.vala',
  'src/audio_player.vala',
  'src/audio_recorder.vala',
  'src/conversation_media_bar.vala',
  'src/compose_bar.vala',
  'src/emoji.vala',
  'src/file_drop.vala',
  'src/conversation_view.vala',
  'src/full_message_dialog.vala',
  'src/chat_info_dialog.vala',
  'src/sticker_store.vala',
  'src/sticker_manager_dialog.vala',
  'src/sticker_picker.vala',
  'src/contact_picker_dialog.vala',
  'src/new_group_dialog.vala',
  'src/settings_dialog.vala',
  'src/tray_icon.vala',
  'src/storage_quota.vala',
  'src/profile_dialog.vala',
  'src/qr_code_view.vala',
  'src/pinned_messages_manager.vala',
  'src/quick_switch_dialog.vala',
  'src/event_handler.vala',
  'src/message_details_dialog.vala',
  'src/message_actions.vala',
  'src/account_creation.vala',
  'src/relay_picker.vala',
)

if host_machine.system() == 'darwin'
  add_languages('objc', native: false)
  sources += files('src/platform_macos.m')
  deps += dependency('appleframeworks', modules: ['Cocoa'])
endif

if host_machine.system() == 'windows'
  sources += files('src/platform_win32.c')
  deps += dependency('gio-windows-2.0')
  windows = import('windows')
  sources += windows.compile_resources(
    'data/parla.rc',
    depend_files: files('data/parla.ico'),
    include_directories: include_directories('data'),
  )
endif

executable('parla',
  sources, config_file, appdata_vala, resources,
  dependencies: deps,
  include_directories: src_inc,
  install: true,
  # GUI subsystem on Windows so no console window pops up; ignored elsewhere.
  win_subsystem: 'windows',
)

install_data(
  'data/io.github.trufae.Parla.desktop',
  install_dir: get_option('datadir') / 'applications',
)

install_data(
  'data/icons/hicolor/scalable/apps/io.github.trufae.Parla.svg',
  'data/icons/hicolor/scalable/apps/parla-welcome.svg',
  'data/icons/hicolor/scalable/apps/parla-tray.svg',
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps',
)

storage_quota_test = executable(
  'storage-quota-test',
  files('tests/storage_quota_test.vala', 'src/storage_quota.vala'),
  dependencies: [dependency('glib-2.0'), dependency('gobject-2.0')],
  install: false,
)

test('storage-quota', storage_quota_test)

markdown_test = executable(
  'markdown-test',
  files('tests/markdown_test.vala', 'src/markdown.vala'),
  dependencies: [dependency('glib-2.0'), dependency('pango')],
  install: false,
)

test('markdown', markdown_test)

mentions_test = executable(
  'mentions-test',
  files('tests/mentions_test.vala', 'src/mentions.vala', 'src/markdown.vala'),
  dependencies: [dependency('glib-2.0'), dependency('gobject-2.0'),
                 dependency('pango')],
  install: false,
)

test('mentions', mentions_test)

attachment_types_test = executable(
  'attachment-types-test',
  files('tests/attachment_types_test.vala', 'src/attachment_types.vala'),
  dependencies: [dependency('glib-2.0'), dependency('gobject-2.0')],
  install: false,
)

test('attachment-types', attachment_types_test)

message_history_test = executable(
  'message-history-test',
  files('tests/message_history_test.vala', 'src/message_history.vala'),
  dependencies: [dependency('glib-2.0'), dependency('gobject-2.0'),
                 dependency('json-glib-1.0')],
  install: false,
)

test('message-history', message_history_test)
