/*
 * codecomment.vala
 *
 * Copyright 2021 Nicola Tudino
 *
 * This file is part of xed-codecomment-plugin.
 *
 * xed-codecomment-plugin is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, version 3 of the License.
 *
 * xed-codecomment-plugin is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with xed-codecomment-plugin.  If not, see <http://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */


namespace CodeCommentPlugin {


    /*
    * Register plugin extension types
    */
    [CCode (cname="G_MODULE_EXPORT peas_register_types")]
    [ModuleInit]
    public void peas_register_types (TypeModule module) 
    {
        var objmodule = module as Peas.ObjectModule;

        // Register my plugin extension
        objmodule.register_extension_type (typeof (Xed.AppActivatable), typeof (CodeCommentPlugin.CodeCommentApp));
        objmodule.register_extension_type (typeof (Xed.WindowActivatable), typeof (CodeCommentPlugin.CodeCommentWindow));
        objmodule.register_extension_type (typeof (Xed.ViewActivatable), typeof (CodeCommentPlugin.CodeCommentView));
        // Register my config dialog
        objmodule.register_extension_type (typeof (PeasGtk.Configurable), typeof (CodeCommentPlugin.ConfigCodeComment));
    }

    private CodeCommentView code_comment_view;
    
    /*
    * AppActivatable
    */
    public class CodeCommentApp : Xed.AppActivatable, Peas.ExtensionBase {

        public CodeCommentApp () {
            GLib.Object ();
        }

        public Xed.App app {
            owned get; construct;
        }

        public void activate () {
            // print ("CodeCommentApp activated\n");
            app.set_accels_for_action ("win.comment", {"<Primary>M"});
            app.set_accels_for_action ("win.uncomment", {"<Primary><Shift>M"});
        }

        public void deactivate () {
            // print ("CodeCommentApp deactivated\n");
            app.set_accels_for_action ("win.comment", {});
            app.set_accels_for_action ("win.uncomment", {});
        }
    }
    
    /*
    * WindowActivatable
    */
    public class CodeCommentWindow : Xed.WindowActivatable, Peas.ExtensionBase {

        public CodeCommentWindow () {
            GLib.Object ();
        }

        public Xed.Window window {
            owned get; construct;
        }

        public void activate () {
            // print ("CodeCommentWindow activated\n");
            SimpleAction action_comment = new SimpleAction ("comment", null);
            action_comment.activate.connect (this.do_comment);
            window.add_action (action_comment);

            SimpleAction action_uncomment = new SimpleAction ("uncomment", null);
            action_uncomment.activate.connect (this.do_uncomment);
            window.add_action (action_uncomment);
        }

        public void deactivate () {
            // print ("CodeCommentWindow deactivated\n");
            window.remove_action ("comment");
            window.remove_action ("uncomment");
        }

        public void update_state () {
            // print ("CodeCommentWindow update_state\n");
            bool sensitive = false;
            var view = window.get_active_view();
            if (view != null && code_comment_view != null) {
                sensitive = code_comment_view.doc_has_comment_tags ();
                code_comment_view.set_document ((Xed.Document) view.get_buffer ());
            }

            var comment_action = (SimpleAction) window.lookup_action ("comment");
            comment_action.set_enabled (sensitive);
            var uncomment_action = (SimpleAction) window.lookup_action ("uncomment");
            uncomment_action.set_enabled (sensitive);
        }
        
        public void do_comment () {
            var view = window.get_active_view ();
            if (view != null && code_comment_view != null) {
                code_comment_view.set_document ((Xed.Document) view.get_buffer ());
                code_comment_view.do_comment_indent ();
            }
        }

        public void do_uncomment () {
            var view = window.get_active_view ();
            if (view != null && code_comment_view != null) {
                code_comment_view.set_document ((Xed.Document) view.get_buffer ());
                code_comment_view.do_comment_unindent ();
            }
        }
    }
    
    /*
    * ViewActivatable
    */
    public class CodeCommentView : Xed.ViewActivatable, Peas.ExtensionBase {

        // If the language is listed here we prefer block comments over line comments.
        // Maybe this list should be user configurable, but just C comes to my mind...
        string[] block_comment_languages;
        // private const string[] block_comment_languages = {
        //    "c", "chdr"
        // };

        private ulong popup_handler_id;
        private bool unindent = false;
        private const string[] empty = {"", ""};
        private Xed.Document doc;

        public CodeCommentView () {
            popup_handler_id = 0;
            GLib.Object ();
        }

        public Xed.View view {
            owned get; construct;
        }

        public void activate () {
            // print ("CodeCommentView activated\n");
            //get settings from compiled schema
            GLib.Settings settings = new GLib.Settings ("com.github.tudo75.xed-codecomment-plugin");
            string[] tmp_block_comment_languages = settings.get_string ("block-comments-languages").split (",");
            foreach (var item in tmp_block_comment_languages)
                item = item.strip ();
            block_comment_languages = tmp_block_comment_languages;

            
            code_comment_view = this;
            doc = (Xed.Document) view.get_buffer ();
            popup_handler_id = (ulong) this.view.populate_popup.connect (this.populate_popup);
        }

        public void deactivate () {
            // print ("CodeCommentView deactivated\n");
            if (popup_handler_id != 0) {
                this.view.disconnect (popup_handler_id);
                popup_handler_id = 0;
            }
            code_comment_view = null;
        }
        
        private void populate_popup (Gtk.Menu popup) {
            var item = new Gtk.SeparatorMenuItem ();
            item.show ();
            popup.append (item);

            var comment_item = new Gtk.MenuItem.with_mnemonic (_("Co_mment Code"));
            comment_item.set_sensitive (this.doc_has_comment_tags ());
            comment_item.show ();
            comment_item.activate.connect (this.do_comment_indent);
            popup.append(comment_item);

            var uncomment_item = new Gtk.MenuItem.with_mnemonic (_("U_ncomment Code"));
            uncomment_item.set_sensitive (this.doc_has_comment_tags ());
            uncomment_item.show ();
            uncomment_item.activate.connect (this.do_comment_unindent);
            popup.append (uncomment_item);

        }

        public bool doc_has_comment_tags () {
            bool has_comment_tags = false;
            var doc = (Xed.Document) view.get_buffer ();
            if (doc != null) {
                Gtk.SourceLanguage lang = doc.get_language ();
                if (lang != null) {
                    has_comment_tags = this.get_comment_tags (lang) != empty;
                }
            }
            return has_comment_tags;
        }

        public string[] get_block_comment_tags (Gtk.SourceLanguage lang) {
            string start_tag = lang.get_metadata ("block-comment-start");
            string end_tag = lang.get_metadata ("block-comment-end");
            if (start_tag != null && end_tag != null) {
                return {start_tag, end_tag};
            }
            return empty;
        }

        public string[] get_line_comment_tags (Gtk.SourceLanguage lang) {
            string start_tag = lang.get_metadata ("line-comment-start");
            if (start_tag != null) {
                return {start_tag, ""};
            }
            return empty;
        }

        public string[] get_comment_tags (Gtk.SourceLanguage lang) {
            bool get_block = false;
            string[] tags = empty;
            foreach (var item in block_comment_languages) {
                if (item == lang.get_id ())
                    get_block = true;
            }
            if (get_block) {
                tags = this.get_block_comment_tags (lang);
                if (tags == empty) {
                    tags = get_line_comment_tags (lang);
                }
            } else {
                tags = get_line_comment_tags (lang);
                if (tags == empty) {
                    tags = this.get_block_comment_tags (lang);
                }
            }
            return tags;
        }

        private bool  get_tag_position_in_line (string tag, Gtk.TextIter head_iter, Gtk.TextIter iter) {
            bool found = false;
            while (! found && ! iter.ends_line ()) {
                string s = iter.get_slice (head_iter);
                if (s == tag) 
                    found = true;
                else
                    head_iter.forward_char ();
                    iter.forward_char ();
            }
            return found;
        }

        private Gtk.TextMark get_tag_mark (Xed.Document document, string tag, Gtk.TextIter head_iter, Gtk.TextIter iter) {
            bool found = false;
            Gtk.TextMark fmark = null;
            while (! found && ! iter.ends_line ()) {
                string s = iter.get_slice (head_iter);
                if (s == tag) {
                    found = true;
                    fmark = document.create_mark ("found", iter, false);
                } else {
                    head_iter.forward_char ();
                    iter.forward_char ();
                }
            }
            return fmark;
        }

        private void add_comment_characters (Xed.Document document, string start_tag, string end_tag, Gtk.TextIter start, Gtk.TextIter end) {
            Gtk.TextMark smark = document.create_mark ("start", start, false);
            Gtk.TextMark imark = document.create_mark ("iter", start, false);
            Gtk.TextMark emark = document.create_mark ("end", end, false);
            int number_lines = end.get_line () - start.get_line ();

            document.begin_user_action ();
  
            for (int i = 0; i <= number_lines; i++) {
                Gtk.TextIter iter;
                document.get_iter_at_mark (out iter, imark);
                if (! iter.ends_line ()) {
                    document.insert (ref iter, start_tag, start_tag.length);
                    if (end_tag != "" && end_tag != null) {
                        if (i <= number_lines - 1) {
                            document.get_iter_at_mark (out iter, imark);
                            iter.forward_to_line_end ();
                            document.insert (ref iter, end_tag, end_tag.length);
                        } else {
                            document.get_iter_at_mark (out iter, emark);
                            document.insert (ref iter, end_tag, end_tag.length);
                        }
                    }
                }
                document.get_iter_at_mark (out iter, imark);
                iter.forward_line ();
                document.delete_mark (imark);
                imark = document.create_mark ("iter", iter, false);
            }

            document.end_user_action ();

            document.delete_mark (imark);
            Gtk.TextIter new_start, new_end;
            document.get_iter_at_mark (out new_start, smark);
            document.get_iter_at_mark (out new_end, emark);
            if (! new_start.ends_line ()) {
                new_start.backward_chars (start_tag.length);
            }
            document.select_range (new_start, new_end);
            document.delete_mark (smark);
            document.delete_mark (emark);
        }

        private void remove_comment_characters (Xed.Document document, string start_tag, string end_tag, Gtk.TextIter start, Gtk.TextIter end) {
            Gtk.TextMark smark = document.create_mark ("start", start, false);
            Gtk.TextMark emark = document.create_mark ("end", end, false);
            int number_lines = end.get_line () - start.get_line ();
            Gtk.TextIter iter = start.copy ();
            Gtk.TextIter head_iter = iter.copy ();
            head_iter.forward_chars (start_tag.length);

            document.begin_user_action ();

            for (int i = 0; i <= number_lines; i++) {
                if (this.get_tag_position_in_line (start_tag, head_iter, iter)) {
                    Gtk.TextMark dmark = document.create_mark ("delete", iter, false);
                    document.delete (ref iter, ref head_iter);
                    if (end_tag != "" && end_tag != null) {
                        document.get_iter_at_mark (out iter, dmark);
                        head_iter = iter.copy ();
                        head_iter.forward_chars (end_tag.length);
                        if (this.get_tag_position_in_line (end_tag, head_iter, iter)) {
                            Gtk.TextMark end_tag_mark =  this.get_tag_mark (document, end_tag, head_iter, iter);
                            if (end_tag_mark != null) {
                                document.get_iter_at_mark (out iter, end_tag_mark);
                                head_iter = iter.copy ();
                                head_iter.forward_chars (end_tag.length);
                                document.delete (ref iter, ref head_iter);
                            }
                            document.delete_mark (end_tag_mark);
                        }
                    }
                    document.delete_mark (dmark);
                }
                document.get_iter_at_mark (out iter, smark);
                iter.forward_line ();
                document.delete_mark (smark);
                head_iter = iter.copy ();
                head_iter.forward_chars (start_tag.length);
                smark = document.create_mark ("iter", iter, false);
            }
            
            document.end_user_action();

            document.delete_mark(smark);
            document.delete_mark(emark);
        }

        public void set_document (Xed.Document document) {
            doc = document;
        }

        public void do_comment_indent () {
            unindent = false;
            this.do_comment ();
        }

        public void do_comment_unindent () {
            unindent = true;
            this.do_comment ();
        }

        public void do_comment () {
            // print ("CodeCommentView.do_comment unindent :" + unindent.to_string () + "\n");
            Xed.Document document;
            if ( doc != null) {
                document = doc;
            } else {
                document = (Xed.Document) view.get_buffer ();
            }

            Gtk.TextMark current_pos_mark = document.get_insert ();
            bool deselect = false;
            Gtk.TextIter start, end;
            var sel = document.get_selection_bounds (out start, out end);
            if (sel) {
                if (start.ends_line ())
                    start.forward_line ();
                else if (! start.starts_line ())
                    start.set_line_offset (0);
                if (end.starts_line ())
                    end.backward_char ();
                else if (! end.ends_line ())
                    end.forward_to_line_end ();
            } else {
                deselect = true;
                document.get_iter_at_mark (out start, current_pos_mark);
                start.set_line_offset (0);
                end = start.copy ();
                end.forward_to_line_end ();
            }
            Gtk.SourceLanguage lang = document.get_language ();
            if (lang == null)
                return;

            string[] tags = this.get_comment_tags (lang);
            if (tags[0] == "" && tags[1] == "")
                return;
                
            if (unindent) {
                // remove comment
                this.remove_comment_characters (document, tags[0], tags[1], start, end);
            } else {
                // add comment
                this.add_comment_characters (document, tags[0], tags[1], start, end);
            }

            if (deselect) {
                Gtk.TextIter old_pos_iter;
                document.get_iter_at_mark (out old_pos_iter, current_pos_mark);
                document.select_range (old_pos_iter, old_pos_iter);
                document.place_cursor (old_pos_iter); 
            }
            doc = null;
        }
    }

    /*
    * Plugin config dialog
    */
    public class ConfigCodeComment : Peas.ExtensionBase, PeasGtk.Configurable
    {
        public ConfigCodeComment () 
        {
            GLib.Object ();
        }

        public Gtk.Widget create_configure_widget () 
        {
            //get settings from compiled schema
            GLib.Settings settings = new GLib.Settings ("com.github.tudo75.xed-codecomment-plugin");

            var label = new Gtk.Label ("");
            label.set_markup (_("<big>Xed CodeComment Plugin Settings</big>"));
            label.set_margin_top (10);
            label.set_margin_bottom (15);
            label.set_margin_start (10);
            label.set_margin_end (10);

            var entry_label = new Gtk.Label ("");
            entry_label.set_markup (_("Programming languages which prefer block comments over line comments <b>(comma separated values)</b>."));
            entry_label.set_halign (Gtk.Align.START);
            Gtk.Entry entry = new Gtk.Entry ();
            settings.bind ("block-comments-languages", entry, "text", GLib.SettingsBindFlags.DEFAULT | GLib.SettingsBindFlags.GET_NO_CHANGES);

            Gtk.Label instructions_title =  new Gtk.Label ("");
            instructions_title.set_markup (_("<b>Instructions</b>:"));
            instructions_title.set_halign (Gtk.Align.START);
            instructions_title.set_margin_top (10);
            Gtk.Label instructions_text = new Gtk.Label ("");
            instructions_text.set_markup (_("Use <i>Ctrl+M</i> to comment and <i>Ctrl+Shift+M</i> to uncomment, or the commands from the context menu."));
            instructions_text.set_halign (Gtk.Align.START);

            Gtk.Grid main_grid = new Gtk.Grid ();
            main_grid.set_valign (Gtk.Align.START);
            main_grid.set_margin_top (10);
            main_grid.set_margin_bottom (10);
            main_grid.set_margin_start (10);
            main_grid.set_margin_end (10);
            main_grid.set_column_homogeneous (false);
            main_grid.set_row_homogeneous (false);
            main_grid.set_vexpand (true);
            main_grid.attach (label, 0, 0, 1, 1);
            main_grid.attach (entry_label, 0, 1, 1, 1);
            main_grid.attach (entry, 0, 2, 1, 1);
            main_grid.attach (instructions_title, 0, 3, 1, 1);
            main_grid.attach (instructions_text, 0, 4, 1, 1);

            return main_grid;
        }
    }
}
