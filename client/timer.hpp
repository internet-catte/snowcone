#pragma once
/**
 * @file timer.hpp
 * @author Eric Mertens (emertens@gmail.com)
 * @brief Asyncronous timer objects
 *
 */

struct lua_State;

/**
 * @brief Construct a new timer
 *
 * Lua object methods:
 * * start(milliseconds, callback)
 * * cancel()
 *
 * @param L Lua state
 * @return 1
 */
auto l_new_timer(lua_State* L) -> int;
