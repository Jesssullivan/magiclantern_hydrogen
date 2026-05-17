//! Bayer CFA plane decomposition for ML's RGGB sensors.
//!
//! Canon 5D2/5D3/5D4 (and most Canon DSLRs) use the standard RGGB
//! Bayer pattern:
//!
//!   row 0:  R  G1 R  G1 ...
//!   row 1:  G2 B  G2 B  ...
//!   row 2:  R  G1 R  G1 ...
//!   row 3:  G2 B  G2 B  ...
//!
//! i.e. for (x, y):
//!   even y, even x -> R
//!   even y, odd  x -> G1
//!   odd  y, even x -> G2
//!   odd  y, odd  x -> B
//!
//! Each Bayer plane has width / 2 by height / 2 samples.

const std = @import("std");

pub const Plane = enum { r, g1, g2, b };

pub fn planeOf(x: usize, y: usize) Plane {
    const x_even = (x & 1) == 0;
    const y_even = (y & 1) == 0;
    if (y_even and x_even) return .r;
    if (y_even and !x_even) return .g1;
    if (!y_even and x_even) return .g2;
    return .b;
}

pub const PlaneStats = struct {
    plane: Plane,
    count: u64,
    min: u16,
    max: u16,
    sum: u64,

    pub fn mean(self: PlaneStats) u64 {
        return if (self.count > 0) self.sum / self.count else 0;
    }
};

/// Compute per-plane min/max/mean across a width x height RGGB image
/// stored row-major in `pixels`.
pub fn summarize(pixels: []const u16, width: usize, height: usize) ![4]PlaneStats {
    if (pixels.len != width * height) return error.PixelCountMismatch;

    var result: [4]PlaneStats = [_]PlaneStats{
        .{ .plane = .r, .count = 0, .min = std.math.maxInt(u16), .max = 0, .sum = 0 },
        .{ .plane = .g1, .count = 0, .min = std.math.maxInt(u16), .max = 0, .sum = 0 },
        .{ .plane = .g2, .count = 0, .min = std.math.maxInt(u16), .max = 0, .sum = 0 },
        .{ .plane = .b, .count = 0, .min = std.math.maxInt(u16), .max = 0, .sum = 0 },
    };

    var y: usize = 0;
    while (y < height) : (y += 1) {
        var x: usize = 0;
        while (x < width) : (x += 1) {
            const p = pixels[y * width + x];
            const idx: usize = @intFromEnum(planeOf(x, y));
            var s = &result[idx];
            s.count += 1;
            s.sum += p;
            if (p < s.min) s.min = p;
            if (p > s.max) s.max = p;
        }
    }

    // Replace untouched min with 0 for empty planes (shouldn't happen
    // with a valid even-size sensor, but defensive).
    for (&result) |*s| {
        if (s.count == 0) s.min = 0;
    }
    return result;
}

pub fn planeName(p: Plane) []const u8 {
    return switch (p) {
        .r => "R",
        .g1 => "G1",
        .g2 => "G2",
        .b => "B",
    };
}

test "RGGB plane assignment matches Bayer convention" {
    try std.testing.expectEqual(Plane.r, planeOf(0, 0));
    try std.testing.expectEqual(Plane.g1, planeOf(1, 0));
    try std.testing.expectEqual(Plane.g2, planeOf(0, 1));
    try std.testing.expectEqual(Plane.b, planeOf(1, 1));
    try std.testing.expectEqual(Plane.r, planeOf(2, 2));
    try std.testing.expectEqual(Plane.b, planeOf(3, 3));
}

test "summarize splits 4x4 image into 4 planes of 4 samples each" {
    var px: [16]u16 = .{
        // y=0
        100, 200, 100, 200,
        // y=1
        50,  300, 50,  300,
        // y=2
        100, 200, 100, 200,
        // y=3
        50,  300, 50,  300,
    };
    const stats = try summarize(&px, 4, 4);
    try std.testing.expectEqual(@as(u64, 4), stats[@intFromEnum(Plane.r)].count);
    try std.testing.expectEqual(@as(u64, 4), stats[@intFromEnum(Plane.g1)].count);
    try std.testing.expectEqual(@as(u64, 4), stats[@intFromEnum(Plane.g2)].count);
    try std.testing.expectEqual(@as(u64, 4), stats[@intFromEnum(Plane.b)].count);
    try std.testing.expectEqual(@as(u16, 100), stats[@intFromEnum(Plane.r)].min);
    try std.testing.expectEqual(@as(u16, 100), stats[@intFromEnum(Plane.r)].max);
    try std.testing.expectEqual(@as(u16, 200), stats[@intFromEnum(Plane.g1)].min);
    try std.testing.expectEqual(@as(u16, 50), stats[@intFromEnum(Plane.g2)].max);
    try std.testing.expectEqual(@as(u16, 300), stats[@intFromEnum(Plane.b)].mean());
}
