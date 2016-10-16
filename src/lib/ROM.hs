module ROM where

import Data.Word (Word8, Word16)
import Data.ByteString (ByteString)
import qualified Data.ByteString as B
import Data.Attoparsec.ByteString
import qualified Memory as M

data Region = NTSC | PAL deriving (Eq, Show)

data ROM = ROM {
    -- header is 16 bytes
    -- First 4 bytes are 'N' 'E' 'S' '\x1a'
    prgSize16KB :: Word8, -- x16KB
    chrSize8KB :: Word8, -- x8KB
    ramSize8KB :: Word8, -- x8KB
    flags6 :: Word8,
    flags7 :: Word8,
    flags9 :: Word8,
    flags10 :: Word8
    --mapper :: Word8,
    --tranier :: Bool,
    --persistent :: Bool,
    --region :: Region,
    {- MMMMATPA
    /// * A: 0xx0: vertical arrangement/horizontal mirroring (CIRAM A10 = PPU A11)
    ///      0xx1: horizontal arrangement/vertical mirroring (CIRAM A10 = PPU A10)
    ///      1xxx: four-screen VRAM
    pub flags_6: u8,
    /// * V: If 0b10, all following flags are in NES 2.0 format
    /// * P: ROM is for the PlayChoice-10
    /// * U: ROM is for VS Unisystem
    pub flags_7: u8,
    pub flags_10: u8,-}
    -- Last 5 bytes are zero
    --prg :: M.Ram,
    --chr :: M.Ram
}

instance Eq ROM where
    _ == _ = False

instance Show ROM where
    show = const "ROM"

x |> f = f x

pMagic = "NES\x1a" |> map (fromIntegral . fromEnum) |> B.pack |> string

pHeader = do
    pMagic
    prgSize16KB <- anyWord8
    chrSize8KB <- anyWord8
    flags6 <- anyWord8
    flags7 <- anyWord8
    ramSize8KB <- anyWord8
    flags9 <- anyWord8
    flags10 <- anyWord8
    count 5 (word8 0x00)

pROM = pHeader

parseROM :: ByteString -> Either String ROM
parseROM bytes =
    case parseOnly pROM bytes of
    Right _ -> Left "magic matches"
    x -> Left "error"
