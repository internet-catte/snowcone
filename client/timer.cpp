#include "timer.hpp"

#include "app.hpp"
#include "safecall.hpp"
#include "userdata.hpp"
#include "uv.hpp"

extern "C" {
#include <lua.h>
#include <lauxlib.h>
}

#include <boost/asio/steady_timer.hpp>
#include <chrono>

template<> char const* udata_name<boost::asio::steady_timer> = "steady_timer";

namespace {
luaL_Reg const MT[] = {
    {"close", [](auto const L) {
        auto const timer = check_udata<boost::asio::steady_timer>(L, 1);
        lua_pushnil(L);
        lua_rawsetp(L, LUA_REGISTRYINDEX, timer);
        timer->~basic_waitable_timer();
        return 0;
    }},

    {"start", [](auto const L) {
        auto const timer = check_udata<boost::asio::steady_timer>(L, 1);
        auto const start = luaL_checkinteger(L, 2);
        luaL_checkany(L, 3);
        lua_settop(L, 3);

        // store the callback function
        lua_setuservalue(L, 1);

        timer->expires_after(std::chrono::milliseconds{start});
        timer->async_wait([L, timer](auto const error) {
            if (!error) {
                lua_rawgetp(L, LUA_REGISTRYINDEX, timer);
                lua_getuservalue(L, -1);
                lua_insert(L, -2);
                safecall(L, "timer", 1);
            }});

        return 0;
    }},

    {"stop", [](auto const L) {
        auto const timer = check_udata<boost::asio::steady_timer>(L, 1);
        timer->cancel();
        // forget the current callback.
        lua_pushnil(L);
        lua_setuservalue(L, -2);

        return 0;
    }},

    {}
};
}

void push_new_timer(lua_State *L)
{
    auto const timer = new_udata<boost::asio::steady_timer>(L, [L](){
        // Build metatable the first time
        luaL_setfuncs(L, MT, 0);
        lua_pushvalue(L, -1);
        lua_setfield(L, -2, "__index");
    });
    new (timer) boost::asio::steady_timer {App::from_lua(L)->io_context};

    // Keep the timer alive until it is closed in uv
    lua_pushvalue(L, -1);
    lua_rawsetp(L, LUA_REGISTRYINDEX, timer);
}