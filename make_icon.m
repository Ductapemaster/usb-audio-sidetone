// make_icon.m — build-time tool that generates AppIcon.iconset/ for Sidetone.app.
// Renders the "ear" SF Symbol on a rounded-rect background with light and dark variants.
// Run via build.sh; output is consumed by iconutil.

#import <AppKit/AppKit.h>

static NSData *renderPNG(int px, BOOL dark) {
    NSBitmapImageRep *bmp = [[NSBitmapImageRep alloc]
        initWithBitmapDataPlanes:NULL
        pixelsWide:px pixelsHigh:px
        bitsPerSample:8 samplesPerPixel:4
        hasAlpha:YES isPlanar:NO
        colorSpaceName:NSDeviceRGBColorSpace
        bytesPerRow:0 bitsPerPixel:0];

    NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:bmp];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:ctx];

    // Transparent base
    [[NSColor clearColor] setFill];
    NSRectFill(NSMakeRect(0, 0, px, px));

    // Rounded-rect background (macOS Big Sur icon shape, ~22.5% corner radius)
    CGFloat r = px * 0.225;
    NSColor *bg = dark
        ? [NSColor colorWithRed:0.13 green:0.14 blue:0.16 alpha:1.0]  // dark slate
        : [NSColor colorWithRed:0.95 green:0.95 blue:0.97 alpha:1.0]; // near-white
    [bg setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(0, 0, px, px)
                                    xRadius:r yRadius:r] fill];

    // "ear" SF Symbol, monochrome, centered with ~19% padding on each side
    NSImageSymbolConfiguration *cfg =
        [NSImageSymbolConfiguration configurationPreferringMonochrome];
    NSImage *ear = [[NSImage imageWithSystemSymbolName:@"ear"
                                accessibilityDescription:nil]
                    imageWithSymbolConfiguration:cfg];

    NSColor *fg = dark
        ? [NSColor colorWithWhite:1.0 alpha:1.0]
        : [NSColor colorWithWhite:0.0 alpha:1.0];
    [fg set];

    CGFloat pad = px * 0.19;
    [ear drawInRect:NSMakeRect(pad, pad, px - pad * 2, px - pad * 2)
           fromRect:NSZeroRect
          operation:NSCompositingOperationSourceOver
           fraction:1.0
     respectFlipped:NO
               hints:nil];

    [NSGraphicsContext restoreGraphicsState];

    return [bmp representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication]; // required for SF Symbol loading

        NSString *dir = @"AppIcon.iconset";
        NSError *err = nil;
        [[NSFileManager defaultManager] createDirectoryAtPath:dir
            withIntermediateDirectories:YES attributes:nil error:&err];
        if (err) { NSLog(@"mkdir failed: %@", err); return 1; }

        struct { int logical; int scale; } specs[] = {
            {16,1},{16,2},{32,1},{32,2},
            {128,1},{128,2},{256,1},{256,2},{512,1},{512,2}
        };
        int n = (int)(sizeof(specs) / sizeof(specs[0]));

        for (int i = 0; i < n; i++) {
            int logical = specs[i].logical;
            int scale   = specs[i].scale;
            int px      = logical * scale;

            NSString *base = (scale > 1)
                ? [NSString stringWithFormat:@"icon_%dx%d@%dx", logical, logical, scale]
                : [NSString stringWithFormat:@"icon_%dx%d",     logical, logical];

            for (int dark = 0; dark <= 1; dark++) {
                NSString *name = dark
                    ? [NSString stringWithFormat:@"%@~dark.png", base]
                    : [NSString stringWithFormat:@"%@.png",      base];
                NSData *png = renderPNG(px, (BOOL)dark);
                [png writeToFile:[dir stringByAppendingPathComponent:name] atomically:YES];
            }
        }
    }
    return 0;
}
