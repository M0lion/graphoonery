const std = @import("std");

const MAGIC_NUMBER: u32 = 0x07230203;

const Header = extern struct {
    magicWord: u32,
    version: u32,
    generatorMagicNumber: u32,
    bound: u32,
    reserved: u32,
};

const InstructionHeader = extern struct {
    opcode: u16,
    wordCount: u16,
};

const OpCodes = enum(u16) {
    OpName = 5,
    OpMemberName = 6,
    OpTypeStruct = 30,
    OpTypePointer = 32,
    OpVariable = 59,
    OpDecorate = 71,
    _,

    fn fromU16(code: u16) OpCodes {
        return @as(OpCodes, @enumFromInt(code));
    }

    fn fromInstruction(instruction: Instruction) OpCodes {
        return OpCodes.fromU16(instruction.header.opcode);
    }
};

const Variable = struct {
    id: u32,
    type: SpirvType,
    binding: ?u32 = null,
    name: ?[]const u8 = null,
};

const Name = struct {
    id: u32,
    name: []const u8,
};

const Binding = struct {
    target: u32,
    binding: u32,
};

fn getVariable(variables: *ComtimeBufferArray(Variable), names: *ComtimeBufferArray(Name), id: u32) *Variable {
    for (variables.buffer[0..variables.len]) |*variable| {
        if (variable.id == id) return variable;
    }

    variables.append(Variable{
        .id = id,
    });

    var variable = &variables.buffer[variables.len - 1];

    if (variable.name == null) {
        for (names.slice()) |name| {
            if (name.id == variable.id) {
                variable.name = name.name;
                break;
            }
        }
    }

    return variable;
}

pub fn parseSpriv(comptime spirv: []const u8) []const Variable {
    const words: []const u32 = @alignCast(std.mem.bytesAsSlice(u32, spirv));

    var variables = ComtimeBufferArray(Variable).init();

    const header = @as(*const Header, @ptrCast(@alignCast(words.ptr)));

    if (header.magicWord != MAGIC_NUMBER) {
        @compileError("Invalid magic number for shader");
    }

    const instructions = Instructions{
        .words = words,
    };

    var iter = instructions.iter();
    @setEvalBranchQuota(instructions.words.len * instructions.words.len);
    while (iter.next()) |instruction| {
        switch (OpCodes.fromU16(instruction.header.opcode)) {
            .OpDecorate => {
                const target = instruction.words[1];
                const decorator = instruction.words[2];
                switch (decorator) {
                    33 => { // Binding
                        variables.append(getVariableForBinding(target, instruction.words[3], &instructions));
                    },
                    else => {},
                }
            },
            _ => {},
            else => {},
        }
    }

    const final = variables.slice()[0..].*;

    return &final;
}

fn getVariableForBinding(variableId: u32, binding: u32, instructions: *const Instructions) Variable {
    var iter = instructions.iter();
    while (iter.next()) |instruction| {
        if (OpCodes.fromU16(instruction.header.opcode) == OpCodes.OpVariable and variableId == instruction.words[2]) {
            return Variable{
                .id = variableId,
                .binding = binding,
                .name = getName(variableId, instructions),
                .type = getType(instruction.words[1], instructions),
            };
        }
    }
    @compileError(std.fmt.comptimePrint("Could not find variable {} for binding {}", .{ variableId, binding }));
}

fn getName(id: u32, instructions: *const Instructions) ?[]const u8 {
    var iter = instructions.iter();
    while (iter.next()) |instruction| {
        if (OpCodes.fromU16(instruction.header.opcode) == OpCodes.OpName and id == instruction.words[1]) {
            return std.mem.sliceTo(std.mem.sliceAsBytes(instruction.words[2..]), 0);
        }
    }
    return null;
}

fn getMemberName(id: u32, instructions: *const Instructions) ?[]const u8 {
    var iter = instructions.iter();
    while (iter.next()) |instruction| {
        if (OpCodes.fromU16(instruction.header.opcode) == OpCodes.OpMemberName and id == instruction.words[1]) {
            return std.mem.sliceTo(std.mem.sliceAsBytes(instruction.words[2..]), 0);
        }
    }
    return null;
}

const SpirvTypes = enum {
    Pointer,
    Struct,
};

const SpirvType = union(SpirvTypes) {
    Pointer: PointerType,
    Struct: StructType,
};

const PointerType = struct {
    target: SpirvType,
};

const StructType = struct {
    name: []const u8,
    members: ComtimeBufferArray(StructMember) = ComtimeBufferArray(StructMember).init(),
};

const StructMember = struct {
    type: SpirvType,
    name: []const u8,
};

fn getType(id: u32, instructions: *const Instructions) SpirvType {
    var iter = instructions.iter();
    while (iter.next()) |instruction| {
        if (instruction.words[1] == id) {
            switch (OpCodes.fromInstruction(instruction)) {
                .OpTypePointer => {
                    const targetTypeId = instruction.words[3];
                    const targetType = getType(targetTypeId, instructions);
                    return SpirvType{
                        .Pointer = PointerType{ .target = targetType },
                    };
                },
                .OpTypeStruct => {
                    const structType = StructType{
                        .name = getName(id, instructions),
                    };

                    for (instruction.words[3..]) |memberId| {
                        structType.members.append(StructMember{
                            .name = getMemberName(memberId, instructions),
                            .type = getType(memberId, instructions),
                        });
                    }

                    return SpirvType{
                        .Struct = structType,
                    };
                },
                else => {},
            }
        }
    }

    @compileError(std.fmt.comptimePrint("Could not find type {}", .{id}));
}

const Instruction = struct {
    header: *const InstructionHeader,
    words: []const u32,
};

const Instructions = struct {
    const initialOffset = 5;
    words: []const u32,

    const InstructionIterator = struct {
        words: []const u32,
        offset: usize = initialOffset,

        fn next(self: *InstructionIterator) ?Instruction {
            if (self.offset >= self.words.len) return null;

            const instructionHeader = @as(*const InstructionHeader, @ptrCast(@alignCast(self.words.ptr + self.offset)));
            const instructionWords = self.words[self.offset..(self.offset + instructionHeader.wordCount)];

            self.offset += instructionHeader.wordCount;

            return Instruction{
                .header = instructionHeader,
                .words = instructionWords,
            };
        }
    };

    fn iter(self: *const Instructions) InstructionIterator {
        return InstructionIterator{
            .words = self.words,
        };
    }
};

fn ComtimeBufferArray(t: type) type {
    return struct {
        const Self = @This();
        const bufferSize = 30;

        buffer: [30]t = undefined,
        len: usize = 0,

        fn init() Self {
            return Self{};
        }

        fn append(self: *Self, item: t) void {
            if (self.len >= self.buffer.len) {
                @compileError("Ran out of buffer");
            }

            self.buffer[self.len] = item;
            self.len += 1;
        }

        fn slice(self: *Self) []t {
            return self.buffer[0..self.len];
        }
    };
}
