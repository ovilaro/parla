using Dc;

int failures = 0;

void check (bool cond, string what) {
    if (!cond) {
        stderr.printf ("FAIL: %s\n", what);
        failures++;
    }
}

void touch (string dir, string name) {
    try {
        FileUtils.set_contents (Path.build_filename (dir, name), "x");
    } catch (Error e) {
        stderr.printf ("setup failed: %s\n", e.message);
        failures++;
    }
}

int main () {
    string tmpl = Path.build_filename (Environment.get_tmp_dir (),
                                       "parla-save-XXXXXX");
    string? dir = DirUtils.mkdtemp (tmpl);
    if (dir == null) {
        stderr.printf ("mkdtemp failed\n");
        return 1;
    }
    var folder = File.new_for_path (dir);

    check (SaveFolder.unique_destination (folder, "photo.jpg")
           .get_basename () == "photo.jpg", "fresh name is unchanged");

    touch (dir, "photo.jpg");
    check (SaveFolder.unique_destination (folder, "photo.jpg")
           .get_basename () == "photo (2).jpg", "first collision gets (2)");

    touch (dir, "photo (2).jpg");
    check (SaveFolder.unique_destination (folder, "photo.jpg")
           .get_basename () == "photo (3).jpg", "second collision gets (3)");

    touch (dir, "notes");
    check (SaveFolder.unique_destination (folder, "notes")
           .get_basename () == "notes (2)", "extensionless appends (2)");

    touch (dir, "archive.tar.gz");
    check (SaveFolder.unique_destination (folder, "archive.tar.gz")
           .get_basename () == "archive.tar (2).gz",
           "multi-part extension splits at last dot");

    touch (dir, ".bashrc");
    check (SaveFolder.unique_destination (folder, ".bashrc")
           .get_basename () == ".bashrc (2)",
           "leading-dot name treated as extensionless");

    /* best-effort cleanup */
    try {
        var en = folder.enumerate_children ("standard::name", 0, null);
        FileInfo? info;
        while ((info = en.next_file (null)) != null) {
            folder.get_child (info.get_name ()).delete (null);
        }
        folder.delete (null);
    } catch (Error e) { /* leave temp dir behind */ }

    return failures == 0 ? 0 : 1;
}
