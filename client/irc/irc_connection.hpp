#pragma once

#include <boost/asio.hpp>

extern "C" {
#include <lua.h>
#include <lauxlib.h>
}

#include <deque>
#include <functional>
#include <memory>
#include <optional>

#include "../net/stream.hpp"

struct lua_State;

class irc_connection final : public std::enable_shared_from_this<irc_connection>
{
    boost::asio::steady_timer write_timer;
    lua_State *L;
    int irc_cb_;
    std::deque<int> write_refs;
    std::deque<boost::asio::const_buffer> write_buffers;

public:
    using stream_type = CommonStream;

    stream_type stream_; // exposed for reading

    auto get_stream() -> stream_type&
    {
        return stream_;
    }

    irc_connection(boost::asio::io_context&, lua_State *L, int, stream_type&&);
    ~irc_connection();

    auto operator=(irc_connection const&) -> irc_connection& = delete;
    auto operator=(irc_connection &&) -> irc_connection& = delete;
    irc_connection(irc_connection const&) = delete;
    irc_connection(irc_connection &&) = delete;

    // Queue messages for writing
    auto write(std::string_view cmd, int const ref) -> void;

    auto close() -> void { stream_.close(); }

    static std::size_t const irc_buffer_size = 131'072;

    // There's data now, actually write it
    auto write_thread_actual() -> void
    {
        boost::asio::async_write(
            stream_,
            write_buffers,
            [weak = weak_from_this(), n = write_buffers.size()]
            (boost::system::error_code const& error, std::size_t)
            {
                if (not error)
                {
                    if (auto const self = weak.lock())
                    {
                        for (std::size_t i = 0; i < n; i++)
                        {
                            luaL_unref(self->L, LUA_REGISTRYINDEX, self->write_refs.front());
                            self->write_buffers.pop_front();
                            self->write_refs.pop_front();
                        }

                        self->write_thread();
                    }
                }
            });
    }

    // Either write data now or wait for there to be data
    auto write_thread() -> void
    {
        if (write_buffers.empty())
        {
            write_timer.async_wait(
                [weak = weak_from_this()](auto)
                {
                    if (auto const self = weak.lock())
                    {
                        if (not self->write_buffers.empty())
                        {
                            self->write_thread_actual();
                        }
                    }
                }
            );
        }
        else
        {
            write_thread_actual();
        }
    }
};

