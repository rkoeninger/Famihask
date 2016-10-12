module Memory (
    Ram,
    malloc,
    store,
    load,
    storeWord,
    loadWord)
where

import           Data.Bits                   ((.|.), (.&.), shiftR, shiftL)
import           Data.Word                   (Word8, Word16)
import           Data.Functor                ((<$>))
import           Control.Monad.Primitive     (PrimState)
import qualified Data.Vector.Generic.Mutable as M
import qualified Data.Vector.Unboxed         as U

type Ram = U.MVector (PrimState IO) Word8

malloc :: Int -> IO Ram
malloc n = M.replicate n 0

store :: Ram -> Word16 -> Word8 -> IO ()
store ram index val = M.write ram (fromIntegral index) val

load :: Ram -> Word16 -> IO Word8
load ram index = M.read ram (fromIntegral index)

storeWord :: Ram -> Word16 -> Word16 -> IO ()
storeWord ram index word =
    let b0 = fromIntegral $ word .&. 0xff in
    let b1 = fromIntegral $ word `shiftR` 8 in
    store ram index b0 >> store ram (index + 1) b1

loadWord :: Ram -> Word16 -> IO Word16
loadWord ram index = do
    b0 <- fromIntegral <$> load ram index
    b1 <- fromIntegral <$> load ram (index + 1)
    return $ b0 .|. (b1 `shiftL` 8)
