#include "buffer.h"

#include <string.h>
#include <stdlib.h>

void buffer_close(uv_buf_t const *buf)
{
    free(buf->base);
}

void buffer_init(uv_buf_t *buf, size_t n)
{
    buf->base = calloc(n, 1);
    buf->len = n;
}

void append_buffer(uv_buf_t *dst, ssize_t n, uv_buf_t const *src)
{
    if (dst->base == NULL)
    {
        buffer_init(dst, 512);
    }

    if (!src->base)
        return;

    size_t dlen = strlen(dst->base);
    size_t len = dlen + n;

    if (len >= dst->len)
    {
        while (len >= dst->len)
        {
            dst->len *= 2;
        }
        dst->base = realloc(dst->base, dst->len);
    }

    memcpy(dst->base + dlen, src->base, n);
    dst->base[len] = '\0';

    buffer_close(src);
}