{-# LANGUAGE FlexibleInstances #-}

module Memory where

import Data.Bits (Bits, (.|.), (.&.), shiftR, shiftL, complement, bit, testBit)
import Data.Default (Default(..))
import Data.Sequence (Seq, update, index, fromList)
import Data.Sequence as S
import Data.Word (Word8, Word16)
import ROM (ROM(..))

import Base

nmiVector   = 0xfffa :: Word16
resetVector = 0xfffc :: Word16
breakVector = 0xfffe :: Word16

data Sprite = Sprite {
    xPosition :: Word8,
    yPosition :: Word8,
    tileIndex :: Word8,
    attribute :: Word8
}

data SpriteSize = Size8x8 | Size8x16
data SpritePriority = AboveBackground | BelowBackground
data ScrollDirection = XDirection | YDirection
data PixelLayer = BackgroundLayer | SpriteLayer
type Color = (Word8, Word8, Word8)
type SpriteColor = (SpritePriority, Color)
data SpriteTile = Tile8x8 Word16 | Tile8x16 Word16 Word16

data MachineState = MachineState {
    cycleCount    :: Int,
    ram           :: Seq Word8,
    aReg          :: Word8,
    xReg          :: Word8,
    yReg          :: Word8,
    sReg          :: Word8,
    flagReg       :: Word8,
    pcReg         :: Word16,
    ppuCycleCount :: Int,
    controlReg    :: Word8,
    maskReg       :: Word8,
    statusReg     :: Word8,
    oamAddr       :: Word8,
    oamData       :: Seq Word8,
    ppuAddr       :: Word16,
    ppuAddrHi     :: Bool,
    ppuScrollX    :: Word8,
    ppuScrollY    :: Word8,
    ppuScrollDir  :: ScrollDirection,
    ppuDataBuffer :: Word8,
    scanline      :: Int,
    nametables    :: Seq Word8,
    palette       :: Seq Word8,
    screen        :: Seq Color,
    rom           :: ROM
}

instance Default MachineState where
    def = MachineState {
        cycleCount    = 0,
        ram           = vector 2048,
        aReg          = 0x00,
        xReg          = 0x00,
        yReg          = 0x00,
        sReg          = 0xfd,
        flagReg       = unusedMask .|. irqMask,
        pcReg         = 0xc000,
        ppuCycleCount = 0,
        controlReg    = 0x00,
        maskReg       = 0x00,
        statusReg     = 0x00,
        oamAddr       = 0x00,
        oamData       = vector 256,
        ppuAddr       = 0x0000,
        ppuAddrHi     = True,
        ppuScrollX    = 0x00,
        ppuScrollY    = 0x00,
        ppuScrollDir  = XDirection,
        ppuDataBuffer = 0x00,
        scanline      = 0,
        nametables    = vector 2048,
        palette       = vector 32,
        screen        = vector (256 * 240),
        rom           = def
    }

addCycles cycles state = state { cycleCount = cycleCount state + cycles }
addPPUCycles cycles state = state { ppuCycleCount = ppuCycleCount state + cycles }

setRAM           value state = state { ram = value }
setNametables    value state = state { nametables = value }
setPalette       value state = state { palette = value }
setAReg          value state = (setZN value state) { aReg = value }
setXReg          value state = (setZN value state) { xReg = value }
setYReg          value state = (setZN value state) { yReg = value }
setSReg          value state = state { sReg = value }
setPCReg         value state = state { pcReg = value }
setFlagReg       value state = state { flagReg = (value .|. unusedMask) .&. complement breakMask }
setControlReg    value state = state { controlReg = value }
setMaskReg       value state = state { maskReg = value }
setStatusReg     value state = state { statusReg = value }
setPPUAddr       value state = state { ppuAddr = value }
setPPUAddrHi     value state = state { ppuAddrHi = value }
setPPUScrollX    value state = state { ppuScrollX = value }
setPPUScrollY    value state = state { ppuScrollY = value }
setPPUScrollDir  value state = state { ppuScrollDir = value }
setPPUDataBuffer value state = state { ppuDataBuffer = value }

setZN :: Word8 -> MachineState -> MachineState
setZN value = setZeroFlag (value == 0)
          .>> setNegativeFlag (testBit value 7)

setFlag :: Word8 -> Bool -> MachineState -> MachineState
setFlag mask value state = state { flagReg = op mask (flagReg state) }
    where op = if value then (.|.) else (.&.) . complement

getFlag :: Word8 -> MachineState -> Bool
getFlag mask state = flagReg state .&. mask /= 0

carryBit, zeroBit, irqBit, decimalBit, breakBit, unusedBit, overflowBit, negativeBit :: Int
carryBit    = 0
zeroBit     = 1
irqBit      = 2
decimalBit  = 3
breakBit    = 4
unusedBit   = 5
overflowBit = 6
negativeBit = 7

carryMask, zeroMask, irqMask, decimalMask, breakMask, unusedMask, overflowMask, negativeMask :: Word8
carryMask    = bit carryBit
zeroMask     = bit zeroBit
irqMask      = bit irqBit
decimalMask  = bit decimalBit -- NOTE: unused since BCD is disabled in NES
breakMask    = bit breakBit
unusedMask   = bit unusedBit -- NOTE: should always be 1 for some reason
overflowMask = bit overflowBit
negativeMask = bit negativeBit

setCarryFlag    = setFlag carryMask
setZeroFlag     = setFlag zeroMask
setIRQFlag      = setFlag irqMask
setDecimalFlag  = setFlag decimalMask
setBreakFlag    = setFlag breakMask
setOverflowFlag = setFlag overflowMask
setNegativeFlag = setFlag negativeMask

carryFlag    = getFlag carryMask
zeroFlag     = getFlag zeroMask
irqFlag      = getFlag irqMask
decimalFlag  = getFlag decimalMask
breakFlag    = getFlag breakMask
overflowFlag = getFlag overflowMask
negativeFlag = getFlag negativeMask

loadRAM        f state = mapSnd (`setRAM`        state) (f (ram state))
loadNametables f state = mapSnd (`setNametables` state) (f (nametables state))
loadPalette    f state = mapSnd (`setPalette`    state) (f (palette state))

storeRAM        f = ram        .>> f ->> setRAM
storeNametables f = nametables .>> f ->> setNametables
storePalette    f = palette    .>> f ->> setPalette

modifyAReg      f = aReg      .>> f ->> setAReg
modifyXReg      f = xReg      .>> f ->> setXReg
modifyYReg      f = yReg      .>> f ->> setYReg
modifySReg      f = sReg      .>> f ->> setSReg
modifyPCReg     f = pcReg     .>> f ->> setPCReg
modifyStatusReg f = statusReg .>> f ->> setStatusReg
modifyPPUAddr   f = ppuAddr   .>> f ->> setPPUAddr

xScrollOffset              state =    testBit (controlReg state) 0
yScrollOffset              state =    testBit (controlReg state) 1
vramAddrIncrement          state = if testBit (controlReg state) 2 then 0x0020 else 0x0001 :: Word16
spritePatternTableAddr     state = if testBit (controlReg state) 3 then 0x1000 else 0x0000 :: Word16
backgroundPatternTableAddr state = if testBit (controlReg state) 4 then 0x1000 else 0x0000 :: Word16
spriteSize                 state = if testBit (controlReg state) 5 then Size8x16 else Size8x8
ppuMasterSlave             state =    testBit (controlReg state) 6
vBlankNMI                  state =    testBit (controlReg state) 7

patternTableAddr SpriteLayer     = spritePatternTableAddr
patternTableAddr BackgroundLayer = backgroundPatternTableAddr

isGrayscale        state = testBit (maskReg state) 0
showBackgroundLeft state = testBit (maskReg state) 1
showSpritesLeft    state = testBit (maskReg state) 2
showBackground     state = testBit (maskReg state) 3
showSprites        state = testBit (maskReg state) 4
enhancedReds       state = testBit (maskReg state) 5
enhancedGreens     state = testBit (maskReg state) 6
enhancedBlues      state = testBit (maskReg state) 7

setSpriteOverflow value state = if value then modifyStatusReg (.|. bit 5) state else state
setSpriteZeroHit  value state = if value then modifyStatusReg (.|. bit 6) state else state
setInVBlank       value state = if value then modifyStatusReg (.|. bit 7) state else state

incScanline state = state { scanline = scanline state + 1 }

incOAMAddr state = state { oamAddr = oamAddr state + 1 }

loadOAMByte :: MachineState -> (Word8, MachineState)
loadOAMByte state = (at (oamAddr state) (oamData state), state)

storeOAMByte :: Word8 -> MachineState -> MachineState
storeOAMByte value state = (incOAMAddr state) { oamData = storeByte (byteToWord $ oamAddr state) value (oamData state) }

dmaTransfer :: Word8 -> MachineState -> MachineState
dmaTransfer value state = do
    let start = byteToWord value `shiftL` 8
    let copy addr = loadByte addr *>> storeOAMByte
    foldr copy state [start .. start + 255]

storePPUAddrByte :: Word8 -> MachineState -> MachineState
storePPUAddrByte value state = state { ppuAddr = newAddr, ppuAddrHi = not hi }
    where hi = ppuAddrHi state
          addr = ppuAddr state
          value16 = byteToWord value
          newAddr = if hi then addr .&. 0x00ff .|. value16 `shiftL` 8
                          else addr .&. 0xff00 .|. value16

storePPUScrollByte :: Word8 -> MachineState -> MachineState
storePPUScrollByte value state = case ppuScrollDir state of
    XDirection -> state { ppuScrollX = value, ppuScrollDir = YDirection }
    YDirection -> state { ppuScrollY = value, ppuScrollDir = XDirection }

-- TODO: refactor to not return (Word8, MachineState) ?
loadVramByte :: Word16 -> MachineState -> (Word8, MachineState)
loadVramByte addr state
    | addr < 0x2000 = (0, state) -- TODO: mapper to chr_data
    | addr < 0x3f00 = loadNametables (loadByte (addr .&. 0x07ff)) state
    | addr < 0x4000 = loadPalette    (loadByte (addr .&. 0x1f))   state
    | otherwise = error $ "Storage VRAM loadByte: Address out of range: " ++ show addr

paletteAddr addr = if maskedAddr == 0x10 then 0x00 else maskedAddr
    where maskedAddr = addr .&. 0x1f

storeVramByte :: Word16 -> Word8 -> MachineState -> MachineState
storeVramByte addr val state
    | addr < 0x2000 = state -- TODO: mapper to chr_data
    | addr < 0x3f00 = storeNametables (storeByte (addr .&. 0x07ff)  val) state
    | addr < 0x4000 = storePalette    (storeByte (paletteAddr addr) val) state
    | otherwise = error $ "Storage VRAM storeByte: Address out of range: " ++ show addr

loadPPUStatus :: MachineState -> (Word8, MachineState)
loadPPUStatus state = (statusReg state, state { ppuAddrHi = True, ppuScrollDir = XDirection })

storePPUDataByte :: Word8 -> MachineState -> MachineState
storePPUDataByte value = ppuAddr
                     ->> (`storeVramByte` value)
                     .>> ((+) . vramAddrIncrement)
                     ->> modifyPPUAddr

loadPPUDataByte :: MachineState -> (Word8, MachineState)
loadPPUDataByte state = if ppuAddr state < 0x3f00 then buffer normal else normal
    where (val, stat2) = transfer ppuAddr loadVramByte state
          stat3 = transfer ((+) . vramAddrIncrement) modifyPPUAddr stat2
          normal = (val, stat3)
          buffer (value, stat4) = (ppuDataBuffer stat4, setPPUDataBuffer value stat4)

class Storage m where
    loadByte :: Word16 -> m -> (Word8, m)

    loadWord :: Word16 -> m -> (Word16, m)
    loadWord addr = loadByte addr
                $>> loadByte (addr + 1)
                .>> mapFst (uncurry bytesToWord)

    storeByte :: Word16 -> Word8 -> m -> m

    storeWord :: Word16 -> Word16 -> m -> m
    storeWord addr word = storeByte addr b0
                      .>> storeByte (addr + 1) b1
        where (b0, b1) = wordToBytes word

instance Storage (Seq Word8) where
    loadByte addr ram = (at addr ram, ram)
    storeByte = update . fromIntegral

data MapperResult = Continue | Irq

-- TODO: support other mappers
--        code not designed to generalize for other mappers

data Mapper = NROM ROM

loadPrgByte :: Word16 -> Mapper -> Word8
loadPrgByte addr (NROM rom) = result
    where result
            | addr < 0x8000 =
                0x08
            | S.length (prg rom) > 16384 =
                fst $ loadByte (addr .&. 0x7fff) (prg rom)
            | otherwise =
                fst $ loadByte (addr .&. 0x3fff) (prg rom)

loadChrByte :: Word16 -> Mapper -> Word8
loadChrByte addr (NROM rom) = result
    where result = fst $ loadByte addr (chr rom)

storePrgByte :: Word16 -> Word8 -> Mapper -> Mapper
storePrgByte = error "Can't write to PRG ROM"

storeChrByte :: Word16 -> Word8 -> Mapper -> Mapper
storeChrByte = error "Can't write to CHR ROM"

mapperNextScanline :: Mapper -> MapperResult
mapperNextScanline _ = Continue

instance Storage MachineState where
    loadByte addr state
        | addr <  0x2000 = loadRAM (loadByte (addr .&. 0x07ff)) state
        | addr == 0x2000 = error "attempt to read from PPU Control 0x2000"
        | addr == 0x2001 = error "attempt to read from PPU Mask 0x2001"
        | addr == 0x2002 = loadPPUStatus state
        | addr == 0x2003 = error "attempt to read from OAM Addr 0x2003"
        | addr == 0x2004 = loadOAMByte state
        | addr == 0x2005 = error "attempt to read from PPU Scroll 0x2005"
        | addr == 0x2006 = error "attempt to read from PPU Addr 0x2006"
        | addr == 0x2007 = loadPPUDataByte state
        | addr <  0x4000 = loadVramByte addr state
        | addr <  0x4004 = error "attempt to read from APU Pulse 0 0x4001" -- TODO: implement
        | addr <  0x4008 = error "attempt to read from APU Pulse 1 0x4005" -- TODO: implement
        | addr <  0x400c = error "attempt to read from APU Triangle 0x4009" -- TODO: implement
        | addr <  0x4010 = error "attempt to read from APU Noise 0x400b" -- TODO: implement
        | addr == 0x4014 = error "attempt to read from DMA Trigger 0x4014"
        | addr == 0x4015 = error "attempt to read from APU Status 0x4015" -- TODO: implement
        | addr == 0x4016 = error "attempt to read from Input 0x4016"
        | addr <= 0x4018 = error "attempt to read from APU 0x4018"
        | addr <  0x6000 = (0, state) -- TODO: some mappers use this area?
        | addr == breakVector || addr == (breakVector + 1) = (0, state) -- TODO: implement (mapper?)
        | otherwise      = (loadPrgByte addr (NROM (rom state)), state)

    storeByte addr value state
        | addr <  0x2000 = storeRAM (storeByte (addr .&. 0x07ff) value) state
        | addr == 0x2000 = setControlReg value state
        | addr == 0x2001 = setMaskReg value state
        | addr == 0x2002 = error "attempt to write to PPU Status 0x2002"
        | addr == 0x2003 = state { oamAddr = value }
        | addr == 0x2004 = storeOAMByte value state
        | addr == 0x2005 = storePPUScrollByte value state
        | addr == 0x2006 = storePPUAddrByte value state
        | addr == 0x2007 = storePPUDataByte value state
        | addr <  0x4000 = storeVramByte addr value state
        | addr <  0x4004 = error "attempt to write to APU Pulse 0 0x4001" -- TODO: implement
        | addr <  0x4008 = error "attempt to write to APU Pulse 1 0x4005" -- TODO: implement
        | addr <  0x400c = error "attempt to write to APU Triangle 0x4009" -- TODO: implement
        | addr <  0x4010 = error "attempt to write to APU Noise 0x400b" -- TODO: implement
        | addr == 0x4014 = dmaTransfer value state
        | addr == 0x4015 = error "attempt to write to APU Status 0x4015" -- TODO: implement
        | addr == 0x4016 = error "attempt to write to Input 0x4016"
        | addr <= 0x4018 = error "attempt to write to APU 0x4018"
        | addr <  0x6000 = state -- TODO: some mappers use this area?
        | otherwise      = state -- TODO: Mapper0 doesn't store anyway --storePrgByte addr value (NROM (rom state))
