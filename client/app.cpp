#include "app.hpp"

#include "applib.hpp"
#include "bracketed_paste.hpp"
#include "myncurses.h"
#include "safecall.hpp"

extern "C"
{
#include <lua.h>
#include <lauxlib.h>
}

#include <ncurses.h>

#include <iostream>
#include <unistd.h>

App::App()
    : io_context{}, stdin_poll{io_context, STDIN_FILENO}, winch{io_context, SIGWINCH}
{
    L = luaL_newstate();
    *reinterpret_cast<App **>(lua_getextraspace(L)) = this;
}

App::~App()
{
    lua_close(L);
}

auto App::from_lua(lua_State *const L) -> App *
{
    return *reinterpret_cast<App **>(lua_getextraspace(L));
}

auto App::do_mouse(int y, int x) -> void
{
    lua_pushinteger(L, y);
    lua_pushinteger(L, x);
    lua_callback(L, "on_mouse");
}

auto App::do_keyboard(long key) -> void
{
    lua_pushinteger(L, key);
    auto const success = lua_callback(L, "on_keyboard");
    // fallback ^C
    if (not success and key == 3)
    {
        raise(SIGINT);
    }
}

auto App::do_paste(std::string const& paste) -> void
{
    lua_pushlstring(L, paste.data(), paste.size());
    lua_callback(L, "on_paste");
}

auto App::winch_thread() -> boost::asio::awaitable<void>
{
    for (;;) {
        co_await winch.async_wait(boost::asio::use_awaitable);
        endwin();
        refresh();
        l_ncurses_resize(this->L);
        lua_callback(this->L, "on_resize");
    }
}

auto App::stdin_thread() -> boost::asio::awaitable<void>
{
    std::string paste;
    bool in_paste = false;
    mbstate_t mbstate{};

    for(;;) {
        co_await stdin_poll.async_wait(
            boost::asio::posix::stream_descriptor::wait_read,
            boost::asio::use_awaitable);

        for (int key; ERR != (key = getch());)
        {
            if (in_paste)
            {
                if (BracketedPaste::end_paste == key)
                {
                    do_paste(paste);
                    paste.clear();
                    in_paste = false;
                }
                else
                {
                    paste.push_back(key);
                }
            }
            else if (key == '\x1b')
            {
                key = getch();
                do_keyboard(ERR == key ? '\x1b' : -key);
            }
            else if (KEY_MOUSE == key)
            {
                MEVENT ev;
                getmouse(&ev);
                if (ev.bstate == BUTTON1_CLICKED)
                {
                    do_mouse(ev.y, ev.x);
                }
            }
            else if (BracketedPaste::start_paste == key)
            {
                in_paste = true;
            }
            else if (BracketedPaste::focus_gained == key)
            {
                do_keyboard(-KEY_RESUME);
            }
            else if (BracketedPaste::focus_lost == key)
            {
                do_keyboard(-KEY_EXIT);
            }
            else if (key > 0xff)
            {
                do_keyboard(-key);
            }
            else if (isascii(key))
            {
                do_keyboard(key);
            }
            else
            {
                char const c = key;
                wchar_t code;
                size_t const r = mbrtowc(&code, &c, 1, &mbstate);
                if (r < (size_t)-2)
                {
                    do_keyboard(code);
                }
            }
        }
    }
}

auto App::startup() -> void
{
    boost::asio::co_spawn(io_context, stdin_thread(), boost::asio::detached);
    boost::asio::co_spawn(io_context, winch_thread(), boost::asio::detached);
    io_context.run();
}

auto App::shutdown() -> void
{
    stdin_poll.close();
    winch.cancel();
}
