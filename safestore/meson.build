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

core_deps = [
  dependency('glib-2.0'),
  dependency('gio-2.0'),
]

if host_machine.system() != 'windows'
  util_dep = cc.find_library('util', required: false)
  if util_dep.found()
    core_deps += util_dep
  endif
endif

# The Secret Service keyring backend; macOS uses /usr/bin/security instead
# and Windows has no keyring backend yet.
if host_machine.system() != 'darwin' and host_machine.system() != 'windows'
  secret_dep = dependency('libsecret-1', required: false)
  if secret_dep.found()
    add_project_arguments('--define=HAVE_LIBSECRET', language: 'vala')
    core_deps += secret_dep
  endif
endif

core_sources = files(
  'lib/accounts_path.vala',
  'lib/path_policy.vala',
  'lib/settings.vala',
  'lib/backend.vala',
  'lib/zip_backend.vala',
  'lib/plaintext_eraser.vala',
  'lib/mount_check.vala',
  'lib/vault.vala',
  'lib/keyring.vala',
  'lib/cryfs_controller.vala',
)
core_sources += files('lib/pty_password.c')

core_lib = static_library(
  'safestore-core',
  core_sources,
  dependencies: core_deps,
)

core_dep = declare_dependency(
  link_with: core_lib,
  dependencies: core_deps,
)

executable(
  'safestore',
  files('cli/main.vala'),
  dependencies: core_dep,
  install: true,
)

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

executable(
  'safestore-gui',
  files('gui/main.vala', 'gui/window.vala'),
  dependencies: [core_dep, dependency('gtk4'), adwaita_dep],
  install: true,
  win_subsystem: 'windows',
)

install_data(
  'data/io.github.trufae.SafeStore.desktop',
  install_dir: get_option('datadir') / 'applications',
)

path_policy_test = executable(
  'path-policy-test',
  files('tests/path_policy_test.vala'),
  dependencies: core_dep,
  install: false,
)

test('path-policy', path_policy_test)

accounts_path_test = executable(
  'accounts-path-test',
  files('tests/accounts_path_test.vala'),
  dependencies: core_dep,
  install: false,
)

test('accounts-path', accounts_path_test)

backend_test = executable(
  'backend-test',
  files('tests/backend_test.vala'),
  dependencies: core_dep,
  install: false,
)

test('backends', backend_test)
