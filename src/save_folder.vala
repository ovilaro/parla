namespace Dc {

    /** Helpers for saving attachments into a user-chosen folder. */
    public class SaveFolder {

        /** folder/name, adding " (2)", " (3)", … before the extension when
            a file with that name already exists. Multi-part extensions use
            the last dot: "a.tar.gz" collides into "a.tar (2).gz". */
        public static File unique_destination (File folder, string name) {
            var dest = folder.get_child (name);
            if (!dest.query_exists ()) return dest;

            string stem = name;
            string ext = "";
            int dot = name.last_index_of_char ('.');
            if (dot > 0) {
                stem = name[0 : dot];
                ext = name[dot : name.length];
            }
            for (int i = 2; ; i++) {
                var candidate = folder.get_child (
                    "%s (%d)%s".printf (stem, i, ext));
                if (!candidate.query_exists ()) return candidate;
            }
        }
    }
}
