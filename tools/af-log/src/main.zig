//! af-log — host CLI for AFLG MLV blocks from magiclantern_hydrogen.
//!
//! Sprint C4 / Linear TIN-1230. See
//! developer_guide/10_00_af_lens_telemetry.md for the property surface
//! and `mlv_aflg_hdr_t` in modules/raw_video/mlv_rec/mlv.h for the
//! wire format.
//!
//! Subcommands:
//!   replay FILE.mlv      Annotated text timeline of AFLG events
//!   summary FILE.mlv     Counts per event type
//!   detect FILE.mlv      Detect focus-bracket / tracking / hunting (stub)

const std = @import("std");
const mlv = @import("mlv.zig");
const tl = @import("timeline.zig");

const VERSION = "0.1.0";

const Subcommand = enum {
    help,
    version,
    replay,
    summary,
    detect,
};

fn parseSubcommand(arg: []const u8) ?Subcommand {
    const map = .{
        .{ "help", .help },
        .{ "--help", .help },
        .{ "-h", .help },
        .{ "version", .version },
        .{ "--version", .version },
        .{ "-V", .version },
        .{ "replay", .replay },
        .{ "summary", .summary },
        .{ "detect", .detect },
    };
    inline for (map) |entry| {
        if (std.mem.eql(u8, arg, entry[0])) return entry[1];
    }
    return null;
}

fn printUsage(w: anytype) !void {
    try w.print(
        \\af-log {s} — AF/lens telemetry CLI for magiclantern_hydrogen
        \\
        \\Usage: af-log <subcommand> [args...]
        \\
        \\Subcommands:
        \\  replay FILE.mlv     Annotated text timeline of AFLG events
        \\  summary FILE.mlv    Counts per event type
        \\  detect FILE.mlv     Detect focus-bracket / tracking / hunting patterns (stub)
        \\
        \\Global flags:
        \\  --help, -h          This message
        \\  --version, -V       Print version
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
        try stderr.print("af-log: unknown subcommand '{s}'\n\n", .{args[1]});
        try printUsage(stderr);
        return 2;
    };

    switch (subcommand) {
        .help => {
            try printUsage(stdout);
            return 0;
        },
        .version => {
            try stdout.print("af-log {s}\n", .{VERSION});
            return 0;
        },
        .replay => return try runReplay(allocator, args[2..]),
        .summary => return try runSummary(allocator, args[2..]),
        .detect => {
            try stderr.print("af-log detect: not yet implemented (TIN-1230).\n", .{});
            try stderr.print("Pattern classifier (focus-bracket / tracking / hunting) is the next slice.\n", .{});
            return 1;
        },
    }
}

fn openFile(args: [][:0]u8, name: []const u8) !std.fs.File {
    const stderr = std.io.getStdErr().writer();
    if (args.len != 1) {
        try stderr.print("af-log {s}: expected 1 argument (path to MLV file)\n", .{name});
        return error.UsageError;
    }
    return std.fs.cwd().openFile(args[0], .{}) catch |err| {
        try stderr.print("af-log {s}: cannot open '{s}': {s}\n", .{ name, args[0], @errorName(err) });
        return error.OpenFailed;
    };
}

fn runReplay(allocator: std.mem.Allocator, args: [][:0]u8) !u8 {
    var file = openFile(args, "replay") catch return 2;
    defer file.close();

    var reader = mlv.Reader.init(allocator, file.reader().any());
    defer reader.deinit();

    const stdout = std.io.getStdOut().writer();
    try tl.renderHeader(stdout);

    var seen_aflg: u64 = 0;
    while (try reader.next()) |hdr| {
        if (mlv.blockTypeEquals(hdr.block_type, "AFLG")) {
            const aflg = try reader.readAflg(hdr);
            try tl.renderRow(stdout, hdr.timestamp, aflg);
            seen_aflg += 1;
        } else {
            try reader.skipBlockBody(hdr);
        }
    }

    if (seen_aflg == 0) {
        const stderr = std.io.getStdErr().writer();
        try stderr.print("af-log replay: no AFLG blocks in file (is af_logger emitting?)\n", .{});
        return 1;
    }
    return 0;
}

fn runSummary(allocator: std.mem.Allocator, args: [][:0]u8) !u8 {
    var file = openFile(args, "summary") catch return 2;
    defer file.close();

    var reader = mlv.Reader.init(allocator, file.reader().any());
    defer reader.deinit();

    var counts: [10]u64 = .{0} ** 10;
    var total: u64 = 0;
    while (try reader.next()) |hdr| {
        if (mlv.blockTypeEquals(hdr.block_type, "AFLG")) {
            const aflg = try reader.readAflg(hdr);
            const idx = if (aflg.event_type < counts.len) aflg.event_type else 0;
            counts[idx] += 1;
            total += 1;
        } else {
            try reader.skipBlockBody(hdr);
        }
    }

    const stdout = std.io.getStdOut().writer();
    try stdout.print("af-log summary: {d} AFLG blocks total\n", .{total});
    const names = [_][]const u8{
        "(invalid event=0)",
        "HALF_PRESS",
        "FOCUS_DONE",
        "FOCUS_DATA",
        "AF_POINT_CHANGE",
        "AF_AREA_CHANGE",
        "APERTURE_CHANGE",
        "IS_STATE_CHANGE",
        "LENS_DYNAMIC",
        "HSP_COUNTDOWN",
    };
    for (counts, 0..) |n, i| {
        if (n > 0) try stdout.print("  {s:<18} {d}\n", .{ names[i], n });
    }
    return 0;
}

test "version flag" {
    try std.testing.expectEqual(@as(?Subcommand, .version), parseSubcommand("--version"));
}
