// TODO
// Add error handling

const std: type = @import("std");
const rl: type = @import("raylib");

const FontDTO: type = struct {
    size: ?u8 = null,
    characterSpacing: ?f32 = null,
    lineSpacing: ?f32 = null,
};

const FontConfig: type = struct {
    size: u8 = 20,
    characterSpacing: f32 = 0,
    lineSpacing: f32 = 0,
};

const ColorDTO: type = struct {
    r: ?u8 = null,
    g: ?u8 = null,
    b: ?u8 = null,
    a: ?u8 = null,
};

const StyleDTO: type = struct {
    background: ?ColorDTO = null,
    characterHighlight: ?ColorDTO = null,
    errorBackground: ?ColorDTO = null,
    errorText: ?ColorDTO = null,
    headerBackground: ?ColorDTO = null,
    headerText: ?ColorDTO = null,
    lineHighlight: ?ColorDTO = null,
    scrollbarBackground: ?ColorDTO = null,
    scrollbarForeground: ?ColorDTO = null,
    statusbarBackground: ?ColorDTO = null,
    statusbarText: ?ColorDTO = null,
    text: ?ColorDTO = null,
    textHighlighted: ?ColorDTO = null,
};

const StyleConfig: type = struct {
    background: rl.Color = rl.Color.dark_gray,
    characterHighlight: rl.Color = rl.Color.white,
    errorBackground: rl.Color = rl.Color.red,
    errorText: rl.Color = rl.Color.white,
    headerBackground: rl.Color = rl.Color.white,
    headerText: rl.Color = rl.Color.black,
    lineHighlight: rl.Color = rl.Color.light_gray,
    scrollbarBackground: rl.Color = rl.Color.white,
    scrollbarForeground: rl.Color = rl.Color.black,
    statusbarBackground: rl.Color = rl.Color.white,
    statusbarText: rl.Color = rl.Color.black,
    text: rl.Color = rl.Color.light_gray,
    textHighlighted: rl.Color = rl.Color.black,
};

const ConfigDTO: type = struct {
    font: ?FontDTO = null,
    style: ?StyleDTO = null,
    bytesPerLine: ?u8 = null,
    errorDuration: ?f32 = null,
    screenLines: ?u8 = null,
    scrollbarScale: ?f32 = null,
};

const Config: type = struct {
    font: FontConfig = FontConfig{},
    style: StyleConfig = StyleConfig{},
    bytesPerLine: u8 = 16,
    errorDuration: f32 = 2,
    screenLines: u8 = 32,
    scrollbarScale: f32 = 2.1,
};

var config: Config = Config{};

const CONFIG_FILE: *const [11:0]u8 = "config.json";

const FONT_DATA = @embedFile("embed/firacode.ttf");
const FONT_SIZE_MIN: u8 = 16;
const FONT_SIZE_MAX: u8 = 32;
const FONT_CHARACTER_SPACING_MIN: f32 = 0;
const FONT_CHARACTER_SPACING_MAX: f32 = 16;
const FONT_LINE_SPACING_MIN: f32 = 0;
const FONT_LINE_SPACING_MAX: f32 = 16;

const BYTES_PER_LINE_MIN: u8 = 1;
const BYTES_PER_LINE_MAX: u8 = 32;

const ERROR_DURATION_MIN: f32 = 0.1;
const ERROR_DURATION_MAX: f32 = 5;

const SCREEN_LINES_MIN: u8 = 1;
const SCREEN_LINES_MAX: u8 = 64;

const SCROLLBAR_SCALE_MIN: f32 = 0.1;
const SCROLLBAR_SCALE_MAX: f32 = 5;

var fontSpacing: u31 = undefined;
var fontSpacingHalf: u31 = undefined;

var lineSpacing: u31 = undefined;
var lineSpacingHalf: u31 = undefined;

var BYTES_PER_LINE: u8 = undefined;
var SCREEN_LINES: u31 = undefined;
var SCREEN_COLUMNS: u31 = undefined;

const HEXADECIMAL_CHARACTERS: [22]u8 = .{
    '0', '1', '2', '3', '4', '5', '6', '7',
    '8', '9', 'A', 'B', 'C', 'D', 'E', 'F',
    'a', 'b', 'c', 'd', 'e', 'f',
};

const INPUT_BUFFER_SIZE: u16 = 256;

const EditMode: type = enum {
    Character,
    Hexadecimal,
};

var editorMode: EditorMode = .Command;

var font: rl.Font = undefined;

var screenWidth: u31 = undefined;
var screenHeight: u31 = undefined;

var characterWidth: u31 = undefined;
var lineHeight: u31 = undefined;

var scrollbarHeight: u31 = undefined;
var scrollbarHeightHalf: u31 = undefined;
var scrollbarClicked: bool = false;

var gpa: std.heap.GeneralPurposeAllocator(.{}) = undefined;

var editLine: u31 = 0;
var editColumn: u8 = 0;
var editNibble: u1 = 0;
var editMode: EditMode = .Character;

var errorBuffer: std.ArrayList(u8) = undefined;
var headerBuffer: std.ArrayList(u8) = undefined;
var lineBuffer: std.ArrayList(u8) = undefined;

var errorElapsed: f32 = 0;
var shouldClose: bool = false;

var camera: rl.Camera2D = undefined;

const ROMError: type = error{
    EmptyFile,
    EmptyFont,
    SymbolAlreadyReplaced,
    TypingAlreadyReplaced,
};

const ROM: type = struct {
    filename: []u8,
    data: []u8,
    size: u64,
    lines: u31,
    lastLine: u31,
    address: u31,
    symbols: [256]u8,
    symbolReplacements: ?std.AutoHashMap(u8, u8),
    typingReplacements: ?std.AutoHashMap(u8, u8),

    pub fn init(filename: []u8) anyerror!ROM {
        var romFile: std.fs.File = try std.fs.cwd().openFile(filename, .{});
        defer romFile.close();

        const size: u64 = try romFile.getEndPos();

        if (size == 0) {
            return ROMError.EmptyFile;
        }

        const data: []u8 = try gpa.allocator().alloc(u8, size);

        _ = try romFile.readAll(data);

        var symbols: [256]u8 = .{'.'} ** 256;

        for (0..256) |i| {
            if (i >= 32 and i <= 127) {
                symbols[i] = @as(u8, @intCast(i));
            }
        }

        const extension: []const u8 = std.fs.path.extension(filename);
        const truncatedName: []const u8 = filename[0 .. filename.len - extension.len];
        const tableFilename: [:0]u8 = try std.mem.joinZ(gpa.allocator(), "", &.{ truncatedName, ".tbl" });

        var symbolReplacements: ?std.AutoHashMap(u8, u8) = null;
        var typingReplacements: ?std.AutoHashMap(u8, u8) = null;
        var tableExists: bool = true;

        _ = std.fs.cwd().openFile(tableFilename, .{}) catch |tableFileAccessError| {
            tableExists = if (tableFileAccessError == error.FileNotFound) false else true;
        };

        if (tableExists) {
            symbolReplacements = std.AutoHashMap(u8, u8).init(gpa.allocator());
            typingReplacements = std.AutoHashMap(u8, u8).init(gpa.allocator());

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

                const byte: u8 = try std.fmt.parseInt(u8, trimmedLine[0..2], 16);

                if (symbolReplacements.?.contains(byte)) {
                    return ROMError.SymbolAlreadyReplaced;
                }

                const char: u8 = trimmedLine[3];

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
        const romFilename: []u8 = try gpa.allocator().alloc(u8, filename.len);

        @memcpy(romFilename, filename);

        return ROM{
            .filename = romFilename,
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
        if (self.size > 0) {
            gpa.allocator().free(self.data);
        }

        if (self.filename.len > 0) {
            gpa.allocator().free(self.filename);
        }

        if (self.symbolReplacements != null) {
            self.symbolReplacements.?.deinit();
        }

        if (self.typingReplacements != null) {
            self.typingReplacements.?.deinit();
        }

        self.address = 0;
        self.data = undefined;
        self.filename = undefined;
        self.lastLine = 0;
        self.lines = 0;
        self.size = 0;
        self.symbols = undefined;
        self.symbolReplacements = null;
        self.typingReplacements = null;
    }
};

var rom: ROM = std.mem.zeroes(ROM);

const ScrollDirection: type = enum {
    Down,
    Left,
    Right,
    Up,
};

const SearchDirection: type = enum {
    Backward,
    Forward,
};

const EditorMode: type = enum {
    Command,
    Edit,
};

const CommandMode: type = enum {
    GotoAddress,
    Menu,
    Open,
    RelativeSearch,
    Search,
    Write,
};

const InputBufferMode: type = enum {
    Insert,
    Replace,
};

const InputBuffer: type = struct {
    data: [INPUT_BUFFER_SIZE:0]u8 = .{0} ** INPUT_BUFFER_SIZE,
    count: u8 = 0,
    index: u8 = 0,
    mode: InputBufferMode = .Insert,
    maxLength: u16 = INPUT_BUFFER_SIZE - 1,

    pub fn reset(self: *InputBuffer) void {
        @memset(&self.data, 0);

        self.count = 0;
        self.index = 0;
        self.mode = .Insert;
        self.maxLength = INPUT_BUFFER_SIZE - 1;
    }

    pub fn setIndex(self: *InputBuffer, index: @TypeOf(INPUT_BUFFER_SIZE)) void {
        self.index = @min(index, if (self.mode == .Insert) self.count else (if (self.count > 0) self.count - 1 else 0));
    }

    pub fn decreaseIndex(self: *InputBuffer) void {
        self.setIndex(if (self.index > 0) self.index - 1 else 0);
    }

    pub fn increaseIndex(self: *InputBuffer) void {
        self.setIndex(self.index + 1);
    }

    pub fn setMode(self: *InputBuffer, mode: InputBufferMode) void {
        if (self.count == 0) {
            self.mode = .Insert;

            return;
        }

        self.mode = mode;
    }
};

const CommandHandler: type = struct {
    buffer: InputBuffer = std.mem.zeroes(InputBuffer),
    mode: CommandMode = .Menu,
    textSize: u8 = 0,

    pub fn reset(self: *CommandHandler) void {
        self.buffer.reset();

        self.textSize = switch (self.mode) {
            .GotoAddress => 16,
            .Menu => 10,
            .Open => 7,
            .Search => 9,
            .RelativeSearch => 18,
            .Write => 8,
        };

        self.buffer.maxLength = @as(u16, @intCast(SCREEN_COLUMNS)) - self.textSize - 1;
    }
};

var commandHandler: CommandHandler = .{};

pub fn drawTextCustom(text: [:0]const u8, x: i32, y: i32, color: rl.Color) void {
    rl.drawTextEx(
        font,
        text,
        rl.Vector2{
            .x = @floatFromInt(x),
            .y = @floatFromInt(y),
        },
        @floatFromInt(font.baseSize),
        @floatFromInt(fontSpacing),
        color,
    );
}

pub fn configureFontAndScreen() anyerror!void {
    if (font.glyphCount > 0) {
        rl.unloadFont(font);
    }

    font = try rl.loadFontFromMemory(".ttf", FONT_DATA, config.font.size, null);

    if (font.glyphCount == 0) {
        return ROMError.EmptyFont;
    }

    fontSpacing = @as(u31, @intFromFloat(@round(config.font.characterSpacing)));
    fontSpacingHalf = @divFloor(fontSpacing, 2);

    lineSpacing = @as(u31, @intFromFloat(@round(config.font.lineSpacing)));
    lineSpacingHalf = @divFloor(lineSpacing, 2);

    const fontMeasurements: rl.Vector2 = rl.measureTextEx(
        font,
        "K",
        @floatFromInt(font.baseSize),
        @floatFromInt(fontSpacing),
    );

    const fontWidth: u31 = @as(u31, @intFromFloat(@round(fontMeasurements.x)));
    const fontHeight: u31 = @as(u31, @intFromFloat(@round(fontMeasurements.y)));

    BYTES_PER_LINE = config.bytesPerLine;
    SCREEN_LINES = config.screenLines;
    SCREEN_COLUMNS = 8 + 1 + (BYTES_PER_LINE * 2) + (BYTES_PER_LINE - 1) + 1 + BYTES_PER_LINE + 1;
    // Offset  ------^   ^   ^                      ^                      ^   ^                ^
    // Space   ----------´   |                      |                      |   |                |
    // Bytes as hex 00 ------´                      |                      |   |                |
    // Bytes' spaces   -----------------------------´                      |   |                |
    // Space           ----------------------------------------------------´   |                |
    // Bytes as char . --------------------------------------------------------´                |
    // Scrollbar       -------------------------------------------------------------------------´

    screenWidth = SCREEN_COLUMNS * fontWidth + (SCREEN_COLUMNS - 1) * fontSpacing;
    screenHeight = (SCREEN_LINES + 2) * fontHeight + (SCREEN_LINES + 2) * lineSpacing;
    // Here it does not take off 1 because there are half line spacing      ^
    // on top and half at bottom -------------------------------------------´

    characterWidth = @as(u31, @intFromFloat(@round(fontMeasurements.x))) + fontSpacing;
    lineHeight = @as(u31, @intFromFloat(@round(fontMeasurements.y))) + lineSpacing;
    scrollbarHeight = @as(u31, @intFromFloat(@as(f32, @floatFromInt(lineHeight)) * config.scrollbarScale));
    scrollbarHeightHalf = @divFloor(scrollbarHeight, 2);

    rl.setWindowSize(screenWidth, screenHeight);

    const monitor: i32 = rl.getCurrentMonitor();
    const monitorWidth: i32 = rl.getMonitorWidth(monitor);
    const monitorHeight: i32 = rl.getMonitorHeight(monitor);
    const windowX: i32 = @divFloor(monitorWidth - screenWidth, 2);
    const windowY: i32 = @divFloor(monitorHeight - screenHeight, 2);

    rl.setWindowPosition(windowX, windowY);

    headerBuffer.clearRetainingCapacity();

    try headerBuffer.appendSlice(" Offset  ");

    for (0..BYTES_PER_LINE) |i| {
        try headerBuffer.writer().print("{X:0>2} ", .{i});
    }

    for (0..BYTES_PER_LINE) |i| {
        try headerBuffer.writer().print("{X:1}", .{i % 16});
    }

    try headerBuffer.append(0);
}

pub fn loadConfiguration() anyerror!void {
    config.font.size = 20;
    config.font.characterSpacing = 0;
    config.font.lineSpacing = 0;

    config.style.background = rl.Color.dark_gray;
    config.style.characterHighlight = rl.Color.white;
    config.style.errorBackground = rl.Color.red;
    config.style.errorText = rl.Color.white;
    config.style.headerBackground = rl.Color.white;
    config.style.headerText = rl.Color.black;
    config.style.lineHighlight = rl.Color.light_gray;
    config.style.scrollbarBackground = rl.Color.white;
    config.style.scrollbarForeground = rl.Color.black;
    config.style.statusbarBackground = rl.Color.white;
    config.style.statusbarText = rl.Color.black;
    config.style.text = rl.Color.light_gray;
    config.style.textHighlighted = rl.Color.black;

    config.bytesPerLine = 16;
    config.errorDuration = 2;
    config.screenLines = 32;
    config.scrollbarScale = 2.1;

    var configExists: bool = true;

    _ = std.fs.cwd().openFile(CONFIG_FILE, .{}) catch |configFileAccessError| {
        configExists = if (configFileAccessError == error.FileNotFound) false else true;
    };

    if (!configExists) {
        return;
    }

    const configFile: std.fs.File = try std.fs.cwd().openFile(CONFIG_FILE, .{});
    defer configFile.close();

    const size: u64 = try configFile.getEndPos();

    if (size == 0) {
        return;
    }

    const data: []u8 = try gpa.allocator().alloc(u8, size);

    _ = try configFile.readAll(data);

    const parsed = try std.json.parseFromSlice(ConfigDTO, gpa.allocator(), data, .{});
    defer parsed.deinit();

    if (parsed.value.font) |configFont| {
        if (configFont.size != null) {
            config.font.size = std.math.clamp(
                configFont.size.?,
                FONT_SIZE_MIN,
                FONT_SIZE_MAX,
            );
        }

        if (configFont.characterSpacing != null) {
            config.font.characterSpacing = std.math.clamp(
                configFont.characterSpacing.?,
                FONT_CHARACTER_SPACING_MIN,
                FONT_CHARACTER_SPACING_MAX,
            );
        }

        if (configFont.lineSpacing != null) {
            config.font.lineSpacing = std.math.clamp(
                configFont.lineSpacing.?,
                FONT_LINE_SPACING_MIN,
                FONT_LINE_SPACING_MAX,
            );
        }
    }

    if (parsed.value.style) |configStyle| {
        if (configStyle.background) |color| {
            config.style.background = rl.Color.init(
                color.r orelse 0,
                color.g orelse 0,
                color.b orelse 0,
                color.a orelse 0,
            );
        }

        if (configStyle.characterHighlight) |color| {
            config.style.characterHighlight = rl.Color.init(
                color.r orelse 0,
                color.g orelse 0,
                color.b orelse 0,
                color.a orelse 0,
            );
        }

        if (configStyle.errorBackground) |color| {
            config.style.errorBackground = rl.Color.init(
                color.r orelse 0,
                color.g orelse 0,
                color.b orelse 0,
                color.a orelse 0,
            );
        }

        if (configStyle.errorText) |color| {
            config.style.errorText = rl.Color.init(
                color.r orelse 0,
                color.g orelse 0,
                color.b orelse 0,
                color.a orelse 0,
            );
        }

        if (configStyle.headerBackground) |color| {
            config.style.headerBackground = rl.Color.init(
                color.r orelse 0,
                color.g orelse 0,
                color.b orelse 0,
                color.a orelse 0,
            );
        }

        if (configStyle.headerText) |color| {
            config.style.headerText = rl.Color.init(
                color.r orelse 0,
                color.g orelse 0,
                color.b orelse 0,
                color.a orelse 0,
            );
        }

        if (configStyle.lineHighlight) |color| {
            config.style.lineHighlight = rl.Color.init(
                color.r orelse 0,
                color.g orelse 0,
                color.b orelse 0,
                color.a orelse 0,
            );
        }

        if (configStyle.scrollbarBackground) |color| {
            config.style.scrollbarBackground = rl.Color.init(
                color.r orelse 0,
                color.g orelse 0,
                color.b orelse 0,
                color.a orelse 0,
            );
        }

        if (configStyle.scrollbarForeground) |color| {
            config.style.scrollbarForeground = rl.Color.init(
                color.r orelse 0,
                color.g orelse 0,
                color.b orelse 0,
                color.a orelse 0,
            );
        }

        if (configStyle.statusbarBackground) |color| {
            config.style.statusbarBackground = rl.Color.init(
                color.r orelse 0,
                color.g orelse 0,
                color.b orelse 0,
                color.a orelse 0,
            );
        }

        if (configStyle.statusbarText) |color| {
            config.style.statusbarText = rl.Color.init(
                color.r orelse 0,
                color.g orelse 0,
                color.b orelse 0,
                color.a orelse 0,
            );
        }

        if (configStyle.text) |color| {
            config.style.text = rl.Color.init(
                color.r orelse 0,
                color.g orelse 0,
                color.b orelse 0,
                color.a orelse 0,
            );
        }

        if (configStyle.textHighlighted) |color| {
            config.style.textHighlighted = rl.Color.init(
                color.r orelse 0,
                color.g orelse 0,
                color.b orelse 0,
                color.a orelse 0,
            );
        }
    }

    if (parsed.value.bytesPerLine) |bytesPerLine| {
        config.bytesPerLine = std.math.clamp(
            bytesPerLine,
            BYTES_PER_LINE_MIN,
            BYTES_PER_LINE_MAX,
        );
    }

    if (parsed.value.errorDuration) |errorDuration| {
        config.errorDuration = std.math.clamp(
            errorDuration,
            ERROR_DURATION_MIN,
            ERROR_DURATION_MAX,
        );
    }

    if (parsed.value.screenLines) |screenLines| {
        config.screenLines = std.math.clamp(
            screenLines,
            SCREEN_LINES_MIN,
            SCREEN_LINES_MAX,
        );
    }

    if (parsed.value.scrollbarScale) |scrollbarScale| {
        config.scrollbarScale = std.math.clamp(
            scrollbarScale,
            SCROLLBAR_SCALE_MIN,
            SCROLLBAR_SCALE_MAX,
        );
    }

    try configureFontAndScreen();
}

pub fn saveConfiguration() anyerror!void {
    var string = std.ArrayList(u8).init(gpa.allocator());

    try std.json.stringify(config, .{}, string.writer());

    const configFile: std.fs.File = try std.fs.cwd().createFile(CONFIG_FILE, .{});
    defer configFile.close();

    _ = try configFile.writeAll(string.items);
}

pub fn getCameraMouseX() i32 {
    return rl.getMouseX() - @as(i32, @intFromFloat(camera.offset.x));
}

pub fn getCameraMouseY() i32 {
    return rl.getMouseY() - @as(i32, @intFromFloat(camera.offset.y));
}

pub fn searchData(direction: SearchDirection, retry: bool) anyerror!void {
    if (commandHandler.buffer.count < 1) {
        return;
    }

    if (commandHandler.buffer.count > rom.size) {
        return;
    }

    const searchNeedle: []u8 = commandHandler.buffer.data[0..commandHandler.buffer.count];

    if (rom.typingReplacements != null) {
        for (0..searchNeedle.len) |i| {
            if (!rom.typingReplacements.?.contains(searchNeedle[i])) {
                continue;
            }

            searchNeedle[i] = rom.typingReplacements.?.get(searchNeedle[i]).?;
        }
    }

    const searchStart: u31 = if (!retry) editLine * BYTES_PER_LINE + editColumn + 1 else 0;
    const searchEnd: u31 = if (!retry) editLine * BYTES_PER_LINE + editColumn + @as(u31, @intCast(searchNeedle.len)) - 1 else @as(u31, @intCast(rom.size));

    var foundAtIndex: ?usize = null;

    if (direction == .Forward) {
        foundAtIndex = std.mem.indexOf(u8, rom.data[searchStart..], searchNeedle);
    } else {
        foundAtIndex = std.mem.lastIndexOf(u8, rom.data[0..searchEnd], searchNeedle);
    }

    if (foundAtIndex == null) {
        if (!retry) {
            try searchData(direction, true);
        } else {
            try showError("Not found");
        }

        return;
    }

    if (direction == .Forward) {
        foundAtIndex = foundAtIndex.? + searchStart;
    }

    const foundAtLine: u31 = @as(u31, @intCast(@divFloor(foundAtIndex.?, BYTES_PER_LINE)));
    const foundAtColumn: u8 = @as(u8, @intCast(@mod(foundAtIndex.?, BYTES_PER_LINE)));

    if (foundAtLine > editLine) {
        try scrollEditBy(foundAtLine - editLine, .Down);
    } else if (foundAtLine < editLine) {
        try scrollEditBy(editLine - foundAtLine, .Up);
    }

    editColumn = foundAtColumn;
    editNibble = 0;
}

pub fn relativeSearchData(direction: SearchDirection, retry: bool) anyerror!void {
    if (commandHandler.buffer.count < 2) {
        return;
    }

    if (commandHandler.buffer.count > rom.size) {
        return;
    }

    const searchNeedle: []u8 = commandHandler.buffer.data[0..commandHandler.buffer.count];

    if (rom.typingReplacements != null) {
        for (0..searchNeedle.len) |i| {
            if (!rom.typingReplacements.?.contains(searchNeedle[i])) {
                continue;
            }

            searchNeedle[i] = rom.typingReplacements.?.get(searchNeedle[i]).?;
        }
    }

    const searchStart: u31 = if (!retry) editLine * BYTES_PER_LINE + editColumn + 1 else 0;
    const searchEnd: u31 = if (!retry) editLine * BYTES_PER_LINE + editColumn + @as(u31, @intCast(searchNeedle.len)) - 1 - 1 else @as(u31, @intCast(rom.size));

    var relativeDifferences: [INPUT_BUFFER_SIZE - 2]i9 = .{0} ** (INPUT_BUFFER_SIZE - 2);

    for (1..commandHandler.buffer.count) |i| {
        relativeDifferences[i - 1] = @as(i9, @intCast(commandHandler.buffer.data[i])) - @as(i9, @intCast(commandHandler.buffer.data[i - 1]));
    }

    var foundAtIndex: ?usize = null;

    if (direction == .Forward) {
        for (searchStart..rom.size - (commandHandler.buffer.count - 1)) |i| {
            var found: bool = true;

            for (0..commandHandler.buffer.count - 1) |j| {
                const difference: i9 = @as(i9, @intCast(rom.data[i + j + 1])) - @as(i9, @intCast(rom.data[i + j]));

                if (difference != relativeDifferences[j]) {
                    found = false;

                    break;
                }
            }

            if (found) {
                foundAtIndex = i;

                break;
            }
        }
    } else {
        var i: usize = searchEnd;

        while (i >= (commandHandler.buffer.count - 1)) {
            var found: bool = true;

            for (0..commandHandler.buffer.count - 1) |j| {
                const difference: i9 = @as(i9, @intCast(rom.data[i - (commandHandler.buffer.count - 1) + j + 1])) - @as(i9, @intCast(rom.data[i - (commandHandler.buffer.count - 1) + j]));

                if (difference != relativeDifferences[j]) {
                    found = false;

                    break;
                }
            }

            if (found) {
                foundAtIndex = i - (commandHandler.buffer.count - 1);

                break;
            }

            i -= 1;
        }
    }

    if (foundAtIndex == null) {
        if (!retry) {
            try relativeSearchData(direction, true);
        } else {
            try showError("Not found");
        }

        return;
    }

    const foundAtLine: u31 = @as(u31, @intCast(@divFloor(foundAtIndex.?, BYTES_PER_LINE)));
    const foundAtColumn: u8 = @as(u8, @intCast(@mod(foundAtIndex.?, BYTES_PER_LINE)));

    if (foundAtLine > editLine) {
        try scrollEditBy(foundAtLine - editLine, .Down);
    } else if (foundAtLine < editLine) {
        try scrollEditBy(editLine - foundAtLine, .Up);
    }

    editColumn = foundAtColumn;
    editNibble = 0;
}

pub fn processEditorShortcuts() anyerror!void {
    if (rl.isKeyPressed(.escape)) {
        if (editorMode != .Command or commandHandler.mode != .Menu) {
            editorMode = .Command;
            commandHandler.mode = .Menu;

            commandHandler.reset();
        } else if (rom.size > 0) {
            editorMode = .Edit;
        }
    }

    if (rl.isKeyDown(.left_control)) {
        if (rl.isKeyPressed(.equal)) {
            config.font.size = @min(config.font.size + 1, FONT_SIZE_MAX);

            try configureFontAndScreen();
            try saveConfiguration();
        } else if (rl.isKeyPressed(.minus)) {
            config.font.size = @max(FONT_SIZE_MIN, config.font.size - 1);

            try configureFontAndScreen();
            try saveConfiguration();
        }
    }
}

pub fn processEditorMouse() anyerror!void {
    const wheel: f32 = rl.getMouseWheelMove();

    if (wheel != 0.0) {
        if (rl.isKeyDown(.left_control)) {
            const amount: u8 = @as(u8, @intFromFloat(@abs(wheel)));

            if (wheel < 0) {
                config.font.size = @max(FONT_SIZE_MIN, config.font.size - amount);

                try saveConfiguration();
            } else {
                config.font.size = @min(config.font.size + amount, FONT_SIZE_MAX);

                try saveConfiguration();
            }

            try configureFontAndScreen();
        }
    }
}

pub fn processCommandKeyboard() anyerror!void {
    if (commandHandler.mode == .Menu) {
        if (rl.isKeyPressed(.q)) {
            shouldClose = true;
        } else if (rl.isKeyPressed(.o)) {
            commandHandler.mode = .Open;
        } else if (rl.isKeyPressed(.w)) {
            commandHandler.mode = .Write;
        } else if (rl.isKeyPressed(.p)) {
            if (rom.size == 0) {
                return;
            }

            const filename: []u8 = try gpa.allocator().alloc(u8, rom.filename.len);
            defer gpa.allocator().free(filename);

            @memcpy(filename, rom.filename);

            rom.deinit();

            rom = try ROM.init(filename);

            editorMode = .Edit;
        } else if (rl.isKeyPressed(.s)) {
            commandHandler.mode = .Search;
        } else if (rl.isKeyPressed(.r)) {
            commandHandler.mode = .RelativeSearch;
        } else if (rl.isKeyPressed(.g)) {
            commandHandler.mode = .GotoAddress;
        } else if (rl.isKeyPressed(.t)) {
            try loadConfiguration();
        }

        commandHandler.reset();

        if (commandHandler.mode == .GotoAddress) {
            commandHandler.buffer.maxLength = 8;
        } else if (commandHandler.mode == .Open or commandHandler.mode == .Write) {
            for (0..rom.filename.len) |i| {
                commandHandler.buffer.data[i] = rom.filename[i];
            }

            commandHandler.buffer.count = @truncate(rom.filename.len);
            commandHandler.buffer.setIndex(@truncate(rom.filename.len));
        }

        return;
    }

    if (rl.isKeyPressed(.backspace) or rl.isKeyPressedRepeat(.backspace)) {
        if (commandHandler.buffer.count == 0 or commandHandler.buffer.index == 0) {
            return;
        }

        for (commandHandler.buffer.index - 1..commandHandler.buffer.count) |i| {
            commandHandler.buffer.data[i] = commandHandler.buffer.data[i + 1];
        }

        commandHandler.buffer.count -= 1;

        commandHandler.buffer.decreaseIndex();

        return;
    } else if (rl.isKeyPressed(.delete) or rl.isKeyPressedRepeat(.delete)) {
        if (commandHandler.buffer.count == 0 or commandHandler.buffer.index == commandHandler.buffer.count) {
            return;
        }

        for (commandHandler.buffer.index..commandHandler.buffer.count) |i| {
            commandHandler.buffer.data[i] = commandHandler.buffer.data[i + 1];
        }

        commandHandler.buffer.count -= 1;

        if (commandHandler.buffer.mode == .Replace and commandHandler.buffer.index == commandHandler.buffer.count) {
            commandHandler.buffer.decreaseIndex();

            if (commandHandler.buffer.count == 0) {
                commandHandler.buffer.setMode(.Insert);
            }
        }

        return;
    } else if (rl.isKeyPressed(.home) or rl.isKeyPressedRepeat(.home)) {
        commandHandler.buffer.setIndex(0);

        return;
    } else if (rl.isKeyPressed(.end) or rl.isKeyPressedRepeat(.end)) {
        commandHandler.buffer.setIndex(commandHandler.buffer.count);

        return;
    } else if (rl.isKeyPressed(.left) or rl.isKeyPressedRepeat(.left)) {
        if (commandHandler.buffer.index > 0) {
            commandHandler.buffer.decreaseIndex();
        }

        return;
    } else if (rl.isKeyPressed(.right) or rl.isKeyPressed(.right)) {
        if (commandHandler.buffer.index < commandHandler.buffer.count) {
            commandHandler.buffer.increaseIndex();
        }

        return;
    } else if (rl.isKeyPressed(.insert) or rl.isKeyPressedRepeat(.insert)) {
        commandHandler.buffer.setMode(@enumFromInt(@intFromEnum(commandHandler.buffer.mode) ^ 1));

        if (commandHandler.buffer.count == 0) {
            return;
        }

        if (commandHandler.buffer.mode == .Insert and commandHandler.buffer.index == commandHandler.buffer.count - 1) {
            commandHandler.buffer.setIndex(commandHandler.buffer.count);
        } else if (commandHandler.buffer.mode == .Replace and commandHandler.buffer.index == commandHandler.buffer.count) {
            commandHandler.buffer.setIndex(commandHandler.buffer.count - 1);
        }

        return;
    } else if (rl.isKeyPressed(.enter)) {
        if (commandHandler.buffer.count == 0) {
            return;
        }

        if (commandHandler.mode == .Open) {
            if (rom.size > 0) {
                rom.deinit();
            }

            rom = try ROM.init(commandHandler.buffer.data[0..commandHandler.buffer.count]);

            editLine = 0;
            editColumn = 0;
            editNibble = 0;

            editorMode = .Edit;
        } else if (commandHandler.mode == .Write and rom.size > 0) {
            const romFile: std.fs.File = try std.fs.cwd().createFile(commandHandler.buffer.data[0..commandHandler.buffer.count], .{});
            defer romFile.close();

            try romFile.writeAll(rom.data);

            const romFilename: []u8 = try gpa.allocator().alloc(u8, commandHandler.buffer.count);

            @memcpy(romFilename, commandHandler.buffer.data[0..commandHandler.buffer.count]);

            gpa.allocator().free(rom.filename);

            rom.filename = romFilename;

            editorMode = .Edit;
        } else if (commandHandler.mode == .Search and rom.size > 0) {
            try searchData(.Forward, false);

            editorMode = .Edit;
        } else if (commandHandler.mode == .RelativeSearch and rom.size > 0) {
            try relativeSearchData(.Forward, false);

            editorMode = .Edit;
        } else if (commandHandler.mode == .GotoAddress and rom.size > 0) {
            const newAddress: u32 = try std.fmt.parseInt(u32, commandHandler.buffer.data[0..commandHandler.buffer.count], 16);
            const newLine: u31 = @as(u31, @intCast(@divFloor(newAddress, BYTES_PER_LINE)));
            const newColumn: u8 = @as(u8, @intCast(@mod(newAddress, BYTES_PER_LINE)));

            if (newLine > editLine) {
                try scrollEditBy(newLine - editLine, .Down);
            } else if (newLine < editLine) {
                try scrollEditBy(editLine - newLine, .Up);
            }

            editColumn = newColumn;

            editorMode = .Edit;
        }

        return;
    }

    if (commandHandler.buffer.mode == .Insert and commandHandler.buffer.count == INPUT_BUFFER_SIZE) {
        return;
    }

    if (commandHandler.buffer.mode == .Replace or commandHandler.buffer.count < commandHandler.buffer.maxLength) {
        var key: u8 = @as(u8, @intCast(rl.getCharPressed()));

        while (key != 0) {
            if (commandHandler.mode == .GotoAddress and !std.mem.containsAtLeast(u8, &HEXADECIMAL_CHARACTERS, 1, &.{key})) {
                key = @as(u8, @intCast(rl.getCharPressed()));

                continue;
            }

            if (commandHandler.buffer.mode == .Insert) {
                var i: usize = commandHandler.buffer.count;

                while (i >= commandHandler.buffer.index and i > 0) {
                    commandHandler.buffer.data[i] = commandHandler.buffer.data[i - 1];

                    i -= 1;
                }

                commandHandler.buffer.count += 1;
            }

            commandHandler.buffer.data[commandHandler.buffer.index] = key;

            if (commandHandler.buffer.mode == .Insert or commandHandler.buffer.index < commandHandler.buffer.count - 1) {
                commandHandler.buffer.increaseIndex();
            }

            key = @as(u8, @intCast(rl.getCharPressed()));
        }
    }
}

pub fn drawCommandFrame() anyerror!void {
    // Clear background
    rl.clearBackground(config.style.background);

    // Draw top bar
    rl.drawRectangle(0, 0, screenWidth, lineHeight, config.style.headerBackground);

    lineBuffer.clearRetainingCapacity();

    try lineBuffer.writer().print("{[value]s: ^[width]}", .{ .value = "Stardust", .width = SCREEN_COLUMNS });
    try lineBuffer.append(0);

    drawTextCustom(@ptrCast(lineBuffer.items), fontSpacingHalf, lineSpacingHalf, config.style.headerText);

    // Draw status bar
    rl.drawRectangle(0, screenHeight - lineHeight, screenWidth, lineHeight, config.style.statusbarBackground);

    if (commandHandler.mode == .Menu) {
        lineBuffer.clearRetainingCapacity();

        try lineBuffer.writer().print("{[value]s: ^[width]}", .{ .value = "C O M M A N D S", .width = SCREEN_COLUMNS });
        try lineBuffer.append(0);

        drawTextCustom(@ptrCast(lineBuffer.items), fontSpacingHalf, 2 * lineHeight + lineSpacingHalf, config.style.text);

        const menuItems: [9][]const u8 = .{
            "o     Open file             ",
            "w     Write file            ",
            "p     Reload file           ",
            "s     Search text           ",
            "r     Search text relatively",
            "g     Go to address         ",
            "t     Reload theme          ",
            "Esc   Back to editor        ",
            "q     Quit                  ",
        };

        for (0..menuItems.len, menuItems) |menuIndex, menuItem| {
            lineBuffer.clearRetainingCapacity();

            try lineBuffer.writer().print("{[value]s: ^[width]}", .{ .value = menuItem, .width = SCREEN_COLUMNS });
            try lineBuffer.append(0);

            drawTextCustom(@ptrCast(lineBuffer.items), fontSpacingHalf, (4 + @as(i32, @intCast(menuIndex))) * lineHeight + lineSpacingHalf, config.style.text);
        }
    }

    lineBuffer.clearRetainingCapacity();

    try lineBuffer.writer().print("{[value]s: ^[width]}", .{ .value = "By Wagner \"SultansOfCode\" Barongello", .width = SCREEN_COLUMNS });
    try lineBuffer.append(0);

    drawTextCustom(@ptrCast(lineBuffer.items), fontSpacingHalf, (SCREEN_LINES - 2) * lineHeight + lineSpacingHalf, config.style.text);

    lineBuffer.clearRetainingCapacity();

    try lineBuffer.writer().print("{[value]s: ^[width]}", .{ .value = "Version 0.1b", .width = SCREEN_COLUMNS });
    try lineBuffer.append(0);

    drawTextCustom(@ptrCast(lineBuffer.items), fontSpacingHalf, (SCREEN_LINES - 1) * lineHeight + lineSpacingHalf, config.style.text);

    // Handle status bar
    lineBuffer.clearRetainingCapacity();

    try lineBuffer.appendSlice(switch (commandHandler.mode) {
        .GotoAddress => " Go to address: ",
        .Menu => " Command: ",
        .Open => " Open: ",
        .Write => " Write: ",
        .Search => " Search: ",
        .RelativeSearch => " Relative search: ",
    });

    try lineBuffer.append(0);

    const inputY: u31 = screenHeight - lineHeight + lineSpacingHalf;

    drawTextCustom(@ptrCast(lineBuffer.items), fontSpacingHalf, inputY, config.style.statusbarText);

    // Handle input
    const inputX: u31 = (commandHandler.textSize + commandHandler.buffer.index) * characterWidth;

    rl.drawRectangleLines(inputX, inputY, if (commandHandler.buffer.mode == .Insert) 1 else characterWidth, lineHeight, config.style.statusbarText);

    drawTextCustom(&commandHandler.buffer.data, commandHandler.textSize * characterWidth, inputY, config.style.statusbarText);
}

pub fn scrollEditBy(amount: u31, direction: ScrollDirection) anyerror!void {
    if (amount == 0) {
        return;
    }

    if (direction == .Up and editLine == 0) {
        editColumn = 0;
        editNibble = 0;

        return;
    }

    if (direction == .Down and editLine == rom.lastLine) {
        editColumn = BYTES_PER_LINE - 1;
        editNibble = 0;

        return;
    }

    if (direction == .Left and editLine == 0 and editColumn == 0) {
        return;
    }

    if (direction == .Right and editLine == rom.lastLine and editColumn == BYTES_PER_LINE - 1) {
        return;
    }

    if (direction == .Up or direction == .Down) {
        const viewTopLine: u31 = @divFloor(rom.address, BYTES_PER_LINE);
        const viewBottomLine: u31 = viewTopLine + SCREEN_LINES - 1;

        var newLine: u31 = undefined;

        if (direction == .Down) {
            newLine = @min(editLine + amount, rom.lastLine);
        } else if (direction == .Up) {
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
        if (direction == .Left) {
            if (editColumn > 0) {
                editColumn -= 1;
            } else if (editLine > 0) {
                editColumn = BYTES_PER_LINE - 1;

                try scrollEditBy(1, .Up);
            }
        } else {
            if (editColumn < BYTES_PER_LINE - 1) {
                editColumn += 1;
            } else if (editLine < rom.lastLine) {
                editColumn = 0;

                try scrollEditBy(1, .Down);
            }
        }
    }
}

pub fn scrollEditByScrollbar() anyerror!void {
    const scrollbarLimitTop: u31 = lineHeight + scrollbarHeightHalf;
    const scrollbarLimitBottom: u31 = screenHeight - lineHeight - scrollbarHeightHalf;
    const mouseY: u31 = @as(u31, @intCast(std.math.clamp(getCameraMouseY(), scrollbarLimitTop, scrollbarLimitBottom))) - scrollbarLimitTop;
    const scrollbarSpace: u31 = SCREEN_LINES * lineHeight - scrollbarHeight;
    const scrollbarPercentage: f32 = @as(f32, @floatFromInt(mouseY)) / @as(f32, @floatFromInt(scrollbarSpace));
    const scrolledLine: u31 = @as(u31, @intFromFloat(@as(f32, @floatFromInt(rom.lastLine)) * scrollbarPercentage));
    const linesDifference: u31 = @as(u31, @intCast(@abs(@as(i32, @intCast(editLine)) - @as(i32, @intCast(scrolledLine)))));

    if (scrolledLine < editLine) {
        try scrollEditBy(linesDifference, .Up);
    } else if (scrolledLine > editLine) {
        try scrollEditBy(linesDifference, .Down);
    }
}

pub fn advanceNibble(direction: ScrollDirection) anyerror!void {
    if (direction == .Left) {
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
    if (rl.isKeyPressed(.down) or rl.isKeyPressedRepeat(.down)) {
        try scrollEditBy(1, .Down);
    } else if (rl.isKeyPressed(.up) or rl.isKeyPressedRepeat(.up)) {
        try scrollEditBy(1, .Up);
    } else if (rl.isKeyPressed(.page_down) or rl.isKeyPressedRepeat(.page_down)) {
        try scrollEditBy(SCREEN_LINES, .Down);
    } else if (rl.isKeyPressed(.page_up) or rl.isKeyPressedRepeat(.page_up)) {
        try scrollEditBy(SCREEN_LINES, .Up);
    } else if (rl.isKeyPressed(.left) or rl.isKeyPressedRepeat(.left)) {
        if (editMode == .Character) {
            try scrollEditBy(1, .Left);
        } else {
            try advanceNibble(.Left);
        }
    } else if (rl.isKeyPressed(.right) or rl.isKeyPressedRepeat(.right)) {
        if (editMode == .Character) {
            try scrollEditBy(1, .Right);
        } else {
            try advanceNibble(.Right);
        }
    } else if (rl.isKeyPressed(.tab) or rl.isKeyPressedRepeat(.tab)) {
        editMode = @enumFromInt(@as(u2, @intFromEnum(editMode) ^ 1));
        editNibble = 0;
    } else if (rl.isKeyDown(.home)) {
        editColumn = 0;
        editNibble = 0;
    } else if (rl.isKeyDown(.end)) {
        editColumn = BYTES_PER_LINE - 1;
        editNibble = 0;
    }

    if (rl.isKeyDown(.left_control)) {
        if (rl.isKeyDown(.home)) {
            editColumn = 0;
            editNibble = 0;

            try scrollEditBy(editLine, .Up);
        } else if (rl.isKeyDown(.end)) {
            editColumn = BYTES_PER_LINE - 1;
            editNibble = 0;

            try scrollEditBy(rom.lines - editLine - 1, .Down);
        }
    }

    if ((rl.isKeyPressed(.f3) or rl.isKeyPressedRepeat(.f3)) and (commandHandler.mode == .Search or commandHandler.mode == .RelativeSearch) and commandHandler.buffer.count > 0) {
        if (commandHandler.mode == .Search) {
            try searchData(if (rl.isKeyDown(.left_shift)) .Backward else .Forward, false);
        } else if (commandHandler.mode == .RelativeSearch) {
            try relativeSearchData(if (rl.isKeyDown(.left_shift)) .Backward else .Forward, false);
        }
    }
}

pub fn processEditKeyboard() anyerror!void {
    var key: u8 = @as(u8, @intCast(rl.getCharPressed()));

    while (key != 0) {
        if (editMode == .Hexadecimal) {
            if (std.mem.containsAtLeast(u8, &HEXADECIMAL_CHARACTERS, 1, &.{key})) {
                const byteIndex: u31 = editLine * BYTES_PER_LINE + editColumn;
                const byte: u8 = rom.data[byteIndex];
                const typedByte: u8 = try std.fmt.parseInt(u8, &.{key}, 16);

                if (editNibble == 0) {
                    rom.data[byteIndex] = typedByte * 0x10 + (byte & 0x0F);
                } else {
                    rom.data[byteIndex] = (byte & 0xF0) + typedByte;
                }

                try advanceNibble(.Right);
            }
        } else {
            const byteIndex: u31 = editLine * BYTES_PER_LINE + editColumn;
            const byte: u8 = if (rom.typingReplacements.?.contains(key)) rom.typingReplacements.?.get(key).? else rom.symbols[key];

            rom.data[byteIndex] = byte;

            try scrollEditBy(1, .Right);
        }

        key = @as(u8, @intCast(rl.getCharPressed()));
    }
}

pub fn processEditMouse() anyerror!void {
    const wheel: f32 = rl.getMouseWheelMove();

    if (wheel != 0.0) {
        const amount: u31 = @as(u31, @intFromFloat(@round(@abs(wheel) * 3)));

        if (wheel < 0) {
            try scrollEditBy(amount, .Down);
        } else {
            try scrollEditBy(amount, .Up);
        }
    }

    if (rl.isMouseButtonDown(rl.MouseButton.left)) {
        if (scrollbarClicked) {
            try scrollEditByScrollbar();

            return;
        }

        const mouseX: i32 = getCameraMouseX();
        const mouseY: i32 = getCameraMouseY();

        if (mouseX < 0 or mouseX >= screenWidth or mouseY < 0 or mouseY >= screenHeight) {
            return;
        }

        const line: u31 = @divFloor(@as(u31, @intCast(mouseY)), lineHeight);
        const column: u31 = @divFloor(@as(u31, @intCast(mouseX)), characterWidth);

        viewArea: {
            if (line < 1 or line > SCREEN_LINES) {
                break :viewArea;
            }

            if (rl.isMouseButtonPressed(.left) and column == SCREEN_COLUMNS - 1) {
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
                        editMode = .Hexadecimal;
                        editNibble = @as(u1, @intCast(nibbleIndex));
                        editColumn = @as(u8, @intCast(byteIndex));
                    }
                } else if (column >= charactersStartColumn and column <= charactersEndColumn) {
                    const byteIndex: u31 = column - charactersStartColumn;

                    editMode = .Character;
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
    rl.clearBackground(config.style.background);

    // Draw top bar
    rl.drawRectangle(0, 0, screenWidth, lineHeight, config.style.headerBackground);

    drawTextCustom(@ptrCast(headerBuffer.items), fontSpacingHalf, lineSpacingHalf, config.style.headerText);

    // Draw status bar
    rl.drawRectangle(0, screenHeight - lineHeight, screenWidth, lineHeight, config.style.statusbarBackground);

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
    try lineBuffer.writer().print("{s}", .{if (editMode == .Character) "Character" else "Hexadecimal"});
    try lineBuffer.append(0);

    drawTextCustom(@ptrCast(lineBuffer.items), fontSpacingHalf, screenHeight - lineHeight + lineSpacingHalf, config.style.statusbarText);

    // Draw selected highlight
    rl.drawRectangle(0, (editLine - viewTopLine + 1) * lineHeight, screenWidth - characterWidth, lineHeight, config.style.lineHighlight);

    const editHighlightY: i32 = (editLine - viewTopLine + 1) * lineHeight;
    const editHexadecimalHighlightX: i32 = (8 + 1 + (editColumn * 3) + editNibble) * characterWidth;
    const editCharacterHighlightX: i32 = (8 + 1 + (2 * BYTES_PER_LINE) + (BYTES_PER_LINE - 1) + 1 + editColumn) * characterWidth;

    if (editMode == .Character) {
        rl.drawRectangleLines(editHexadecimalHighlightX, editHighlightY, characterWidth * 2, lineHeight, rl.Color.black);
        rl.drawRectangle(editCharacterHighlightX, editHighlightY, characterWidth, lineHeight, config.style.characterHighlight);
    } else {
        rl.drawRectangle(editHexadecimalHighlightX, editHighlightY, characterWidth, lineHeight, config.style.characterHighlight);
        rl.drawRectangleLines(editCharacterHighlightX, editHighlightY, characterWidth, lineHeight, rl.Color.black);
    }

    // Draw scrollbar
    const scrollbarSpace: u31 = SCREEN_LINES * lineHeight - scrollbarHeight;
    const scrollbarX: u31 = screenWidth - characterWidth;
    const scrollbarY: u31 = @as(u31, @intFromFloat(@as(f32, @floatFromInt(editLine)) * @as(f32, @floatFromInt(scrollbarSpace)) / @as(f32, @floatFromInt(rom.lastLine)) + @as(f32, @floatFromInt(lineHeight))));

    rl.drawRectangle(screenWidth - characterWidth, lineHeight, characterWidth, SCREEN_LINES * lineHeight, config.style.scrollbarBackground);
    rl.drawRectangle(scrollbarX, scrollbarY, characterWidth, scrollbarHeight, config.style.scrollbarForeground);

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

        drawTextCustom(@ptrCast(lineBuffer.items), fontSpacingHalf, @as(u31, @intCast(i + 1)) * lineHeight + lineSpacingHalf, if (viewTopLine + @as(u31, @intCast(i)) == editLine) config.style.textHighlighted else config.style.text);
    }
}

pub fn processAndDrawError() anyerror!void {
    if (errorBuffer.items.len == 0) {
        return;
    }

    rl.drawRectangle(0, 0, screenWidth, lineHeight, config.style.errorBackground);

    drawTextCustom(@ptrCast(errorBuffer.items), fontSpacingHalf, lineSpacingHalf, config.style.errorText);

    errorElapsed += rl.getFrameTime();

    if (errorElapsed < config.errorDuration) {
        return;
    }

    errorBuffer.clearAndFree();

    errorElapsed = 0.0;
}

pub fn showError(message: []const u8) anyerror!void {
    try errorBuffer.writer().print("ERROR: {s}", .{message});
    try errorBuffer.append(0);

    errorElapsed = 0;
}

pub fn main() anyerror!u8 {
    gpa = std.heap.GeneralPurposeAllocator(.{}){};

    errorBuffer = std.ArrayList(u8).init(gpa.allocator());
    defer errorBuffer.deinit();

    headerBuffer = std.ArrayList(u8).init(gpa.allocator());
    defer headerBuffer.deinit();

    lineBuffer = std.ArrayList(u8).init(gpa.allocator());
    defer lineBuffer.deinit();

    rl.initWindow(814, 640, "Stardust");
    defer rl.closeWindow();

    const icon: rl.Image = try rl.loadImage("resources/icon.png");
    defer rl.unloadImage(icon);

    rl.setWindowIcon(icon);

    rl.setExitKey(.null);

    try loadConfiguration();
    defer if (font.glyphCount > 0) rl.unloadFont(font);

    rl.setTargetFPS(60);

    camera = rl.Camera2D{
        .offset = rl.Vector2.init(0, 0),
        .target = rl.Vector2.init(0, 0),
        .rotation = 0.0,
        .zoom = 1.0,
    };

    while (!rl.windowShouldClose() and !shouldClose) {
        rl.beginDrawing();
        defer rl.endDrawing();

        const screenW = rl.getScreenWidth();
        const screenH = rl.getScreenHeight();

        camera.offset.x = @as(f32, @floatFromInt(screenW - screenWidth)) / 2;
        camera.offset.y = @as(f32, @floatFromInt(screenH - screenHeight)) / 2;

        rl.beginMode2D(camera);
        defer rl.endMode2D();

        try processEditorShortcuts();
        try processEditorMouse();

        if (editorMode == .Command) {
            try processCommandKeyboard();
            try drawCommandFrame();
        } else if (editorMode == .Edit) {
            try processEditShortcuts();
            try processEditKeyboard();
            try processEditMouse();

            try drawEditFrame();
        }

        try processAndDrawError();
    }

    return 0;
}
