//! MLV reader for af-log. Subset of the schema in
//! `modules/raw_video/mlv_rec/mlv.h` — only what af-log needs.
//!
//! Mirrors `tools/raw-stack/src/mlv.zig` (kept duplicated rather than
//! shared as a Zig package while both tools are small). When the
//! shared surface grows, lift to `tools/mlv-zig/` or a Bazel-managed
//! local module.

const std = @import("std");

pub const BLOCK_HEADER_SIZE: usize = 16;

pub const BlockHeader = struct {
    block_type: [4]u8,
    block_size: u32,
    timestamp: u64,

    pub fn read(reader: anytype) !?BlockHeader {
        var buf: [BLOCK_HEADER_SIZE]u8 = undefined;
        const n = reader.readAll(&buf) catch |err| return err;
        if (n == 0) return null;
        if (n < BLOCK_HEADER_SIZE) return error.TruncatedHeader;

        return .{
            .block_type = buf[0..4].*,
            .block_size = std.mem.readInt(u32, buf[4..8], .little),
            .timestamp = std.mem.readInt(u64, buf[8..16], .little),
        };
    }
};

pub fn blockTypeEquals(bt: [4]u8, want: []const u8) bool {
    if (want.len != 4) return false;
    return std.mem.eql(u8, &bt, want);
}

pub const Aflg = struct {
    version: u16,
    event_type: u16,
    fields_present: u32,
    af_point: u16,
    af_area_mode: u16,
    focus_magnitude: u16,
    af_result: u16,
    hsp_countdown: u8,
    af_mf_physical: u8,
    is_state: u8,
    reserved1: u8,
    focus_near: u16,
    focus_far: u16,
    focus_pos: u16,
    focal_length: u16,
    aperture_raw: u32,
    afma_offset: i32,

    pub const HAS_DYNAMIC_LENS: u32 = 1 << 0;
    pub const HAS_LV_FOCUS_DATA: u32 = 1 << 1;
    pub const HAS_AFMA: u32 = 1 << 2;
    pub const HAS_AF_AREA: u32 = 1 << 3;
    pub const HAS_IS_STATE: u32 = 1 << 4;
    pub const HAS_PHYSICAL_SWITCH: u32 = 1 << 5;

    pub const PAYLOAD_SIZE: usize = 2 + 2 + 4 + 2 + 2 + 2 + 2 + 1 + 1 + 1 + 1 + 2 + 2 + 2 + 2 + 4 + 4;
};

pub const Reader = struct {
    allocator: std.mem.Allocator,
    underlying: std.io.AnyReader,

    pub fn init(allocator: std.mem.Allocator, underlying: std.io.AnyReader) Reader {
        return .{ .allocator = allocator, .underlying = underlying };
    }

    pub fn deinit(self: *Reader) void {
        _ = self;
    }

    pub fn next(self: *Reader) !?BlockHeader {
        return try BlockHeader.read(self.underlying);
    }

    pub fn skipBlockBody(self: *Reader, hdr: BlockHeader) !void {
        const remaining = @as(usize, hdr.block_size) -| BLOCK_HEADER_SIZE;
        var skipped: usize = 0;
        var buf: [4096]u8 = undefined;
        while (skipped < remaining) {
            const want = @min(buf.len, remaining - skipped);
            const got = try self.underlying.readAll(buf[0..want]);
            if (got == 0) return error.UnexpectedEof;
            skipped += got;
        }
    }

    pub fn readAflg(self: *Reader, hdr: BlockHeader) !Aflg {
        const remaining = @as(usize, hdr.block_size) -| BLOCK_HEADER_SIZE;
        if (remaining < Aflg.PAYLOAD_SIZE) return error.TruncatedAflg;

        var buf: [Aflg.PAYLOAD_SIZE]u8 = undefined;
        const n = try self.underlying.readAll(&buf);
        if (n < Aflg.PAYLOAD_SIZE) return error.UnexpectedEof;

        // Skip any trailing padding.
        var skipped: usize = Aflg.PAYLOAD_SIZE;
        var sink: [256]u8 = undefined;
        while (skipped < remaining) {
            const want = @min(sink.len, remaining - skipped);
            const got = try self.underlying.readAll(sink[0..want]);
            if (got == 0) return error.UnexpectedEof;
            skipped += got;
        }

        return .{
            .version = std.mem.readInt(u16, buf[0..2], .little),
            .event_type = std.mem.readInt(u16, buf[2..4], .little),
            .fields_present = std.mem.readInt(u32, buf[4..8], .little),
            .af_point = std.mem.readInt(u16, buf[8..10], .little),
            .af_area_mode = std.mem.readInt(u16, buf[10..12], .little),
            .focus_magnitude = std.mem.readInt(u16, buf[12..14], .little),
            .af_result = std.mem.readInt(u16, buf[14..16], .little),
            .hsp_countdown = buf[16],
            .af_mf_physical = buf[17],
            .is_state = buf[18],
            .reserved1 = buf[19],
            .focus_near = std.mem.readInt(u16, buf[20..22], .little),
            .focus_far = std.mem.readInt(u16, buf[22..24], .little),
            .focus_pos = std.mem.readInt(u16, buf[24..26], .little),
            .focal_length = std.mem.readInt(u16, buf[26..28], .little),
            .aperture_raw = std.mem.readInt(u32, buf[28..32], .little),
            .afma_offset = std.mem.readInt(i32, buf[32..36], .little),
        };
    }
};

test "blockTypeEquals" {
    try std.testing.expect(blockTypeEquals(.{ 'A', 'F', 'L', 'G' }, "AFLG"));
}

test "Aflg PAYLOAD_SIZE" {
    try std.testing.expectEqual(@as(usize, 36), Aflg.PAYLOAD_SIZE);
}
