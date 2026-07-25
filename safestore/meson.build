project(
  'safestore',
  'vala',
  version: '0.1.0',
  meson_version: '>= 0.59.0',
)

if host_machine.system() == 'windows'
  add_project_arguments('--define=WINDOWS', language: 'vala')
elif host_machine.system() == 'darwin'
  add_project_arguments(
    ['--define=DARWIN', '--pkg', 'posix'],
    language: 'vala',
  )
else
  add_project_arguments(
    ['--define=LINUX', '--pkg', 'posix'],
    language: 'vala',
  )
endif

adwaita_dep = dependency('libadwaita-1', version: '>= 1.5')
if host_machine.system() == 'darwin'
  # Homebrew installs the VAPI beside the keg instead of in valac's
  # versioned default search directory.
  adwaita_prefix = adwaita_dep.get_variable(pkgconfig: 'prefix')
  add_project_arguments(
    '--vapidir=' + adwaita_prefix / 'share' / 'vala' / 'vapi',
    language: 'vala',
  )
endif

deps = [
  dependency('glib-2.0'),
  dependency('gio-2.0'),
  dependency('gtk4'),
  adwaita_dep,
]

# These warnings come from valac-generated C rather than the Vala source.
cc = meson.get_compiler('c')
add_project_arguments(
  cc.get_supported_arguments([
    '-Wno-unused-but-set-variable',
    '-Wno-unused-function',
    '-Wno-unused-value',
    '-Wno-unused-variable',
  ]),
  language: 'c',
)

safestore_sources = files(
  'src/main.vala',
  'src/settings.vala',
  'src/path_policy.vala',
  'src/cryfs_controller.vala',
  'src/window.vala',
)

executable(
  'safestore',
  safestore_sources,
  dependencies: deps,
  install: true,
  win_subsystem: 'windows',
)

install_data(
  'data/io.github.trufae.SafeStore.desktop',
  install_dir: get_option('datadir') / 'applications',
)

path_policy_test = executable(
  'path-policy-test',
  files('tests/path_policy_test.vala', 'src/path_policy.vala'),
  dependencies: [
    dependency('glib-2.0'),
    dependency('gio-2.0'),
  ],
  install: false,
)

test('path-policy', path_policy_test)
