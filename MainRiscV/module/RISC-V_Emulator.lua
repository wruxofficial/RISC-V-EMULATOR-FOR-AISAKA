local RISC_V = {}

local REGISTERS = {}
local MEMORY = {}
local PC = 0
local RUNNING = false
local MAX_MEM = 65536
local LOG = {}

function RISC_V:log(text)
	LOG[#LOG + 1] = text
end

function RISC_V:get_log()
	return table.concat(LOG, "\n")
end

function RISC_V:clear_log()
	LOG = {}
end

function RISC_V:init()
	for i = 0, 31 do REGISTERS[i] = 0 end
	for i = 1, MAX_MEM do MEMORY[i] = 0 end
	PC = 0
	RUNNING = true
	REGISTERS[0] = 0
	self:clear_log()
	self:log("CPU initialized")
end

function RISC_V:load_program(bytes)
	for i, byte in ipairs(bytes) do
		if i <= MAX_MEM then MEMORY[i] = byte end
	end
	self:log("Loaded " .. #bytes .. " bytes into memory")
end

function RISC_V:load_word(addr)
	local val = 0
	for i = 0, 3 do
		local byte = MEMORY[addr + i + 1] or 0
		val = val + byte * (256 ^ i)
	end
	return val
end

function RISC_V:store_word(addr, value)
	for i = 0, 3 do
		MEMORY[addr + i + 1] = bit32.band(bit32.rshift(value, i * 8), 255)
	end
end

function RISC_V:read_string(addr, max_len)
	local str = ""
	local i = 0
	while i < max_len do
		local byte = MEMORY[addr + i + 1] or 0
		if byte == 0 then break end
		str = str .. string.char(byte)
		i = i + 1
	end
	return str
end

function RISC_V:step()
	if not RUNNING then return false end
	if PC < 0 or PC >= MAX_MEM - 4 then
		self:log("ERROR: PC out of bounds at " .. string.format("0x%08X", PC))
		RUNNING = false
		return false
	end
	local instr = self:load_word(PC)
	local opcode = bit32.band(instr, 0x7F)
	local rd = bit32.band(bit32.rshift(instr, 7), 0x1F)
	local rs1 = bit32.band(bit32.rshift(instr, 15), 0x1F)
	local rs2 = bit32.band(bit32.rshift(instr, 20), 0x1F)
	local funct3 = bit32.band(bit32.rshift(instr, 12), 0x7)
	local funct7 = bit32.rshift(instr, 25)
	local imm_i = bit32.rshift(instr, 20)
	if bit32.band(imm_i, 0x800) ~= 0 then imm_i = bit32.bor(imm_i, 0xFFFFF000) end
	local imm_s = bit32.bor(
		bit32.band(bit32.rshift(instr, 20), 0xFE0),
		bit32.band(bit32.rshift(instr, 7), 0x1F)
	)
	if bit32.band(imm_s, 0x800) ~= 0 then imm_s = bit32.bor(imm_s, 0xFFFFF000) end
	local imm_b = bit32.bor(
		bit32.lshift(bit32.band(bit32.rshift(instr, 8), 0xF), 1),
		bit32.lshift(bit32.band(bit32.rshift(instr, 25), 0x3F), 5),
		bit32.lshift(bit32.band(bit32.rshift(instr, 7), 0x1), 11),
		bit32.lshift(bit32.band(bit32.rshift(instr, 31), 0x1), 12)
	)
	if bit32.band(imm_b, 0x1000) ~= 0 then imm_b = bit32.bor(imm_b, 0xFFFFE000) end
	local imm_u = bit32.band(bit32.rshift(instr, 12), 0xFFFFF)
	imm_u = bit32.lshift(imm_u, 12)
	local imm_j = bit32.bor(
		bit32.lshift(bit32.band(bit32.rshift(instr, 21), 0x3FF), 1),
		bit32.lshift(bit32.band(bit32.rshift(instr, 20), 0x1), 11),
		bit32.lshift(bit32.band(bit32.rshift(instr, 12), 0xFF), 12),
		bit32.lshift(bit32.band(bit32.rshift(instr, 31), 0x1), 20)
	)
	if bit32.band(imm_j, 0x100000) ~= 0 then imm_j = bit32.bor(imm_j, 0xFFE00000) end
	local jumped = false
	local op_name = "unknown"
	if opcode == 0x13 then
		local val = REGISTERS[rs1] or 0
		if funct3 == 0 then
			val = val + imm_i
			op_name = "addi"
		elseif funct3 == 1 then
			val = bit32.lshift(val, bit32.band(imm_i, 31))
			op_name = "slli"
		elseif funct3 == 2 then
			val = bit32.rshift(val, bit32.band(imm_i, 31))
			op_name = "srli"
		elseif funct3 == 3 then
			val = bit32.band(val, imm_i)
			op_name = "andi"
		elseif funct3 == 4 then
			val = bit32.bor(val, imm_i)
			op_name = "ori"
		elseif funct3 == 5 then
			val = bit32.bxor(val, imm_i)
			op_name = "xori"
		elseif funct3 == 6 then
			val = bit32.rshift(val, bit32.band(imm_i, 31))
			op_name = "srai"
		end
		if rd ~= 0 then REGISTERS[rd] = bit32.band(val, 0xFFFFFFFF) end
	elseif opcode == 0x33 then
		local val1 = REGISTERS[rs1] or 0
		local val2 = REGISTERS[rs2] or 0
		local val = 0
		if funct3 == 0 then
			if funct7 == 0 then
				val = val1 + val2
				op_name = "add"
			elseif funct7 == 32 then
				val = val1 - val2
				op_name = "sub"
			end
		elseif funct3 == 1 then
			val = bit32.lshift(val1, bit32.band(val2, 31))
			op_name = "sll"
		elseif funct3 == 2 then
			val = bit32.rshift(val1, bit32.band(val2, 31))
			op_name = "srl"
		elseif funct3 == 3 then
			val = bit32.band(val1, val2)
			op_name = "and"
		elseif funct3 == 4 then
			val = bit32.bor(val1, val2)
			op_name = "or"
		elseif funct3 == 5 then
			val = bit32.bxor(val1, val2)
			op_name = "xor"
		elseif funct3 == 6 then
			val = bit32.rshift(val1, bit32.band(val2, 31))
			op_name = "sra"
		elseif funct3 == 7 then
			val = 0
			if val1 < val2 then val = 1 end
			op_name = "slt"
		end
		if rd ~= 0 then REGISTERS[rd] = bit32.band(val, 0xFFFFFFFF) end
	elseif opcode == 0x03 then
		local addr = REGISTERS[rs1] + imm_i
		local val = 0
		if funct3 == 0 then
			val = MEMORY[addr + 1] or 0
			op_name = "lb"
		elseif funct3 == 1 then
			val = self:load_word(addr)
			val = bit32.band(val, 0xFFFF)
			op_name = "lh"
		elseif funct3 == 2 then
			val = self:load_word(addr)
			op_name = "lw"
		elseif funct3 == 4 then
			val = MEMORY[addr + 1] or 0
			op_name = "lbu"
		elseif funct3 == 5 then
			val = self:load_word(addr)
			val = bit32.band(val, 0xFFFF)
			op_name = "lhu"
		end
		if rd ~= 0 then REGISTERS[rd] = bit32.band(val, 0xFFFFFFFF) end
	elseif opcode == 0x23 then
		local addr = REGISTERS[rs1] + imm_s
		local val = REGISTERS[rs2] or 0
		if funct3 == 0 then
			MEMORY[addr + 1] = bit32.band(val, 255)
			op_name = "sb"
		elseif funct3 == 1 then
			self:store_word(addr, bit32.band(val, 0xFFFF))
			op_name = "sh"
		elseif funct3 == 2 then
			self:store_word(addr, val)
			op_name = "sw"
		end
	elseif opcode == 0x63 then
		local val1 = REGISTERS[rs1] or 0
		local val2 = REGISTERS[rs2] or 0
		local branch = false
		if funct3 == 0 then
			if val1 == val2 then branch = true end
			op_name = "beq"
		elseif funct3 == 1 then
			if val1 ~= val2 then branch = true end
			op_name = "bne"
		elseif funct3 == 4 then
			if val1 < val2 then branch = true end
			op_name = "blt"
		elseif funct3 == 5 then
			if val1 >= val2 then branch = true end
			op_name = "bge"
		elseif funct3 == 6 then
			if val1 < val2 then branch = true end
			op_name = "bltu"
		elseif funct3 == 7 then
			if val1 >= val2 then branch = true end
			op_name = "bgeu"
		end
		if branch then
			PC = PC + imm_b
			jumped = true
			self:log("Branch taken to " .. string.format("0x%08X", PC))
		end
	elseif opcode == 0x37 then
		if rd ~= 0 then REGISTERS[rd] = bit32.band(imm_u, 0xFFFFFFFF) end
		op_name = "lui"
	elseif opcode == 0x17 then
		if rd ~= 0 then REGISTERS[rd] = bit32.band(PC + imm_u, 0xFFFFFFFF) end
		op_name = "auipc"
	elseif opcode == 0x6F then
		if rd ~= 0 then REGISTERS[rd] = bit32.band(PC + 4, 0xFFFFFFFF) end
		PC = PC + imm_j
		jumped = true
		op_name = "jal"
		self:log("Jump to " .. string.format("0x%08X", PC))
	elseif opcode == 0x67 then
		if rd ~= 0 then REGISTERS[rd] = bit32.band(PC + 4, 0xFFFFFFFF) end
		PC = REGISTERS[rs1] + imm_i
		jumped = true
		op_name = "jalr"
		self:log("Jump to " .. string.format("0x%08X", PC))
	elseif opcode == 0x73 then
		if funct3 == 0 then
			local syscall_num = REGISTERS[17] or 0
			local a0 = REGISTERS[10] or 0
			local a1 = REGISTERS[11] or 0
			local a2 = REGISTERS[12] or 0

			if syscall_num == 64 then
				-- sys_write
				local fd = a0
				local buf = a1
				local len = a2
				local output = ""
				for i = 0, len - 1 do
					local byte = MEMORY[buf + i + 1] or 0
					if byte == 0 then break end
					output = output .. string.char(byte)
				end
				if fd == 1 or fd == 2 then
					print("[RISC-V] " .. output)
					self:log("[STDOUT] " .. output)
				else
					self:log("[WRITE fd=" .. fd .. "] " .. output)
				end
				REGISTERS[10] = len
				op_name = "ecall(write)"
			elseif syscall_num == 93 then
				-- sys_exit
				local exit_code = a0
				self:log("ECALL: exit(" .. exit_code .. ")")
				RUNNING = false
				op_name = "ecall(exit)"
			elseif syscall_num == 94 then
				-- sys_exit_group
				local exit_code = a0
				self:log("ECALL: exit_group(" .. exit_code .. ")")
				RUNNING = false
				op_name = "ecall(exit_group)"
			elseif syscall_num == 57 then
				-- sys_close
				self:log("ECALL: close(" .. a0 .. ")")
				REGISTERS[10] = 0
				op_name = "ecall(close)"
			elseif syscall_num == 63 then
				-- sys_openat
				self:log("ECALL: openat(" .. a0 .. ", 0x" .. string.format("%X", a1) .. ", " .. a2 .. ")")
				REGISTERS[10] = -1
				op_name = "ecall(openat)"
			elseif syscall_num == 160 then
				-- sys_getpid
				REGISTERS[10] = 1
				op_name = "ecall(getpid)"
			else
				self:log("ECALL: unknown syscall " .. syscall_num .. " (halt)")
				RUNNING = false
				op_name = "ecall(unknown)"
			end
		end
	else
		self:log("ERROR: Unknown opcode 0x" .. string.format("%02X", opcode) .. " at PC=0x" .. string.format("%08X", PC))
		RUNNING = false
		return false
	end
	if not jumped then
		PC = PC + 4
	end
	REGISTERS[0] = 0
	if PC >= MAX_MEM then
		RUNNING = false
		self:log("ERROR: PC out of memory bounds")
	end
	return true
end

function RISC_V:run(steps)
	steps = steps or 1000
	self:log("Running " .. steps .. " steps")
	for i = 1, steps do
		if not self:step() then break end
	end
	if RUNNING then
		self:log("Execution finished after " .. steps .. " steps")
	end
end

function RISC_V:get_registers()
	return REGISTERS
end

function RISC_V:get_pc()
	return PC
end

function RISC_V:get_memory()
	return MEMORY
end

function RISC_V:stop()
	RUNNING = false
	self:log("CPU stopped")
end

function RISC_V:is_running()
	return RUNNING
end

function RISC_V:assemble(code)
	self:clear_log()
	self:log("Assembling code...")
	local lines = {}
	for line in string.gmatch(code, "[^\r\n]+") do
		local trimmed = string.gsub(line, "%s+$", "")
		trimmed = string.gsub(trimmed, "^%s+", "")
		if trimmed ~= "" and string.sub(trimmed, 1, 1) ~= ";" then
			lines[#lines + 1] = trimmed
		end
	end
	local bytes = {}
	local labels = {}
	local addr = 0
	for i, line in ipairs(lines) do
		if string.find(line, ":") then
			local label = string.gsub(line, ":", "")
			labels[label] = addr
			self:log("Label " .. label .. " = " .. string.format("0x%08X", addr))
		else
			addr = addr + 4
		end
	end
	local function get_reg(name)
		local regs = {
			zero=0, ra=1, sp=2, gp=3, tp=4,
			t0=5, t1=6, t2=7,
			s0=8, fp=8, s1=9,
			a0=10, a1=11, a2=12, a3=13, a4=14, a5=15, a6=16, a7=17,
			s2=18, s3=19, s4=20, s5=21, s6=22, s7=23, s8=24, s9=25, s10=26, s11=27,
			t3=28, t4=29, t5=30, t6=31
		}
		if regs[name] then return regs[name] end
		if string.sub(name, 1, 1) == "x" then
			return tonumber(string.sub(name, 2)) or 0
		end
		return 0
	end
	local function parse_imm(val)
		if labels[val] then return labels[val] end
		if string.sub(val, 1, 1) == "0" and string.sub(val, 2, 2) == "x" then
			return tonumber(string.sub(val, 3), 16) or 0
		end
		return tonumber(val) or 0
	end
	local function parse_string(val)
		if string.sub(val, 1, 1) == '"' and string.sub(val, -1, -1) == '"' then
			return string.sub(val, 2, -2)
		end
		return val
	end
	local function emit(instr)
		for i = 0, 3 do
			bytes[#bytes + 1] = bit32.band(bit32.rshift(instr, i * 8), 255)
		end
	end
	local function emit_string(str)
		for i = 1, #str do
			bytes[#bytes + 1] = string.byte(str, i)
		end
		bytes[#bytes + 1] = 0
	end
	addr = 0
	local assembled_count = 0
	for i, line in ipairs(lines) do
		if not string.find(line, ":") then
			local parts = {}
			for word in string.gmatch(line, "[^, ]+") do
				parts[#parts + 1] = word
			end
			local op = parts[1]
			local instr = 0
			local success = true

			if op == ".string" or op == ".ascii" or op == ".asciiz" then
				local str = parts[2]
				if string.sub(str, 1, 1) == '"' and string.sub(str, -1, -1) == '"' then
					str = string.sub(str, 2, -2)
				end
				emit_string(str)
				addr = addr + #str + 1
				assembled_count = assembled_count + 1
				self:log(string.format("0x%08X: .asciiz \"%s\"", addr - #str - 1, str))
				success = false
			elseif op == "addi" then
				local rd = get_reg(parts[2])
				local rs1 = get_reg(parts[3])
				local imm = parse_imm(parts[4])
				instr = bit32.bor(0x13, bit32.lshift(rd, 7), bit32.lshift(rs1, 15), bit32.lshift(bit32.band(imm, 0xFFF), 20))
				self:log(string.format("0x%08X: %s x%d, x%d, %d", addr, op, rd, rs1, imm))
			elseif op == "add" then
				local rd = get_reg(parts[2])
				local rs1 = get_reg(parts[3])
				local rs2 = get_reg(parts[4])
				instr = bit32.bor(0x33, bit32.lshift(rd, 7), bit32.lshift(rs1, 15), bit32.lshift(rs2, 20))
				self:log(string.format("0x%08X: %s x%d, x%d, x%d", addr, op, rd, rs1, rs2))
			elseif op == "sub" then
				local rd = get_reg(parts[2])
				local rs1 = get_reg(parts[3])
				local rs2 = get_reg(parts[4])
				instr = bit32.bor(0x33, bit32.lshift(rd, 7), bit32.lshift(rs1, 15), bit32.lshift(rs2, 20), bit32.lshift(32, 25))
				self:log(string.format("0x%08X: %s x%d, x%d, x%d", addr, op, rd, rs1, rs2))
			elseif op == "li" then
				local rd = get_reg(parts[2])
				local imm = parse_imm(parts[3])
				if imm >= -2048 and imm <= 2047 then
					instr = bit32.bor(0x13, bit32.lshift(rd, 7), bit32.lshift(bit32.band(imm, 0xFFF), 20))
					self:log(string.format("0x%08X: %s x%d, %d (single instruction)", addr, op, rd, imm))
					emit(instr)
					addr = addr + 4
					assembled_count = assembled_count + 1
					success = false
				else
					local hi = bit32.rshift(bit32.band(imm, 0xFFFFF000), 12)
					local lo = bit32.band(imm, 0xFFF)
					if lo >= 2048 then
						lo = lo - 4096
						hi = hi + 1
					end
					local instr1 = bit32.bor(0x37, bit32.lshift(rd, 7), bit32.lshift(bit32.band(hi, 0xFFFFF), 12))
					local instr2 = bit32.bor(0x13, bit32.lshift(rd, 7), bit32.lshift(rd, 15), bit32.lshift(bit32.band(lo, 0xFFF), 20))
					self:log(string.format("0x%08X: lui x%d, %d", addr, rd, hi))
					emit(instr1)
					addr = addr + 4
					assembled_count = assembled_count + 1
					self:log(string.format("0x%08X: addi x%d, x%d, %d", addr, rd, rd, lo))
					instr = instr2
					success = true
				end
			elseif op == "lw" then
				local rd = get_reg(parts[2])
				local mem = parts[3]
				local offset, rs1
				local off_str, reg_str = string.match(mem, "(%d*)%(([%w]+)%)")
				if off_str and off_str ~= "" then
					offset = tonumber(off_str) or 0
				else
					offset = 0
				end
				rs1 = get_reg(reg_str or mem)
				instr = bit32.bor(0x03, bit32.lshift(rd, 7), bit32.lshift(2, 12), bit32.lshift(rs1, 15), bit32.lshift(bit32.band(offset, 0xFFF), 20))
				self:log(string.format("0x%08X: %s x%d, %d(x%d)", addr, op, rd, offset, rs1))
			elseif op == "sw" then
				local rs2 = get_reg(parts[2])
				local mem = parts[3]
				local offset, rs1
				local off_str, reg_str = string.match(mem, "(%d*)%(([%w]+)%)")
				if off_str and off_str ~= "" then
					offset = tonumber(off_str) or 0
				else
					offset = 0
				end
				rs1 = get_reg(reg_str or mem)
				local imm_s = bit32.bor(
					bit32.lshift(bit32.band(offset, 0x1F), 7),
					bit32.lshift(bit32.band(bit32.rshift(offset, 5), 0x7F), 25)
				)
				instr = bit32.bor(0x23, bit32.lshift(2, 12), bit32.lshift(rs1, 15), bit32.lshift(rs2, 20), imm_s)
				self:log(string.format("0x%08X: %s x%d, %d(x%d)", addr, op, rs2, offset, rs1))
			elseif op == "beq" then
				local rs1 = get_reg(parts[2])
				local rs2 = get_reg(parts[3])
				local imm = parse_imm(parts[4])
				local off = imm - addr
				instr = bit32.bor(0x63, bit32.lshift(rs1, 15), bit32.lshift(rs2, 20), bit32.lshift(bit32.band(off, 0x1F), 7), bit32.lshift(bit32.band(bit32.rshift(off, 5), 0x7F), 25))
				self:log(string.format("0x%08X: %s x%d, x%d, 0x%08X (offset %d)", addr, op, rs1, rs2, imm, off))
			elseif op == "bne" then
				local rs1 = get_reg(parts[2])
				local rs2 = get_reg(parts[3])
				local imm = parse_imm(parts[4])
				local off = imm - addr
				instr = bit32.bor(0x63, bit32.lshift(1, 12), bit32.lshift(rs1, 15), bit32.lshift(rs2, 20), bit32.lshift(bit32.band(off, 0x1F), 7), bit32.lshift(bit32.band(bit32.rshift(off, 5), 0x7F), 25))
				self:log(string.format("0x%08X: %s x%d, x%d, 0x%08X", addr, op, rs1, rs2, imm))
			elseif op == "blt" then
				local rs1 = get_reg(parts[2])
				local rs2 = get_reg(parts[3])
				local imm = parse_imm(parts[4])
				local off = imm - addr
				instr = bit32.bor(0x63, bit32.lshift(4, 12), bit32.lshift(rs1, 15), bit32.lshift(rs2, 20), bit32.lshift(bit32.band(off, 0x1F), 7), bit32.lshift(bit32.band(bit32.rshift(off, 5), 0x7F), 25))
				self:log(string.format("0x%08X: %s x%d, x%d, 0x%08X", addr, op, rs1, rs2, imm))
			elseif op == "bge" then
				local rs1 = get_reg(parts[2])
				local rs2 = get_reg(parts[3])
				local imm = parse_imm(parts[4])
				local off = imm - addr
				instr = bit32.bor(0x63, bit32.lshift(5, 12), bit32.lshift(rs1, 15), bit32.lshift(rs2, 20), bit32.lshift(bit32.band(off, 0x1F), 7), bit32.lshift(bit32.band(bit32.rshift(off, 5), 0x7F), 25))
				self:log(string.format("0x%08X: %s x%d, x%d, 0x%08X", addr, op, rs1, rs2, imm))
			elseif op == "bltu" then
				local rs1 = get_reg(parts[2])
				local rs2 = get_reg(parts[3])
				local imm = parse_imm(parts[4])
				local off = imm - addr
				instr = bit32.bor(0x63, bit32.lshift(6, 12), bit32.lshift(rs1, 15), bit32.lshift(rs2, 20), bit32.lshift(bit32.band(off, 0x1F), 7), bit32.lshift(bit32.band(bit32.rshift(off, 5), 0x7F), 25))
				self:log(string.format("0x%08X: %s x%d, x%d, 0x%08X", addr, op, rs1, rs2, imm))
			elseif op == "bgeu" then
				local rs1 = get_reg(parts[2])
				local rs2 = get_reg(parts[3])
				local imm = parse_imm(parts[4])
				local off = imm - addr
				instr = bit32.bor(0x63, bit32.lshift(7, 12), bit32.lshift(rs1, 15), bit32.lshift(rs2, 20), bit32.lshift(bit32.band(off, 0x1F), 7), bit32.lshift(bit32.band(bit32.rshift(off, 5), 0x7F), 25))
				self:log(string.format("0x%08X: %s x%d, x%d, 0x%08X", addr, op, rs1, rs2, imm))
			elseif op == "jal" then
				local rd = get_reg(parts[2])
				local imm = parse_imm(parts[3])
				local off = imm - addr
				instr = bit32.bor(0x6F, bit32.lshift(rd, 7), bit32.lshift(bit32.band(off, 0x7FF), 21), bit32.lshift(bit32.band(bit32.rshift(off, 11), 0x1), 20), bit32.lshift(bit32.band(bit32.rshift(off, 12), 0xFF), 12))
				self:log(string.format("0x%08X: %s x%d, 0x%08X", addr, op, rd, imm))
			elseif op == "jalr" then
				local rd = get_reg(parts[2])
				local rs1 = get_reg(parts[3])
				local imm = parse_imm(parts[4]) or 0
				instr = bit32.bor(0x67, bit32.lshift(rd, 7), bit32.lshift(rs1, 15), bit32.lshift(bit32.band(imm, 0xFFF), 20))
				self:log(string.format("0x%08X: %s x%d, x%d, %d", addr, op, rd, rs1, imm))
			elseif op == "ecall" then
				instr = 0x00000073
				self:log(string.format("0x%08X: ecall", addr))
			elseif op == "nop" then
				instr = 0x00000013
				self:log(string.format("0x%08X: nop", addr))
			elseif op == "la" then
				local rd = get_reg(parts[2])
				local label = parts[3]
				local target = labels[label] or 0
				local offset = target - addr
				local hi = bit32.rshift(bit32.band(target, 0xFFFFF000), 12)
				local lo = bit32.band(target, 0xFFF)
				if lo >= 2048 then
					lo = lo - 4096
					hi = hi + 1
				end
				local instr1 = bit32.bor(0x37, bit32.lshift(rd, 7), bit32.lshift(bit32.band(hi, 0xFFFFF), 12))
				local instr2 = bit32.bor(0x13, bit32.lshift(rd, 7), bit32.lshift(rd, 15), bit32.lshift(bit32.band(lo, 0xFFF), 20))
				self:log(string.format("0x%08X: lui x%d, %d (la %s)", addr, rd, hi, label))
				emit(instr1)
				addr = addr + 4
				assembled_count = assembled_count + 1
				self:log(string.format("0x%08X: addi x%d, x%d, %d", addr, rd, rd, lo))
				instr = instr2
				success = true
			elseif op == "mv" then
				local rd = get_reg(parts[2])
				local rs = get_reg(parts[3])
				instr = bit32.bor(0x13, bit32.lshift(rd, 7), bit32.lshift(rs, 15))
				self:log(string.format("0x%08X: addi x%d, x%d, 0", addr, rd, rs))
			else
				self:log("ERROR: Unknown instruction '" .. op .. "' at line " .. i)
				success = false
			end
			if success then
				emit(instr)
				addr = addr + 4
				assembled_count = assembled_count + 1
			end
		end
	end
	self:log("Assembled " .. assembled_count .. " instructions (" .. #bytes .. " bytes)")
	return bytes
end

function RISC_V:parse_hex(hex_str)
	self:clear_log()
	self:log("Parsing HEX string...")
	local bytes = {}
	local cleaned = string.gsub(hex_str, "[^0-9a-fA-F]", "")
	if #cleaned % 2 ~= 0 then
		self:log("ERROR: Invalid hex string length")
		return bytes
	end
	for i = 1, #cleaned, 2 do
		local byte = tonumber(string.sub(cleaned, i, i+1), 16)
		if byte then
			bytes[#bytes + 1] = byte
		else
			self:log("ERROR: Invalid hex byte at position " .. i)
			return {}
		end
	end
	self:log("Parsed " .. #bytes .. " bytes from HEX")
	return bytes
end

function RISC_V:get_state_string()
	local lines = {}
	lines[#lines + 1] = "=== CPU STATE ==="
	lines[#lines + 1] = "PC: " .. string.format("0x%08X", PC)
	lines[#lines + 1] = "Running: " .. tostring(RUNNING)
	lines[#lines + 1] = ""
	lines[#lines + 1] = "Registers:"
	local names = {"zero","ra","sp","gp","tp","t0","t1","t2","s0/fp","s1","a0","a1","a2","a3","a4","a5","a6","a7","s2","s3","s4","s5","s6","s7","s8","s9","s10","s11","t3","t4","t5","t6"}
	for i = 0, 31 do
		lines[#lines + 1] = string.format("%-8s: %s", names[i+1], string.format("0x%08X", REGISTERS[i] or 0))
	end
	return table.concat(lines, "\n")
end

return RISC_V
