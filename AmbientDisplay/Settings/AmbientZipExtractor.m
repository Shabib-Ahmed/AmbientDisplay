#import "AmbientZipExtractor.h"
#import <compression.h>

NSString * const AmbientZipExtractorErrorDomain = @"AmbientZipExtractorErrorDomain";

static const NSUInteger kMaxEntries = 4096;
static const uint64_t kMaxTotalBytes = 1536ULL * 1024 * 1024;   // 1.5 GB extracted
static const size_t kChunkSize = 64 * 1024;

static NSError *ZipError(NSString *message) {
    return [NSError errorWithDomain:AmbientZipExtractorErrorDomain
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

#define ZIP_FAIL(msg) do { if (error) { *error = ZipError(msg); } return NO; } while (0)

static inline uint16_t rd16(const uint8_t *p) {
    uint16_t v;
    memcpy(&v, p, sizeof(v));
    return CFSwapInt16LittleToHost(v);
}

static inline uint32_t rd32(const uint8_t *p) {
    uint32_t v;
    memcpy(&v, p, sizeof(v));
    return CFSwapInt32LittleToHost(v);
}

// Streams a raw-deflate payload to `f` in fixed-size chunks, so large
// deflated entries never need an entry-sized buffer in memory.
static BOOL InflateToFile(const uint8_t *src, size_t srcSize, uint64_t expected, FILE *f, NSString **why) {
    uint8_t *buffer = malloc(kChunkSize);
    if (!buffer) {
        *why = @"Out of memory.";
        return NO;
    }

    compression_stream stream;
    if (compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) != COMPRESSION_STATUS_OK) {
        free(buffer);
        *why = @"Couldn't start decompression.";
        return NO;
    }

    stream.src_ptr = src;
    stream.src_size = srcSize;
    stream.dst_ptr = buffer;
    stream.dst_size = kChunkSize;

    uint64_t written = 0;
    BOOL ok = NO;

    while (YES) {
        compression_status status = compression_stream_process(&stream, COMPRESSION_STREAM_FINALIZE);
        if (status == COMPRESSION_STATUS_ERROR) {
            *why = @"The zip contains corrupt compressed data.";
            break;
        }

        size_t produced = kChunkSize - stream.dst_size;
        if (produced > 0) {
            written += produced;
            if (written > expected) {
                *why = @"A file in the zip is larger than it declares.";
                break;
            }
            if (fwrite(buffer, 1, produced, f) != produced) {
                *why = @"Couldn't write to disk (is the device out of space?).";
                break;
            }
            stream.dst_ptr = buffer;
            stream.dst_size = kChunkSize;
        } else if (status == COMPRESSION_STATUS_OK) {
            // No output and not finished: would spin forever.
            *why = @"The zip contains corrupt compressed data.";
            break;
        }

        if (status == COMPRESSION_STATUS_END) {
            if (written == expected) {
                ok = YES;
            } else {
                *why = @"A file in the zip doesn't match its declared size.";
            }
            break;
        }
    }

    compression_stream_destroy(&stream);
    free(buffer);
    return ok;
}

static BOOL WriteEntry(const uint8_t *src, uint16_t method, uint64_t csize, uint64_t usize,
                       const char *path, NSString **why) {
    FILE *f = fopen(path, "wb");
    if (!f) {
        *why = @"Couldn't create a file on disk.";
        return NO;
    }

    BOOL ok = NO;
    if (method == 0) {
        if (csize != usize) {
            *why = @"A stored file in the zip has inconsistent sizes.";
        } else if (usize == 0 || fwrite(src, 1, (size_t)usize, f) == (size_t)usize) {
            ok = YES;
        } else {
            *why = @"Couldn't write to disk (is the device out of space?).";
        }
    } else if (method == 8) {
        ok = InflateToFile(src, (size_t)csize, usize, f, why);
    } else {
        *why = [NSString stringWithFormat:@"Unsupported zip compression method (%u).", method];
    }

    if (fclose(f) != 0 && ok) {
        ok = NO;
        *why = @"Couldn't finish writing a file to disk.";
    }
    return ok;
}

@implementation AmbientZipExtractor

+ (BOOL)extractZipAtURL:(NSURL *)zipURL
         toDirectoryURL:(NSURL *)directoryURL
                  error:(NSError **)error {
    NSError *readError = nil;
    NSData *data = [NSData dataWithContentsOfURL:zipURL
                                         options:NSDataReadingMappedIfSafe
                                           error:&readError];
    if (!data) {
        ZIP_FAIL(readError.localizedDescription ?: @"Couldn't read the zip file.");
    }

    const uint8_t *base = data.bytes;
    uint64_t len = data.length;
    if (len < 22) {
        ZIP_FAIL(@"That file isn't a valid zip archive.");
    }

    // Locate the End Of Central Directory record (scan back over a possible comment).
    int64_t eocd = -1;
    int64_t minPos = (len > (22 + 65535)) ? (int64_t)(len - (22 + 65535)) : 0;
    for (int64_t i = (int64_t)len - 22; i >= minPos; i--) {
        if (rd32(base + i) == 0x06054b50) {
            eocd = i;
            break;
        }
    }
    if (eocd < 0) {
        ZIP_FAIL(@"That file isn't a valid zip archive.");
    }

    uint16_t entryCount = rd16(base + eocd + 10);
    uint32_t cdSize = rd32(base + eocd + 12);
    uint32_t cdOffset = rd32(base + eocd + 16);

    if (entryCount == 0xFFFF || cdSize == 0xFFFFFFFF || cdOffset == 0xFFFFFFFF) {
        ZIP_FAIL(@"Zip64 archives aren't supported. Re-zip with a standard zip tool.");
    }
    if ((uint64_t)cdOffset + cdSize > len) {
        ZIP_FAIL(@"The zip's directory is corrupt.");
    }
    if (entryCount > kMaxEntries) {
        ZIP_FAIL(@"The zip contains too many files.");
    }

    NSFileManager *fm = [[NSFileManager alloc] init];
    NSError *dirError = nil;
    if (![fm createDirectoryAtURL:directoryURL withIntermediateDirectories:YES attributes:nil error:&dirError]) {
        ZIP_FAIL(dirError.localizedDescription ?: @"Couldn't create a working folder.");
    }
    NSString *root = directoryURL.URLByStandardizingPath.path;
    NSString *rootPrefix = [root stringByAppendingString:@"/"];

    uint64_t pos = cdOffset;
    uint64_t end = (uint64_t)cdOffset + cdSize;
    uint64_t total = 0;

    for (NSUInteger i = 0; i < entryCount; i++) {
        if (pos + 46 > end) {
            ZIP_FAIL(@"The zip's directory is corrupt.");
        }
        const uint8_t *p = base + pos;
        if (rd32(p) != 0x02014b50) {
            ZIP_FAIL(@"The zip's directory is corrupt.");
        }

        uint16_t madeBy = rd16(p + 4);
        uint16_t flags = rd16(p + 8);
        uint16_t method = rd16(p + 10);
        uint32_t csize = rd32(p + 20);
        uint32_t usize = rd32(p + 24);
        uint16_t nameLen = rd16(p + 28);
        uint16_t extraLen = rd16(p + 30);
        uint16_t commentLen = rd16(p + 32);
        uint32_t externalAttrs = rd32(p + 38);
        uint32_t localOffset = rd32(p + 42);

        uint64_t next = pos + 46 + (uint64_t)nameLen + extraLen + commentLen;
        if (next > end) {
            ZIP_FAIL(@"The zip's directory is corrupt.");
        }

        NSString *name = [[NSString alloc] initWithBytes:p + 46 length:nameLen encoding:NSUTF8StringEncoding];
        if (!name) {
            name = [[NSString alloc] initWithBytes:p + 46 length:nameLen encoding:NSISOLatin1StringEncoding];
        }
        pos = next;

        if (!name || name.length == 0) {
            continue;
        }
        if (flags & 0x1) {
            ZIP_FAIL(@"Encrypted zips aren't supported.");
        }
        if ((madeBy >> 8) == 3 && ((externalAttrs >> 16) & 0xF000) == 0xA000) {
            ZIP_FAIL(@"Zips containing symbolic links aren't supported.");
        }
        if ([name hasPrefix:@"/"] || [name containsString:@"\\"] || memchr(p + 46, 0, nameLen) != NULL) {
            ZIP_FAIL(@"The zip contains an unsafe file path.");
        }

        // Build a clean relative path. Reject "..", drop "." and empty parts.
        NSMutableArray<NSString *> *parts = [NSMutableArray array];
        for (NSString *part in [name componentsSeparatedByString:@"/"]) {
            if (part.length == 0 || [part isEqualToString:@"."]) {
                continue;
            }
            if ([part isEqualToString:@".."]) {
                ZIP_FAIL(@"The zip contains an unsafe file path.");
            }
            [parts addObject:part];
        }
        if (parts.count == 0) {
            continue;
        }
        // macOS Finder noise: skip silently.
        if ([parts.firstObject isEqualToString:@"__MACOSX"] ||
            [parts.lastObject isEqualToString:@".DS_Store"] ||
            [parts.lastObject hasPrefix:@"._"]) {
            continue;
        }

        NSString *relative = [parts componentsJoinedByString:@"/"];
        NSString *destination = [[root stringByAppendingPathComponent:relative] stringByStandardizingPath];
        if (![destination hasPrefix:rootPrefix]) {
            ZIP_FAIL(@"The zip contains an unsafe file path.");
        }

        BOOL isDirectory = [name hasSuffix:@"/"];
        if (isDirectory) {
            [fm createDirectoryAtPath:destination withIntermediateDirectories:YES attributes:nil error:nil];
            continue;
        }

        total += usize;
        if (total > kMaxTotalBytes) {
            ZIP_FAIL(@"The zip is too large to import.");
        }

        // Local header -> start of the entry's data.
        if ((uint64_t)localOffset + 30 > len) {
            ZIP_FAIL(@"The zip is corrupt.");
        }
        const uint8_t *lp = base + localOffset;
        if (rd32(lp) != 0x04034b50) {
            ZIP_FAIL(@"The zip is corrupt.");
        }
        uint64_t dataStart = (uint64_t)localOffset + 30 + rd16(lp + 26) + rd16(lp + 28);
        if (dataStart + csize > len) {
            ZIP_FAIL(@"The zip is truncated or corrupt.");
        }

        NSError *parentError = nil;
        if (![fm createDirectoryAtPath:[destination stringByDeletingLastPathComponent]
           withIntermediateDirectories:YES attributes:nil error:&parentError]) {
            ZIP_FAIL(parentError.localizedDescription ?: @"Couldn't create a folder.");
        }

        NSString *why = nil;
        if (!WriteEntry(base + dataStart, method, csize, usize, destination.fileSystemRepresentation, &why)) {
            ZIP_FAIL(why ?: @"Couldn't extract a file from the zip.");
        }
    }

    return YES;
}

@end
