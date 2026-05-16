//! Pattern detection on AFLG timelines.
//!
//! Classifies sequences of AFLG events into named patterns so downstream
//! consumers (the future robotic-optics actuator, manual review, post
//! analysis) can find interesting moments without scrubbing entire
//! captures.
//!
//! Today's classifiers:
//!   - **focus_bracket**: many FOCUS_DATA events within a short window
//!   - **tracking_dwell**: AF_POINT_CHANGE followed by FOCUS_DONE
//!     within a tight window
//!   - **hunting**: rapid focus_magnitude oscillation
//!
//! Operates on the in-memory event stream produced by reading AFLG
//! blocks from an MLV file. Time is in hardware ticks (us-granularity
//! per `mlv_hdr_t.timestamp`).

const std = @import("std");
const mlv = @import("mlv.zig");

pub const Event = struct {
    ts: u64,
    aflg: mlv.Aflg,
};

pub const Pattern = enum {
    focus_bracket,
    tracking_dwell,
    hunting,

    pub fn label(self: Pattern) []const u8 {
        return switch (self) {
            .focus_bracket => "focus_bracket",
            .tracking_dwell => "tracking_dwell",
            .hunting => "hunting",
        };
    }
};

pub const Detection = struct {
    pattern: Pattern,
    start_ts: u64,
    end_ts: u64,
    event_count: u32,
};

pub const Options = struct {
    /// Detection windows in hardware ticks (matching ts_us granularity).
    bracket_window_us: u64 = 1_000_000, // 1 second
    bracket_min_events: u32 = 3,

    tracking_window_us: u64 = 100_000, // 100 ms

    hunting_window_us: u64 = 500_000, // 500 ms
    hunting_min_reversals: u32 = 3,
};

pub fn detect(allocator: std.mem.Allocator, events: []const Event, opts: Options) ![]Detection {
    var out = std.ArrayList(Detection).init(allocator);
    errdefer out.deinit();

    try detectFocusBrackets(&out, events, opts);
    try detectTrackingDwell(&out, events, opts);
    try detectHunting(&out, events, opts);

    return out.toOwnedSlice();
}

fn isEvent(e: Event, want_type: u16) bool {
    return e.aflg.event_type == want_type;
}

/// "focus_bracket": >= bracket_min_events FOCUS_DATA events within
/// bracket_window_us of the first. Emits one Detection per cluster.
fn detectFocusBrackets(out: *std.ArrayList(Detection), events: []const Event, opts: Options) !void {
    var i: usize = 0;
    while (i < events.len) : (i += 1) {
        if (!isEvent(events[i], 3)) continue; // FOCUS_DATA

        var j: usize = i;
        var count: u32 = 0;
        while (j < events.len and events[j].ts - events[i].ts <= opts.bracket_window_us) : (j += 1) {
            if (isEvent(events[j], 3)) count += 1;
        }

        if (count >= opts.bracket_min_events) {
            try out.append(.{
                .pattern = .focus_bracket,
                .start_ts = events[i].ts,
                .end_ts = if (j > 0) events[j - 1].ts else events[i].ts,
                .event_count = count,
            });
            i = j; // skip past this cluster
        }
    }
}

/// "tracking_dwell": AF_POINT_CHANGE followed by FOCUS_DONE within
/// tracking_window_us. Indicates AF settled after a user-driven AF
/// point switch (vs hunting).
fn detectTrackingDwell(out: *std.ArrayList(Detection), events: []const Event, opts: Options) !void {
    var i: usize = 0;
    while (i < events.len) : (i += 1) {
        if (!isEvent(events[i], 4)) continue; // AF_POINT_CHANGE

        var j: usize = i + 1;
        while (j < events.len and events[j].ts - events[i].ts <= opts.tracking_window_us) : (j += 1) {
            if (isEvent(events[j], 2)) { // FOCUS_DONE
                try out.append(.{
                    .pattern = .tracking_dwell,
                    .start_ts = events[i].ts,
                    .end_ts = events[j].ts,
                    .event_count = 2,
                });
                break;
            }
        }
    }
}

/// "hunting": focus_magnitude reverses direction >= hunting_min_reversals
/// times within hunting_window_us. Indicates AF struggling to lock.
fn detectHunting(out: *std.ArrayList(Detection), events: []const Event, opts: Options) !void {
    if (events.len < opts.hunting_min_reversals) return;

    var window_start: usize = 0;
    var i: usize = 1;
    while (i < events.len) : (i += 1) {
        // Slide window forward.
        while (window_start < i and events[i].ts - events[window_start].ts > opts.hunting_window_us) {
            window_start += 1;
        }

        // Count reversals in [window_start, i].
        var reversals: u32 = 0;
        var prev_dir: i8 = 0;
        var k: usize = window_start + 1;
        while (k <= i) : (k += 1) {
            const before = events[k - 1].aflg.focus_magnitude;
            const after = events[k].aflg.focus_magnitude;
            const dir: i8 = if (after > before) 1 else if (after < before) -1 else 0;
            if (dir != 0 and prev_dir != 0 and dir != prev_dir) reversals += 1;
            if (dir != 0) prev_dir = dir;
        }

        if (reversals >= opts.hunting_min_reversals) {
            try out.append(.{
                .pattern = .hunting,
                .start_ts = events[window_start].ts,
                .end_ts = events[i].ts,
                .event_count = @intCast(i - window_start + 1),
            });
            i = i + 1; // advance past detected cluster, avoid repeats
            window_start = i;
        }
    }
}

pub fn renderDetections(w: anytype, detections: []const Detection) !void {
    if (detections.len == 0) {
        try w.print("No patterns detected.\n", .{});
        return;
    }
    try w.print(
        "{s:<16} {s:<18} {s:<18} {s:<8}\n",
        .{ "pattern", "start_ts", "end_ts", "events" },
    );
    try w.print("{s}\n", .{"-" ** 64});
    for (detections) |d| {
        try w.print(
            "{s:<16} {d:<18} {d:<18} {d:<8}\n",
            .{ d.pattern.label(), d.start_ts, d.end_ts, d.event_count },
        );
    }
}

test "detectFocusBrackets finds rapid FOCUS_DATA cluster" {
    const allocator = std.testing.allocator;
    var events = std.ArrayList(Event).init(allocator);
    defer events.deinit();

    // 5 FOCUS_DATA events within 500 ms.
    var i: u64 = 0;
    while (i < 5) : (i += 1) {
        try events.append(.{
            .ts = i * 100_000,
            .aflg = std.mem.zeroInit(mlv.Aflg, .{ .event_type = 3, .focus_magnitude = @as(u16, @intCast(100 + i)) }),
        });
    }

    const detections = try detect(allocator, events.items, .{});
    defer allocator.free(detections);

    try std.testing.expect(detections.len >= 1);
    var found = false;
    for (detections) |d| {
        if (d.pattern == .focus_bracket) found = true;
    }
    try std.testing.expect(found);
}

test "detectTrackingDwell finds AF_POINT_CHANGE -> FOCUS_DONE within window" {
    const allocator = std.testing.allocator;
    var events = std.ArrayList(Event).init(allocator);
    defer events.deinit();

    try events.append(.{
        .ts = 1_000_000,
        .aflg = std.mem.zeroInit(mlv.Aflg, .{ .event_type = 4 }), // AF_POINT_CHANGE
    });
    try events.append(.{
        .ts = 1_050_000,
        .aflg = std.mem.zeroInit(mlv.Aflg, .{ .event_type = 2 }), // FOCUS_DONE 50 ms later
    });

    const detections = try detect(allocator, events.items, .{});
    defer allocator.free(detections);

    var found = false;
    for (detections) |d| {
        if (d.pattern == .tracking_dwell) found = true;
    }
    try std.testing.expect(found);
}

test "detectHunting finds direction reversals" {
    const allocator = std.testing.allocator;
    var events = std.ArrayList(Event).init(allocator);
    defer events.deinit();

    // focus_magnitude: 100, 200, 100, 200, 100 -- 4 reversals in 400 ms.
    const mags = [_]u16{ 100, 200, 100, 200, 100 };
    var i: u64 = 0;
    for (mags) |m| {
        try events.append(.{
            .ts = i * 100_000,
            .aflg = std.mem.zeroInit(mlv.Aflg, .{ .event_type = 3, .focus_magnitude = m }),
        });
        i += 1;
    }

    const detections = try detect(allocator, events.items, .{});
    defer allocator.free(detections);

    var found = false;
    for (detections) |d| {
        if (d.pattern == .hunting) found = true;
    }
    try std.testing.expect(found);
}
