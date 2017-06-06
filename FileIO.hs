-- | Handles all I/O operations like reading from files.
module FileIO (getPrefix, readModel) where

import Model
import Control.Monad (replicateM_)
import Data.List.Split (splitOneOf)
import qualified Data.Map.Strict as Map
import System.IO
import System.IO.Error

-- | Returns the prefix for the word suggestion.
getPrefix
    :: String       -- ^ path to text file
    -> Int          -- ^ length of prefix
    -> Int          -- ^ line number (1-based)
    -> Int          -- ^ column number (1-based)
    -> IO [String]  -- ^ found prefix
getPrefix textPath prefixLen line col = try `catchIOError` handler
    where
        try :: IO [String]
        try = do
            textHandle <- openFile textPath ReadMode
            replicateM_ (line - 1) $ hGetLine textHandle
            foundLine <- hGetLine textHandle
            hClose textHandle
            return $ lastN prefixLen $ words $ fst $ splitAt col foundLine

        lastN :: Int -> [a] -> [a]
        lastN n xs = drop (length xs - n) xs


-- | Reads the entire model from the ARPA file.
readModel
    :: String    -- ^ path to model file
    -> IO Model  -- ^ read model
readModel modelPath = try `catchIOError` handler
    where
        try :: IO Model
        try = do
            modelHandle <- openFile modelPath ReadMode
            header <- readHeader modelHandle
            allNGrams <- readAllNGrams modelHandle $ headerGetNMax header
            hClose modelHandle
            return $ Model header allNGrams

        headerGetNMax :: Header -> Int
        headerGetNMax (Header nMax _) = nMax


-- | Handler for exceptions that can occur during I/O actions like opening
-- a file.
handler
    :: IOError  -- ^ error that occurred
    -> IO a     -- ^ I/O action of the handler
handler e
    | isDoesNotExistError e = error $ "File "
        ++ maybe "" (\s -> '\'' : s ++ "\'") (ioeGetFileName e)
        ++ " could not be found! There might be an error in the path."
    | otherwise = ioError e


-- | Reads the header of an ARPA file.
-- CAUTION: The handle MUST be at the beginning of the file or this function
-- won't work!
readHeader
    :: Handle     -- ^ handle of model file
    -> IO Header  -- ^ read model header
readHeader modelHandle = go $ Header 0 []
    where
        go :: Header -> IO Header
        go header@(Header n nums) = do
            line <- maybeGetLine modelHandle
            let split = maybeSplit "=" line

            case split of
                Nothing -> return header
                Just [""] -> return header
                Just [_, num] -> let header' = Header (n+1) (nums ++ [read num])
                                 in go header'            --_^^^^^^^^^^^^^^^^^^ performance goes over board
                _ -> go header


-- | Reads the n-gram sections of an ARPA file that follow the header.
-- CAUTION: The handle MUST be hehind the ARPA header or this function
-- won't work!
readAllNGrams
    :: Handle       -- ^ handle of model file
    -> Int          -- ^ maximum n for n-grams
    -> IO [NGrams]  -- ^ all read n-grams for n = 1..max
readAllNGrams modelHandle nMax = go 1
    where
        go :: Int -> IO [NGrams]
        go n
            | n == nMax = do
                ngrams <- readNGrams Map.empty True
                return [ngrams]
            | otherwise = do
                ngrams <- readNGrams Map.empty False
                rest <- go (n + 1)
             --_^^^^^^^^^^^^^^^^^^ performance ???
                return $ ngrams : rest

        readNGrams :: NGrams -> Bool -> IO NGrams
        readNGrams ngrams isMax = do
            line <- maybeGetLine modelHandle
            let split = maybeSplit " \t" line

            case split of
                Nothing -> return ngrams
                Just [""] -> return ngrams
                Just [_] -> readNGrams ngrams isMax
                Just [] -> undefined
                Just split' -> let (ngram, prob) = if isMax
                                                   then parseMaxNGram split'
                                                   else parseNGram split'
                                   ngrams' = Map.insert ngram prob ngrams
                               in readNGrams ngrams' isMax

        parseNGram :: [String] -> ([String], Prob)
        parseNGram (pStr : xs) = let p = read pStr
                                     w = init xs
                                     b = read $ last xs
                                 in (w, Prob p b)
        parseNGram _ = undefined

        parseMaxNGram :: [String] -> ([String], Prob)
        parseMaxNGram (pStr : xs) = let p = read pStr
                                        w = xs
                                    in (w, ProbMax p)
        parseMaxNGram _ = undefined


-- | Wrapper for hGetLine that handles EOF using the Maybe monad.
maybeGetLine
    :: Handle             -- ^ handle of file that is to be read from
    -> IO (Maybe String)  -- ^ Just (read string) or Nothing
maybeGetLine handle = do
    eof <- hIsEOF handle
    if eof
    then return Nothing
    else do
        line <- hGetLine handle
        return $ Just line


-- | Wrapper for splitOneOf that works with the Maybe monad.
maybeSplit
    :: String          -- ^ string of all possible char delimiters
    -> Maybe String    -- ^ Just (string that is to be split) or Nothing
    -> Maybe [String]  -- ^ Just (split string) or Nothing
maybeSplit _ Nothing = Nothing
maybeSplit dels (Just s) = Just $ splitOneOf dels s
