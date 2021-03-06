module CPU (step, nmi, irq, pushWord, pushByte, pullWord, pullByte) where

import Data.Bits ((.|.), (.&.), xor, shiftL, shiftR, testBit)
import Data.Word (Word8, Word16)

import Base
import Memory

type Loader = MachineState -> (Word8, MachineState)
type Storer = Word8 -> MachineState -> MachineState
type Addresser = (Loader, Storer)
type AddresserBuilder = MachineState -> (Addresser, MachineState)
type Operation = Addresser -> MachineState -> MachineState

loadByteIncPc :: MachineState -> (Word8, MachineState)
loadByteIncPc = pcReg
            ->> loadByte
            .>> mapSnd (modifyPCReg (+ 1))

loadWordIncPc :: MachineState -> (Word16, MachineState)
loadWordIncPc = pcReg
            ->> loadWord
            .>> mapSnd (modifyPCReg (+ 2))

loadWordZeroPage :: Word8 -> MachineState -> (Word16, MachineState)
loadWordZeroPage addr = loadByte (byteToWord addr)
                    $>> loadByte (byteToWord addr + 1)
                    .>> mapFst (uncurry bytesToWord)

pushByte :: Word8 -> MachineState -> MachineState
pushByte val state = storeByte (0x0100 + byteToWord (sReg state)) val state
                  |> modifySReg (subtract 1)

pushWord :: Word16 -> MachineState -> MachineState
pushWord val state = storeWord (0x0100 + byteToWord (sReg state - 1)) val state
                  |> modifySReg (subtract 2)

pullByte :: MachineState -> (Word8, MachineState)
pullByte state = loadByte (0x0101 + byteToWord (sReg state)) state
             |> mapSnd (modifySReg (+ 1))

pullWord :: MachineState -> (Word16, MachineState)
pullWord state = loadWord (0x0101 + byteToWord (sReg state)) state
             |> mapSnd (modifySReg (+ 2))

impMode :: AddresserBuilder
impMode state = ((loader, storer), state)
    where loader = error "This operation should not access memory"
          storer = error "This operation should not access memory"

accMode :: AddresserBuilder
accMode state = ((loader, storer), state)
    where loader state = (aReg state, state)
          storer = setAReg

imdMode :: AddresserBuilder
imdMode state = ((loader, storer), state)
    where loader = loadByteIncPc
          storer = error "Can't store in immediate mode"

memoryMode :: Word16 -> Addresser
memoryMode addr = (loader, storer)
    where loader = loadByte addr
          storer = storeByte addr

zpgMode :: AddresserBuilder
zpgMode state = mapFst mode (loadByteIncPc state)
    where mode = byteToWord
             .>> memoryMode

zpxMode :: AddresserBuilder
zpxMode state = mapFst mode (loadByteIncPc state)
    where mode = (+ xReg state)
             .>> byteToWord
             .>> memoryMode

zpyMode :: AddresserBuilder
zpyMode state = mapFst mode (loadByteIncPc state)
    where mode = (+ yReg state)
             .>> byteToWord
             .>> memoryMode

absMode :: AddresserBuilder
absMode state = mapFst memoryMode (loadWordIncPc state)

abxMode :: AddresserBuilder
abxMode state = mapFst mode (loadWordIncPc state)
    where mode = (+ byteToWord (xReg state))
             .>> memoryMode

abyMode :: AddresserBuilder
abyMode state = mapFst mode (loadWordIncPc state)
    where mode = (+ byteToWord (yReg state))
             .>> memoryMode

iixMode :: AddresserBuilder
iixMode s0 = do
    let (v1, s1) = loadByteIncPc s0
    let (v2, s2) = loadWordZeroPage (v1 + xReg s1) s1
    (memoryMode v2, s2)

-- TODO: refactor these using composition operators

iiyMode :: AddresserBuilder
iiyMode s0 = do
    let (v1, s1) = loadByteIncPc s0
    let (v2, s2) = loadWordZeroPage v1 s1
    let v3 = v2 + byteToWord (yReg s2)
    (memoryMode v3, s2)

lda (load, _)  = load *>> setAReg
ldx (load, _)  = load *>> setXReg
ldy (load, _)  = load *>> setYReg
sta (_, store) = aReg ->> store
stx (_, store) = xReg ->> store
sty (_, store) = yReg ->> store

adc (load, _) s0 = do
    let (val, s1) = load s0
    let a = aReg s1
    let resultWord = byteToWord a + byteToWord val + (if carryFlag s1 then 1 else 0)
    let resultByte = wordToByte resultWord
    let carry = testBit resultWord 8
    let overflow = (testBit a 7 == testBit val 7) && (testBit a 7 /= testBit resultByte 7)
    s1 |> setAReg resultByte |> setCarryFlag carry |> setOverflowFlag overflow

sbc (load, _) s0 = do
    let (val, s1) = load s0
    let a = aReg s1
    let resultWord = byteToWord a - byteToWord val - (if carryFlag s1 then 0 else 1)
    let resultByte = wordToByte resultWord
    let carry = not $ testBit resultWord 8
    let overflow = (testBit a 7 /= testBit val 7) && (testBit a 7 /= testBit resultByte 7)
    s1 |> setAReg resultByte |> setCarryFlag carry |> setOverflowFlag overflow

comp :: (MachineState -> Word8) -> Operation
comp reg (load, _) s0 = do
    let (val, s1) = load s0
    let result = byteToWord (reg s1) - byteToWord val
    s1 |> setZN (wordToByte result) |> setCarryFlag (testBit result 8)

cmp = comp aReg
cpx = comp xReg
cpy = comp yReg

add (load, _) = load .>> mapFst (.&.) *>> modifyAReg
ora (load, _) = load .>> mapFst (.|.) *>> modifyAReg
eor (load, _) = load .>> mapFst  xor  *>> modifyAReg

bit (load, _) s0 = do
    let (val, s1) = load s0
    let zero = val .&. aReg s1 == 0
    let overflow = testBit val overflowBit
    let negative = testBit val negativeBit
    s1 |> setOverflowFlag overflow |> setNegativeFlag negative |> setZeroFlag zero

shiftLeft :: Bool -> Operation
shiftLeft lsb (load, store) s0 = do
    let (val, s1) = load s0
    let carry = testBit val 7
    let result = val `shiftL` 1 .|. (if lsb && carryFlag s1 then 0x01 else 0x00)
    s1 |> setZN result |> setCarryFlag carry |> store result

shiftRight :: Bool -> Operation
shiftRight msb (load, store) s0 = do
    let (val, s1) = load s0
    let carry = testBit val 0
    let result = val `shiftR` 1 .|. (if msb && carryFlag s1 then 0x80 else 0x00)
    s1 |> setZN result |> setCarryFlag carry |> store result

rol = shiftLeft  True
ror = shiftRight True
asl = shiftLeft  False
lsr = shiftRight False

inc (load, store) s0 = do
    let (val, s1) = mapFst (+ 1) $ load s0
    s1 |> setZN val |> store val

dec (load, store) s0 = do
    let (val, s1) = mapFst (subtract 1) $ load s0
    s1 |> setZN val |> store val

inx _ = modifyXReg (+ 1)
dex _ = modifyXReg (subtract 1)
iny _ = modifyYReg (+ 1)
dey _ = modifyYReg (subtract 1)
tax _ = aReg ->> setXReg
tay _ = aReg ->> setYReg
txa _ = xReg ->> setAReg
tya _ = yReg ->> setAReg
txs _ = xReg ->> setSReg
tsx _ = sReg ->> setXReg
clc _ = setCarryFlag    False
sec _ = setCarryFlag    True
cli _ = setIRQFlag      False
sei _ = setIRQFlag      True
clv _ = setOverflowFlag False
cld _ = setDecimalFlag  False -- NOTE: decimal flag isn't used since BCD commands are disabled
sed _ = setDecimalFlag  True

branch :: (MachineState -> Bool) -> Operation
branch condf _ = ifs condf (loadByteIncPc .>> mapFst ((+) . byteToWord) *>> modifyPCReg) id

bpl = branch $ not . negativeFlag
bvc = branch $ not . overflowFlag
bcc = branch $ not . carryFlag
bne = branch $ not . zeroFlag
bmi = branch negativeFlag
bvs = branch overflowFlag
bcs = branch carryFlag
beq = branch zeroFlag

jmp _ = loadWordIncPc
    *>> setPCReg

-- NOTE: apparently there's a hack here for the hi byte made necessary by bug in 6502 chip ???
addrHack addr = addr .&. 0xff00 .|. (addr + 1) .&. 0x00ff

jpi _ s0 = do
    let (addr, s1) = mapFst byteToWord $ loadByteIncPc s0
    let loadIntoPc = loadByte addr
                 $>> loadByte (addrHack addr)
                 .>> mapFst (uncurry bytesToWord)
                 *>> setPCReg
    loadIntoPc s1

jsr _ s0 = do
    let (addr, s1) = loadWordIncPc s0
    s1 |> pushWord (pcReg s1 - 1) |> setPCReg addr

rts _ = pullWord
    .>> mapFst (+ 1)
    *>> setPCReg

brk _ = (pcReg .>> (+) 1 ->> pushWord)
    .>> (flagReg .>> (.|.) breakMask ->> pushByte)
    .>> setIRQFlag True
    .>> loadWord breakVector
    *>> setPCReg

rti _ = pullByte
    *>> setFlagReg
    .>> pullWord
    *>> setPCReg

pha _ = aReg
    ->> pushByte

pla _ = pullByte
    *>> setAReg

php _ = flagReg
    .>> (.|.) breakMask
    ->> pushByte

plp _ = pullByte
    *>> setFlagReg

nop _ = id

reset = loadWord resetVector
    *>> setPCReg

interrupt addr = (pcReg ->> pushWord)
             .>> (flagReg ->> pushByte)
             .>> loadWord addr
             *>> setPCReg

nmi = interrupt nmiVector

irq = ifs irqFlag id (interrupt breakVector)

step :: MachineState -> MachineState
step = loadByteIncPc
   *>> eval

eval :: Word8 -> MachineState -> MachineState
eval opCode = builder
          *>> op
          .>> addCycles cycles
    where (op, builder, cycles) = decode opCode

decode :: Word8 -> (Operation, AddresserBuilder, Int)
decode 0xa9 = (lda, imdMode, 2)
decode 0xa5 = (lda, zpgMode, 3)
decode 0xb5 = (lda, zpxMode, 4)
decode 0xad = (lda, absMode, 4)
decode 0xbd = (lda, abxMode, 4) -- +1 if page crossed
decode 0xb9 = (lda, abyMode, 4) -- +1 if page crossed
decode 0xa1 = (lda, iixMode, 6)
decode 0xb1 = (lda, iiyMode, 5) -- +1 if page crossed
decode 0xa2 = (ldx, imdMode, 2)
decode 0xa6 = (ldx, zpgMode, 3)
decode 0xb6 = (ldx, zpyMode, 4)
decode 0xae = (ldx, absMode, 4)
decode 0xbe = (ldx, abyMode, 4) -- +1 if page crossed
decode 0xa0 = (ldy, imdMode, 2)
decode 0xa4 = (ldy, zpgMode, 3)
decode 0xb4 = (ldy, zpxMode, 4)
decode 0xac = (ldy, absMode, 4)
decode 0xbc = (ldy, abxMode, 4) -- +1 if page crossed
decode 0x85 = (sta, zpgMode, 3)
decode 0x95 = (sta, zpxMode, 4)
decode 0x8d = (sta, absMode, 4)
decode 0x9d = (sta, abxMode, 5)
decode 0x99 = (sta, abyMode, 5)
decode 0x81 = (sta, iixMode, 6)
decode 0x91 = (sta, iiyMode, 6)
decode 0x86 = (stx, zpgMode, 3)
decode 0x96 = (stx, zpyMode, 4)
decode 0x8e = (stx, absMode, 4)
decode 0x84 = (sty, zpgMode, 3)
decode 0x94 = (sty, zpxMode, 4)
decode 0x8c = (sty, absMode, 4)
decode 0x69 = (adc, imdMode, 2)
decode 0x65 = (adc, zpgMode, 3)
decode 0x75 = (adc, zpxMode, 4)
decode 0x6d = (adc, absMode, 4)
decode 0x7d = (adc, abxMode, 4) -- +1 if page crossed
decode 0x79 = (adc, abyMode, 4) -- +1 if page crossed
decode 0x61 = (adc, iixMode, 6)
decode 0x71 = (adc, iiyMode, 5) -- +1 if page crossed
decode 0xe9 = (sbc, imdMode, 2)
decode 0xe5 = (sbc, zpgMode, 3)
decode 0xf5 = (sbc, zpxMode, 4)
decode 0xed = (sbc, absMode, 4)
decode 0xfd = (sbc, abxMode, 4) -- +1 if page crossed
decode 0xf9 = (sbc, abyMode, 4) -- +1 if page crossed
decode 0xe1 = (sbc, iixMode, 6)
decode 0xf1 = (sbc, iiyMode, 5) -- +1 if page crossed
decode 0xc9 = (cmp, imdMode, 2)
decode 0xc5 = (cmp, zpgMode, 3)
decode 0xd5 = (cmp, zpxMode, 4)
decode 0xcd = (cmp, absMode, 4)
decode 0xdd = (cmp, abxMode, 4) -- +1 if page crossed
decode 0xd9 = (cmp, abyMode, 4) -- +1 if page crossed
decode 0xc1 = (cmp, iixMode, 6)
decode 0xd1 = (cmp, iiyMode, 5) -- +1 if page crossed
decode 0xe0 = (cpx, imdMode, 2)
decode 0xe4 = (cpx, zpgMode, 3)
decode 0xec = (cpx, absMode, 4)
decode 0xc0 = (cpy, imdMode, 2)
decode 0xc4 = (cpy, zpgMode, 3)
decode 0xcc = (cpy, absMode, 4)
decode 0x29 = (add, imdMode, 2)
decode 0x25 = (add, zpgMode, 3)
decode 0x35 = (add, zpxMode, 4)
decode 0x2d = (add, absMode, 4)
decode 0x3d = (add, abxMode, 4) -- +1 if page crossed
decode 0x39 = (add, abyMode, 4) -- +1 if page crossed
decode 0x21 = (add, iixMode, 6)
decode 0x31 = (add, iiyMode, 5) -- +1 if page crossed
decode 0x09 = (ora, imdMode, 2)
decode 0x05 = (ora, zpgMode, 3)
decode 0x15 = (ora, zpxMode, 4)
decode 0x0d = (ora, absMode, 4)
decode 0x1d = (ora, abxMode, 4) -- +1 if page crossed
decode 0x19 = (ora, abyMode, 4) -- +1 if page crossed
decode 0x01 = (ora, iixMode, 6)
decode 0x11 = (ora, iiyMode, 5) -- +1 if page crossed
decode 0x49 = (eor, imdMode, 2)
decode 0x45 = (eor, zpgMode, 3)
decode 0x55 = (eor, zpxMode, 4)
decode 0x4d = (eor, absMode, 4)
decode 0x5d = (eor, abxMode, 4) -- +1 if page crossed
decode 0x59 = (eor, abyMode, 4) -- +1 if page crossed
decode 0x41 = (eor, iixMode, 6)
decode 0x51 = (eor, iiyMode, 5) -- +1 if page crossed
decode 0x24 = (bit, zpgMode, 3)
decode 0x2c = (bit, absMode, 4)
decode 0x2a = (rol, accMode, 2)
decode 0x26 = (rol, zpgMode, 5)
decode 0x36 = (rol, zpxMode, 6)
decode 0x2e = (rol, absMode, 6)
decode 0x3e = (rol, abxMode, 7)
decode 0x6a = (ror, accMode, 2)
decode 0x66 = (ror, zpgMode, 5)
decode 0x76 = (ror, zpxMode, 6)
decode 0x6e = (ror, absMode, 6)
decode 0x7e = (ror, abxMode, 7)
decode 0x0a = (asl, accMode, 2)
decode 0x06 = (asl, zpgMode, 5)
decode 0x16 = (asl, zpxMode, 6)
decode 0x0e = (asl, absMode, 6)
decode 0x1e = (asl, abxMode, 7)
decode 0x4a = (lsr, accMode, 2)
decode 0x46 = (lsr, zpgMode, 5)
decode 0x56 = (lsr, zpxMode, 6)
decode 0x4e = (lsr, absMode, 6)
decode 0x5e = (lsr, abxMode, 7)
decode 0xe6 = (inc, zpgMode, 5)
decode 0xf6 = (inc, zpxMode, 6)
decode 0xee = (inc, absMode, 6)
decode 0xfe = (inc, abxMode, 7)
decode 0xc6 = (dec, zpgMode, 5)
decode 0xd6 = (dec, zpxMode, 6)
decode 0xce = (dec, absMode, 6)
decode 0xde = (dec, abxMode, 7)
decode 0xe8 = (inx, impMode, 2)
decode 0xca = (dex, impMode, 2)
decode 0xc8 = (iny, impMode, 2)
decode 0x88 = (dey, impMode, 2)
decode 0xaa = (tax, impMode, 2)
decode 0xa8 = (tay, impMode, 2)
decode 0x8a = (txa, impMode, 2)
decode 0x98 = (tya, impMode, 2)
decode 0x9a = (txs, impMode, 2)
decode 0xba = (tsx, impMode, 2)
decode 0x18 = (clc, impMode, 2)
decode 0x38 = (sec, impMode, 2)
decode 0x58 = (cli, impMode, 2)
decode 0x78 = (sei, impMode, 2)
decode 0xb8 = (clv, impMode, 2)
decode 0xd8 = (cld, impMode, 2)
decode 0xf8 = (sed, impMode, 2)
decode 0x10 = (bpl, impMode, 2) -- +1 if branch succeeds, +2 if page crossed
decode 0x30 = (bmi, impMode, 2) -- +1 if branch succeeds, +2 if page crossed
decode 0x50 = (bvc, impMode, 2) -- +1 if branch succeeds, +2 if page crossed
decode 0x70 = (bvs, impMode, 2) -- +1 if branch succeeds, +2 if page crossed
decode 0x90 = (bcc, impMode, 2) -- +1 if branch succeeds, +2 if page crossed
decode 0xb0 = (bcs, impMode, 2) -- +1 if branch succeeds, +2 if page crossed
decode 0xd0 = (bne, impMode, 2) -- +1 if branch succeeds, +2 if page crossed
decode 0xf0 = (beq, impMode, 2) -- +1 if branch succeeds, +2 if page crossed
decode 0x4c = (jmp, impMode, 3)
decode 0x6c = (jpi, impMode, 5)
decode 0x20 = (jsr, impMode, 6)
decode 0x60 = (rts, impMode, 6)
decode 0x00 = (brk, impMode, 7)
decode 0x40 = (rti, impMode, 6)
decode 0x48 = (pha, impMode, 3)
decode 0x68 = (pla, impMode, 4)
decode 0x08 = (php, impMode, 3)
decode 0x28 = (plp, impMode, 4)
decode 0xea = (nop, impMode, 2)
decode opCode = error $ "Invalid op code: " ++ show opCode
