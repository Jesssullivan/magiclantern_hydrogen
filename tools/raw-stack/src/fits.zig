//! Minimal FITS image writer.
//!
//! Produces a single-HDU FITS file with BITPIX=16 (signed 16-bit
//! integer, **big-endian** per the FITS standard) and NAXIS=2. ML's
//! raw bayer values are 14-bit (0..16383) so they fit in int16 without
//! BZERO offset.
//!
//! Output structure:
//!   - Header: 2880-byte block, 80-char lines, ASCII, terminated by END.
//!   - Data: width * height int16 big-endian, padded to next 2880-byte
//!     boundary with zeros.
//!
//! Keywords emitted: SIMPLE, BITPIX, NAXIS, NAXIS1, NAXIS2, BZERO,
//! BSCALE, OBJECT, ORIGIN, COMMENT, END.
//!
//! For higher-bit-depth, channel splitting, or multi-extension HDUs,
//! extend in a follow-up. See https://fits.gsfc.nasa.gov/fits_standard.html.

const std = @import("std");

pub const BLOCK_SIZE: usize = 2880;
pub const LINE_SIZE: usize = 80;

pub const Options = struct {
    width: i32,
    height: i32,
    /// Optional OBJECT keyword (max 70 chars after quote framing).
    object: ?[]const u8 = null,
    /// Optional ORIGIN keyword.
    origin: ?[]const u8 = "magiclantern_hydrogen tools/raw-stack",
    /// Optional COMMENT lines.
    comments: []const []const u8 = &[_][]const u8{},
};

pub fn writeImage(writer: anytype, pixels: []const u16, opts: Options) !void {
    if (opts.width <= 0 or opts.height <= 0) return error.InvalidDimensions;
    const total_pixels = @as(usize, @intCast(opts.width)) * @as(usize, @intCast(opts.height));
    if (pixels.len != total_pixels) return error.PixelCountMismatch;

    // ---- Header ----
    var hdr_buf: [BLOCK_SIZE]u8 = [_]u8{' '} ** BLOCK_SIZE;
    var line_idx: usize = 0;

    try writeKeyword(&hdr_buf, &line_idx, "SIMPLE", "T", "conforms to FITS standard");
    try writeKeyword(&hdr_buf, &line_idx, "BITPIX", "16", "16-bit signed integer pixels");
    try writeKeyword(&hdr_buf, &line_idx, "NAXIS", "2", "two-dimensional image");
    try writeKeywordNumber(&hdr_buf, &line_idx, "NAXIS1", opts.width, "width");
    try writeKeywordNumber(&hdr_buf, &line_idx, "NAXIS2", opts.height, "height");
    try writeKeyword(&hdr_buf, &line_idx, "BZERO", "0", "physical = BSCALE*array + BZERO");
    try writeKeyword(&hdr_buf, &line_idx, "BSCALE", "1", "unscaled");

    if (opts.object) |o| try writeStringKeyword(&hdr_buf, &line_idx, "OBJECT", o);
    if (opts.origin) |o| try writeStringKeyword(&hdr_buf, &line_idx, "ORIGIN", o);

    for (opts.comments) |c| try writeCommentLine(&hdr_buf, &line_idx, c);

    try writeEnd(&hdr_buf, &line_idx);

    try writer.writeAll(&hdr_buf);

    // ---- Data (int16 big-endian) ----
    var bytes_written: usize = 0;
    for (pixels) |p| {
        // 14-bit values map directly to signed int16 since 16383 < 32767.
        const v: i16 = @intCast(p);
        try writer.writeInt(i16, v, .big);
        bytes_written += 2;
    }

    // Pad data to next BLOCK_SIZE boundary.
    const data_pad: usize = (BLOCK_SIZE - (bytes_written % BLOCK_SIZE)) % BLOCK_SIZE;
    if (data_pad > 0) {
        var z: [BLOCK_SIZE]u8 = [_]u8{0} ** BLOCK_SIZE;
        try writer.writeAll(z[0..data_pad]);
    }
}

fn lineSlice(buf: *[BLOCK_SIZE]u8, idx: usize) ![]u8 {
    const start = idx * LINE_SIZE;
    if (start + LINE_SIZE > BLOCK_SIZE) return error.HeaderFull;
    return buf[start .. start + LINE_SIZE];
}

fn writeKeyword(
    buf: *[BLOCK_SIZE]u8,
    idx: *usize,
    keyword: []const u8,
    value: []const u8,
    comment: []const u8,
) !void {
    const line = try lineSlice(buf, idx.*);
    @memset(line, ' ');
    // FITS keyword: 8-char left-justified.
    const key_end = @min(keyword.len, 8);
    @memcpy(line[0..key_end], keyword[0..key_end]);
    line[8] = '=';
    // Right-justify value to col 30 (FITS convention for numeric/logical).
    const val_dst_start = 30 - @min(value.len, 20);
    const val_dst_end = val_dst_start + value.len;
    @memcpy(line[val_dst_start..val_dst_end], value);
    // Comment after value, starting at col 32 with " / ".
    if (comment.len > 0 and val_dst_end + 4 <= LINE_SIZE) {
        const com_start = val_dst_end + 1;
        const sep = " / ";
        @memcpy(line[com_start..][0..sep.len], sep);
        const com_dst = com_start + sep.len;
        const com_len = @min(comment.len, LINE_SIZE - com_dst);
        @memcpy(line[com_dst..][0..com_len], comment[0..com_len]);
    }
    idx.* += 1;
}

fn writeKeywordNumber(
    buf: *[BLOCK_SIZE]u8,
    idx: *usize,
    keyword: []const u8,
    value: i32,
    comment: []const u8,
) !void {
    var num_buf: [16]u8 = undefined;
    const num_str = try std.fmt.bufPrint(&num_buf, "{d}", .{value});
    try writeKeyword(buf, idx, keyword, num_str, comment);
}

fn writeStringKeyword(
    buf: *[BLOCK_SIZE]u8,
    idx: *usize,
    keyword: []const u8,
    value: []const u8,
) !void {
    const line = try lineSlice(buf, idx.*);
    @memset(line, ' ');
    const key_end = @min(keyword.len, 8);
    @memcpy(line[0..key_end], keyword[0..key_end]);
    line[8] = '=';
    line[9] = ' ';
    line[10] = '\'';
    const max_str = LINE_SIZE - 12;
    const v_len = @min(value.len, max_str);
    @memcpy(line[11..][0..v_len], value[0..v_len]);
    line[11 + v_len] = '\'';
    idx.* += 1;
}

fn writeCommentLine(buf: *[BLOCK_SIZE]u8, idx: *usize, text: []const u8) !void {
    const line = try lineSlice(buf, idx.*);
    @memset(line, ' ');
    const kw = "COMMENT ";
    @memcpy(line[0..kw.len], kw);
    const max_t = LINE_SIZE - kw.len;
    const t_len = @min(text.len, max_t);
    @memcpy(line[kw.len..][0..t_len], text[0..t_len]);
    idx.* += 1;
}

fn writeEnd(buf: *[BLOCK_SIZE]u8, idx: *usize) !void {
    const line = try lineSlice(buf, idx.*);
    @memset(line, ' ');
    const kw = "END";
    @memcpy(line[0..kw.len], kw);
    idx.* += 1;
}

test "FITS header SIMPLE+BITPIX+NAXIS appear" {
    var sink = std.ArrayList(u8).init(std.testing.allocator);
    defer sink.deinit();

    var pixels: [4]u16 = .{ 100, 200, 16383, 0 };
    try writeImage(sink.writer(), &pixels, .{ .width = 2, .height = 2 });

    try std.testing.expect(sink.items.len % BLOCK_SIZE == 0);
    try std.testing.expectEqualStrings("SIMPLE  =", sink.items[0..9]);
    try std.testing.expect(std.mem.indexOf(u8, sink.items[0..BLOCK_SIZE], "BITPIX") != null);
    try std.testing.expect(std.mem.indexOf(u8, sink.items[0..BLOCK_SIZE], "NAXIS1") != null);
    try std.testing.expect(std.mem.indexOf(u8, sink.items[0..BLOCK_SIZE], "END") != null);
}

test "FITS data block is big-endian int16" {
    var sink = std.ArrayList(u8).init(std.testing.allocator);
    defer sink.deinit();

    var pixels: [2]u16 = .{ 0x0102, 0x0304 };
    try writeImage(sink.writer(), &pixels, .{ .width = 2, .height = 1 });

    // After 2880-byte header: data starts at offset 2880.
    try std.testing.expectEqual(@as(u8, 0x01), sink.items[BLOCK_SIZE]);
    try std.testing.expectEqual(@as(u8, 0x02), sink.items[BLOCK_SIZE + 1]);
    try std.testing.expectEqual(@as(u8, 0x03), sink.items[BLOCK_SIZE + 2]);
    try std.testing.expectEqual(@as(u8, 0x04), sink.items[BLOCK_SIZE + 3]);
}

test "FITS total size aligned to 2880" {
    var sink = std.ArrayList(u8).init(std.testing.allocator);
    defer sink.deinit();

    const pixels = try std.testing.allocator.alloc(u16, 100 * 100);
    defer std.testing.allocator.free(pixels);
    for (pixels) |*p| p.* = 4242;

    try writeImage(sink.writer(), pixels, .{ .width = 100, .height = 100 });
    try std.testing.expect(sink.items.len % BLOCK_SIZE == 0);
}

test "pixel count mismatch rejected" {
    var sink = std.ArrayList(u8).init(std.testing.allocator);
    defer sink.deinit();
    var pixels: [3]u16 = .{ 1, 2, 3 };
    try std.testing.expectError(
        error.PixelCountMismatch,
        writeImage(sink.writer(), &pixels, .{ .width = 2, .height = 2 }),
    );
}
