namespace Dc.Platform {
    [CCode (cheader_filename = "platform.h", cname = "parla_get_executable_path")]
    private extern string? platform_get_executable_path ();

    public string? get_executable_path () {
        return platform_get_executable_path ();
    }

    public string? get_executable_dir () {
        string? exe_path = get_executable_path ();
        return exe_path != null ? Path.get_dirname (exe_path) : null;
    }
}
