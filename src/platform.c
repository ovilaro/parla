#include "platform.h"

#if defined(__APPLE__)
# include <mach-o/dyld.h>
# include <glib/gstdio.h>
# include <stdlib.h>
# include <string.h>
#elif defined(__linux__)
# include <limits.h>
# include <unistd.h>
#endif

gchar *
parla_get_executable_path (void)
{
#if defined(__APPLE__)
	char probe[1];
	uint32_t size = sizeof (probe);
	if (_NSGetExecutablePath (probe, &size) == 0) {
		return g_strdup (probe);
	}

	char *path = g_malloc0 (size + 1);
	if (_NSGetExecutablePath (path, &size) != 0) {
		g_free (path);
		return NULL;
	}

	char *resolved = realpath (path, NULL);
	if (resolved != NULL) {
		gchar *result = g_strdup (resolved);
		free (resolved);
		g_free (path);
		return result;
	}

	return path;
#elif defined(__linux__)
	char path[PATH_MAX + 1];
	ssize_t size = readlink ("/proc/self/exe", path, sizeof (path) - 1);
	if (size < 0) {
		return NULL;
	}
	path[size] = '\0';
	return g_strdup (path);
#else
	return NULL;
#endif
}

gboolean
parla_platform_is_macos (void)
{
#if defined(__APPLE__)
	return TRUE;
#else
	return FALSE;
#endif
}

#if defined(__APPLE__)
static void
prepend_env_path (const gchar *name, const gchar *path)
{
	const gchar *old_value = g_getenv (name);
	if (old_value && *old_value) {
		g_autofree gchar *value = g_strconcat (path, G_SEARCHPATH_SEPARATOR_S, old_value, NULL);
		g_setenv (name, value, TRUE);
	} else {
		g_setenv (name, path, TRUE);
	}
}

static gchar **
pixbuf_query_argv (const gchar *query_path, const gchar *loaders_dir)
{
	GDir *dir = g_dir_open (loaders_dir, 0, NULL);
	if (!dir) {
		return NULL;
	}

	GPtrArray *argv = g_ptr_array_new_with_free_func (g_free);
	guint loaders = 0;
	g_ptr_array_add (argv, g_strdup (query_path));

	const gchar *name;
	while ((name = g_dir_read_name (dir)) != NULL) {
		if (g_str_has_suffix (name, ".so")) {
			g_ptr_array_add (argv, g_build_filename (loaders_dir, name, NULL));
			loaders++;
		}
	}
	g_dir_close (dir);

	if (loaders == 0) {
		g_ptr_array_free (argv, TRUE);
		return NULL;
	}

	g_ptr_array_add (argv, NULL);
	return (gchar **) g_ptr_array_free (argv, FALSE);
}

static gboolean
cache_mentions_loader_dir (const gchar *cache_path, const gchar *loaders_dir)
{
	g_autofree gchar *contents = NULL;
	if (!g_file_get_contents (cache_path, &contents, NULL, NULL)) {
		return FALSE;
	}
	return strstr (contents, loaders_dir) != NULL;
}

static gchar *
macos_cache_root (void)
{
	const gchar *xdg_cache_home = g_getenv ("XDG_CACHE_HOME");
	if (xdg_cache_home && *xdg_cache_home) {
		return g_strdup (xdg_cache_home);
	}

	const gchar *home = g_get_home_dir ();
	if (home && *home) {
		return g_build_filename (home, "Library", "Caches", NULL);
	}

	return g_strdup (g_get_tmp_dir ());
}

static void
setup_pixbuf_cache (const gchar *resources_dir)
{
	g_autofree gchar *loaders_dir = g_build_filename (
		resources_dir, "lib", "gdk-pixbuf-2.0", "2.10.0", "loaders", NULL);
	g_autofree gchar *query_path = g_build_filename (
		resources_dir, "bin", "gdk-pixbuf-query-loaders", NULL);

	if (!g_file_test (loaders_dir, G_FILE_TEST_IS_DIR) ||
	    !g_file_test (query_path, G_FILE_TEST_IS_EXECUTABLE)) {
		return;
	}

	g_autofree gchar *cache_root = macos_cache_root ();
	g_autofree gchar *cache_dir = g_build_filename (cache_root, "Parla", NULL);
	g_autofree gchar *cache_path = g_build_filename (
		cache_dir, "gdk-pixbuf-loaders.cache", NULL);

	if (g_mkdir_with_parents (cache_dir, 0700) == 0 &&
	    !cache_mentions_loader_dir (cache_path, loaders_dir)) {
		g_auto(GStrv) argv = pixbuf_query_argv (query_path, loaders_dir);
		g_autofree gchar *stdout_data = NULL;
		gint wait_status = 0;

		if (argv &&
		    g_spawn_sync (NULL, argv, NULL, G_SPAWN_DEFAULT, NULL, NULL,
		                  &stdout_data, NULL, &wait_status, NULL) &&
		    wait_status == 0 &&
		    stdout_data != NULL) {
			g_file_set_contents (cache_path, stdout_data, -1, NULL);
		} else {
			g_unlink (cache_path);
		}
	}

	if (g_file_test (cache_path, G_FILE_TEST_EXISTS)) {
		g_setenv ("GDK_PIXBUF_MODULE_FILE", cache_path, TRUE);
	}
	g_setenv ("GDK_PIXBUF_MODULEDIR", loaders_dir, TRUE);
}
#endif

void
parla_setup_macos_bundle_environment (void)
{
#if defined(__APPLE__)
	g_autofree gchar *exe_path = parla_get_executable_path ();
	if (!exe_path) {
		return;
	}

	g_autofree gchar *macos_dir = g_path_get_dirname (exe_path);
	g_autofree gchar *macos_base = g_path_get_basename (macos_dir);
	if (g_strcmp0 (macos_base, "MacOS") != 0) {
		return;
	}

	g_autofree gchar *contents_dir = g_path_get_dirname (macos_dir);
	g_autofree gchar *contents_base = g_path_get_basename (contents_dir);
	if (g_strcmp0 (contents_base, "Contents") != 0) {
		return;
	}

	g_autofree gchar *resources_dir = g_build_filename (contents_dir, "Resources", NULL);
	if (!g_file_test (resources_dir, G_FILE_TEST_IS_DIR)) {
		return;
	}

	g_autofree gchar *share_dir = g_build_filename (resources_dir, "share", NULL);
	g_autofree gchar *schema_dir = g_build_filename (
		share_dir, "glib-2.0", "schemas", NULL);
	g_autofree gchar *gio_modules_dir = g_build_filename (
		resources_dir, "lib", "gio", "modules", NULL);

	prepend_env_path ("XDG_DATA_DIRS", share_dir);
	g_setenv ("GSETTINGS_SCHEMA_DIR", schema_dir, TRUE);
	g_setenv ("GTK_DATA_PREFIX", resources_dir, TRUE);
	g_setenv ("GTK_EXE_PREFIX", contents_dir, TRUE);
	g_setenv ("GTK_PATH", resources_dir, TRUE);
	g_setenv ("GIO_EXTRA_MODULES", gio_modules_dir, TRUE);
	setup_pixbuf_cache (resources_dir);
#endif
}

#if !defined(__APPLE__)
void
parla_macos_install_file_drop_handler (GtkWidget                  *widget,
                                       ParlaMacosFileDropCallback  callback,
                                       gpointer                    user_data)
{
	(void) widget;
	(void) callback;
	(void) user_data;
}
#endif
