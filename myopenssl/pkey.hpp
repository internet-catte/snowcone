#pragma once

struct lua_State;

auto l_read_raw(lua_State * L) -> int;
auto l_read_pkey(lua_State * L) -> int;