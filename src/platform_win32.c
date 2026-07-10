#include "platform.h"

#ifdef _WIN32

#include <windows.h>
#include <string.h>
#include <gio/gwin32inputstream.h>
#include <gio/gwin32outputstream.h>

/*
 * Append one argument to a CreateProcessW command line using the quoting
 * rules the Microsoft CRT argv parser expects (backslashes only act as
 * escapes in front of a double quote).
 */
static void
append_quoted (GString *line, const gchar *arg)
{
	if (line->len > 0) {
		g_string_append_c (line, ' ');
	}

	if (*arg != '\0' && strpbrk (arg, " \t\"") == NULL) {
		g_string_append (line, arg);
		return;
	}

	g_string_append_c (line, '"');
	for (const gchar *p = arg; *p != '\0'; p++) {
		guint backslashes = 0;
		while (*p == '\\') {
			backslashes++;
			p++;
		}
		if (*p == '\0') {
			for (guint i = 0; i < backslashes * 2; i++) {
				g_string_append_c (line, '\\');
			}
			break;
		}
		if (*p == '"') {
			backslashes = backslashes * 2 + 1;
		}
		for (guint i = 0; i < backslashes; i++) {
			g_string_append_c (line, '\\');
		}
		g_string_append_c (line, *p);
	}
	g_string_append_c (line, '"');
}

static void
set_win32_error (GError **error, const gchar *what)
{
	gchar *message = g_win32_error_message (GetLastError ());
	g_set_error (error, G_IO_ERROR, G_IO_ERROR_FAILED,
	             "%s: %s", what, message);
	g_free (message);
}

static void
close_handle_if_set (HANDLE *handle)
{
	if (*handle != NULL && *handle != INVALID_HANDLE_VALUE) {
		CloseHandle (*handle);
	}
	*handle = NULL;
}

gboolean
parla_win32_spawn (const gchar * const  *argv,
                   const gchar          *cwd,
                   const gchar          *env_name,
                   const gchar          *env_value,
                   gboolean              with_stdin,
                   void                **process_out,
                   GOutputStream       **stdin_out,
                   GInputStream        **stdout_out,
                   GInputStream        **stderr_out,
                   GError              **error)
{
	SECURITY_ATTRIBUTES sa = { sizeof (sa), NULL, TRUE };
	HANDLE in_read = NULL, in_write = NULL;
	HANDLE out_read = NULL, out_write = NULL;
	HANDLE err_read = NULL, err_write = NULL;
	gboolean ok = FALSE;

	*process_out = NULL;
	*stdin_out = NULL;
	*stdout_out = NULL;
	*stderr_out = NULL;

	/* Only the child ends of the pipes may be inherited, or the child
	   never sees EOF because we would hold its write ends open too. */
	if (!CreatePipe (&out_read, &out_write, &sa, 0) ||
	    !SetHandleInformation (out_read, HANDLE_FLAG_INHERIT, 0) ||
	    !CreatePipe (&err_read, &err_write, &sa, 0) ||
	    !SetHandleInformation (err_read, HANDLE_FLAG_INHERIT, 0)) {
		set_win32_error (error, "Could not create stdio pipes");
		goto out;
	}
	if (with_stdin) {
		if (!CreatePipe (&in_read, &in_write, &sa, 0) ||
		    !SetHandleInformation (in_write, HANDLE_FLAG_INHERIT, 0)) {
			set_win32_error (error, "Could not create stdin pipe");
			goto out;
		}
	} else {
		in_read = CreateFileW (L"NUL", GENERIC_READ, FILE_SHARE_READ,
		                       &sa, OPEN_EXISTING, 0, NULL);
		if (in_read == INVALID_HANDLE_VALUE) {
			in_read = NULL;
			set_win32_error (error, "Could not open NUL for stdin");
			goto out;
		}
	}

	GString *cmdline = g_string_new (NULL);
	for (const gchar * const *a = argv; *a != NULL; a++) {
		append_quoted (cmdline, *a);
	}

	wchar_t *wcmd = (wchar_t *) g_utf8_to_utf16 (cmdline->str, -1, NULL, NULL, error);
	g_string_free (cmdline, TRUE);
	wchar_t *wcwd = NULL;
	if (wcmd != NULL && cwd != NULL) {
		wcwd = (wchar_t *) g_utf8_to_utf16 (cwd, -1, NULL, NULL, error);
		if (wcwd == NULL) {
			g_free (wcmd);
			wcmd = NULL;
		}
	}
	if (wcmd == NULL) {
		goto out;
	}

	/* The child inherits our environment block; an extra variable is set
	   around CreateProcessW and restored right after, which is safe because
	   the child snapshots the environment at creation time. */
	gchar *saved_env = NULL;
	if (env_name != NULL) {
		saved_env = g_strdup (g_getenv (env_name));
		g_setenv (env_name, env_value != NULL ? env_value : "", TRUE);
	}

	STARTUPINFOW si;
	PROCESS_INFORMATION pi;
	memset (&si, 0, sizeof (si));
	memset (&pi, 0, sizeof (pi));
	si.cb = sizeof (si);
	si.dwFlags = STARTF_USESTDHANDLES;
	si.hStdInput = in_read;
	si.hStdOutput = out_write;
	si.hStdError = err_write;

	BOOL created = CreateProcessW (NULL, wcmd, NULL, NULL,
	                               TRUE /* inherit handles */,
	                               CREATE_NO_WINDOW | CREATE_UNICODE_ENVIRONMENT,
	                               NULL, wcwd, &si, &pi);

	if (env_name != NULL) {
		if (saved_env != NULL) {
			g_setenv (env_name, saved_env, TRUE);
		} else {
			g_unsetenv (env_name);
		}
		g_free (saved_env);
	}
	g_free (wcmd);
	g_free (wcwd);

	if (!created) {
		set_win32_error (error, "Could not start process");
		goto out;
	}

	CloseHandle (pi.hThread);
	*process_out = pi.hProcess;
	if (with_stdin) {
		*stdin_out = g_win32_output_stream_new (in_write, TRUE);
		in_write = NULL;
	}
	*stdout_out = g_win32_input_stream_new (out_read, TRUE);
	out_read = NULL;
	*stderr_out = g_win32_input_stream_new (err_read, TRUE);
	err_read = NULL;
	ok = TRUE;

out:
	/* Child-side ends always close in the parent; parent-side ends only
	   when they were not handed over to a stream above. */
	close_handle_if_set (&in_read);
	close_handle_if_set (&out_write);
	close_handle_if_set (&err_write);
	close_handle_if_set (&in_write);
	close_handle_if_set (&out_read);
	close_handle_if_set (&err_read);
	return ok;
}

gint
parla_win32_process_wait_sync (void *process, guint timeout_ms)
{
	DWORD code = 0;
	if (WaitForSingleObject ((HANDLE) process, timeout_ms) != WAIT_OBJECT_0) {
		return -1;
	}
	if (!GetExitCodeProcess ((HANDLE) process, &code)) {
		return -1;
	}
	return (gint) code;
}

void
parla_win32_process_terminate (void *process)
{
	TerminateProcess ((HANDLE) process, 1);
}

void
parla_win32_process_free (void *process)
{
	CloseHandle ((HANDLE) process);
}

#endif /* _WIN32 */
