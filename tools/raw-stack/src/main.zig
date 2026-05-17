//! raw-stack — host-side raw / spectral reconstruction pipeline for
//! magiclantern_hydrogen MLV captures with RAWX calibration metadata.
//!
//! Sprint B3 / Linear TIN-1223.
//!
//! Subcommands:
//!   inspect FILE        Dump MLV block taxonomy + RAWX summary
//!   stack ...           Multi-frame stacker (stub)
//!   demosaic-skip ...   Spectral mode: skip-demosaic to FITS (stub)
//!   calibrate ...       Dark / flat / bias calibration (stub)
//!
//! See developer_guide/09_00_raw_sensor_stack.md for the MLV taxonomy
//! and RAWX block definition. Block definitions live in
//! modules/raw_video/mlv_rec/mlv.h.

const std = @import("std");
const mlv = @import("mlv.zig");
const fixture = @import("fixture.zig");
const stack_mod = @import("stack.zig");
const pixels_mod = @import("pixels.zig");
const fits = @import("fits.zig");
const bayer = @import("bayer.zig");

const VERSION = "0.3.0";

const Subcommand = enum {
    help,
    version,
    inspect,
    stack,
    demosaic_skip,
    calibrate,
    fixture,
    frames,
    raw_stats,
    info,
    pixel_stats,
    mean_frame,
    bayer_stats,
    median_frame,
    dark_subtract,
    sigma_stack,
};

fn parseSubcommand(arg: []const u8) ?Subcommand {
    const map = .{
        .{ "help", .help },
        .{ "--help", .help },
        .{ "-h", .help },
        .{ "version", .version },
        .{ "--version", .version },
        .{ "-V", .version },
        .{ "inspect", .inspect },
        .{ "stack", .stack },
        .{ "demosaic-skip", .demosaic_skip },
        .{ "calibrate", .calibrate },
        .{ "fixture", .fixture },
        .{ "frames", .frames },
        .{ "raw-stats", .raw_stats },
        .{ "info", .info },
        .{ "pixel-stats", .pixel_stats },
        .{ "mean-frame", .mean_frame },
        .{ "bayer-stats", .bayer_stats },
        .{ "median-frame", .median_frame },
        .{ "dark-subtract", .dark_subtract },
        .{ "sigma-stack", .sigma_stack },
    };
    inline for (map) |entry| {
        if (std.mem.eql(u8, arg, entry[0])) return entry[1];
    }
    return null;
}

fn printUsage(w: anytype) !void {
    try w.print(
        \\raw-stack {s} — host raw / spectral pipeline for magiclantern_hydrogen
        \\
        \\Usage: raw-stack <subcommand> [args...]
        \\
        \\Subcommands:
        \\  inspect FILE.mlv            Dump block taxonomy and RAWX/AFLG summary
        \\  stack FILE...               Aggregate RAWX metadata across input MLVs
        \\  demosaic-skip FILE          Spectral mode → FITS (stub)
        \\  calibrate KIND DIR          Build dark/flat/bias frames (stub)
        \\  fixture OUT.mlv             Write a synthetic RAWX+AFLG fixture (for tests)
        \\  mean-frame IN.mlv ... OUT   Per-pixel mean stack (FITS or raw u16 LE by extension)
        \\  median-frame IN.mlv ... OUT Per-pixel median stack (outlier-robust)
        \\  dark-subtract DARK IN.mlv ... OUT  Subtract master dark from each frame, mean-stack
        \\  sigma-stack [--sigma N] [--iters N] IN.mlv ... OUT  Iterative sigma-clipped mean stack
        \\
        \\Global flags:
        \\  --help, -h                  This message
        \\  --version, -V               Print version
        \\
        \\Sprint B3 deliverable. See developer_guide/09_00_raw_sensor_stack.md.
        \\
    , .{VERSION});
}

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    if (args.len < 2) {
        try printUsage(stderr);
        return 2;
    }

    const subcommand = parseSubcommand(args[1]) orelse {
        try stderr.print("raw-stack: unknown subcommand '{s}'\n\n", .{args[1]});
        try printUsage(stderr);
        return 2;
    };

    switch (subcommand) {
        .help => {
            try printUsage(stdout);
            return 0;
        },
        .version => {
            try stdout.print("raw-stack {s}\n", .{VERSION});
            return 0;
        },
        .inspect => return try runInspect(allocator, args[2..]),
        .stack => return try runStack(allocator, args[2..]),
        .demosaic_skip => {
            try stderr.print("raw-stack demosaic-skip: not yet implemented (TIN-1223).\n", .{});
            return 1;
        },
        .calibrate => {
            try stderr.print("raw-stack calibrate: not yet implemented (TIN-1223).\n", .{});
            return 1;
        },
        .fixture => return try runFixture(args[2..]),
        .frames => return try runFrames(allocator, args[2..]),
        .raw_stats => return try runRawStats(allocator, args[2..]),
        .info => return try runInfo(allocator, args[2..]),
        .pixel_stats => return try runPixelStats(allocator, args[2..]),
        .mean_frame => return try runMeanFrame(allocator, args[2..]),
        .bayer_stats => return try runBayerStats(allocator, args[2..]),
        .median_frame => return try runMedianFrame(allocator, args[2..]),
        .dark_subtract => return try runDarkSubtract(allocator, args[2..]),
        .sigma_stack => return try runSigmaStack(allocator, args[2..]),
    }
}

/// dark-subtract MASTER_DARK IN.mlv [IN2.mlv ...] OUT[.fits|.bin]
/// Master dark is a raw u16 little-endian file (typically the output of
/// `mean-frame` or `median-frame` run over a set of dark-frame
/// exposures). For each VIDF in the inputs, subtracts the master dark
/// per-pixel (saturating at 0), then computes the per-pixel mean across
/// all subtracted frames. Output format inferred from extension same as
/// mean-frame / median-frame.
fn runDarkSubtract(allocator: std.mem.Allocator, args: [][:0]u8) !u8 {
    const stderr = std.io.getStdErr().writer();
    if (args.len < 3) {
        try stderr.print(
            "raw-stack dark-subtract: expected MASTER_DARK INPUT.mlv [INPUT2.mlv ...] OUT\n",
            .{},
        );
        return 2;
    }
    const dark_path = args[0];
    const out_path = args[args.len - 1];
    const inputs = args[1 .. args.len - 1];

    // Load master dark as raw u16 LE.
    var dark_file = std.fs.cwd().openFile(dark_path, .{}) catch |err| {
        try stderr.print("raw-stack dark-subtract: cannot open master dark '{s}': {s}\n", .{ dark_path, @errorName(err) });
        return 1;
    };
    defer dark_file.close();
    const dark_size = try dark_file.getEndPos();
    if (dark_size == 0 or dark_size % 2 != 0) {
        try stderr.print(
            "raw-stack dark-subtract: master dark must be raw u16 LE (got {d} bytes)\n",
            .{dark_size},
        );
        return 1;
    }
    const dark_pixels = try allocator.alloc(u16, dark_size / 2);
    defer allocator.free(dark_pixels);
    {
        var r = dark_file.reader();
        for (dark_pixels) |*p| p.* = try r.readInt(u16, .little);
    }

    var dims: ?struct { w: i32, h: i32 } = null;
    var running_sum: ?[]i64 = null;
    var sample_count: u64 = 0;
    defer if (running_sum) |s| allocator.free(s);

    for (inputs) |in_path| {
        var file = std.fs.cwd().openFile(in_path, .{}) catch |err| {
            try stderr.print("raw-stack dark-subtract: cannot open '{s}': {s}\n", .{ in_path, @errorName(err) });
            return 1;
        };
        defer file.close();

        var reader = mlv.Reader.init(allocator, file.reader().any());
        defer reader.deinit();

        while (try reader.next()) |hdr| {
            if (mlv.blockTypeEquals(hdr.block_type, "RAWI")) {
                const r = try reader.readRawi(hdr);
                if (r.bits_per_pixel != 14) {
                    try stderr.print(
                        "raw-stack dark-subtract: '{s}' bits_per_pixel={d}; only 14 supported\n",
                        .{ in_path, r.bits_per_pixel },
                    );
                    return 1;
                }
                if (dims) |d| {
                    if (d.w != r.width or d.h != r.height) {
                        try stderr.print(
                            "raw-stack dark-subtract: dimension mismatch '{s}' {d}x{d} vs {d}x{d}\n",
                            .{ in_path, r.width, r.height, d.w, d.h },
                        );
                        return 1;
                    }
                } else dims = .{ .w = r.width, .h = r.height };
            } else if (mlv.blockTypeEquals(hdr.block_type, "VIDF")) {
                const r = try reader.readVidfWithPayload(hdr);
                defer allocator.free(r.payload);
                if (r.payload.len == 0 or r.payload.len % pixels_mod.BYTES_PER_BLOCK != 0) continue;

                const px = try pixels_mod.unpackBuffer(allocator, r.payload);
                defer allocator.free(px);

                if (px.len != dark_pixels.len) {
                    try stderr.print(
                        "raw-stack dark-subtract: frame pixel count {d} != master dark pixel count {d}\n",
                        .{ px.len, dark_pixels.len },
                    );
                    return 1;
                }

                if (running_sum == null) {
                    running_sum = try allocator.alloc(i64, px.len);
                    for (running_sum.?) |*s| s.* = 0;
                }

                for (px, dark_pixels, running_sum.?) |p, d, *s| {
                    s.* += @as(i64, p) - @as(i64, d);
                }
                sample_count += 1;
            } else {
                try reader.skipBlockBody(hdr);
            }
        }
    }

    if (running_sum == null or sample_count == 0) {
        try stderr.print("raw-stack dark-subtract: no VIDF samples decoded\n", .{});
        return 1;
    }

    const out_pixels = try allocator.alloc(u16, running_sum.?.len);
    defer allocator.free(out_pixels);
    var clipped_low: u64 = 0;
    var clipped_high: u64 = 0;
    for (running_sum.?, out_pixels) |s, *o| {
        const m = @divTrunc(s, @as(i64, @intCast(sample_count)));
        if (m < 0) {
            o.* = 0;
            clipped_low += 1;
        } else if (m > @as(i64, pixels_mod.MAX_PIXEL_VALUE)) {
            o.* = pixels_mod.MAX_PIXEL_VALUE;
            clipped_high += 1;
        } else {
            o.* = @intCast(m);
        }
    }

    var out_file = try std.fs.cwd().createFile(out_path, .{ .truncate = true });
    defer out_file.close();
    var w = out_file.writer();
    const is_fits = std.mem.endsWith(u8, out_path, ".fits") or std.mem.endsWith(u8, out_path, ".fit");

    if (is_fits) {
        if (dims == null) {
            try stderr.print("raw-stack dark-subtract: FITS output requires RAWI dimensions\n", .{});
            return 1;
        }
        const want = @as(usize, @intCast(dims.?.w)) * @as(usize, @intCast(dims.?.h));
        const fw: i32 = if (want == out_pixels.len) dims.?.w else @as(i32, @intCast(out_pixels.len));
        const fh: i32 = if (want == out_pixels.len) dims.?.h else 1;
        try fits.writeImage(w, out_pixels, .{
            .width = fw,
            .height = fh,
            .object = "dark-subtracted stack",
            .comments = &[_][]const u8{"Generated by raw-stack dark-subtract."},
        });
    } else {
        for (out_pixels) |p| try w.writeInt(u16, p, .little);
    }

    const stdout = std.io.getStdOut().writer();
    try stdout.print(
        "raw-stack dark-subtract: stacked {d} VIDF frames -> {d} pixels (clipped {d} low, {d} high) @ {s}\n",
        .{ sample_count, out_pixels.len, clipped_low, clipped_high, out_path },
    );
    return 0;
}

/// sigma-stack [--sigma N] [--iters N] IN.mlv [IN2.mlv ...] OUT
/// Iterative sigma-clipped mean stacker. Per pixel: collect samples
/// across all frames, compute mean + stddev, reject samples >sigma*stddev
/// from mean, repeat for `iters` iterations, emit final mean. Robust to
/// transient outliers (cosmic rays, sensor glitches) without the
/// information loss of pure median.
///
/// Defaults: sigma=3.0, iters=2.
fn runSigmaStack(allocator: std.mem.Allocator, args: [][:0]u8) !u8 {
    const stderr = std.io.getStdErr().writer();

    var sigma: f64 = 3.0;
    var iters: u32 = 2;
    var positional = std.ArrayList([:0]u8).init(allocator);
    defer positional.deinit();

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--sigma")) {
            if (i + 1 >= args.len) {
                try stderr.print("raw-stack sigma-stack: --sigma needs a value\n", .{});
                return 2;
            }
            i += 1;
            sigma = std.fmt.parseFloat(f64, args[i]) catch {
                try stderr.print("raw-stack sigma-stack: invalid sigma '{s}'\n", .{args[i]});
                return 2;
            };
        } else if (std.mem.eql(u8, args[i], "--iters")) {
            if (i + 1 >= args.len) {
                try stderr.print("raw-stack sigma-stack: --iters needs a value\n", .{});
                return 2;
            }
            i += 1;
            iters = std.fmt.parseInt(u32, args[i], 10) catch {
                try stderr.print("raw-stack sigma-stack: invalid iters '{s}'\n", .{args[i]});
                return 2;
            };
        } else {
            try positional.append(args[i]);
        }
    }

    if (positional.items.len < 2) {
        try stderr.print(
            "raw-stack sigma-stack: expected [--sigma N] [--iters N] INPUT.mlv [INPUT2.mlv ...] OUT\n",
            .{},
        );
        return 2;
    }
    const out_path = positional.items[positional.items.len - 1];
    const inputs = positional.items[0 .. positional.items.len - 1];

    var dims: ?struct { w: i32, h: i32 } = null;
    var samples = std.ArrayList(std.ArrayList(u16)).init(allocator);
    defer {
        for (samples.items) |*s| s.deinit();
        samples.deinit();
    }
    var samples_initialized = false;

    for (inputs) |in_path| {
        var file = std.fs.cwd().openFile(in_path, .{}) catch |err| {
            try stderr.print("raw-stack sigma-stack: cannot open '{s}': {s}\n", .{ in_path, @errorName(err) });
            return 1;
        };
        defer file.close();

        var reader = mlv.Reader.init(allocator, file.reader().any());
        defer reader.deinit();

        while (try reader.next()) |hdr| {
            if (mlv.blockTypeEquals(hdr.block_type, "RAWI")) {
                const r = try reader.readRawi(hdr);
                if (r.bits_per_pixel != 14) {
                    try stderr.print(
                        "raw-stack sigma-stack: '{s}' bits_per_pixel={d}; only 14 supported\n",
                        .{ in_path, r.bits_per_pixel },
                    );
                    return 1;
                }
                if (dims) |d| {
                    if (d.w != r.width or d.h != r.height) {
                        try stderr.print(
                            "raw-stack sigma-stack: dimension mismatch '{s}' {d}x{d} vs {d}x{d}\n",
                            .{ in_path, r.width, r.height, d.w, d.h },
                        );
                        return 1;
                    }
                } else dims = .{ .w = r.width, .h = r.height };
            } else if (mlv.blockTypeEquals(hdr.block_type, "VIDF")) {
                const r = try reader.readVidfWithPayload(hdr);
                defer allocator.free(r.payload);
                if (r.payload.len == 0 or r.payload.len % pixels_mod.BYTES_PER_BLOCK != 0) continue;

                const px = try pixels_mod.unpackBuffer(allocator, r.payload);
                defer allocator.free(px);

                if (!samples_initialized) {
                    try samples.ensureTotalCapacity(px.len);
                    var k: usize = 0;
                    while (k < px.len) : (k += 1) {
                        try samples.append(std.ArrayList(u16).init(allocator));
                    }
                    samples_initialized = true;
                } else if (samples.items.len != px.len) {
                    try stderr.print(
                        "raw-stack sigma-stack: VIDF pixel count varies ({d} vs {d})\n",
                        .{ px.len, samples.items.len },
                    );
                    return 1;
                }

                for (px, 0..) |p, j| try samples.items[j].append(p);
            } else {
                try reader.skipBlockBody(hdr);
            }
        }
    }

    if (!samples_initialized or samples.items.len == 0) {
        try stderr.print("raw-stack sigma-stack: no VIDF samples decoded\n", .{});
        return 1;
    }

    const out_pixels = try allocator.alloc(u16, samples.items.len);
    defer allocator.free(out_pixels);

    var total_in: u64 = 0;
    var total_kept: u64 = 0;
    var per_pixel_in: u64 = 0;
    for (samples.items, 0..) |*s, idx| {
        const result = sigmaClipMean(s.items, sigma, iters);
        out_pixels[idx] = result.mean_u16;
        total_in += s.items.len;
        total_kept += result.kept;
        if (idx == 0) per_pixel_in = s.items.len;
    }

    var out_file = try std.fs.cwd().createFile(out_path, .{ .truncate = true });
    defer out_file.close();
    var w = out_file.writer();
    const is_fits = std.mem.endsWith(u8, out_path, ".fits") or std.mem.endsWith(u8, out_path, ".fit");

    if (is_fits) {
        if (dims == null) {
            try stderr.print("raw-stack sigma-stack: FITS output requires RAWI dimensions\n", .{});
            return 1;
        }
        const want = @as(usize, @intCast(dims.?.w)) * @as(usize, @intCast(dims.?.h));
        const fw: i32 = if (want == out_pixels.len) dims.?.w else @as(i32, @intCast(out_pixels.len));
        const fh: i32 = if (want == out_pixels.len) dims.?.h else 1;
        try fits.writeImage(w, out_pixels, .{
            .width = fw,
            .height = fh,
            .object = "sigma-clipped stack",
            .comments = &[_][]const u8{"Generated by raw-stack sigma-stack."},
        });
    } else {
        for (out_pixels) |p| try w.writeInt(u16, p, .little);
    }

    const stdout = std.io.getStdOut().writer();
    try stdout.print(
        "raw-stack sigma-stack: sigma={d:.2} iters={d} samples-per-pixel={d} pixels={d} kept={d}/{d} samples @ {s}\n",
        .{ sigma, iters, per_pixel_in, out_pixels.len, total_kept, total_in, out_path },
    );
    return 0;
}

const SigmaClipResult = struct { mean_u16: u16, kept: u64 };

fn sigmaClipMean(samples: []const u16, sigma: f64, iters: u32) SigmaClipResult {
    if (samples.len == 0) return .{ .mean_u16 = 0, .kept = 0 };

    // Initial mean.
    var sum: f64 = 0;
    for (samples) |p| sum += @as(f64, @floatFromInt(p));
    var mean: f64 = sum / @as(f64, @floatFromInt(samples.len));

    // Track which samples survive via a bool mask on the stack-allocated
    // path (heap on overflow). For our typical N (a handful per pixel
    // for stacks, hundreds for long sequences) a small fixed-size mask
    // on stack is fine via a fixed buffer.
    var kept_mask: [4096]bool = undefined;
    if (samples.len > kept_mask.len) {
        // Degenerate fallback: just return naive mean.
        return .{ .mean_u16 = clampToPixel(mean), .kept = samples.len };
    }
    for (kept_mask[0..samples.len]) |*k| k.* = true;
    var kept_count: usize = samples.len;

    var it: u32 = 0;
    while (it < iters and kept_count > 1) : (it += 1) {
        // Recompute mean + variance on kept samples.
        var s: f64 = 0;
        for (samples, 0..) |p, idx| {
            if (kept_mask[idx]) s += @as(f64, @floatFromInt(p));
        }
        const m = s / @as(f64, @floatFromInt(kept_count));
        var var_sum: f64 = 0;
        for (samples, 0..) |p, idx| {
            if (kept_mask[idx]) {
                const d = @as(f64, @floatFromInt(p)) - m;
                var_sum += d * d;
            }
        }
        const variance = var_sum / @as(f64, @floatFromInt(kept_count));
        const std_dev = @sqrt(variance);
        const cutoff = sigma * std_dev;

        var new_kept: usize = 0;
        for (samples, 0..) |p, idx| {
            if (kept_mask[idx]) {
                const d = @abs(@as(f64, @floatFromInt(p)) - m);
                if (d <= cutoff) {
                    new_kept += 1;
                } else {
                    kept_mask[idx] = false;
                }
            }
        }

        // No samples rejected this iteration -> converged.
        if (new_kept == kept_count) {
            mean = m;
            break;
        }
        kept_count = new_kept;
        mean = m;
    }

    // Final mean over surviving samples.
    if (kept_count > 0) {
        var s: f64 = 0;
        for (samples, 0..) |p, idx| {
            if (kept_mask[idx]) s += @as(f64, @floatFromInt(p));
        }
        mean = s / @as(f64, @floatFromInt(kept_count));
    }
    return .{ .mean_u16 = clampToPixel(mean), .kept = @intCast(kept_count) };
}

fn clampToPixel(m: f64) u16 {
    if (m < 0) return 0;
    if (m > @as(f64, @floatFromInt(pixels_mod.MAX_PIXEL_VALUE))) return pixels_mod.MAX_PIXEL_VALUE;
    return @intFromFloat(@round(m));
}

test "sigmaClipMean rejects single outlier with tight sigma" {
    // Cluster of 5 samples near 1000, plus one massive outlier.
    const samples = [_]u16{ 1000, 1002, 998, 1001, 999, 9000 };
    const r = sigmaClipMean(&samples, 2.0, 3);
    // After clipping, outlier should be gone; mean should be ~1000.
    try std.testing.expect(r.kept == 5);
    try std.testing.expect(r.mean_u16 >= 998 and r.mean_u16 <= 1002);
}

test "sigmaClipMean keeps all samples when within sigma" {
    const samples = [_]u16{ 100, 102, 98, 101, 99 };
    const r = sigmaClipMean(&samples, 3.0, 2);
    try std.testing.expectEqual(@as(u64, 5), r.kept);
}

test "sigmaClipMean handles empty input" {
    const samples = [_]u16{};
    const r = sigmaClipMean(&samples, 3.0, 2);
    try std.testing.expectEqual(@as(u16, 0), r.mean_u16);
    try std.testing.expectEqual(@as(u64, 0), r.kept);
}

/// median-frame INPUT.mlv [INPUT2.mlv ...] OUT
/// Per-pixel median across every decoded VIDF frame. More robust than
/// `mean-frame` against outliers (cosmic rays, hot pixels firing in
/// just one exposure). Output format inferred from extension same as
/// mean-frame.
fn runMedianFrame(allocator: std.mem.Allocator, args: [][:0]u8) !u8 {
    const stderr = std.io.getStdErr().writer();
    if (args.len < 2) {
        try stderr.print("raw-stack median-frame: expected INPUT.mlv [INPUT2.mlv ...] OUT\n", .{});
        return 2;
    }
    const out_path = args[args.len - 1];
    const inputs = args[0 .. args.len - 1];

    var dims: ?struct { w: i32, h: i32 } = null;

    // samples[pixel_idx] = list of values across frames.
    var samples = std.ArrayList(std.ArrayList(u16)).init(allocator);
    defer {
        for (samples.items) |*s| s.deinit();
        samples.deinit();
    }
    var samples_initialized = false;

    for (inputs) |in_path| {
        var file = std.fs.cwd().openFile(in_path, .{}) catch |err| {
            try stderr.print("raw-stack median-frame: cannot open '{s}': {s}\n", .{ in_path, @errorName(err) });
            return 1;
        };
        defer file.close();

        var reader = mlv.Reader.init(allocator, file.reader().any());
        defer reader.deinit();

        while (try reader.next()) |hdr| {
            if (mlv.blockTypeEquals(hdr.block_type, "RAWI")) {
                const r = try reader.readRawi(hdr);
                if (r.bits_per_pixel != 14) {
                    try stderr.print(
                        "raw-stack median-frame: '{s}' bits_per_pixel={d}; only 14 supported\n",
                        .{ in_path, r.bits_per_pixel },
                    );
                    return 1;
                }
                if (dims) |d| {
                    if (d.w != r.width or d.h != r.height) {
                        try stderr.print(
                            "raw-stack median-frame: dimension mismatch '{s}' {d}x{d} vs {d}x{d}\n",
                            .{ in_path, r.width, r.height, d.w, d.h },
                        );
                        return 1;
                    }
                } else dims = .{ .w = r.width, .h = r.height };
            } else if (mlv.blockTypeEquals(hdr.block_type, "VIDF")) {
                const r = try reader.readVidfWithPayload(hdr);
                defer allocator.free(r.payload);
                if (r.payload.len == 0 or r.payload.len % pixels_mod.BYTES_PER_BLOCK != 0) continue;

                const px = try pixels_mod.unpackBuffer(allocator, r.payload);
                defer allocator.free(px);

                if (!samples_initialized) {
                    try samples.ensureTotalCapacity(px.len);
                    var i: usize = 0;
                    while (i < px.len) : (i += 1) {
                        try samples.append(std.ArrayList(u16).init(allocator));
                    }
                    samples_initialized = true;
                } else if (samples.items.len != px.len) {
                    try stderr.print(
                        "raw-stack median-frame: VIDF pixel count varies ({d} vs {d})\n",
                        .{ px.len, samples.items.len },
                    );
                    return 1;
                }

                for (px, 0..) |p, i| try samples.items[i].append(p);
            } else {
                try reader.skipBlockBody(hdr);
            }
        }
    }

    if (!samples_initialized or samples.items.len == 0) {
        try stderr.print("raw-stack median-frame: no VIDF samples decoded\n", .{});
        return 1;
    }

    // Compute per-pixel median (sort + middle).
    const out_pixels = try allocator.alloc(u16, samples.items.len);
    defer allocator.free(out_pixels);
    var total_frames: u64 = 0;
    for (samples.items, 0..) |*s, i| {
        std.mem.sort(u16, s.items, {}, std.sort.asc(u16));
        const n = s.items.len;
        if (n == 0) {
            out_pixels[i] = 0;
            continue;
        }
        out_pixels[i] = if (n % 2 == 1)
            s.items[n / 2]
        else
            @intCast((@as(u32, s.items[n / 2 - 1]) + @as(u32, s.items[n / 2])) / 2);
        if (i == 0) total_frames = n;
    }

    var out_file = try std.fs.cwd().createFile(out_path, .{ .truncate = true });
    defer out_file.close();
    var w = out_file.writer();
    const is_fits = std.mem.endsWith(u8, out_path, ".fits") or std.mem.endsWith(u8, out_path, ".fit");

    if (is_fits) {
        if (dims == null) {
            try stderr.print("raw-stack median-frame: FITS output requires RAWI dimensions\n", .{});
            return 1;
        }
        const want = @as(usize, @intCast(dims.?.w)) * @as(usize, @intCast(dims.?.h));
        const fw: i32 = if (want == out_pixels.len) dims.?.w else @as(i32, @intCast(out_pixels.len));
        const fh: i32 = if (want == out_pixels.len) dims.?.h else 1;
        try fits.writeImage(w, out_pixels, .{
            .width = fw,
            .height = fh,
            .object = "median stack",
            .comments = &[_][]const u8{"Generated by raw-stack median-frame."},
        });
    } else {
        for (out_pixels) |p| try w.writeInt(u16, p, .little);
    }

    const stdout = std.io.getStdOut().writer();
    try stdout.print(
        "raw-stack median-frame: stacked {d} samples-per-pixel across {d} pixels @ {s}\n",
        .{ total_frames, out_pixels.len, out_path },
    );
    return 0;
}

/// Per-VIDF + aggregate RGGB plane statistics.
fn runBayerStats(allocator: std.mem.Allocator, args: [][:0]u8) !u8 {
    const stderr = std.io.getStdErr().writer();
    if (args.len != 1) {
        try stderr.print("raw-stack bayer-stats: expected 1 argument (path to MLV file)\n", .{});
        return 2;
    }

    var file = std.fs.cwd().openFile(args[0], .{}) catch |err| {
        try stderr.print("raw-stack bayer-stats: cannot open '{s}': {s}\n", .{ args[0], @errorName(err) });
        return 1;
    };
    defer file.close();

    var reader = mlv.Reader.init(allocator, file.reader().any());
    defer reader.deinit();

    const stdout = std.io.getStdOut().writer();
    var rawi: ?mlv.Rawi = null;

    // Aggregate plane sums across all frames in the file.
    var agg = [_]bayer.PlaneStats{
        .{ .plane = .r, .count = 0, .min = std.math.maxInt(u16), .max = 0, .sum = 0 },
        .{ .plane = .g1, .count = 0, .min = std.math.maxInt(u16), .max = 0, .sum = 0 },
        .{ .plane = .g2, .count = 0, .min = std.math.maxInt(u16), .max = 0, .sum = 0 },
        .{ .plane = .b, .count = 0, .min = std.math.maxInt(u16), .max = 0, .sum = 0 },
    };

    try stdout.print(
        "{s:<8} {s:<6} {s:<8} {s:<8} {s:<10}\n",
        .{ "frame", "plane", "min", "max", "mean" },
    );
    try stdout.print("{s}\n", .{"-" ** 48});

    var vidf_count: u64 = 0;
    while (try reader.next()) |hdr| {
        if (mlv.blockTypeEquals(hdr.block_type, "RAWI")) {
            rawi = try reader.readRawi(hdr);
            if (rawi.?.bits_per_pixel != 14) {
                try stderr.print("raw-stack bayer-stats: only 14-bit RAWI supported\n", .{});
                return 1;
            }
        } else if (mlv.blockTypeEquals(hdr.block_type, "VIDF")) {
            if (rawi == null) {
                try stderr.print("raw-stack bayer-stats: VIDF before RAWI; skipping\n", .{});
                try reader.skipBlockBody(hdr);
                continue;
            }
            const r = try reader.readVidfWithPayload(hdr);
            defer allocator.free(r.payload);
            if (r.payload.len == 0 or r.payload.len % pixels_mod.BYTES_PER_BLOCK != 0) continue;

            const px = try pixels_mod.unpackBuffer(allocator, r.payload);
            defer allocator.free(px);

            const w: usize = @intCast(rawi.?.width);
            const h: usize = @intCast(rawi.?.height);
            if (px.len != w * h) continue;

            const stats = try bayer.summarize(px, w, h);
            for (stats) |s| {
                try stdout.print(
                    "{d:<8} {s:<6} {d:<8} {d:<8} {d:<10}\n",
                    .{ r.vidf.frame_number, bayer.planeName(s.plane), s.min, s.max, s.mean() },
                );
                // Merge into aggregate.
                const idx = @intFromEnum(s.plane);
                var a = &agg[idx];
                a.count += s.count;
                a.sum += s.sum;
                if (s.min < a.min) a.min = s.min;
                if (s.max > a.max) a.max = s.max;
            }
            vidf_count += 1;
        } else {
            try reader.skipBlockBody(hdr);
        }
    }

    try stdout.print("\n{d} VIDF frames decoded\n", .{vidf_count});
    try stdout.print("Aggregate (across all frames):\n", .{});
    for (agg) |a| {
        const min_display = if (a.count > 0) a.min else 0;
        try stdout.print(
            "  {s:<6} count={d:<8} min={d:<6} max={d:<6} mean={d}\n",
            .{ bayer.planeName(a.plane), a.count, min_display, a.max, a.mean() },
        );
    }
    return 0;
}

/// mean-frame INPUT.mlv [INPUT2.mlv ...] OUT
/// Iterates VIDF blocks from every input MLV, unpacks 14-bit pixels,
/// computes per-pixel running mean, writes the result.
///
/// Output format inferred from extension: ".fits" / ".fit" -> FITS,
/// anything else -> raw u16 little-endian (compatible with numpy
/// `np.fromfile(dtype='<u2')`).
///
/// All inputs must agree on RAWI width/height.
fn runMeanFrame(allocator: std.mem.Allocator, args: [][:0]u8) !u8 {
    const stderr = std.io.getStdErr().writer();
    if (args.len < 2) {
        try stderr.print("raw-stack mean-frame: expected INPUT.mlv [INPUT2.mlv ...] OUT.bin\n", .{});
        return 2;
    }
    const out_path = args[args.len - 1];
    const inputs = args[0 .. args.len - 1];

    var dims: ?struct { w: i32, h: i32 } = null;
    var running_sum: ?[]u64 = null;
    var sample_count: u64 = 0;
    defer if (running_sum) |s| allocator.free(s);

    for (inputs) |in_path| {
        var file = std.fs.cwd().openFile(in_path, .{}) catch |err| {
            try stderr.print("raw-stack mean-frame: cannot open '{s}': {s}\n", .{ in_path, @errorName(err) });
            return 1;
        };
        defer file.close();

        var reader = mlv.Reader.init(allocator, file.reader().any());
        defer reader.deinit();

        while (try reader.next()) |hdr| {
            if (mlv.blockTypeEquals(hdr.block_type, "RAWI")) {
                const r = try reader.readRawi(hdr);
                if (r.bits_per_pixel != 14) {
                    try stderr.print(
                        "raw-stack mean-frame: '{s}' bits_per_pixel={d}; only 14 supported\n",
                        .{ in_path, r.bits_per_pixel },
                    );
                    return 1;
                }
                if (dims) |d| {
                    if (d.w != r.width or d.h != r.height) {
                        try stderr.print(
                            "raw-stack mean-frame: dimension mismatch '{s}' {d}x{d} vs {d}x{d}\n",
                            .{ in_path, r.width, r.height, d.w, d.h },
                        );
                        return 1;
                    }
                } else {
                    dims = .{ .w = r.width, .h = r.height };
                }
            } else if (mlv.blockTypeEquals(hdr.block_type, "VIDF")) {
                const r = try reader.readVidfWithPayload(hdr);
                defer allocator.free(r.payload);

                if (r.payload.len == 0) continue;
                if (r.payload.len % pixels_mod.BYTES_PER_BLOCK != 0) continue;

                const px = try pixels_mod.unpackBuffer(allocator, r.payload);
                defer allocator.free(px);

                if (running_sum == null) {
                    running_sum = try allocator.alloc(u64, px.len);
                    for (running_sum.?) |*s| s.* = 0;
                } else if (running_sum.?.len != px.len) {
                    try stderr.print(
                        "raw-stack mean-frame: VIDF pixel count varies between frames ({d} vs {d})\n",
                        .{ px.len, running_sum.?.len },
                    );
                    return 1;
                }

                for (px, running_sum.?) |p, *s| s.* += p;
                sample_count += 1;
            } else {
                try reader.skipBlockBody(hdr);
            }
        }
    }

    if (running_sum == null or sample_count == 0) {
        try stderr.print("raw-stack mean-frame: no VIDF samples decoded\n", .{});
        return 1;
    }

    // Compute per-pixel mean (integer-rounded).
    const out_pixels = try allocator.alloc(u16, running_sum.?.len);
    defer allocator.free(out_pixels);
    for (running_sum.?, out_pixels) |s, *o| {
        const m = s / sample_count;
        o.* = @intCast(@min(m, @as(u64, pixels_mod.MAX_PIXEL_VALUE)));
    }

    var out_file = try std.fs.cwd().createFile(out_path, .{ .truncate = true });
    defer out_file.close();
    var w = out_file.writer();

    const is_fits = std.mem.endsWith(u8, out_path, ".fits") or std.mem.endsWith(u8, out_path, ".fit");

    if (is_fits) {
        if (dims == null) {
            try stderr.print("raw-stack mean-frame: FITS output requires RAWI block (width/height) in input\n", .{});
            return 1;
        }
        // Sanity check: the unpacked pixel count must match w*h. For
        // the fixture this won't, since the fixture's payload is far
        // smaller than 1920x1080. Adapt output dimensions to the
        // actual pixel count when they disagree (single-row layout).
        const want_pixels = @as(usize, @intCast(dims.?.w)) * @as(usize, @intCast(dims.?.h));
        if (want_pixels != out_pixels.len) {
            // Fall back to a 1D / single-row image with width = pixel count.
            try fits.writeImage(w, out_pixels, .{
                .width = @as(i32, @intCast(out_pixels.len)),
                .height = 1,
                .object = "mean stack",
                .comments = &[_][]const u8{
                    "Generated by raw-stack mean-frame.",
                    "Pixel count did not match RAWI width*height; using 1-row layout.",
                },
            });
        } else {
            try fits.writeImage(w, out_pixels, .{
                .width = dims.?.w,
                .height = dims.?.h,
                .object = "mean stack",
                .comments = &[_][]const u8{
                    "Generated by raw-stack mean-frame.",
                },
            });
        }
    } else {
        for (out_pixels) |p| try w.writeInt(u16, p, .little);
    }

    const stdout = std.io.getStdOut().writer();
    try stdout.print(
        "raw-stack mean-frame: stacked {d} VIDF frames -> {d} pixels @ {s}\n",
        .{ sample_count, out_pixels.len, out_path },
    );
    if (dims) |d| {
        const fmt = if (is_fits) "FITS" else "raw u16 LE";
        try stdout.print(
            "  (raw geometry from RAWI: {d}x{d}; output format: {s})\n",
            .{ d.w, d.h, fmt },
        );
    }
    return 0;
}

fn runPixelStats(allocator: std.mem.Allocator, args: [][:0]u8) !u8 {
    const stderr = std.io.getStdErr().writer();
    if (args.len != 1) {
        try stderr.print("raw-stack pixel-stats: expected 1 argument (path to MLV file)\n", .{});
        return 2;
    }

    var file = std.fs.cwd().openFile(args[0], .{}) catch |err| {
        try stderr.print("raw-stack pixel-stats: cannot open '{s}': {s}\n", .{ args[0], @errorName(err) });
        return 1;
    };
    defer file.close();

    var reader = mlv.Reader.init(allocator, file.reader().any());
    defer reader.deinit();

    const stdout = std.io.getStdOut().writer();

    var rawi_found = false;
    var bits_per_pixel: i32 = 14; // default

    // Track aggregate stats across all VIDF frames.
    var frame_count: u64 = 0;
    var total_pixels: u64 = 0;
    var agg_min: u16 = pixels_mod.MAX_PIXEL_VALUE;
    var agg_max: u16 = 0;
    var agg_sum: u64 = 0;

    try stdout.print(
        "{s:<8} {s:<10} {s:<8} {s:<8} {s:<10}\n",
        .{ "n", "pixels", "min", "max", "mean" },
    );
    try stdout.print("{s}\n", .{"-" ** 48});

    while (try reader.next()) |hdr| {
        if (mlv.blockTypeEquals(hdr.block_type, "RAWI")) {
            const r = try reader.readRawi(hdr);
            rawi_found = true;
            bits_per_pixel = r.bits_per_pixel;
            if (bits_per_pixel != 14) {
                try stderr.print(
                    "raw-stack pixel-stats: bits_per_pixel={d}; only 14 is supported (see TIN-1223 for other formats)\n",
                    .{bits_per_pixel},
                );
                return 1;
            }
        } else if (mlv.blockTypeEquals(hdr.block_type, "VIDF")) {
            const r = try reader.readVidfWithPayload(hdr);
            defer allocator.free(r.payload);

            if (r.payload.len == 0) continue;
            if (r.payload.len % pixels_mod.BYTES_PER_BLOCK != 0) {
                try stderr.print(
                    "raw-stack pixel-stats: VIDF frame {d} payload {d} bytes not a multiple of {d}; skipping\n",
                    .{ r.vidf.frame_number, r.payload.len, pixels_mod.BYTES_PER_BLOCK },
                );
                continue;
            }

            const px = try pixels_mod.unpackBuffer(allocator, r.payload);
            defer allocator.free(px);

            var fmin: u16 = pixels_mod.MAX_PIXEL_VALUE;
            var fmax: u16 = 0;
            var fsum: u64 = 0;
            for (px) |p| {
                if (p < fmin) fmin = p;
                if (p > fmax) fmax = p;
                fsum += p;
            }
            const fmean: u64 = if (px.len > 0) fsum / px.len else 0;
            try stdout.print(
                "{d:<8} {d:<10} {d:<8} {d:<8} {d:<10}\n",
                .{ r.vidf.frame_number, px.len, fmin, fmax, fmean },
            );
            frame_count += 1;
            total_pixels += px.len;
            if (fmin < agg_min) agg_min = fmin;
            if (fmax > agg_max) agg_max = fmax;
            agg_sum += fsum;
        } else {
            try reader.skipBlockBody(hdr);
        }
    }

    try stdout.print("\n{d} VIDF frames, {d} total pixels (14-bit)\n", .{ frame_count, total_pixels });
    if (total_pixels > 0) {
        const agg_mean = agg_sum / total_pixels;
        try stdout.print("aggregate pixel stats: min={d} max={d} mean={d}\n", .{ agg_min, agg_max, agg_mean });
    }
    if (!rawi_found) {
        try stdout.print("(no RAWI block in stream; assumed 14-bit)\n", .{});
    }
    return 0;
}

fn runInfo(allocator: std.mem.Allocator, args: [][:0]u8) !u8 {
    const stderr = std.io.getStdErr().writer();
    if (args.len != 1) {
        try stderr.print("raw-stack info: expected 1 argument (path to MLV file)\n", .{});
        return 2;
    }

    var file = std.fs.cwd().openFile(args[0], .{}) catch |err| {
        try stderr.print("raw-stack info: cannot open '{s}': {s}\n", .{ args[0], @errorName(err) });
        return 1;
    };
    defer file.close();

    var reader = mlv.Reader.init(allocator, file.reader().any());
    defer reader.deinit();

    const stdout = std.io.getStdOut().writer();
    var rawi_found = false;
    var rawi: mlv.Rawi = undefined;
    var vidf_count: u64 = 0;
    var rawx_count: u64 = 0;
    var aflg_count: u64 = 0;

    while (try reader.next()) |hdr| {
        if (mlv.blockTypeEquals(hdr.block_type, "RAWI")) {
            rawi = try reader.readRawi(hdr);
            rawi_found = true;
        } else if (mlv.blockTypeEquals(hdr.block_type, "VIDF")) {
            vidf_count += 1;
            try reader.skipBlockBody(hdr);
        } else if (mlv.blockTypeEquals(hdr.block_type, "RAWX")) {
            rawx_count += 1;
            try reader.skipBlockBody(hdr);
        } else if (mlv.blockTypeEquals(hdr.block_type, "AFLG")) {
            aflg_count += 1;
            try reader.skipBlockBody(hdr);
        } else {
            try reader.skipBlockBody(hdr);
        }
    }

    if (rawi_found) {
        try stdout.print(
            "RAWI: {d}x{d} (logical {d}x{d}), {d}-bit, frame_size={d}, pitch={d}\n",
            .{ rawi.width, rawi.height, rawi.x_res, rawi.y_res, rawi.bits_per_pixel, rawi.frame_size, rawi.pitch },
        );
    } else {
        try stdout.print("RAWI: not present (no per-camera raw geometry)\n", .{});
    }
    try stdout.print("VIDF blocks: {d}\n", .{vidf_count});
    try stdout.print("RAWX blocks: {d}\n", .{rawx_count});
    try stdout.print("AFLG blocks: {d}\n", .{aflg_count});
    return 0;
}

fn runRawStats(allocator: std.mem.Allocator, args: [][:0]u8) !u8 {
    const stderr = std.io.getStdErr().writer();
    if (args.len != 1) {
        try stderr.print("raw-stack raw-stats: expected 1 argument (path to MLV file)\n", .{});
        return 2;
    }

    var file = std.fs.cwd().openFile(args[0], .{}) catch |err| {
        try stderr.print("raw-stack raw-stats: cannot open '{s}': {s}\n", .{ args[0], @errorName(err) });
        return 1;
    };
    defer file.close();

    var reader = mlv.Reader.init(allocator, file.reader().any());
    defer reader.deinit();

    const stdout = std.io.getStdOut().writer();
    try stdout.print(
        "{s:<8} {s:<10} {s:<8} {s:<8} {s:<10}\n",
        .{ "n", "payload", "min", "max", "mean" },
    );
    try stdout.print("{s}\n", .{"-" ** 50});

    var frame_count: u64 = 0;
    var total_bytes: u64 = 0;
    var agg_min: u8 = 255;
    var agg_max: u8 = 0;
    var agg_sum: u64 = 0;

    while (try reader.next()) |hdr| {
        if (mlv.blockTypeEquals(hdr.block_type, "VIDF")) {
            const r = try reader.readVidfWithPayload(hdr);
            defer allocator.free(r.payload);

            var fmin: u8 = 255;
            var fmax: u8 = 0;
            var fsum: u64 = 0;
            for (r.payload) |b| {
                if (b < fmin) fmin = b;
                if (b > fmax) fmax = b;
                fsum += b;
            }
            const fmean: u64 = if (r.payload.len > 0) fsum / r.payload.len else 0;
            try stdout.print(
                "{d:<8} {d:<10} {d:<8} {d:<8} {d:<10}\n",
                .{ r.vidf.frame_number, r.payload.len, fmin, fmax, fmean },
            );

            frame_count += 1;
            total_bytes += r.payload.len;
            if (r.payload.len > 0) {
                if (fmin < agg_min) agg_min = fmin;
                if (fmax > agg_max) agg_max = fmax;
                agg_sum += fsum;
            }
        } else {
            try reader.skipBlockBody(hdr);
        }
    }

    try stdout.print("\n{d} VIDF blocks, {d} total payload bytes\n", .{ frame_count, total_bytes });
    if (total_bytes > 0) {
        const agg_mean = agg_sum / total_bytes;
        try stdout.print("aggregate byte stats: min={d} max={d} mean={d}\n", .{ agg_min, agg_max, agg_mean });
    }
    return 0;
}

fn runFrames(allocator: std.mem.Allocator, args: [][:0]u8) !u8 {
    const stderr = std.io.getStdErr().writer();
    if (args.len != 1) {
        try stderr.print("raw-stack frames: expected 1 argument (path to MLV file)\n", .{});
        return 2;
    }

    var file = std.fs.cwd().openFile(args[0], .{}) catch |err| {
        try stderr.print("raw-stack frames: cannot open '{s}': {s}\n", .{ args[0], @errorName(err) });
        return 1;
    };
    defer file.close();

    var reader = mlv.Reader.init(allocator, file.reader().any());
    defer reader.deinit();

    const stdout = std.io.getStdOut().writer();
    try stdout.print(
        "{s:<8} {s:<16} {s:<10} {s:<8} {s:<8} {s:<8} {s:<8} {s:<10}\n",
        .{ "n", "ts", "size", "crop_x", "crop_y", "pan_x", "pan_y", "fSpace" },
    );
    try stdout.print("{s}\n", .{"-" ** 80});

    var count: u64 = 0;
    while (try reader.next()) |hdr| {
        if (mlv.blockTypeEquals(hdr.block_type, "VIDF")) {
            const v = try reader.readVidf(hdr);
            try stdout.print(
                "{d:<8} {d:<16} {d:<10} {d:<8} {d:<8} {d:<8} {d:<8} {d:<10}\n",
                .{ v.frame_number, hdr.timestamp, hdr.block_size, v.cropPos_x, v.cropPos_y, v.panPos_x, v.panPos_y, v.frameSpace },
            );
            count += 1;
        } else {
            try reader.skipBlockBody(hdr);
        }
    }
    try stdout.print("\n{d} VIDF blocks total\n", .{count});
    return 0;
}

fn runStack(allocator: std.mem.Allocator, args: [][:0]u8) !u8 {
    const stderr = std.io.getStdErr().writer();
    if (args.len < 1) {
        try stderr.print("raw-stack stack: expected at least 1 MLV file\n", .{});
        return 2;
    }

    var stats = std.ArrayList(stack_mod.FileStats).init(allocator);
    defer stats.deinit();

    for (args) |path| {
        const s = stack_mod.stackFile(allocator, path, .{}) catch |err| {
            try stderr.print("raw-stack stack: '{s}': {s}\n", .{ path, @errorName(err) });
            return 1;
        };
        try stats.append(s);
    }

    try stack_mod.renderStats(std.io.getStdOut().writer(), stats.items);
    return 0;
}

fn runFixture(args: [][:0]u8) !u8 {
    const stderr = std.io.getStdErr().writer();
    if (args.len < 1 or args.len > 2) {
        try stderr.print("raw-stack fixture: expected OUT [complex|simple]\n", .{});
        return 2;
    }
    var complex = false;
    if (args.len == 2) {
        if (std.mem.eql(u8, args[1], "complex")) complex = true else if (std.mem.eql(u8, args[1], "simple")) complex = false else {
            try stderr.print("raw-stack fixture: 2nd arg must be 'complex' or 'simple'\n", .{});
            return 2;
        }
    }

    var file = std.fs.cwd().createFile(args[0], .{ .truncate = true }) catch |err| {
        try stderr.print("raw-stack fixture: cannot create '{s}': {s}\n", .{ args[0], @errorName(err) });
        return 1;
    };
    defer file.close();
    try fixture.writeFixture(file.writer(), .{ .include_complex_patterns = complex });
    try std.io.getStdOut().writer().print(
        "raw-stack fixture: wrote {s} MLV to '{s}'\n",
        .{ if (complex) "complex" else "simple", args[0] },
    );
    return 0;
}

fn runInspect(allocator: std.mem.Allocator, args: [][:0]u8) !u8 {
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    if (args.len != 1) {
        try stderr.print("raw-stack inspect: expected 1 argument (path to MLV file)\n", .{});
        return 2;
    }

    var file = std.fs.cwd().openFile(args[0], .{}) catch |err| {
        try stderr.print("raw-stack inspect: cannot open '{s}': {s}\n", .{ args[0], @errorName(err) });
        return 1;
    };
    defer file.close();

    var reader = mlv.Reader.init(allocator, file.reader().any());
    defer reader.deinit();

    var summary = mlv.Summary{};
    while (try reader.next()) |hdr| {
        summary.observe(hdr);
        if (mlv.blockTypeEquals(hdr.block_type, "RAWX")) {
            const rawx = try reader.readRawx(hdr);
            try stdout.print(
                "RAWX ts={d:>15} ver={d} fields=0x{x:0>8} analog={d} digital={d} exposure_ns={d}\n",
                .{
                    hdr.timestamp,
                    rawx.version,
                    rawx.fields_present,
                    rawx.analog_gain,
                    rawx.digital_gain,
                    rawx.exposure_ns,
                },
            );
        } else if (mlv.blockTypeEquals(hdr.block_type, "AFLG")) {
            const aflg = try reader.readAflg(hdr);
            try stdout.print(
                "AFLG ts={d:>15} event={d} fields=0x{x:0>8} af_point={d} focus_mag={d}\n",
                .{
                    hdr.timestamp,
                    aflg.event_type,
                    aflg.fields_present,
                    aflg.af_point,
                    aflg.focus_magnitude,
                },
            );
        } else {
            try reader.skipBlockBody(hdr);
        }
    }

    try stdout.print("\nSummary:\n", .{});
    try summary.print(stdout);
    return 0;
}

test "version flag is recognised" {
    try std.testing.expectEqual(@as(?Subcommand, .version), parseSubcommand("--version"));
}
