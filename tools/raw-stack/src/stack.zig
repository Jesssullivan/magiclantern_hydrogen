//! First-cut stacker — RAWX metadata aggregation across one or more
//! MLV files.
//!
//! True multi-frame pixel stacking (drizzle + sigma-clip with
//! sensor-aware noise model, Sprint B3 acceptance criterion) requires
//! decoding the platform-specific bit-packed VIDF payloads. That is a
//! larger lift; this first cut operates on the RAWX **calibration
//! metadata** stream and is useful for validating that captures match
//! across a calibration session.
//!
//! For each input file, computes:
//!   - RAWX block count
//!   - mean / min / max digital_gain (across blocks where
//!     HAS_DIGITAL_GAIN is set)
//!   - first / last hardware timestamp
//!   - by-bit count of fields_present (which calibration fields the
//!     firmware managed to populate)
//!
//! Across the full input set, reports the aggregate.

const std = @import("std");
const mlv = @import("mlv.zig");

pub const FileStats = struct {
    path: []const u8,
    rawx_count: u64 = 0,
    digital_gain_min: u32 = std.math.maxInt(u32),
    digital_gain_max: u32 = 0,
    digital_gain_sum: u64 = 0,
    digital_gain_samples: u64 = 0,
    first_ts: u64 = std.math.maxInt(u64),
    last_ts: u64 = 0,
    fields_present_or: u32 = 0,
};

pub const Options = struct {
    /// Stop after this many RAWX blocks per file (0 = unbounded).
    max_blocks_per_file: u64 = 0,
};

pub fn stackFile(
    allocator: std.mem.Allocator,
    file_path: []const u8,
    opts: Options,
) !FileStats {
    var file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    var reader = mlv.Reader.init(allocator, file.reader().any());
    defer reader.deinit();

    var stats = FileStats{ .path = file_path };

    while (try reader.next()) |hdr| {
        if (mlv.blockTypeEquals(hdr.block_type, "RAWX")) {
            const r = try reader.readRawx(hdr);
            stats.rawx_count += 1;
            stats.fields_present_or |= r.fields_present;
            if (hdr.timestamp < stats.first_ts) stats.first_ts = hdr.timestamp;
            if (hdr.timestamp > stats.last_ts) stats.last_ts = hdr.timestamp;
            if ((r.fields_present & mlv.Rawx.HAS_DIGITAL_GAIN) != 0) {
                stats.digital_gain_samples += 1;
                stats.digital_gain_sum += r.digital_gain;
                if (r.digital_gain < stats.digital_gain_min)
                    stats.digital_gain_min = r.digital_gain;
                if (r.digital_gain > stats.digital_gain_max)
                    stats.digital_gain_max = r.digital_gain;
            }
            if (opts.max_blocks_per_file != 0 and
                stats.rawx_count >= opts.max_blocks_per_file) break;
        } else {
            try reader.skipBlockBody(hdr);
        }
    }
    return stats;
}

pub fn renderStats(w: anytype, stats: []const FileStats) !void {
    try w.print(
        "{s:<40} {s:<8} {s:<10} {s:<10} {s:<10} {s:<18}\n",
        .{ "file", "RAWX", "dg.min", "dg.mean", "dg.max", "span (ticks)" },
    );
    try w.print("{s}\n", .{"-" ** 100});

    var total_count: u64 = 0;
    var total_dg_sum: u64 = 0;
    var total_dg_samples: u64 = 0;
    var union_fields: u32 = 0;

    for (stats) |s| {
        const dg_mean: u64 = if (s.digital_gain_samples > 0)
            s.digital_gain_sum / s.digital_gain_samples
        else
            0;
        const dg_min_display = if (s.digital_gain_samples > 0) s.digital_gain_min else 0;
        const span = if (s.rawx_count > 0) s.last_ts - s.first_ts else 0;

        try w.print(
            "{s:<40} {d:<8} {d:<10} {d:<10} {d:<10} {d:<18}\n",
            .{ s.path, s.rawx_count, dg_min_display, dg_mean, s.digital_gain_max, span },
        );

        total_count += s.rawx_count;
        total_dg_sum += s.digital_gain_sum;
        total_dg_samples += s.digital_gain_samples;
        union_fields |= s.fields_present_or;
    }

    try w.print("{s}\n", .{"-" ** 100});
    const agg_mean: u64 = if (total_dg_samples > 0) total_dg_sum / total_dg_samples else 0;
    try w.print(
        "{s:<40} {d:<8} {s:<10} {d:<10} {s:<10}\n",
        .{ "(aggregate)", total_count, "-", agg_mean, "-" },
    );
    try w.print("\nfields_present union across input set: 0x{x:0>8}\n", .{union_fields});

    // Decode bitmap.
    const bits = [_]struct { mask: u32, name: []const u8 }{
        .{ .mask = mlv.Rawx.HAS_ANALOG_GAIN, .name = "ANALOG_GAIN" },
        .{ .mask = mlv.Rawx.HAS_DIGITAL_GAIN, .name = "DIGITAL_GAIN" },
        .{ .mask = mlv.Rawx.HAS_COLUMN_OFFSET, .name = "COLUMN_OFFSET" },
        .{ .mask = mlv.Rawx.HAS_DARK_TEMP, .name = "DARK_TEMP" },
        .{ .mask = mlv.Rawx.HAS_DPC_REF, .name = "DPC_REF" },
        .{ .mask = mlv.Rawx.HAS_FPN_REF, .name = "FPN_REF" },
        .{ .mask = mlv.Rawx.HAS_NS_TIMESTAMP, .name = "NS_TIMESTAMP" },
    };
    for (bits) |b| {
        const present = (union_fields & b.mask) != 0;
        try w.print("  {s:<16} {s}\n", .{ b.name, if (present) "yes" else "no" });
    }
}
