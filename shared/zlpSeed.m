function seed = zlpSeed(key)
%ZLPSEED  Stable 32-bit random seed from a text key (FNV-1a hash).
%
%   seed = zlpSeed(key)
%
%   The same key gives the same seed on every machine and MATLAB release
%   (pure integer arithmetic: 32-bit FNV-1a over the UTF-8 bytes of key), so a
%   random draw seeded with it is reproducible. Used by the shared macro
%   spike-clean stage (preprocess_macros) with key = sessID | stage | section,
%   2026-10-22. Returns a double in [0, 2^32 - 1], valid for rng(seed, 'twister').
%   zlpSeed('') = 2166136261, zlpSeed('a') = 3826002220 (FNV-1a test vectors).

    bytes = uint64(unicode2native(char(string(key)), 'UTF-8'));
    h = uint64(2166136261);          % FNV offset basis
    prime = uint64(16777619);
    m = uint64(4294967296);          % 2^32
    for i = 1:numel(bytes)
        h = bitxor(h, bytes(i));
        h = mod(h * prime, m);       % h < 2^32, prime < 2^25: the product fits in uint64
    end
    seed = double(h);
end
