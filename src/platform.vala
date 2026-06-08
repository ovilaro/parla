namespace Dc.Platform {
    [CCode (cheader_filename = "platform.h", cname = "parla_get_executable_path")]
    private extern string? platform_get_executable_path ();

    [CCode (cheader_filename = "platform.h", cname = "parla_platform_is_macos")]
    private extern bool platform_is_macos ();

    [CCode (cheader_filename = "platform.h", cname = "parla_setup_macos_bundle_environment")]
    private extern void platform_setup_macos_bundle_environment ();

    public string? get_executable_path () {
        return platform_get_executable_path ();
    }

    public string? get_executable_dir () {
        string? exe_path = get_executable_path ();
        return exe_path != null ? Path.get_dirname (exe_path) : null;
    }

    public bool is_macos () {
        return platform_is_macos ();
    }

    public void setup_macos_bundle_environment () {
        platform_setup_macos_bundle_environment ();
    }

    public Gdk.ModifierType primary_modifier_mask () {
        return is_macos () ? Gdk.ModifierType.META_MASK
                           : Gdk.ModifierType.CONTROL_MASK;
    }

    public bool has_primary_modifier (Gdk.ModifierType state) {
        return (state & primary_modifier_mask ()) != 0;
    }

    public string primary_accelerator_prefix () {
        return is_macos () ? "<Meta>" : "<Control>";
    }

    public string primary_shortcut_text (string key) {
        return "%s+%s".printf (is_macos () ? "Command" : "Ctrl", key);
    }
}
