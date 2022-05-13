/**
 * @file applib.hpp
 * @author Eric Mertens (emertens@gmail.com)
 * @brief Application Lua environment primitives and setup
 * 
 */

#pragma once

struct ircmsg;
struct configuration;

extern "C" {
#include "lua.h"
}

void load_logic(lua_State* L, char const* filename);
void lua_callback(lua_State* L, char const* key);
void pushircmsg(lua_State* L, ircmsg const& msg);
void prepare_globals(lua_State* L, configuration* cfg);