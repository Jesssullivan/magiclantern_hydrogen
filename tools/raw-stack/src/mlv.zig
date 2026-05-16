//! MLV reader: streaming block iteration + RAWX / AFLG decoders.
//!
//! Mirrors the wire layout in modules/raw_video/mlv_rec/mlv.h. We do
//! NOT try to recreate every block type here — only what raw-stack /
//! af-log need today. Unknown blocks are skipped by their declared
//! blockSize.

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

/// RAWX block payload as defined in mlv.h (mlv_rawx_hdr_t).
///
/// Note: the C struct lives inside `#pragma pack(push)` so it is byte-packed.
/// We declare the equivalent here with explicit field offsets in `read`.
pub const Rawx = struct {
    version: u16,
    reserved0: u16,
    fields_present: u32,
    analog_gain: u32,
    digital_gain: u32,
    column_offset: i32,
    dark_temp: i32,
    dpc_table_ref: u32,
    fpn_table_ref: u32,
    exposure_ns: u64,

    pub const HAS_ANALOG_GAIN: u32 = 1 << 0;
    pub const HAS_DIGITAL_GAIN: u32 = 1 << 1;
    pub const HAS_COLUMN_OFFSET: u32 = 1 << 2;
    pub const HAS_DARK_TEMP: u32 = 1 << 3;
    pub const HAS_DPC_REF: u32 = 1 << 4;
    pub const HAS_FPN_REF: u32 = 1 << 5;
    pub const HAS_NS_TIMESTAMP: u32 = 1 << 6;

    pub const SENTINEL_U32: u32 = 0xFFFFFFFF;
    pub const SENTINEL_U16: u16 = 0xFFFF;
    pub const SENTINEL_I32: i32 = @bitCast(@as(u32, 0x80000000));

    /// Wire size of the payload after the 16-byte BlockHeader.
    pub const PAYLOAD_SIZE: usize = 2 + 2 + 4 + 4 + 4 + 4 + 4 + 4 + 4 + 8;
};

/// AFLG block payload (mlv_aflg_hdr_t).
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

    pub const Event = enum(u16) {
        half_press = 1,
        focus_done = 2,
        focus_data = 3,
        af_point_change = 4,
        af_area_change = 5,
        aperture_change = 6,
        is_state_change = 7,
        lens_dynamic = 8,
        hsp_countdown = 9,
        _,
    };

    pub fn eventName(self: Aflg) []const u8 {
        return switch (@as(Event, @enumFromInt(self.event_type))) {
            .half_press => "HALF_PRESS",
            .focus_done => "FOCUS_DONE",
            .focus_data => "FOCUS_DATA",
            .af_point_change => "AF_POINT_CHANGE",
            .af_area_change => "AF_AREA_CHANGE",
            .aperture_change => "APERTURE_CHANGE",
            .is_state_change => "IS_STATE_CHANGE",
            .lens_dynamic => "LENS_DYNAMIC",
            .hsp_countdown => "HSP_COUNTDOWN",
            _ => "UNKNOWN",
        };
    }

    pub const PAYLOAD_SIZE: usize = 2 + 2 + 4 + 2 + 2 + 2 + 2 + 1 + 1 + 1 + 1 + 2 + 2 + 2 + 2 + 4 + 4;
};

pub const Summary = struct {
    block_count: u64 = 0,
    bytes: u64 = 0,
    counts: std.AutoArrayHashMapUnmanaged([4]u8, u64) = .{},

    pub fn observe(self: *Summary, hdr: BlockHeader) void {
        self.block_count += 1;
        self.bytes += hdr.block_size;
        const gop = self.counts.getOrPut(std.heap.page_allocator, hdr.block_type) catch return;
        if (!gop.found_existing) gop.value_ptr.* = 0;
        gop.value_ptr.* += 1;
    }

    pub fn print(self: *const Summary, w: anytype) !void {
        try w.print("  blocks: {d}  bytes: {d}\n", .{ self.block_count, self.bytes });
        try w.print("  by type:\n", .{});
        var it = self.counts.iterator();
        while (it.next()) |entry| {
            try w.print("    {s}: {d}\n", .{ entry.key_ptr.*[0..], entry.value_ptr.* });
        }
    }
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

    pub fn readRawx(self: *Reader, hdr: BlockHeader) !Rawx {
        const remaining = @as(usize, hdr.block_size) -| BLOCK_HEADER_SIZE;
        if (remaining < Rawx.PAYLOAD_SIZE) return error.TruncatedRawx;

        var buf: [Rawx.PAYLOAD_SIZE]u8 = undefined;
        const n = try self.underlying.readAll(&buf);
        if (n < Rawx.PAYLOAD_SIZE) return error.UnexpectedEof;

        // Skip any trailing padding the writer may have left.
        var skipped: usize = Rawx.PAYLOAD_SIZE;
        var sink: [256]u8 = undefined;
        while (skipped < remaining) {
            const want = @min(sink.len, remaining - skipped);
            const got = try self.underlying.readAll(sink[0..want]);
            if (got == 0) return error.UnexpectedEof;
            skipped += got;
        }

        return .{
            .version = std.mem.readInt(u16, buf[0..2], .little),
            .reserved0 = std.mem.readInt(u16, buf[2..4], .little),
            .fields_present = std.mem.readInt(u32, buf[4..8], .little),
            .analog_gain = std.mem.readInt(u32, buf[8..12], .little),
            .digital_gain = std.mem.readInt(u32, buf[12..16], .little),
            .column_offset = std.mem.readInt(i32, buf[16..20], .little),
            .dark_temp = std.mem.readInt(i32, buf[20..24], .little),
            .dpc_table_ref = std.mem.readInt(u32, buf[24..28], .little),
            .fpn_table_ref = std.mem.readInt(u32, buf[28..32], .little),
            .exposure_ns = std.mem.readInt(u64, buf[32..40], .little),
        };
    }

    pub fn readAflg(self: *Reader, hdr: BlockHeader) !Aflg {
        const remaining = @as(usize, hdr.block_size) -| BLOCK_HEADER_SIZE;
        if (remaining < Aflg.PAYLOAD_SIZE) return error.TruncatedAflg;

        var buf: [Aflg.PAYLOAD_SIZE]u8 = undefined;
        const n = try self.underlying.readAll(&buf);
        if (n < Aflg.PAYLOAD_SIZE) return error.UnexpectedEof;

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
    try std.testing.expect(blockTypeEquals(.{ 'R', 'A', 'W', 'X' }, "RAWX"));
    try std.testing.expect(!blockTypeEquals(.{ 'R', 'A', 'W', 'X' }, "RAWI"));
}

test "Rawx PAYLOAD_SIZE matches sum of fields" {
    try std.testing.expectEqual(@as(usize, 40), Rawx.PAYLOAD_SIZE);
}

test "Aflg PAYLOAD_SIZE matches sum of fields" {
    try std.testing.expectEqual(@as(usize, 36), Aflg.PAYLOAD_SIZE);
}
