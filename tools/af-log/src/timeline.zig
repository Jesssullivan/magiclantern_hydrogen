//! Human-readable AFLG event timeline.

const std = @import("std");
const mlv = @import("mlv.zig");

pub fn renderHeader(w: anytype) !void {
    try w.print(
        "{s:<18} {s:<16} {s:<10} {s:<10} {s:<10}\n",
        .{ "ts", "event", "af_point", "focus_mag", "extra" },
    );
    try w.print("{s}\n", .{"-" ** 78});
}

pub fn renderRow(w: anytype, timestamp: u64, aflg: mlv.Aflg) !void {
    const name = eventName(aflg.event_type);
    try w.print("{d:<18} {s:<16} {d:<10} {d:<10} ", .{ timestamp, name, aflg.af_point, aflg.focus_magnitude });

    var first = true;
    if ((aflg.fields_present & mlv.Aflg.HAS_DYNAMIC_LENS) != 0) {
        try writeKv(w, &first, "near", aflg.focus_near);
        try writeKv(w, &first, "far", aflg.focus_far);
        try writeKv(w, &first, "pos", aflg.focus_pos);
        try writeKv(w, &first, "fl", aflg.focal_length);
    }
    if ((aflg.fields_present & mlv.Aflg.HAS_IS_STATE) != 0)
        try writeKv(w, &first, "is", aflg.is_state);
    if ((aflg.fields_present & mlv.Aflg.HAS_PHYSICAL_SWITCH) != 0)
        try writeKv(w, &first, "afmf", aflg.af_mf_physical);
    if ((aflg.fields_present & mlv.Aflg.HAS_AFMA) != 0)
        try writeSigned(w, &first, "afma", aflg.afma_offset);
    if (aflg.aperture_raw != 0)
        try writeKv(w, &first, "ap", aflg.aperture_raw);
    if (aflg.hsp_countdown != 0)
        try writeKv(w, &first, "hsp", aflg.hsp_countdown);

    try w.print("\n", .{});
}

fn writeKv(w: anytype, first: *bool, key: []const u8, value: anytype) !void {
    if (!first.*) try w.print(" ", .{});
    first.* = false;
    try w.print("{s}={d}", .{ key, value });
}

fn writeSigned(w: anytype, first: *bool, key: []const u8, value: i32) !void {
    if (!first.*) try w.print(" ", .{});
    first.* = false;
    try w.print("{s}={d}", .{ key, value });
}

fn eventName(event_type: u16) []const u8 {
    return switch (event_type) {
        1 => "HALF_PRESS",
        2 => "FOCUS_DONE",
        3 => "FOCUS_DATA",
        4 => "AF_POINT",
        5 => "AF_AREA",
        6 => "APERTURE",
        7 => "IS_STATE",
        8 => "LENS_DYN",
        9 => "HSP_COUNTDOWN",
        else => "?",
    };
}
