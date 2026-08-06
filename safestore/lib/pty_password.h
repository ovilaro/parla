#pragma once

#include <gio/gio.h>

gboolean safestore_run_pty_password (gchar **argv,
                                     const gchar *cwd,
                                     const gchar *password,
                                     gboolean confirm,
                                     gchar **output,
                                     GError **error);

int safestore_acquire_accounts_guard (const gchar *lock_path,
                                      GError **error);
void safestore_release_accounts_guard (int descriptor);
