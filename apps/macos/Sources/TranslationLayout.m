#import "Core.h"

static NSArray<NSArray<NSString *> *> *TextLines(NSString *text) {
    NSMutableArray *lines = [NSMutableArray array];
    for (NSUInteger offset = 0; offset < text.length;) {
        NSUInteger end, contentsEnd;
        [text getLineStart:NULL end:&end contentsEnd:&contentsEnd forRange:NSMakeRange(offset, 0)];
        [lines addObject:@[[text substringWithRange:NSMakeRange(offset, contentsEnd - offset)],
                          [text substringWithRange:NSMakeRange(contentsEnd, end - contentsEnd)]]];
        offset = end;
    }
    return lines;
}

static NSString *LineMarker(NSString *text) {
    static NSRegularExpression *markers;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        markers = [NSRegularExpression regularExpressionWithPattern:@"^(?:#{1,6}[ \\t]+|(?:[-+*•‣▪]|[0-9]{1,9}[.)、])[ \\t]+|(?:>[ \\t]*)+)" options:0 error:NULL];
    });
    NSTextCheckingResult *match = [markers firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    return match ? [text substringWithRange:match.range] : @"";
}

NSString *TranslationWithSourceLayout(NSString *translation, NSString *source) {
    NSCharacterSet *content = NSCharacterSet.whitespaceAndNewlineCharacterSet.invertedSet;
    NSString *body = [translation stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!body.length) return nil;
    NSRange first = [source rangeOfCharacterFromSet:content];
    if (!source.length || first.location == NSNotFound) return body;
    NSArray *sourceLines = TextLines(source);
    NSMutableArray<NSString *> *translatedLines = [NSMutableArray array];
    for (NSArray *line in TextLines(body)) {
        NSString *text = [line[0] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (text.length) [translatedLines addObject:text];
    }
    NSUInteger sourceLineCount = 0;
    for (NSArray *line in sourceLines)
        if ([line[0] rangeOfCharacterFromSet:content].location != NSNotFound) sourceLineCount++;
    if (sourceLineCount == translatedLines.count) {
        NSMutableString *result = [NSMutableString string];
        NSUInteger index = 0;
        BOOL inCode = NO;
        NSString *fence = nil;
        for (NSArray *line in sourceLines) {
            NSString *original = line[0];
            NSRange start = [original rangeOfCharacterFromSet:content];
            if (start.location == NSNotFound) { [result appendString:original]; }
            else {
                NSRange end = [original rangeOfCharacterFromSet:content options:NSBackwardsSearch];
                NSString *originalBody = [original substringWithRange:NSMakeRange(start.location, NSMaxRange(end) - start.location)];
                NSString *translatedBody = translatedLines[index++];
                // Code is source data. List/heading repair must not reinterpret it.
                BOOL opensCode = !inCode && ([originalBody hasPrefix:@"```"] || [originalBody hasPrefix:@"~~~"]);
                BOOL closesCode = inCode && [originalBody hasPrefix:fence];
                if (inCode || opensCode) [result appendString:original];
                else {
                    NSString *sourceMarker = LineMarker(originalBody);
                    NSString *outputMarker = LineMarker(translatedBody);
                    [result appendString:[original substringToIndex:start.location]];
                    [result appendString:sourceMarker];
                    [result appendString:[translatedBody substringFromIndex:outputMarker.length]];
                    [result appendString:[original substringFromIndex:NSMaxRange(end)]];
                }
                if (opensCode) { inCode = YES; fence = [originalBody substringToIndex:3]; }
                else if (closesCode) { inCode = NO; fence = nil; }
            }
            [result appendString:line[1]];
        }
        return result;
    }
    // Never guess line correspondence or discard text if the model merges/splits lines.
    // Replace only model-added boundary padding with the source's own whitespace.
    NSRange last = [source rangeOfCharacterFromSet:content options:NSBackwardsSearch];
    return [NSString stringWithFormat:@"%@%@%@", [source substringToIndex:first.location], body, [source substringFromIndex:NSMaxRange(last)]];
}
