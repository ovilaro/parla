#pragma once

#include <glib.h>

typedef struct _GtkWidget GtkWidget;

typedef void (*ParlaMacosFileDropCallback) (const gchar *path,
                                            gpointer     user_data);

gchar *parla_get_executable_path (void);
gboolean parla_platform_is_macos (void);
void parla_setup_macos_bundle_environment (void);
#if defined(__APPLE__) && defined(PARLA_MACOS_CLIPBOARD_WORKAROUND)
gchar *parla_macos_read_pasteboard_text (void);
#endif
void parla_macos_install_file_drop_handler (GtkWidget                  *widget,
                                            ParlaMacosFileDropCallback  callback,
                                            gpointer                    user_data);
