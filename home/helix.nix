{...}: {
  # Helix — themed to Doom Vibrant, with an hlissner/Doom-Emacs-flavoured
  # Space leader. Helix's built-in Space menu is already Doom-like (Space f =
  # files, Space b = buffers, Space / = global search, Space s = symbols), so we
  # keep those and add the window (Space w) and buffer (Space b*) chords Doom
  # users reach for, plus a few quality-of-life normal-mode maps.
  programs.helix = {
    enable = true;
    defaultEditor = false;

    settings = {
      theme = "doom_vibrant";

      editor = {
        line-number = "absolute"; # Doom shows absolute numbers, not relative
        cursorline = true;
        color-modes = true;
        bufferline = "multiple";
        true-color = true;
        scrolloff = 6;
        rulers = [80 120];
        cursor-shape = {
          normal = "block";
          insert = "bar";
          select = "underline";
        };
        indent-guides = {
          render = true;
          character = "▏";
        };
        lsp.display-inlay-hints = true;
        statusline = {
          left = ["mode" "spinner" "file-name" "file-modification-indicator"];
          right = ["diagnostics" "selections" "position" "file-encoding" "file-type"];
        };
      };

      keys.normal = {
        # Doom SPC w — window management (Helix calls these Ctrl-w by default)
        space.w = {
          v = "vsplit";
          s = "hsplit";
          h = "jump_view_left";
          j = "jump_view_down";
          k = "jump_view_up";
          l = "jump_view_right";
          q = "wclose";
          o = "wonly";
          w = "rotate_view";
        };
        # Doom SPC b — buffers
        space.b = {
          b = "buffer_picker";
          d = ":buffer-close";
          n = "goto_next_buffer";
          p = "goto_previous_buffer";
        };
        # Doom SPC c — code
        space.c = {
          a = "code_action";
          r = "rename_symbol";
          f = ":format";
          d = "goto_definition";
          D = "goto_declaration";
          i = "goto_implementation";
        };
        # Doom-style: gd/gr already default; add K hover is default.
        # Quick window nav without the leader (vim-ish)
        "C-h" = "jump_view_left";
        "C-j" = "jump_view_down";
        "C-k" = "jump_view_up";
        "C-l" = "jump_view_right";
      };

      keys.insert = {
        "j" = {k = "normal_mode";}; # jk to escape, Doom/evil habit
      };
    };

    # Doom Vibrant colour scheme.
    themes.doom_vibrant = let
      bg = "#242730";
      base = "#1c1f24";
      fg = "#bbc2cf";
      blue = "#51afef";
      green = "#7bc275";
      yellow = "#fcce7b";
      red = "#ff665c";
      magenta = "#c57bdb";
      cyan = "#5cefff";
      grey = "#62686e";
      border = "#484854";
    in {
      "ui.background" = {bg = base;};
      "ui.text" = fg;
      "ui.text.focus" = {
        fg = fg;
        modifiers = ["bold"];
      };
      "ui.cursor" = {
        fg = base;
        bg = blue;
      };
      "ui.cursor.primary" = {
        fg = base;
        bg = blue;
      };
      "ui.cursor.match" = {
        fg = yellow;
        modifiers = ["bold"];
      };
      "ui.cursorline.primary" = {bg = bg;};
      "ui.linenr" = grey;
      "ui.linenr.selected" = {
        fg = fg;
        modifiers = ["bold"];
      };
      "ui.statusline" = {
        fg = fg;
        bg = bg;
      };
      "ui.statusline.inactive" = {
        fg = grey;
        bg = base;
      };
      "ui.statusline.normal" = {
        fg = base;
        bg = blue;
        modifiers = ["bold"];
      };
      "ui.statusline.insert" = {
        fg = base;
        bg = green;
        modifiers = ["bold"];
      };
      "ui.statusline.select" = {
        fg = base;
        bg = magenta;
        modifiers = ["bold"];
      };
      "ui.popup" = {
        fg = fg;
        bg = bg;
      };
      "ui.window" = border;
      "ui.help" = {
        fg = fg;
        bg = bg;
      };
      "ui.menu" = {
        fg = fg;
        bg = bg;
      };
      "ui.menu.selected" = {
        fg = base;
        bg = blue;
      };
      "ui.virtual.ruler" = {bg = bg;};
      "ui.virtual.whitespace" = grey;
      "ui.virtual.indent-guide" = border;
      "ui.virtual.inlay-hint" = grey;
      "ui.selection" = {bg = border;};
      "ui.selection.primary" = {bg = "#2f3a4d";};

      "comment" = {
        fg = grey;
        modifiers = ["italic"];
      };
      "keyword" = {
        fg = blue;
        modifiers = ["bold"];
      };
      "keyword.control" = {fg = magenta;};
      "function" = green;
      "function.macro" = cyan;
      "type" = yellow;
      "constant" = magenta;
      "constant.numeric" = magenta;
      "constant.builtin" = magenta;
      "string" = green;
      "variable" = fg;
      "variable.builtin" = red;
      "variable.parameter" = fg;
      "label" = cyan;
      "namespace" = yellow;
      "operator" = cyan;
      "punctuation" = fg;
      "constructor" = yellow;
      "tag" = red;
      "attribute" = yellow;

      "diagnostic.error" = {
        underline = {
          color = red;
          style = "curl";
        };
      };
      "diagnostic.warning" = {
        underline = {
          color = yellow;
          style = "curl";
        };
      };
      "diagnostic.info" = {
        underline = {
          color = blue;
          style = "curl";
        };
      };
      "diagnostic.hint" = {
        underline = {
          color = cyan;
          style = "curl";
        };
      };
      "error" = red;
      "warning" = yellow;
      "info" = blue;
      "hint" = cyan;

      "diff.plus" = green;
      "diff.delta" = yellow;
      "diff.minus" = red;

      "markup.heading" = {
        fg = blue;
        modifiers = ["bold"];
      };
      "markup.list" = red;
      "markup.bold" = {modifiers = ["bold"];};
      "markup.italic" = {modifiers = ["italic"];};
      "markup.link.url" = {
        fg = cyan;
        underline = {style = "line";};
      };
      "markup.link.text" = magenta;
      "markup.raw" = green;
    };
  };
}
