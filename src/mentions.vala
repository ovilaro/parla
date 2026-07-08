namespace Dc {

    /**
     * A person that can be mentioned. Used both for the composer autocomplete
     * (members of the current chat) and for resolving mention tokens found in
     * message text (via the roster's address book).
     */
    public class MentionMember : Object {
        public string display_name { get; set; default = ""; }
        public string address { get; set; default = ""; }
        public int contact_id { get; set; default = 0; }
        /* True when this member is the local user (Delta Chat contact id 1). */
        public bool is_self { get; set; default = false; }
        public string? avatar_path { get; set; default = null; }

        public MentionMember (int contact_id, string display_name,
                              string address, bool is_self = false,
                              string? avatar_path = null) {
            this.contact_id = contact_id;
            this.display_name = display_name;
            this.address = address;
            this.is_self = is_self;
            this.avatar_path = avatar_path;
        }
    }

    /**
     * A single resolved mention token located inside message text.
     * Byte offsets index into the raw (unescaped) text.
     */
    public class MentionSpan : Object {
        public int start;      /* byte offset of the leading '@' */
        public int end;        /* byte offset just past the token */
        public string href;    /* "parla-mention:cid=N" or "parla-mention:addr=x" */
        public bool is_self;
        public string display;  /* text to show, without leading '@' */
    }

    /**
     * Mentions are a Parla-only convention layered on plain message text (Delta
     * Chat core has no mention feature). Two token forms are recognized, both
     * only at a word boundary (start of text or after whitespace):
     *
     *   @Display Name          — matched against the chat's member names
     *   @localpart@domain      — matched against known contact addresses
     *
     * A name may contain spaces, so name matching is a longest-prefix match
     * against the roster. Address matching resolves against every known contact
     * (the portable form other clients can resolve if they have the contact).
     * Unresolved tokens are left as plain text.
     */
    public class MentionRoster : Object {

        /* Members of the current chat, for the composer autocomplete. */
        public GenericArray<MentionMember> members =
            new GenericArray<MentionMember> ();

        /* address(down) -> member, for resolving address mentions. Covers the
           chat members plus the account-wide contact address book. */
        private HashTable<string, MentionMember> by_address =
            new HashTable<string, MentionMember> (str_hash, str_equal);

        /* Member display names sorted longest-first, for name matching. */
        private GenericArray<MentionMember>? name_sorted = null;

        /* Down-cased self identifiers (display name + own transport addresses)
           used to flag self-mentions. */
        private GenericArray<string> self_keys = new GenericArray<string> ();

        public void add_member (MentionMember m) {
            members.add (m);
            register_address (m);
            name_sorted = null;
        }

        /* Register an address without adding a composer-visible member. Used to
           feed the account-wide contact address book for resolution only. */
        public void register_address (MentionMember m) {
            if (m.address.length > 0) {
                by_address.insert (m.address.down (), m);
            }
        }

        public void add_self_key (string key) {
            string k = key.strip ().down ();
            if (k.length == 0) return;
            for (int i = 0; i < self_keys.length; i++) {
                if (self_keys[i] == k) return;
            }
            self_keys.add (k);
        }

        public bool has_members () {
            return members.length > 0;
        }

        public MentionMember? lookup_contact (int contact_id) {
            for (int i = 0; i < members.length; i++) {
                if (members[i].contact_id == contact_id) return members[i];
            }
            return null;
        }

        private bool key_is_self (string down_value) {
            for (int i = 0; i < self_keys.length; i++) {
                if (self_keys[i] == down_value) return true;
            }
            return false;
        }

        private GenericArray<MentionMember> names_longest_first () {
            if (name_sorted != null) return name_sorted;
            name_sorted = new GenericArray<MentionMember> ();
            for (int i = 0; i < members.length; i++) {
                if (members[i].display_name.strip ().length > 0) {
                    name_sorted.add (members[i]);
                }
            }
            name_sorted.sort ((a, b) => {
                return (int) b.display_name.length - (int) a.display_name.length;
            });
            return name_sorted;
        }

        /**
         * Try to resolve a mention starting at the '@' at byte offset `at` in
         * `raw`. Returns the span (with token length) or null if nothing
         * resolves. Assumes the caller already checked the word boundary before
         * the '@'.
         */
        public MentionSpan? resolve_at (string raw, int at) {
            /* rest = text right after the '@' */
            int after = at + 1;
            if (after > raw.length) return null;
            string rest = raw.substring (after);

            /* Prefer an address interpretation when the token looks like an
               email — that is the portable form. */
            var span = resolve_address (raw, at, rest);
            if (span != null) return span;
            return resolve_name (raw, at, rest);
        }

        private MentionSpan? resolve_address (string raw, int at, string rest) {
            /* Read localpart@domain: a run of address characters containing an
               '@'. Stop at whitespace; trim trailing punctuation. */
            int len = 0;
            bool seen_at = false;
            unichar c;
            int idx = 0;
            while (rest.get_next_char (ref idx, out c)) {
                if (c.isspace ()) break;
                if (c == '@') seen_at = true;
                len = idx;
            }
            if (!seen_at || len == 0) return null;

            string candidate = rest.substring (0, len);
            candidate = trim_trailing_punct (candidate);
            if (candidate.length == 0 || !candidate.contains ("@")) return null;

            var member = by_address.lookup (candidate.down ());
            if (member == null) return null;

            var span = new MentionSpan ();
            span.start = at;
            span.end = at + 1 + candidate.length;
            span.is_self = member.is_self || key_is_self (candidate.down ());
            span.display = member.display_name.length > 0
                ? member.display_name : candidate;
            span.href = "parla-mention:cid=%d".printf (member.contact_id);
            return span;
        }

        private MentionSpan? resolve_name (string raw, int at, string rest) {
            var candidates = names_longest_first ();
            string rest_down = rest.down ();
            for (int i = 0; i < candidates.length; i++) {
                string name = candidates[i].display_name;
                if (!rest_down.has_prefix (name.down ())) continue;
                /* The char right after the name must be a boundary so "@Ann"
                   does not match a member named "Anna" mid-name. */
                int name_len = name.length;
                if (!boundary_after (rest, name_len)) continue;

                var m = candidates[i];
                var span = new MentionSpan ();
                span.start = at;
                span.end = at + 1 + name_len;
                span.is_self = m.is_self || key_is_self (name.down ());
                span.display = m.display_name;
                span.href = "parla-mention:cid=%d".printf (m.contact_id);
                return span;
            }
            return null;
        }

        /* True when position `pos` (byte offset) in `s` ends the token: either
           end of string or a non-word character follows. */
        private static bool boundary_after (string s, int pos) {
            if (pos >= s.length) return true;
            unichar c;
            int idx = pos;
            if (!s.get_next_char (ref idx, out c)) return true;
            return !(c.isalnum () || c == '_');
        }

        private static string trim_trailing_punct (string s) {
            string result = s;
            while (result.length > 0) {
                char last = result[result.length - 1];
                if (last == '.' || last == ',' || last == ';' || last == ':'
                    || last == '!' || last == '?' || last == ')' || last == ']'
                    || last == '}' || last == '"' || last == '\'' || last == '>') {
                    result = result.substring (0, result.length - 1);
                } else {
                    break;
                }
            }
            return result;
        }
    }

    public class Mentions {

        /* Delimiter wrapped around a mention placeholder while the text passes
           through Markdown.format. U+FFFC (OBJECT REPLACEMENT CHARACTER), here
           as its UTF-8 bytes, is chosen because Markup.escape_text passes it
           through verbatim (unlike control chars, which it turns into numeric
           entities) and no markdown rule treats it specially. */
        private const string SENTINEL = "\xEF\xBF\xBC";

        /**
         * Locate every resolvable mention in `raw`, in order. Only tokens that
         * begin at the start of the text or right after whitespace are
         * considered.
         */
        public static GenericArray<MentionSpan> find_mentions (string raw,
                                                               MentionRoster roster) {
            var spans = new GenericArray<MentionSpan> ();
            int i = 0;
            unichar c;
            bool prev_is_boundary = true; /* start of text is a boundary */

            while (true) {
                int at = i;
                if (!raw.get_next_char (ref i, out c)) break;

                if (c == '@' && prev_is_boundary) {
                    var span = roster.resolve_at (raw, at);
                    if (span != null) {
                        spans.add (span);
                        /* Continue scanning after the token. */
                        i = span.end;
                        prev_is_boundary = false;
                        continue;
                    }
                }
                prev_is_boundary = c.isspace ();
            }
            return spans;
        }

        /**
         * Render message body text to Pango markup with mentions turned into
         * clickable links. Mentions are protected with markdown-inert sentinels
         * so the existing Markdown.format pipeline (escaping, bold/italic,
         * tables, URL linkify) never touches them, then substituted back in.
         */
        public static string render_markup (string raw, MentionRoster? roster) {
            if (roster == null) return Markdown.format (raw);

            var spans = find_mentions (raw, roster);
            if (spans.length == 0) return Markdown.format (raw);

            var protected_text = new StringBuilder ();
            var anchors = new GenericArray<string> ();
            int cursor = 0;
            for (int s = 0; s < spans.length; s++) {
                var span = spans[s];
                if (span.start > cursor) {
                    protected_text.append (raw.substring (cursor, span.start - cursor));
                }
                int idx = anchors.length;
                anchors.add (anchor_markup (span));
                protected_text.append (SENTINEL);
                protected_text.append (idx.to_string ());
                protected_text.append (SENTINEL);
                cursor = span.end;
            }
            if (cursor < raw.length) {
                protected_text.append (raw.substring (cursor));
            }

            string markup = Markdown.format (protected_text.str);
            for (int a = 0; a < anchors.length; a++) {
                markup = markup.replace (
                    SENTINEL + a.to_string () + SENTINEL, anchors[a]);
            }
            return markup;
        }

        private static string anchor_markup (MentionSpan span) {
            string href = Markup.escape_text (span.href);
            string label = Markup.escape_text ("@" + span.display);
            if (span.is_self) {
                return ("<a href=\"%s\"><span background=\"#f9c440\" " +
                        "foreground=\"#000000\"><b>%s</b></span></a>")
                    .printf (href, label);
            }
            return "<a href=\"%s\"><b>%s</b></a>".printf (href, label);
        }

        /**
         * True when `text` mentions the local user. `self_keys` are down-cased
         * identifiers (display name and/or transport addresses). Independent of
         * a roster so it can run on notifications for any account.
         */
        public static bool mentions_self (string? text, string[] self_keys) {
            if (text == null || text.length == 0 || self_keys.length == 0)
                return false;

            int i = 0;
            unichar c;
            bool prev_is_boundary = true;
            while (true) {
                int at = i;
                if (!text.get_next_char (ref i, out c)) break;
                if (c == '@' && prev_is_boundary) {
                    if (matches_self_key_at (text, at + 1, self_keys)) return true;
                }
                prev_is_boundary = c.isspace ();
            }
            return false;
        }

        private static bool matches_self_key_at (string text, int after,
                                                 string[] self_keys) {
            if (after > text.length) return false;
            string rest = text.substring (after).down ();
            foreach (string key in self_keys) {
                if (key.length == 0) continue;
                if (!rest.has_prefix (key)) continue;
                int end = key.length;
                if (end >= rest.length) return true;
                unichar c;
                int idx = end;
                if (!rest.get_next_char (ref idx, out c)) return true;
                /* Addresses end at whitespace; names end at a non-word char. */
                if (key.contains ("@")) {
                    if (c.isspace () || is_addr_terminator (c)) return true;
                } else if (!(c.isalnum () || c == '_')) {
                    return true;
                }
            }
            return false;
        }

        private static bool is_addr_terminator (unichar c) {
            return c == ',' || c == ';' || c == ':' || c == '!' || c == '?'
                || c == ')' || c == ']' || c == '}' || c == '"' || c == '\'';
        }
    }
}
