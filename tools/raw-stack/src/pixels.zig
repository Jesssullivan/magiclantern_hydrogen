//! 14-bit packed bayer pixel codec, matching `struct raw_pixblock` in
//! `src/raw.h`. 8 pixels per 14 bytes, GCC ARM bitfield order
//! (LSB-first within u32 words).
//!
//! Wire layout for one 14-byte block, viewed as u32/u16 LE words:
//!
//!   word0 = bytes[0..4]:
//!     bits 0..1   = b_hi (2)
//!     bits 2..15  = a    (14, pixel 0)
//!     bits 16..19 = c_hi (4)
//!     bits 20..31 = b_lo (12)
//!   word1 = bytes[4..8]:
//!     bits 0..5   = d_hi (6)
//!     bits 6..15  = c_lo (10)
//!     bits 16..23 = e_hi (8)
//!     bits 24..31 = d_lo (8)
//!   word2 = bytes[8..12]:
//!     bits 0..9   = f_hi (10)
//!     bits 10..15 = e_lo (6)
//!     bits 16..27 = g_hi (12)
//!     bits 28..31 = f_lo (4)
//!   word3 = bytes[12..14] (u16):
//!     bits 0..13  = h    (14, pixel 7)
//!     bits 14..15 = g_lo (2)
//!
//! Pixels:
//!   pixel 0 = a
//!   pixel 1 = b = b_lo | (b_hi << 12)
//!   pixel 2 = c = c_lo | (c_hi << 10)
//!   pixel 3 = d = d_lo | (d_hi << 8)
//!   pixel 4 = e = e_lo | (e_hi << 6)
//!   pixel 5 = f = f_lo | (f_hi << 4)
//!   pixel 6 = g = g_lo | (g_hi << 2)
//!   pixel 7 = h
//!
//! Pixels are u14 (0..16383). Pack/unpack are bit-exact inverses.

const std = @import("std");

pub const PIXELS_PER_BLOCK: usize = 8;
pub const BYTES_PER_BLOCK: usize = 14;
pub const MAX_PIXEL_VALUE: u16 = 0x3FFF; // 14-bit

/// Unpack one 14-byte block into 8 pixels.
pub fn unpackBlock(bytes: *const [BYTES_PER_BLOCK]u8) [PIXELS_PER_BLOCK]u16 {
    const w0: u32 = std.mem.readInt(u32, bytes[0..4], .little);
    const w1: u32 = std.mem.readInt(u32, bytes[4..8], .little);
    const w2: u32 = std.mem.readInt(u32, bytes[8..12], .little);
    const w3: u16 = std.mem.readInt(u16, bytes[12..14], .little);

    const b_hi: u16 = @intCast(w0 & 0x3);
    const a: u16 = @intCast((w0 >> 2) & 0x3FFF);
    const c_hi: u16 = @intCast((w0 >> 16) & 0xF);
    const b_lo: u16 = @intCast((w0 >> 20) & 0xFFF);

    const d_hi: u16 = @intCast(w1 & 0x3F);
    const c_lo: u16 = @intCast((w1 >> 6) & 0x3FF);
    const e_hi: u16 = @intCast((w1 >> 16) & 0xFF);
    const d_lo: u16 = @intCast((w1 >> 24) & 0xFF);

    const f_hi: u16 = @intCast(w2 & 0x3FF);
    const e_lo: u16 = @intCast((w2 >> 10) & 0x3F);
    const g_hi: u16 = @intCast((w2 >> 16) & 0xFFF);
    const f_lo: u16 = @intCast((w2 >> 28) & 0xF);

    const h: u16 = @intCast(w3 & 0x3FFF);
    const g_lo: u16 = @intCast((w3 >> 14) & 0x3);

    return .{
        a,
        b_lo | (b_hi << 12),
        c_lo | (c_hi << 10),
        d_lo | (d_hi << 8),
        e_lo | (e_hi << 6),
        f_lo | (f_hi << 4),
        g_lo | (g_hi << 2),
        h,
    };
}

/// Pack 8 pixels into a 14-byte block. Inverse of unpackBlock.
/// Pixels above MAX_PIXEL_VALUE are truncated to 14 bits.
pub fn packBlock(pixels: *const [PIXELS_PER_BLOCK]u16) [BYTES_PER_BLOCK]u8 {
    const a: u32 = pixels[0] & MAX_PIXEL_VALUE;
    const b: u32 = pixels[1] & MAX_PIXEL_VALUE;
    const c: u32 = pixels[2] & MAX_PIXEL_VALUE;
    const d: u32 = pixels[3] & MAX_PIXEL_VALUE;
    const e: u32 = pixels[4] & MAX_PIXEL_VALUE;
    const f: u32 = pixels[5] & MAX_PIXEL_VALUE;
    const g: u32 = pixels[6] & MAX_PIXEL_VALUE;
    const h: u32 = pixels[7] & MAX_PIXEL_VALUE;

    const b_hi: u32 = (b >> 12) & 0x3;
    const b_lo: u32 = b & 0xFFF;
    const c_hi: u32 = (c >> 10) & 0xF;
    const c_lo: u32 = c & 0x3FF;
    const d_hi: u32 = (d >> 8) & 0x3F;
    const d_lo: u32 = d & 0xFF;
    const e_hi: u32 = (e >> 6) & 0xFF;
    const e_lo: u32 = e & 0x3F;
    const f_hi: u32 = (f >> 4) & 0x3FF;
    const f_lo: u32 = f & 0xF;
    const g_hi: u32 = (g >> 2) & 0xFFF;
    const g_lo: u32 = g & 0x3;

    const w0: u32 = b_hi | (a << 2) | (c_hi << 16) | (b_lo << 20);
    const w1: u32 = d_hi | (c_lo << 6) | (e_hi << 16) | (d_lo << 24);
    const w2: u32 = f_hi | (e_lo << 10) | (g_hi << 16) | (f_lo << 28);
    const w3: u16 = @intCast(h | (g_lo << 14));

    var out: [BYTES_PER_BLOCK]u8 = undefined;
    std.mem.writeInt(u32, out[0..4], w0, .little);
    std.mem.writeInt(u32, out[4..8], w1, .little);
    std.mem.writeInt(u32, out[8..12], w2, .little);
    std.mem.writeInt(u16, out[12..14], w3, .little);
    return out;
}

/// Unpack a contiguous buffer of 14-bit packed pixels. The buffer
/// length must be a multiple of BYTES_PER_BLOCK; the output length is
/// `(buf.len / 14) * 8`.
pub fn unpackBuffer(allocator: std.mem.Allocator, buf: []const u8) ![]u16 {
    if (buf.len % BYTES_PER_BLOCK != 0) return error.UnalignedBuffer;
    const block_count = buf.len / BYTES_PER_BLOCK;
    var out = try allocator.alloc(u16, block_count * PIXELS_PER_BLOCK);
    errdefer allocator.free(out);
    var i: usize = 0;
    while (i < block_count) : (i += 1) {
        const src = buf[i * BYTES_PER_BLOCK ..][0..BYTES_PER_BLOCK];
        const pixels = unpackBlock(src);
        @memcpy(out[i * PIXELS_PER_BLOCK ..][0..PIXELS_PER_BLOCK], &pixels);
    }
    return out;
}

test "round-trip — every multiple of 1023" {
    var pixels: [PIXELS_PER_BLOCK]u16 = .{ 0, 1023, 2047, 4095, 8191, 12287, 16383, 100 };
    const bytes = packBlock(&pixels);
    const round = unpackBlock(&bytes);
    for (pixels, round) |orig, got| {
        try std.testing.expectEqual(orig, got);
    }
}

test "round-trip — adversarial bit patterns" {
    const cases = [_][PIXELS_PER_BLOCK]u16{
        .{ 0, 0, 0, 0, 0, 0, 0, 0 },
        .{ 0x3FFF, 0x3FFF, 0x3FFF, 0x3FFF, 0x3FFF, 0x3FFF, 0x3FFF, 0x3FFF },
        .{ 0x2AAA, 0x1555, 0x2AAA, 0x1555, 0x2AAA, 0x1555, 0x2AAA, 0x1555 },
        .{ 0x3FFF, 0x0001, 0x3FFE, 0x0002, 0x3FFC, 0x0004, 0x3FF8, 0x0008 },
    };
    for (cases) |pixels| {
        const bytes = packBlock(&pixels);
        const round = unpackBlock(&bytes);
        for (pixels, round) |orig, got| {
            try std.testing.expectEqual(orig, got);
        }
    }
}

test "unpackBuffer rejects unaligned length" {
    var buf: [13]u8 = undefined;
    try std.testing.expectError(error.UnalignedBuffer, unpackBuffer(std.testing.allocator, &buf));
}

test "unpackBuffer over two blocks" {
    var pixels: [16]u16 = undefined;
    for (&pixels, 0..) |*p, i| p.* = @intCast((i * 1009) & MAX_PIXEL_VALUE);

    var buf: [BYTES_PER_BLOCK * 2]u8 = undefined;
    const blk0 = packBlock(pixels[0..8]);
    const blk1 = packBlock(pixels[8..16]);
    @memcpy(buf[0..BYTES_PER_BLOCK], &blk0);
    @memcpy(buf[BYTES_PER_BLOCK..][0..BYTES_PER_BLOCK], &blk1);

    const unpacked = try unpackBuffer(std.testing.allocator, &buf);
    defer std.testing.allocator.free(unpacked);
    try std.testing.expectEqual(@as(usize, 16), unpacked.len);
    for (pixels, unpacked) |orig, got| {
        try std.testing.expectEqual(orig, got);
    }
}
