// TODO
// Add style's configuration
// Add save of contents
// Add search
// Add relative search

const std = @import("std");
const rl = @import("raylib");

const STYLE_BACKGROUND: rl.Color = rl.Color.dark_gray;
const STYLE_CHARACTER_HIGHLIGHT: rl.Color = rl.Color.white;
const STYLE_HEADER_BACKGROUND: rl.Color = rl.Color.white;
const STYLE_HEADER_TEXT: rl.Color = rl.Color.black;
const STYLE_LINE_HIGHLIGHT: rl.Color = rl.Color.light_gray;
const STYLE_SCROLLBAR_BACKGROUND: rl.Color = rl.Color.white;
const STYLE_SCROLLBAR_FOREGROUND: rl.Color = rl.Color.black;
const STYLE_TEXT: rl.Color = rl.Color.light_gray;
const STYLE_TEXT_HIGHLIGHTED: rl.Color = rl.Color.black;
const STYLE_STATUSBAR_BACKGROUND: rl.Color = rl.Color.white;
const STYLE_STATUSBAR_TEXT: rl.Color = rl.Color.black;

const FONT_FILE: [:0]const u8 = "resources/firacode.ttf";
const FONT_SIZE_MIN: u31 = 16;
const FONT_SIZE_MAX: u31 = 32;
const FONT_SPACING: u31 = 1;
const FONT_SPACING_HALF: u31 = @divFloor(FONT_SPACING, 2);

const LINE_SPACING: u31 = 0;
const LINE_SPACING_HALF: u31 = @divFloor(LINE_SPACING, 2);

const BYTES_PER_LINE: u8 = 16;
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

const SCROLLBAR_SCALE: f32 = 2.1;

const HEXADECIMAL_CHARACTERS: [22]u8 = .{
    '0', '1', '2', '3', '4', '5', '6', '7',
    '8', '9', 'A', 'B', 'C', 'D', 'E', 'F',
    'a', 'b', 'c', 'd', 'e', 'f',
};

const EditMode: type = enum {
    Character,
    Hexadecimal,
    Length,
};

var editorMode: EditorMode = EditorMode.Edit;

var fontSize: u31 = 20;
var font: rl.Font = undefined;
var fontWidth: f32 = undefined;
var fontHeight: f32 = undefined;

var screenWidth: u31 = undefined;
var screenHeight: u31 = undefined;

var characterWidth: u31 = undefined;
var lineHeight: u31 = undefined;

var scrollbarHeight: u31 = undefined;
var scrollbarHeightHalf: u31 = undefined;
var scrollbarClicked: bool = false;

var HEAP: [HEAP_SIZE]u8 = undefined;
var fba: std.heap.FixedBufferAllocator = undefined;
var gpa: std.heap.GeneralPurposeAllocator(.{}) = undefined;

var editLine: u31 = 0;
var editColumn: u8 = 0;
var editNibble: u1 = 0;
var editMode: EditMode = EditMode.Character;

var headerBuffer: std.ArrayList(u8) = undefined;
var lineBuffer: std.ArrayList(u8) = undefined;

const ROMError: type = error{
    EmptyFile,
    EmptyFont,
    SymbolAlreadyReplaced,
    TypingAlreadyReplaced,
};

const ROM: type = struct {
    data: []u8,
    size: u64,
    lines: u31,
    lastLine: u31,
    address: u31,
    symbols: [256]u8,
    symbolReplacements: ?std.AutoHashMap(u8, u8),
    typingReplacements: ?std.AutoHashMap(u8, u8),

    pub fn init(filename: []const u8) anyerror!ROM {
        var romFile: std.fs.File = try std.fs.cwd().openFile(filename, .{});
        defer romFile.close();

        const size: u64 = try romFile.getEndPos();

        if (size == 0) {
            return ROMError.EmptyFile;
        }

        const data: []u8 = try gpa.allocator().alloc(u8, size);

        // const data: []u8 = try romFile.readToEndAlloc(gpa.allocator(), 16 * 1024 * 1024);

        _ = try romFile.readAll(data);

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

                if (!std.mem.containsAtLeast(u8, &HEXADECIMAL_CHARACTERS, 1, &.{trimmedLine[0]})) {
                    continue;
                }

                if (!std.mem.containsAtLeast(u8, &HEXADECIMAL_CHARACTERS, 1, &.{trimmedLine[1]})) {
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

        const lines: u31 = @as(u31, @intCast(try std.math.divCeil(usize, size, BYTES_PER_LINE)));

        return ROM{
            .data = data,
            .size = size,
            .address = 0,
            .lines = lines,
            .lastLine = lines - 1,
            .symbols = symbols,
            .symbolReplacements = symbolReplacements,
            .typingReplacements = typingReplacements,
        };
    }

    pub fn deinit(self: *ROM) void {
        if (self.size == 0) {
            return;
        }

        gpa.allocator().free(self.data);

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
    left,
    right,
    up,
};

const EditorMode: type = enum {
    Command,
    Edit,
    Length,
};

var rom: ROM = undefined;

pub fn drawTextCustom(text: [:0]const u8, x: i32, y: i32, color: rl.Color) void {
    rl.drawTextEx(font, text, rl.Vector2{
        .x = @floatFromInt(x),
        .y = @floatFromInt(y),
    }, @floatFromInt(font.baseSize), FONT_SPACING, color);
}

pub fn configureFontAndScreen() anyerror!void {
    if (font.glyphCount > 0) {
        rl.unloadFont(font);
    }

    font = try rl.loadFontEx(FONT_FILE, fontSize, null);

    if (font.glyphCount == 0) {
        return ROMError.EmptyFont;
    }

    const fontMeasurements: rl.Vector2 = rl.measureTextEx(font, "K", @floatFromInt(font.baseSize), FONT_SPACING);

    fontWidth = fontMeasurements.x;
    fontHeight = fontMeasurements.y;

    screenWidth = @as(u31, @intFromFloat(SCREEN_COLUMNS * fontWidth + (SCREEN_COLUMNS - 1) * FONT_SPACING));
    screenHeight = @as(u31, @intFromFloat((SCREEN_LINES + 2) * fontHeight + (SCREEN_LINES + 2) * LINE_SPACING));
    // Here it does not take off 1 because there are half line spacing      ^
    // on top and half at bottom -------------------------------------------´

    characterWidth = @intFromFloat(@round(fontMeasurements.x) + FONT_SPACING);
    lineHeight = @intFromFloat(@round(fontMeasurements.y) + LINE_SPACING);
    scrollbarHeight = @as(u31, @intFromFloat(@as(f32, @floatFromInt(lineHeight)) * SCROLLBAR_SCALE));
    scrollbarHeightHalf = @divFloor(scrollbarHeight, 2);

    rl.setWindowSize(screenWidth, screenHeight);
}

pub fn drawCommandFrame() anyerror!void {
    // Clear background
    rl.clearBackground(STYLE_BACKGROUND);

    // Draw top bar
    rl.drawRectangle(0, 0, screenWidth, lineHeight, STYLE_HEADER_BACKGROUND);

    lineBuffer.clearRetainingCapacity();

    try lineBuffer.writer().print("{[value]s: ^[width]}", .{ .value = "RayxEdigor", .width = SCREEN_COLUMNS });
    try lineBuffer.append(0);

    drawTextCustom(@ptrCast(lineBuffer.items), FONT_SPACING_HALF, LINE_SPACING_HALF, STYLE_HEADER_TEXT);

    // Draw status bar
    rl.drawRectangle(0, screenHeight - lineHeight, screenWidth, lineHeight, STYLE_STATUSBAR_BACKGROUND);

    lineBuffer.clearRetainingCapacity();

    try lineBuffer.appendSlice(" Command: ");
    try lineBuffer.append(0);

    drawTextCustom(@ptrCast(lineBuffer.items), FONT_SPACING_HALF, screenHeight - lineHeight + LINE_SPACING_HALF, STYLE_STATUSBAR_TEXT);
}

pub fn scrollEditBy(amount: u31, direction: ScrollDirection) anyerror!void {
    if (amount == 0) {
        return;
    }

    if (direction == ScrollDirection.up and editLine == 0) {
        return;
    }

    if (direction == ScrollDirection.down and editLine == rom.lastLine) {
        return;
    }

    if (direction == ScrollDirection.left and editLine == 0 and editColumn == 0) {
        return;
    }

    if (direction == ScrollDirection.right and editLine == rom.lastLine and editColumn == BYTES_PER_LINE - 1) {
        return;
    }

    if (direction == ScrollDirection.up or direction == ScrollDirection.down) {
        const viewTopLine: u31 = @divFloor(rom.address, BYTES_PER_LINE);
        const viewBottomLine: u31 = viewTopLine + SCREEN_LINES - 1;

        var newLine: u31 = undefined;

        if (direction == ScrollDirection.down) {
            newLine = @min(editLine + amount, rom.lastLine);
        } else if (direction == ScrollDirection.up) {
            const iSelectedLine: i32 = editLine;
            const iNewLine: i32 = @max(0, iSelectedLine - amount);

            newLine = @as(u31, @intCast(iNewLine));
        }

        if (newLine > viewBottomLine) {
            rom.address = @min(rom.address + amount * BYTES_PER_LINE, (rom.lines - SCREEN_LINES) * BYTES_PER_LINE);
        } else if (newLine < viewTopLine) {
            const delta: u31 = amount * BYTES_PER_LINE;

            if (rom.address >= delta) {
                rom.address -= delta;
            } else {
                rom.address = 0;
            }
        }

        editLine = newLine;
    } else {
        if (direction == ScrollDirection.left) {
            if (editColumn > 0) {
                editColumn -= 1;
            } else if (editLine > 0) {
                editColumn = BYTES_PER_LINE - 1;

                try scrollEditBy(1, ScrollDirection.up);
            }
        } else {
            if (editColumn < BYTES_PER_LINE - 1) {
                editColumn += 1;
            } else if (editLine < rom.lastLine) {
                editColumn = 0;

                try scrollEditBy(1, ScrollDirection.down);
            }
        }
    }
}

pub fn scrollEditByScrollbar() anyerror!void {
    const scrollbarLimitTop: u31 = lineHeight + scrollbarHeightHalf;
    const scrollbarLimitBottom: u31 = screenHeight - lineHeight - scrollbarHeightHalf;
    const mouseY: u31 = @as(u31, @intCast(std.math.clamp(rl.getMouseY(), scrollbarLimitTop, scrollbarLimitBottom))) - scrollbarLimitTop;
    const scrollbarSpace: u31 = SCREEN_LINES * lineHeight - scrollbarHeight;
    const scrollbarPercentage: f32 = @as(f32, @floatFromInt(mouseY)) / @as(f32, @floatFromInt(scrollbarSpace));
    const scrolledLine: u31 = @as(u31, @intFromFloat(@as(f32, @floatFromInt(rom.lastLine)) * scrollbarPercentage));
    const linesDifference: u31 = @as(u31, @intCast(@abs(@as(i32, @intCast(editLine)) - @as(i32, @intCast(scrolledLine)))));

    if (scrolledLine < editLine) {
        try scrollEditBy(linesDifference, ScrollDirection.up);
    } else if (scrolledLine > editLine) {
        try scrollEditBy(linesDifference, ScrollDirection.down);
    }
}

pub fn advanceNibble(direction: ScrollDirection) anyerror!void {
    if (direction == ScrollDirection.left) {
        if (editNibble == 1) {
            editNibble = 0;
        } else if (editLine > 0 or editColumn > 0) {
            editNibble = 1;

            try scrollEditBy(1, direction);
        }
    } else {
        if (editNibble == 0) {
            editNibble = 1;
        } else if (editLine < rom.lastLine or editColumn < BYTES_PER_LINE - 1) {
            editNibble = 0;

            try scrollEditBy(1, direction);
        }
    }
}

pub fn processEditShortcuts() anyerror!void {
    if (rl.isKeyPressed(rl.KeyboardKey.down) or rl.isKeyPressedRepeat(rl.KeyboardKey.down)) {
        try scrollEditBy(1, ScrollDirection.down);
    } else if (rl.isKeyPressed(rl.KeyboardKey.up) or rl.isKeyPressedRepeat(rl.KeyboardKey.up)) {
        try scrollEditBy(1, ScrollDirection.up);
    } else if (rl.isKeyPressed(rl.KeyboardKey.page_down) or rl.isKeyPressedRepeat(rl.KeyboardKey.page_down)) {
        try scrollEditBy(SCREEN_LINES, ScrollDirection.down);
    } else if (rl.isKeyPressed(rl.KeyboardKey.page_up) or rl.isKeyPressedRepeat(rl.KeyboardKey.page_up)) {
        try scrollEditBy(SCREEN_LINES, ScrollDirection.up);
    } else if (rl.isKeyPressed(rl.KeyboardKey.left) or rl.isKeyPressedRepeat(rl.KeyboardKey.left)) {
        if (editMode == EditMode.Character) {
            try scrollEditBy(1, ScrollDirection.left);
        } else {
            try advanceNibble(ScrollDirection.left);
        }
    } else if (rl.isKeyPressed(rl.KeyboardKey.right) or rl.isKeyPressedRepeat(rl.KeyboardKey.right)) {
        if (editMode == EditMode.Character) {
            try scrollEditBy(1, ScrollDirection.right);
        } else {
            try advanceNibble(ScrollDirection.right);
        }
    } else if (rl.isKeyPressed(rl.KeyboardKey.tab) or rl.isKeyPressedRepeat(rl.KeyboardKey.tab)) {
        editMode = @enumFromInt(@mod(@as(u2, @intFromEnum(editMode)) + 1, @intFromEnum(EditMode.Length)));
        editNibble = 0;
    } else if (rl.isKeyDown(rl.KeyboardKey.home)) {
        editColumn = 0;
        editNibble = 0;
    } else if (rl.isKeyDown(rl.KeyboardKey.end)) {
        editColumn = BYTES_PER_LINE - 1;
        editNibble = 0;
    }

    if (rl.isKeyDown(rl.KeyboardKey.left_control)) {
        if (rl.isKeyDown(rl.KeyboardKey.home)) {
            editColumn = 0;
            editNibble = 0;

            try scrollEditBy(editLine, ScrollDirection.up);
        } else if (rl.isKeyDown(rl.KeyboardKey.end)) {
            editColumn = BYTES_PER_LINE - 1;
            editNibble = 0;

            try scrollEditBy(rom.lines - editLine - 1, ScrollDirection.down);
        } else if (rl.isKeyPressed(rl.KeyboardKey.equal)) {
            fontSize = @min(fontSize + 1, FONT_SIZE_MAX);

            try configureFontAndScreen();
        } else if (rl.isKeyPressed(rl.KeyboardKey.minus)) {
            fontSize = @max(FONT_SIZE_MIN, fontSize - 1);

            try configureFontAndScreen();
        }
    }
}

pub fn processEditKeyboard() anyerror!void {
    var key: u8 = @as(u8, @intCast(rl.getCharPressed()));

    while (key != 0) {
        if (editMode == EditMode.Hexadecimal) {
            if (std.mem.containsAtLeast(u8, &HEXADECIMAL_CHARACTERS, 1, &.{key})) {
                const byteIndex: u31 = editLine * BYTES_PER_LINE + editColumn;
                const byte: u8 = rom.data[byteIndex];
                const typedByte: u8 = try std.fmt.parseInt(u8, &.{key}, 16);

                if (editNibble == 0) {
                    rom.data[byteIndex] = typedByte * 0x10 + (byte & 0x0F);
                } else {
                    rom.data[byteIndex] = (byte & 0xF0) + typedByte;
                }

                try advanceNibble(ScrollDirection.right);
            }
        } else {
            const byteIndex: u31 = editLine * BYTES_PER_LINE + editColumn;
            const byte: u8 = if (rom.typingReplacements.?.contains(key)) rom.typingReplacements.?.get(key).? else rom.symbols[key];

            rom.data[byteIndex] = byte;

            try scrollEditBy(1, ScrollDirection.right);
        }

        key = @as(u8, @intCast(rl.getCharPressed()));
    }
}

pub fn processEditMouse() anyerror!void {
    const wheel: f32 = rl.getMouseWheelMove();

    if (wheel != 0.0) {
        if (rl.isKeyDown(rl.KeyboardKey.left_control)) {
            const amount: u31 = @as(u31, @intFromFloat(@abs(wheel)));

            if (wheel < 0) {
                fontSize = @max(FONT_SIZE_MIN, fontSize - amount);
            } else {
                fontSize = @min(fontSize + amount, FONT_SIZE_MAX);
            }

            try configureFontAndScreen();
        } else {
            const amount: u31 = @as(u31, @intFromFloat(@round(@abs(wheel) * 3)));

            if (wheel < 0) {
                try scrollEditBy(amount, ScrollDirection.down);
            } else {
                try scrollEditBy(amount, ScrollDirection.up);
            }
        }
    }

    if (rl.isMouseButtonDown(rl.MouseButton.left)) {
        if (scrollbarClicked) {
            try scrollEditByScrollbar();

            return;
        }

        const mouseX: u31 = @max(0, rl.getMouseX());
        const mouseY: u31 = @max(0, rl.getMouseY());
        const line: u31 = @divFloor(mouseY, lineHeight);
        const column: u31 = @divFloor(mouseX, characterWidth);

        viewArea: {
            if (line < 1 or line > SCREEN_LINES) {
                break :viewArea;
            }

            if (column == SCREEN_COLUMNS - 1) {
                scrollbarClicked = true;

                try scrollEditByScrollbar();

                break :viewArea;
            } else {
                const viewTopLine: u31 = @divFloor(rom.address, BYTES_PER_LINE);

                editLine = viewTopLine + line - 1;

                const hexadecimalStartColumn: u31 = 8 + 1;
                const hexadecimalEndColumn: u31 = hexadecimalStartColumn + (BYTES_PER_LINE * 2) + (BYTES_PER_LINE - 1) - 1;
                const charactersStartColumn: u31 = 8 + 1 + (BYTES_PER_LINE * 2) + (BYTES_PER_LINE - 1) + 1;
                const charactersEndColumn: u31 = charactersStartColumn + (BYTES_PER_LINE - 1);

                if (column >= hexadecimalStartColumn and column <= hexadecimalEndColumn) {
                    const byteIndex: u31 = @divFloor(column - 9, 3);
                    const nibbleIndex: u31 = @mod(column, 3);

                    if (nibbleIndex < 2) {
                        editMode = EditMode.Hexadecimal;
                        editNibble = @as(u1, @intCast(nibbleIndex));
                        editColumn = @as(u8, @intCast(byteIndex));
                    }
                } else if (column >= charactersStartColumn and column <= charactersEndColumn) {
                    const byteIndex: u31 = column - charactersStartColumn;

                    editMode = EditMode.Character;
                    editNibble = 0;
                    editColumn = @as(u8, @intCast(byteIndex));
                }
            }
        }
    }

    if (rl.isMouseButtonReleased(rl.MouseButton.left)) {
        if (scrollbarClicked) {
            scrollbarClicked = false;
        }
    }
}

pub fn drawEditFrame() anyerror!void {
    const viewTopLine: u31 = @divFloor(rom.address, BYTES_PER_LINE);

    // Clear background
    rl.clearBackground(STYLE_BACKGROUND);

    // Draw top bar
    rl.drawRectangle(0, 0, screenWidth, lineHeight, STYLE_HEADER_BACKGROUND);

    drawTextCustom(@ptrCast(headerBuffer.items), FONT_SPACING_HALF, LINE_SPACING_HALF, STYLE_HEADER_TEXT);

    // Draw status bar
    rl.drawRectangle(0, screenHeight - lineHeight, screenWidth, lineHeight, STYLE_STATUSBAR_BACKGROUND);

    lineBuffer.clearRetainingCapacity();

    try lineBuffer.appendSlice(" Lin: ");
    try lineBuffer.writer().print("{[value]d:[width]}/{[total]d} ({[percentage]d:6.2}%)", .{
        .value = editLine + 1,
        .total = rom.lines,
        .percentage = @as(f32, @floatFromInt(editLine)) * 100.0 / @as(f32, @floatFromInt(rom.lastLine)),
        .width = std.math.log10(rom.lines) + 1,
    });
    try lineBuffer.appendSlice(" Col: ");
    try lineBuffer.writer().print("{X:0>2}", .{editColumn});
    try lineBuffer.appendSlice(" Addr: ");
    try lineBuffer.writer().print("{X:0>8}", .{editLine * BYTES_PER_LINE + editColumn});
    try lineBuffer.appendSlice(" Mode: ");
    try lineBuffer.writer().print("{s}", .{if (editMode == EditMode.Character) "Character" else "Hexadecimal"});
    try lineBuffer.append(0);

    drawTextCustom(@ptrCast(lineBuffer.items), FONT_SPACING_HALF, screenHeight - lineHeight + LINE_SPACING_HALF, STYLE_STATUSBAR_TEXT);

    // Draw selected highlight
    rl.drawRectangle(0, (editLine - viewTopLine + 1) * lineHeight, screenWidth - characterWidth, lineHeight, STYLE_LINE_HIGHLIGHT);

    const editHighlightY: i32 = (editLine - viewTopLine + 1) * lineHeight;
    const editHexadecimalHighlightX: i32 = (8 + 1 + (editColumn * 3) + editNibble) * characterWidth;
    const editCharacterHighlightX: i32 = (8 + 1 + (2 * BYTES_PER_LINE) + (BYTES_PER_LINE - 1) + 1 + editColumn) * characterWidth;

    if (editMode == EditMode.Character) {
        rl.drawRectangleLines(editHexadecimalHighlightX, editHighlightY, characterWidth * 2, lineHeight, rl.Color.black);
        rl.drawRectangle(editCharacterHighlightX, editHighlightY, characterWidth, lineHeight, STYLE_CHARACTER_HIGHLIGHT);
    } else {
        rl.drawRectangle(editHexadecimalHighlightX, editHighlightY, characterWidth, lineHeight, STYLE_CHARACTER_HIGHLIGHT);
        rl.drawRectangleLines(editCharacterHighlightX, editHighlightY, characterWidth, lineHeight, rl.Color.black);
    }

    // Draw scrollbar
    const scrollbarSpace: u31 = SCREEN_LINES * lineHeight - scrollbarHeight;
    const scrollbarX: u31 = screenWidth - characterWidth;
    const scrollbarY: u31 = @as(u31, @intFromFloat(@as(f32, @floatFromInt(editLine)) * @as(f32, @floatFromInt(scrollbarSpace)) / @as(f32, @floatFromInt(rom.lastLine)) + @as(f32, @floatFromInt(lineHeight))));

    rl.drawRectangle(screenWidth - characterWidth, lineHeight, characterWidth, SCREEN_LINES * lineHeight, STYLE_SCROLLBAR_BACKGROUND);
    rl.drawRectangle(scrollbarX, scrollbarY, characterWidth, scrollbarHeight, STYLE_SCROLLBAR_FOREGROUND);

    // Draw contents
    for (0..SCREEN_LINES) |i| {
        const address: u31 = rom.address + BYTES_PER_LINE * @as(u31, @intCast(i));
        var byteIndex: usize = undefined;

        if (address >= rom.size) {
            continue;
        }

        lineBuffer.clearRetainingCapacity();

        try lineBuffer.writer().print("{X:0>8} ", .{address});

        for (0..BYTES_PER_LINE) |j| {
            byteIndex = @as(usize, @intCast(address)) + j;

            if (byteIndex < rom.size) {
                try lineBuffer.writer().print("{X:0>2} ", .{rom.data[byteIndex]});
            } else {
                try lineBuffer.appendSlice("   ");
            }
        }

        for (0..BYTES_PER_LINE) |j| {
            byteIndex = @as(usize, @intCast(address)) + j;

            if (byteIndex < rom.size) {
                try lineBuffer.append(rom.symbols[rom.data[byteIndex]]);
            } else {
                try lineBuffer.append(' ');
            }
        }

        try lineBuffer.append(0);

        drawTextCustom(@ptrCast(lineBuffer.items), FONT_SPACING_HALF, @as(u31, @intCast(i + 1)) * lineHeight + LINE_SPACING_HALF, if (viewTopLine + @as(u31, @intCast(i)) == editLine) STYLE_TEXT_HIGHLIGHTED else STYLE_TEXT);
    }
}

pub fn main() anyerror!u8 {
    fba = std.heap.FixedBufferAllocator.init(&HEAP);
    gpa = std.heap.GeneralPurposeAllocator(.{}){};

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

    rl.setExitKey(rl.KeyboardKey.null);

    try configureFontAndScreen();
    defer if (font.glyphCount > 0) rl.unloadFont(font);

    rom = try ROM.init("resources/test.txt");
    defer rom.deinit();

    rl.setTargetFPS(60);

    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();

        if (rl.isKeyPressed(rl.KeyboardKey.escape)) {
            editorMode = @enumFromInt(@mod(@as(u2, @intFromEnum(editorMode)) + 1, @intFromEnum(EditorMode.Length)));
        }

        if (editorMode == EditorMode.Command) {
            try drawCommandFrame();
        } else if (editorMode == EditorMode.Edit) {
            try processEditShortcuts();
            try processEditKeyboard();
            try processEditMouse();

            try drawEditFrame();
        }
    }

    return 0;
}
