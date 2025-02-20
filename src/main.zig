const std = @import("std");
const rl = @import("raylib");

const FONT_SIZE: i32 = 20;
const SCREEN_LINES: i32 = 32;
const SCREEN_COLUMNS: i32 = 74;

var fontWidth: f32 = undefined;
var fontHeight: f32 = undefined;

var screenWidth: i32 = undefined;
var screenHeight: i32 = undefined;

var lineHeight: i32 = undefined;

var font: rl.Font = undefined;
var selectedLine: i32 = 0;

const ROM: type = struct {
    data: []u8,
    lines: i32,
    address: i32,
    symbols: [256]u8,
    loaded: bool,

    pub fn init(filename: [*:0]const u8) anyerror!ROM {
        const data: []u8 = try rl.loadFileData(filename);
        var symbols: [256]u8 = .{'.'} ** 256;

        for (0..256) |i| {
            if ((i >= 'A' and i <= 'Z') or (i >= 'a' and i <= 'z') or (i >= '0' and i <= '9')) {
                symbols[i] = @as(u8, @intCast(i));
            }
        }

        return ROM{
            .data = data,
            .address = 0,
            .lines = @intFromFloat(@ceil(@as(f32, @floatFromInt(data.len)) / 16.0)),
            .symbols = symbols,
            .loaded = true,
        };
    }

    pub fn deinit(self: *ROM) void {
        if (!self.loaded) {
            return;
        }

        rl.unloadFileData(self.data);

        self.address = 0;
        self.lines = 0;
        self.loaded = false;
    }
};

var rom: ROM = undefined;

pub fn drawTextCustom(text: [*:0]const u8, x: i32, y: i32, color: rl.Color) void {
    rl.drawTextEx(font, text, rl.Vector2{
        .x = @floatFromInt(x),
        .y = @floatFromInt(y),
    }, @floatFromInt(font.baseSize), 1, color);
}

pub fn drawFrame() anyerror!void {
    const viewTopLine: i32 = @divFloor(rom.address, 16);
    const viewBottomLine: i32 = viewTopLine + SCREEN_LINES - 1;

    var buffer = std.ArrayList(u8).init(std.heap.page_allocator);

    defer buffer.deinit();

    // Clear background
    rl.clearBackground(rl.Color.dark_gray);

    // Draw top bar
    rl.drawRectangle(0, 0, screenWidth, lineHeight, rl.Color.white);

    drawTextCustom(" Offset  00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F 0123456789ABCDEF", 0, 0, rl.Color.black);

    // Draw status bar
    rl.drawRectangle(0, screenHeight - lineHeight, screenWidth, lineHeight, rl.Color.white);

    try buffer.appendSlice(" Line: ");
    try buffer.writer().print("{d}/{d} ({d:.1}%)", .{ selectedLine + 1, rom.lines, (@as(f32, @floatFromInt(selectedLine)) + 1.0) * 100.0 / @as(f32, @floatFromInt(rom.lines)) });

    drawTextCustom(@ptrCast(buffer.items), 0, screenHeight - lineHeight, rl.Color.black);

    // Draw selected highlight
    if (selectedLine >= viewTopLine and selectedLine <= viewBottomLine) {
        rl.drawRectangle(0, (selectedLine - viewTopLine + 1) * lineHeight, screenWidth, lineHeight, rl.Color.light_gray);
    }

    // Draw contents
    buffer.clearRetainingCapacity();

    for (0..SCREEN_LINES) |i| {
        const address: i32 = rom.address + 0x10 * @as(i32, @intCast(i));
        var byteIndex: usize = undefined;

        if (address > rom.data.len) {
            continue;
        }

        try buffer.writer().print("{X:0>8} ", .{address});

        for (0..16) |j| {
            byteIndex = @as(usize, @intCast(address)) + j;

            if (byteIndex < rom.data.len) {
                try buffer.writer().print("{X:0>2} ", .{rom.data[byteIndex]});
            } else {
                try buffer.appendSlice("   ");
            }
        }

        for (0..16) |j| {
            byteIndex = @as(usize, @intCast(address)) + j;

            if (byteIndex < rom.data.len) {
                try buffer.append(rom.symbols[rom.data[byteIndex]]);
            } else {
                try buffer.append(' ');
            }
        }

        try buffer.append(0);

        drawTextCustom(@ptrCast(buffer.items), 0, @as(i32, @intCast(i + 1)) * lineHeight, if (viewTopLine + @as(i32, @intCast(i)) == selectedLine) rl.Color.black else rl.Color.light_gray);

        buffer.clearRetainingCapacity();
    }
}

pub fn main() anyerror!u8 {
    rl.initWindow(814, 640, "RayxEdigor");
    defer rl.closeWindow();

    font = try rl.loadFontEx("resources/firacode.ttf", FONT_SIZE, null);
    defer if (font.glyphCount > 0) rl.unloadFont(font);

    if (font.glyphCount == 0) {
        return 1;
    }

    const fontMeasurements: rl.Vector2 = rl.measureTextEx(font, "K", @floatFromInt(font.baseSize), 1);

    fontWidth = fontMeasurements.x;
    fontHeight = fontMeasurements.y;

    screenWidth = @intFromFloat(@round(SCREEN_COLUMNS * fontWidth + SCREEN_COLUMNS - 1));
    screenHeight = @intFromFloat(@round((SCREEN_LINES + 2) * fontHeight));

    lineHeight = @intFromFloat(@round(fontMeasurements.y));

    rl.setWindowSize(screenWidth, screenHeight);

    rom = try ROM.init("resources/test.txt");
    defer rom.deinit();

    if (!rom.loaded) {
        return 1;
    }

    rl.setTargetFPS(60);

    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();

        const viewTopLine = @divFloor(rom.address, 16);
        const viewBottomLine = viewTopLine + SCREEN_LINES - 1;

        if (rl.isKeyPressed(rl.KeyboardKey.down)) {
            if (selectedLine < rom.lines - 1) {
                selectedLine += 1;

                if (selectedLine > viewBottomLine) {
                    rom.address += 16;
                }
            }
        } else if (rl.isKeyPressed(rl.KeyboardKey.up)) {
            if (selectedLine > 0) {
                selectedLine -= 1;

                if (selectedLine < viewTopLine) {
                    rom.address -= 16;
                }
            }
        } else if (rl.isKeyPressed(rl.KeyboardKey.page_down)) {
            const newLine: i32 = @min(rom.lines - 1, selectedLine + SCREEN_LINES);
            const difference: i32 = newLine - selectedLine;

            selectedLine = newLine;

            var newAddress: i32 = rom.address;

            if (difference >= SCREEN_LINES) {
                newAddress += difference * 16;
            } else if (rom.lines > SCREEN_LINES) {
                newAddress = (rom.lines - SCREEN_LINES - 1) * 16;
            }

            try std.io.getStdOut().writer().print("NL: {d} D: {d} RA: {d} NA: {d}\n", .{ newLine, difference, rom.address, newAddress });

            rom.address = newAddress;
        } else if (rl.isKeyPressed(rl.KeyboardKey.page_up)) {
            const newLine: i32 = @max(selectedLine - SCREEN_LINES, 0);
            const difference: i32 = selectedLine - newLine;

            selectedLine = newLine;

            var newAddress: i32 = undefined;

            if (difference >= SCREEN_LINES) {
                newAddress = rom.address - (difference * 16);
            } else {
                newAddress = 0;
            }

            try std.io.getStdOut().writer().print("NL: {d} D: {d} RA: {d} NA: {d}\n", .{ newLine, difference, rom.address, newAddress });

            rom.address = newAddress;
        }

        try drawFrame();
    }

    return 0;
}
