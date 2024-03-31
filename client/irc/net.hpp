#pragma once

#include <boost/asio.hpp>
#include <boost/asio/ssl.hpp>

#include <socks5.hpp>

#include <cstdint>
#include <functional>
#include <iosfwd>
#include <span>
#include <string>

namespace
{
    auto close_stream(boost::asio::ip::tcp::socket &stream) -> void
    {
        boost::system::error_code err;
        stream.shutdown(stream.shutdown_both, err);
        stream.close(err);
    }

    template <typename T>
    auto close_stream(boost::asio::ssl::stream<T> &stream) -> void
    {
        close_stream(stream.next_layer());
    }
}

class AnyStream
{
protected:
    using Sig = void(boost::system::error_code, std::size_t);
    using handler_type = boost::asio::any_completion_handler<Sig>;
    using mutable_buffers = std::span<const boost::asio::mutable_buffer>;
    using const_buffers = std::span<const boost::asio::const_buffer>;

    virtual auto async_read_some_(mutable_buffers, handler_type) -> void = 0;
    virtual auto async_write_some_(const_buffers, handler_type) -> void = 0;

public:
    virtual ~AnyStream() {}

    // AsyncReadStream and AsyncWriteStream type requirement
    using executor_type = boost::asio::any_io_executor;
    virtual auto get_executor() noexcept -> executor_type = 0;

    // AsyncReadStream type requirement
    template <
        typename MutableBufferSequence,
        boost::asio::completion_token_for<Sig> Token>
    auto async_read_some(
        MutableBufferSequence &&buffers,
        Token &&token)
    {
        using namespace std::placeholders;
        return boost::asio::async_initiate<Token, Sig>(
            std::bind(&AnyStream::async_read_some_, _2, _3, _1),
            token,
            this,
            mutable_buffers{
                boost::asio::buffer_sequence_begin(buffers),
                boost::asio::buffer_sequence_end(buffers)});
    }

    // AsyncWriteStream type requirement
    template <
        typename ConstBufferSequence,
        boost::asio::completion_token_for<Sig> Token>
    auto async_write_some(
        ConstBufferSequence &&buffers,
        Token &&token)
    {
        using namespace std::placeholders;
        return boost::asio::async_initiate<Token, Sig>(
            std::bind(&AnyStream::async_write_some_, _2, _3, _1),
            token,
            this,
            const_buffers{
                boost::asio::buffer_sequence_begin(buffers),
                boost::asio::buffer_sequence_end(buffers)});
    }

    // Gracefully tear down the network stream
    virtual auto close() -> void = 0;
};

class TcpStream final : public AnyStream
{
    boost::asio::ip::tcp::socket stream_;

    auto async_read_some_(mutable_buffers, handler_type) -> void override;
    auto async_write_some_(const_buffers, handler_type) -> void override;

public:
    TcpStream(boost::asio::ip::tcp::socket &&stream)
        : stream_{std::move(stream)}
    {
    }

    auto get_executor() noexcept -> executor_type override
    {
        return stream_.get_executor();
    }

    auto close() -> void override
    {
        close_stream(stream_);
    }

    auto get_stream() -> boost::asio::ip::tcp::socket&
    {
        return stream_;
    }
};

template <typename S>
class TlsStream final : public AnyStream
{
    boost::asio::ssl::stream<S> stream_;

    auto async_read_some_(mutable_buffers buffers, handler_type handler) -> void override
    {
        stream_.async_read_some(buffers, std::move(handler));
    }

    auto async_write_some_(const_buffers buffers, handler_type handler) -> void override
    {
        stream_.async_write_some(buffers, std::move(handler));
    }

public:

    TlsStream(boost::asio::ssl::stream<S> &&stream)
        : stream_{std::move(stream)}
    {
    }

    auto get_executor() noexcept -> executor_type override
    {
        return stream_.get_executor();
    }

    auto close() -> void override
    {
        close_stream(stream_);
    }

    auto get_stream() -> boost::asio::ssl::stream<S>&
    {
        return stream_;
    }

    auto set_buffer_size(std::size_t const size) -> void
    {
        auto const ssl = stream_.native_handle();
        BIO_set_buffer_size(SSL_get_rbio(ssl), size);
        BIO_set_buffer_size(SSL_get_wbio(ssl), size);
    }
};

template <typename T>
concept Connectable = requires(T a, std::ostream& os, typename T::stream_type &stream) {
    // Check for the presence of a typedef named stream_type
    typename T::stream_type;

    // Check for the method with the correct signature
    {
        a.connect(os, stream)
    } -> std::same_as<boost::asio::awaitable<void>>;
};

struct TcpConnectParams
{
    using stream_type = boost::asio::ip::tcp::socket;

    std::string host;
    std::uint16_t port;

    std::string bind_host;
    std::uint16_t bind_port;

    auto connect(std::ostream& os, stream_type &stream) -> boost::asio::awaitable<void>;
};

template <Connectable T>
struct SocksConnectParams
{
    using stream_type = typename T::stream_type;

    std::string host;
    std::uint16_t port;
    socks5::Auth auth;
    T base;


    auto connect(std::ostream& os, stream_type &stream) -> boost::asio::awaitable<void>
    {
        co_await base.connect(os, stream);
        os << " socks=";
        os << co_await socks5::async_connect(stream, host, port, auth, boost::asio::use_awaitable);
    }
};

auto peer_fingerprint(std::ostream& os, SSL const* const ssl) -> void;

template <Connectable T>
struct TlsConnectParams
{
    using stream_type = boost::asio::ssl::stream<typename T::stream_type>;

    std::string verify;
    std::string sni;

    T base;

    auto connect(std::ostream& os, stream_type &stream) -> boost::asio::awaitable<void>
    {
        co_await base.connect(os, stream.next_layer());
        os << " tls=";

        // TLS connection
        if (not verify.empty())
        {
            stream.set_verify_mode(boost::asio::ssl::verify_peer);
            stream.set_verify_callback(boost::asio::ssl::host_name_verification(verify));
        }

        if (not sni.empty())
        {
            SSL_set_tlsext_host_name(stream.native_handle(), sni.c_str());
        }
        co_await stream.async_handshake(stream.client, boost::asio::use_awaitable);
        peer_fingerprint(os, stream.native_handle());
    }
};

static_assert(Connectable<TcpConnectParams>);
static_assert(Connectable<SocksConnectParams<TcpConnectParams>>);
static_assert(Connectable<TlsConnectParams<SocksConnectParams<TcpConnectParams>>>);
static_assert(Connectable<TlsConnectParams<TcpConnectParams>>);
