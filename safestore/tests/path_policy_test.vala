private void test_sibling_layout () {
    try {
        SafeStore.PathPolicy.validate_layout (
            "/tmp/safestore-vault",
            "/tmp/safestore-mount"
        );
    } catch (Error error) {
        Test.fail_printf ("Sibling layout should be valid: %s", error.message);
    }
}

private void test_same_layout () {
    assert_layout_fails ("/tmp/safestore", "/tmp/safestore");
}

private void test_mount_inside_vault () {
    assert_layout_fails (
        "/tmp/safestore",
        "/tmp/safestore/plain"
    );
}

private void test_vault_inside_mount () {
    assert_layout_fails (
        "/tmp/safestore/plain/vault",
        "/tmp/safestore/plain"
    );
}

private void test_relative_layout () {
    assert_layout_fails ("vault", "mount");
}

#if !WINDOWS
private void test_symlinked_nested_layout () {
    string? root = null;
    try {
        root = DirUtils.make_tmp ("safestore-path-policy-XXXXXX");
        string vault = Path.build_filename (root, "vault");
        string alias = Path.build_filename (root, "vault-alias");
        assert_true (DirUtils.create (vault, 0700) == 0);
        assert_true (Posix.symlink (vault, alias) == 0);
        assert_layout_fails (
            vault,
            Path.build_filename (alias, "mount")
        );
        assert_true (FileUtils.unlink (alias) == 0);
        assert_true (DirUtils.remove (vault) == 0);
        assert_true (DirUtils.remove (root) == 0);
    } catch (Error error) {
        Test.fail_printf ("Could not prepare symlink test: %s", error.message);
    }
}
#endif

private void assert_layout_fails (string vault, string mount) {
    bool failed = false;
    try {
        SafeStore.PathPolicy.validate_layout (vault, mount);
    } catch (Error error) {
        failed = true;
    }
    assert_true (failed);
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/path-policy/siblings", test_sibling_layout);
    Test.add_func ("/path-policy/same", test_same_layout);
    Test.add_func ("/path-policy/mount-inside-vault", test_mount_inside_vault);
    Test.add_func ("/path-policy/vault-inside-mount", test_vault_inside_mount);
    Test.add_func ("/path-policy/relative", test_relative_layout);
#if !WINDOWS
    Test.add_func (
        "/path-policy/symlinked-nesting",
        test_symlinked_nested_layout
    );
#endif
    return Test.run ();
}
