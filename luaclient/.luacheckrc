return {
ignore = { "212/self" },
std = "lua53+main+snowcone",
stds = {
    snowcone = {
        read_globals = {
            snowcone = {
              fields = {"to_base64", "from_base64", "dnslookup", "pton", "shutdown", "newtimer",
                "setmodule", "raise", "xor_strings", "isalnum", "irccase", "parse_irc_tags",
                "SIGINT", "SIGTSTP", "connect" },
            },
        },
    },
    main = {
        read_globals = {"tty_height", "tty_width", "mygeoip", "ncurses", "mystringprep", "hsfilter"},
        globals = {
            -- general functionality
            "require_", "next_view", "prev_view", "irc_handlers",
            "quit", "send_irc", "exiting", "disconnect",
            "reset_filter", "initialize", "counter_sync_commands",
            "ctrl", "meta", "status", "plugins", "draw_suspend",
            "prepare_kline", "tick_timer", "reconnect_timer", "configuration",

            -- global client state
            "irc_state", "status_message", "input_mode", "talk_target",
            "view", "views", "uptime", "liveness", "scroll", "editor",
            "uv_resources", "filter", "main_views", "buffers",
            "focus", "status_messages", "commands", "config_dir",

            -- IRC console view
            "messages",

            -- Rendering
            "add_click", "add_button", "draw_global_load", "draw",

            -- ncurses helpers
            "addstr", "mvaddstr",
            "bold", "bold_", "underline", "underline_", "normal", "reversevideo", "reversevideo_",
            "red", "green", "cyan", "black", "yellow", "magenta", "white", "blue", "italic", "italic_"
            },
        },
    },
}