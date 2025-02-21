// TODO
// Change all rl.loadFileData to use Zig equivalents

const std = @import("std");
const rl = @import("raylib");

const BYTES_PER_LINE: u8 = 16;
const FONT_SIZE: u31 = 20;
const FONT_SPACING: f32 = 1;
const FONT_SPACING_HALF: u31 = @divFloor(FONT_SPACING, 2);
const LINE_SPACING: f32 = 0;
const LINE_SPACING_HALF: u31 = @divFloor(LINE_SPACING, 2);
const SCREEN_LINES: u31 = 32;
const SCREEN_COLUMNS: u31 = 8 + 1 + (BYTES_PER_LINE * 2) + (BYTES_PER_LINE - 1) + 1 + BYTES_PER_LINE + 1;
// Offset             ------^   ^   ^                      ^                      ^   ^                ^
// Space              ----------´   |                      |                      |   |                |
// Bytes as hex 00    --------------´                      |                      |   |                |
// Bytes' spaces      -------------------------------------´                      |   |                |
// Space              ------------------------------------------------------------´   |                |
// Bytes as char .    ----------------------------------------------------------------´                |
// Scrollbar          ---------------------------------------------------------------------------------´
const HEAP_SIZE: u31 = 4096;

var HEAP: [HEAP_SIZE]u8 = undefined;
var fba: std.heap.FixedBufferAllocator = undefined;

var fontWidth: f32 = undefined;
var fontHeight: f32 = undefined;

var screenWidth: u31 = undefined;
var screenHeight: u31 = undefined;

var lineHeight: u31 = undefined;

var font: rl.Font = undefined;
var selectedLine: u31 = 0;

var headerBuffer: std.ArrayList(u8) = undefined;
var lineBuffer: std.ArrayList(u8) = undefined;

const ROMError: type = error{
    EmptyFile,
    SymbolAlreadyReplaced,
    TypingAlreadyReplaced,
};

const ROM: type = struct {
    data: []u8,
    lines: u31,
    lastLine: u31,
    address: u31,
    symbols: [256]u8,
    symbolReplacements: ?std.AutoHashMap(u8, u8),
    typingReplacements: ?std.AutoHashMap(u8, u8),

    pub fn init(filename: [:0]const u8) anyerror!ROM {
        const data: []u8 = try rl.loadFileData(filename);

        if (data.len == 0) {
            return ROMError.EmptyFile;
        }

        var symbols: [256]u8 = .{'.'} ** 256;

        for (0..256) |i| {
            if (i >= 32 and i <= 127) {
                symbols[i] = @as(u8, @intCast(i));
            }
        }

        const extension: []const u8 = std.fs.path.extension(filename);
        const truncatedName: []const u8 = filename[0 .. filename.len - extension.len];
        const tableFilename: [:0]u8 = try std.mem.joinZ(fba.allocator(), "", &.{ truncatedName, ".tbl" });

        var symbolReplacements: ?std.AutoHashMap(u8, u8) = null;
        var typingReplacements: ?std.AutoHashMap(u8, u8) = null;
        var tableExists: bool = true;

        _ = std.fs.cwd().openFile(tableFilename, .{}) catch |tableFileAccessError| {
            tableExists = if (tableFileAccessError == error.FileNotFound) false else true;
        };

        if (tableExists) {
            const hexadecimalCharacters: [22]u8 = .{ '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F', 'a', 'b', 'c', 'd', 'e', 'f' };

            symbolReplacements = std.AutoHashMap(u8, u8).init(fba.allocator());
            typingReplacements = std.AutoHashMap(u8, u8).init(fba.allocator());

            var tableFile: std.fs.File = try std.fs.cwd().openFile(tableFilename, .{});
            defer tableFile.close();

            var bufferedReader = std.io.bufferedReader(tableFile.reader());
            var inStream = bufferedReader.reader();

            var buffer: [1024]u8 = undefined;

            while (try inStream.readUntilDelimiterOrEof(&buffer, '\n')) |line| {
                const trimmedLine = std.mem.trim(u8, line, &.{ '\r', '\n' });

                if (trimmedLine.len != 4) {
                    continue;
                }

                if (trimmedLine[2] != '=') {
                    continue;
                }

                if (!std.mem.containsAtLeast(u8, &hexadecimalCharacters, 1, &.{trimmedLine[0]})) {
                    continue;
                }

                if (!std.mem.containsAtLeast(u8, &hexadecimalCharacters, 1, &.{trimmedLine[1]})) {
                    continue;
                }

                const byte = try std.fmt.parseInt(u8, trimmedLine[0..2], 16);

                if (symbolReplacements.?.contains(byte)) {
                    return ROMError.SymbolAlreadyReplaced;
                }

                const char = trimmedLine[3];

                if (typingReplacements.?.contains(char)) {
                    return ROMError.TypingAlreadyReplaced;
                }

                symbols[byte] = char;
                symbols[char] = '.';

                try symbolReplacements.?.put(byte, char);
                try typingReplacements.?.put(char, byte);
            }
        }

        const lines: u31 = @as(u31, @intCast(try std.math.divCeil(usize, data.len, BYTES_PER_LINE)));

        return ROM{
            .data = data,
            .address = 0,
            .lines = lines,
            .lastLine = lines - 1,
            .symbols = symbols,
            .symbolReplacements = symbolReplacements,
            .typingReplacements = typingReplacements,
        };
    }

    pub fn deinit(self: *ROM) void {
        if (self.data.len == 0) {
            return;
        }

        rl.unloadFileData(self.data);

        if (self.symbolReplacements != null) {
            self.symbolReplacements.?.deinit();
        }

        if (self.typingReplacements != null) {
            self.typingReplacements.?.deinit();
        }

        self.address = 0;
        self.lines = 0;
    }
};

const ScrollDirection: type = enum {
    down,
    up,
};

var rom: ROM = undefined;

pub fn drawTextCustom(text: [:0]const u8, x: i32, y: i32, color: rl.Color) void {
    rl.drawTextEx(font, text, rl.Vector2{
        .x = @floatFromInt(x),
        .y = @floatFromInt(y),
    }, @floatFromInt(font.baseSize), FONT_SPACING, color);
}

pub fn scrollBy(amount: u31, direction: ScrollDirection) anyerror!void {
    if (amount == 0) {
        return;
    }

    const viewTopLine: u31 = @divFloor(rom.address, BYTES_PER_LINE);
    const viewBottomLine: u31 = viewTopLine + SCREEN_LINES - 1;

    var newLine: u31 = undefined;

    if (direction == ScrollDirection.down) {
        newLine = @min(rom.lastLine, selectedLine + amount);
    } else if (direction == ScrollDirection.up) {
        const iSelectedLine: i32 = selectedLine;
        const iNewLine: i32 = @max(iSelectedLine - amount, 0);

        newLine = @as(u31, @intCast(iNewLine));
    }

    if (newLine > viewBottomLine) {
        rom.address = @min((rom.lines - SCREEN_LINES) * BYTES_PER_LINE, rom.address + amount * BYTES_PER_LINE);
    } else if (newLine < viewTopLine) {
        const delta: u31 = amount * BYTES_PER_LINE;

        if (rom.address >= delta) {
            rom.address -= delta;
        } else {
            rom.address = 0;
        }
    }

    selectedLine = newLine;
}

pub fn drawFrame() anyerror!void {
    const viewTopLine: u31 = @divFloor(rom.address, BYTES_PER_LINE);
    const viewBottomLine: u31 = viewTopLine + SCREEN_LINES - 1;

    // Clear background
    rl.clearBackground(rl.Color.dark_gray);

    // Draw top bar
    rl.drawRectangle(0, 0, screenWidth, lineHeight, rl.Color.white);

    drawTextCustom(@ptrCast(headerBuffer.items), FONT_SPACING_HALF, LINE_SPACING_HALF, rl.Color.black);

    // Draw status bar
    rl.drawRectangle(0, screenHeight - lineHeight, screenWidth, lineHeight, rl.Color.white);

    lineBuffer.clearRetainingCapacity();

    try lineBuffer.appendSlice(" Line: ");
    try lineBuffer.writer().print("{d}/{d} ({d:.2}%)", .{ selectedLine + 1, rom.lines, (@as(f32, @floatFromInt(selectedLine)) + 1.0) * 100.0 / @as(f32, @floatFromInt(rom.lines)) });
    try lineBuffer.append(0);

    drawTextCustom(@ptrCast(lineBuffer.items), FONT_SPACING_HALF, screenHeight - lineHeight + LINE_SPACING_HALF, rl.Color.black);

    // Draw selected highlight
    if (selectedLine >= viewTopLine and selectedLine <= viewBottomLine) {
        rl.drawRectangle(0, (selectedLine - viewTopLine + 1) * lineHeight, screenWidth, lineHeight, rl.Color.light_gray);
    }

    // Draw contents
    for (0..SCREEN_LINES) |i| {
        const address: u31 = rom.address + BYTES_PER_LINE * @as(u31, @intCast(i));
        var byteIndex: usize = undefined;

        if (address >= rom.data.len) {
            continue;
        }

        lineBuffer.clearRetainingCapacity();

        try lineBuffer.writer().print("{X:0>8} ", .{address});

        for (0..BYTES_PER_LINE) |j| {
            byteIndex = @as(usize, @intCast(address)) + j;

            if (byteIndex < rom.data.len) {
                try lineBuffer.writer().print("{X:0>2} ", .{rom.data[byteIndex]});
            } else {
                try lineBuffer.appendSlice("   ");
            }
        }

        for (0..BYTES_PER_LINE) |j| {
            byteIndex = @as(usize, @intCast(address)) + j;

            if (byteIndex < rom.data.len) {
                try lineBuffer.append(rom.symbols[rom.data[byteIndex]]);
            } else {
                try lineBuffer.append(' ');
            }
        }

        try lineBuffer.append(0);

        drawTextCustom(@ptrCast(lineBuffer.items), FONT_SPACING_HALF, @as(u31, @intCast(i + 1)) * lineHeight + LINE_SPACING_HALF, if (viewTopLine + @as(u31, @intCast(i)) == selectedLine) rl.Color.black else rl.Color.light_gray);
    }
}

pub fn main() anyerror!u8 {
    fba = std.heap.FixedBufferAllocator.init(&HEAP);

    headerBuffer = std.ArrayList(u8).init(fba.allocator());
    defer headerBuffer.deinit();

    try headerBuffer.appendSlice(" Offset  ");

    for (0..BYTES_PER_LINE) |i| {
        try headerBuffer.writer().print("{X:0>2} ", .{i});
    }

    for (0..BYTES_PER_LINE) |i| {
        try headerBuffer.writer().print("{X:1}", .{i % 16});
    }

    try headerBuffer.append(0);

    lineBuffer = std.ArrayList(u8).init(fba.allocator());
    defer lineBuffer.deinit();

    rl.initWindow(814, 640, "RayxEdigor");
    defer rl.closeWindow();

    font = try rl.loadFontEx("resources/firacode.ttf", FONT_SIZE, null);
    defer if (font.glyphCount > 0) rl.unloadFont(font);

    if (font.glyphCount == 0) {
        return 1;
    }

    const fontMeasurements: rl.Vector2 = rl.measureTextEx(font, "K", @floatFromInt(font.baseSize), FONT_SPACING);

    fontWidth = fontMeasurements.x;
    fontHeight = fontMeasurements.y;

    screenWidth = @intFromFloat(@round(SCREEN_COLUMNS * fontWidth + (SCREEN_COLUMNS - 1) * FONT_SPACING));
    screenHeight = @intFromFloat(@round((SCREEN_LINES + 2) * fontHeight + (SCREEN_LINES + 2) * LINE_SPACING));
    // Here it does not take off 1 because there are half line spacing    ^
    // on top and half at bottom -----------------------------------------´

    lineHeight = @intFromFloat(@round(fontMeasurements.y) + LINE_SPACING);

    rl.setWindowSize(screenWidth, screenHeight);

    rom = try ROM.init("resources/test.txt");
    defer rom.deinit();

    rl.setTargetFPS(60);

    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();

        if (rl.isKeyPressed(rl.KeyboardKey.down) or rl.isKeyPressedRepeat(rl.KeyboardKey.down)) {
            try scrollBy(1, ScrollDirection.down);
        } else if (rl.isKeyPressed(rl.KeyboardKey.up) or rl.isKeyPressedRepeat(rl.KeyboardKey.up)) {
            try scrollBy(1, ScrollDirection.up);
        } else if (rl.isKeyPressed(rl.KeyboardKey.page_down) or rl.isKeyPressedRepeat(rl.KeyboardKey.page_down)) {
            try scrollBy(SCREEN_LINES, ScrollDirection.down);
        } else if (rl.isKeyPressed(rl.KeyboardKey.page_up) or rl.isKeyPressedRepeat(rl.KeyboardKey.page_up)) {
            try scrollBy(SCREEN_LINES, ScrollDirection.up);
        }

        if (rl.isKeyDown(rl.KeyboardKey.left_control)) {
            if (rl.isKeyDown(rl.KeyboardKey.home)) {
                try scrollBy(rom.lines, ScrollDirection.up);
            } else if (rl.isKeyDown(rl.KeyboardKey.end)) {
                try scrollBy(rom.lines, ScrollDirection.down);
            }
        }

        const wheel: f32 = rl.getMouseWheelMove();

        if (wheel != 0.0) {
            const amount = @as(u31, @intFromFloat(@round(@abs(wheel) * 3)));

            if (wheel < 0) {
                try scrollBy(amount, ScrollDirection.down);
            } else {
                try scrollBy(amount, ScrollDirection.up);
            }
        }

        try drawFrame();
    }

    return 0;
}
