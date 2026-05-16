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

const VERSION = "0.1.0";

const Subcommand = enum {
    help,
    version,
    inspect,
    stack,
    demosaic_skip,
    calibrate,
    fixture,
    frames,
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
    }
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
