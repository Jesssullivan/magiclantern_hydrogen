//! Synthetic MLV fixture generator for raw-stack and af-log tests.
//!
//! Writes a small MLV-shaped file containing alternating RAWX and AFLG
//! blocks at synthesised hardware ticks. The wire layout exactly matches
//! `mlv_rawx_hdr_t` / `mlv_aflg_hdr_t` in
//! `modules/raw_video/mlv_rec/mlv.h`. Lets us exercise the decoder
//! without firmware in the loop.
//!
//! Usage: import this module and call `writeFixture(writer, opts)`.

const std = @import("std");
const mlv = @import("mlv.zig");

pub const Options = struct {
    rawx_frames: u32 = 4,
    aflg_events: u32 = 6,
    /// Number of VIDF blocks to emit. 0 disables VIDF emission.
    vidf_frames: u32 = 4,
    /// Synthetic raw payload bytes per VIDF block. 0 = header-only.
    /// Default 64 bytes lets `raw-stats` exercise byte aggregation
    /// without needing realistic bayer data.
    vidf_payload_bytes: u32 = 64,
    /// Start hardware tick; subsequent blocks advance by `tick_step`.
    tick_start: u64 = 1_000_000,
    tick_step: u64 = 33_000, // ~30 Hz vsync at us granularity
    /// When true, append a "complex" suffix that exercises all three
    /// af-log detect classifiers (focus_bracket / tracking_dwell /
    /// hunting). Used by the integration test.
    include_complex_patterns: bool = false,
};

pub fn writeFixture(writer: anytype, opts: Options) !void {
    var tick = opts.tick_start;

    var v: u32 = 0;
    while (v < opts.vidf_frames) : (v += 1) {
        try writeVidf(writer, .{
            .timestamp = tick,
            .frame_number = v,
            .cropPos_x = 0,
            .cropPos_y = 0,
            .panPos_x = 0,
            .panPos_y = 0,
            .frameSpace = 0,
        }, opts.vidf_payload_bytes);
        tick += opts.tick_step;
    }

    var i: u32 = 0;
    while (i < opts.rawx_frames) : (i += 1) {
        try writeRawx(writer, .{
            .timestamp = tick,
            .fields_present = mlv.Rawx.HAS_DIGITAL_GAIN,
            .analog_gain = mlv.Rawx.SENTINEL_U32,
            .digital_gain = 0x1000 + (i * 0x100),
            .column_offset = mlv.Rawx.SENTINEL_I32,
            .dark_temp = mlv.Rawx.SENTINEL_I32,
            .dpc_table_ref = mlv.Rawx.SENTINEL_U32,
            .fpn_table_ref = mlv.Rawx.SENTINEL_U32,
            .exposure_ns = 0,
        });
        tick += opts.tick_step;
    }

    var j: u32 = 0;
    while (j < opts.aflg_events) : (j += 1) {
        try writeAflg(writer, .{
            .timestamp = tick,
            .event_type = @intCast((j % 9) + 1),
            .fields_present = mlv.Aflg.HAS_LV_FOCUS_DATA,
            .af_point = 7,
            .af_area_mode = 1,
            .focus_magnitude = 200 + (@as(u16, @intCast(j)) * 10),
            .af_result = 0,
            .hsp_countdown = if (j % 9 == 0) 3 else 0,
            .af_mf_physical = 0,
            .is_state = 0,
            .reserved1 = 0,
            .focus_near = mlv.Rawx.SENTINEL_U16,
            .focus_far = mlv.Rawx.SENTINEL_U16,
            .focus_pos = mlv.Rawx.SENTINEL_U16,
            .focal_length = mlv.Rawx.SENTINEL_U16,
            .aperture_raw = 0x05000000,
            .afma_offset = mlv.Rawx.SENTINEL_I32,
        });
        tick += opts.tick_step;
    }

    if (opts.include_complex_patterns) {
        try writeComplexAflgSuffix(writer, &tick, opts.tick_step);
    }
}

/// Append AFLG events exercising all three detect classifiers:
///   1. Focus-bracket: 5× FOCUS_DATA within ~165 ms.
///   2. Tracking-dwell: AF_POINT_CHANGE then FOCUS_DONE 50 ms later.
///   3. Hunting: 5× FOCUS_DATA with magnitude reversing 4 times.
fn writeComplexAflgSuffix(writer: anytype, tick: *u64, step: u64) !void {
    // 1. Focus bracket: 5 FOCUS_DATA events at step intervals.
    var k: u32 = 0;
    while (k < 5) : (k += 1) {
        try writeAflg(writer, basicAflg(tick.*, 3, 500 + @as(u16, @intCast(k * 20))));
        tick.* += step;
    }

    // 2. Tracking dwell: AF_POINT_CHANGE then FOCUS_DONE 50 ms later.
    try writeAflg(writer, basicAflg(tick.*, 4, 0));
    tick.* += 50_000; // 50 ms
    try writeAflg(writer, basicAflg(tick.*, 2, 0));
    tick.* += step;

    // 3. Hunting: 5 FOCUS_DATA with oscillating magnitude (4 reversals).
    const mags = [_]u16{ 100, 200, 100, 200, 100 };
    for (mags) |m| {
        try writeAflg(writer, basicAflg(tick.*, 3, m));
        tick.* += 100_000;
    }
}

fn basicAflg(timestamp: u64, event_type: u16, focus_magnitude: u16) AflgArgs {
    return .{
        .timestamp = timestamp,
        .event_type = event_type,
        .fields_present = mlv.Aflg.HAS_LV_FOCUS_DATA,
        .af_point = 7,
        .af_area_mode = 1,
        .focus_magnitude = focus_magnitude,
        .af_result = 0,
        .hsp_countdown = 0,
        .af_mf_physical = 0,
        .is_state = 0,
        .reserved1 = 0,
        .focus_near = mlv.Rawx.SENTINEL_U16,
        .focus_far = mlv.Rawx.SENTINEL_U16,
        .focus_pos = mlv.Rawx.SENTINEL_U16,
        .focal_length = mlv.Rawx.SENTINEL_U16,
        .aperture_raw = 0,
        .afma_offset = mlv.Rawx.SENTINEL_I32,
    };
}

pub const RawxArgs = struct {
    timestamp: u64,
    fields_present: u32,
    analog_gain: u32,
    digital_gain: u32,
    column_offset: i32,
    dark_temp: i32,
    dpc_table_ref: u32,
    fpn_table_ref: u32,
    exposure_ns: u64,
};

pub const VidfArgs = struct {
    timestamp: u64,
    frame_number: u32,
    cropPos_x: u16,
    cropPos_y: u16,
    panPos_x: u16,
    panPos_y: u16,
    frameSpace: u32,
};

fn writeVidf(writer: anytype, args: VidfArgs, payload_bytes: u32) !void {
    const total: u32 = @intCast(
        mlv.BLOCK_HEADER_SIZE + mlv.Vidf.PAYLOAD_SIZE + args.frameSpace + payload_bytes,
    );
    try writer.writeAll("VIDF");
    try writer.writeInt(u32, total, .little);
    try writer.writeInt(u64, args.timestamp, .little);

    try writer.writeInt(u32, args.frame_number, .little);
    try writer.writeInt(u16, args.cropPos_x, .little);
    try writer.writeInt(u16, args.cropPos_y, .little);
    try writer.writeInt(u16, args.panPos_x, .little);
    try writer.writeInt(u16, args.panPos_y, .little);
    try writer.writeInt(u32, args.frameSpace, .little);

    // frameSpace padding (zeros).
    var space_left = args.frameSpace;
    var z: [256]u8 = [_]u8{0} ** 256;
    while (space_left > 0) {
        const w = @min(@as(u32, z.len), space_left);
        try writer.writeAll(z[0..w]);
        space_left -= w;
    }

    // Synthetic raw payload: byte = (frame_number + i) & 0xFF.
    // Lets raw-stats compute deterministic byte-aggregate stats.
    var i: u32 = 0;
    while (i < payload_bytes) : (i += 1) {
        const b: u8 = @intCast((args.frame_number + i) & 0xFF);
        try writer.writeAll(&[_]u8{b});
    }
}

fn writeRawx(writer: anytype, args: RawxArgs) !void {
    // Block header (BLOCK_HEADER_SIZE) + payload (Rawx.PAYLOAD_SIZE).
    const total: u32 = @intCast(mlv.BLOCK_HEADER_SIZE + mlv.Rawx.PAYLOAD_SIZE);

    try writer.writeAll("RAWX");
    try writer.writeInt(u32, total, .little);
    try writer.writeInt(u64, args.timestamp, .little);

    try writer.writeInt(u16, 1, .little); // version
    try writer.writeInt(u16, 0, .little); // reserved0
    try writer.writeInt(u32, args.fields_present, .little);
    try writer.writeInt(u32, args.analog_gain, .little);
    try writer.writeInt(u32, args.digital_gain, .little);
    try writer.writeInt(i32, args.column_offset, .little);
    try writer.writeInt(i32, args.dark_temp, .little);
    try writer.writeInt(u32, args.dpc_table_ref, .little);
    try writer.writeInt(u32, args.fpn_table_ref, .little);
    try writer.writeInt(u64, args.exposure_ns, .little);
}

pub const AflgArgs = struct {
    timestamp: u64,
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
};

fn writeAflg(writer: anytype, args: AflgArgs) !void {
    const total: u32 = @intCast(mlv.BLOCK_HEADER_SIZE + mlv.Aflg.PAYLOAD_SIZE);

    try writer.writeAll("AFLG");
    try writer.writeInt(u32, total, .little);
    try writer.writeInt(u64, args.timestamp, .little);

    try writer.writeInt(u16, 1, .little); // version
    try writer.writeInt(u16, args.event_type, .little);
    try writer.writeInt(u32, args.fields_present, .little);
    try writer.writeInt(u16, args.af_point, .little);
    try writer.writeInt(u16, args.af_area_mode, .little);
    try writer.writeInt(u16, args.focus_magnitude, .little);
    try writer.writeInt(u16, args.af_result, .little);
    try writer.writeByte(args.hsp_countdown);
    try writer.writeByte(args.af_mf_physical);
    try writer.writeByte(args.is_state);
    try writer.writeByte(args.reserved1);
    try writer.writeInt(u16, args.focus_near, .little);
    try writer.writeInt(u16, args.focus_far, .little);
    try writer.writeInt(u16, args.focus_pos, .little);
    try writer.writeInt(u16, args.focal_length, .little);
    try writer.writeInt(u32, args.aperture_raw, .little);
    try writer.writeInt(i32, args.afma_offset, .little);
}

test "fixture round-trips through Reader" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    try writeFixture(stream.writer(), .{ .rawx_frames = 2, .aflg_events = 3 });

    const bytes_written = stream.pos;
    try std.testing.expect(bytes_written > 0);

    // Decode back.
    var read_stream = std.io.fixedBufferStream(buf[0..bytes_written]);
    var reader = mlv.Reader.init(std.testing.allocator, read_stream.reader().any());
    defer reader.deinit();

    var rawx_count: u32 = 0;
    var aflg_count: u32 = 0;
    while (try reader.next()) |hdr| {
        if (mlv.blockTypeEquals(hdr.block_type, "RAWX")) {
            const r = try reader.readRawx(hdr);
            try std.testing.expect(r.version == 1);
            rawx_count += 1;
        } else if (mlv.blockTypeEquals(hdr.block_type, "AFLG")) {
            const a = try reader.readAflg(hdr);
            try std.testing.expect(a.version == 1);
            aflg_count += 1;
        } else {
            try reader.skipBlockBody(hdr);
        }
    }

    try std.testing.expectEqual(@as(u32, 2), rawx_count);
    try std.testing.expectEqual(@as(u32, 3), aflg_count);
}
