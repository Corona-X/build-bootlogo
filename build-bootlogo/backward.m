#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

typedef UInt64 OSSize;

#if __has_include("XKBootLogo.h")

#include "XKBootLogo.h"

void reverseTransform(uint8_t *buffer)
{
    for (size_t y = 0; y < kXKBootLogoHeight; y++)
    {
        for (size_t x = 0; x < kXKBootLogoWidth; x++)
        {
            UInt64 imageIndex = ((y * 4) * kXKBootLogoWidth) + (x * 4);
            UInt64 index = (y * kXKBootLogoWidth) + x;
            UInt32 rgb = kXKBootLogoPaletteRGB[kXKBootLogoData[index]];

            buffer[imageIndex] = 0;
            buffer[imageIndex + 1] = (rgb >> 0x10) & 0xFF;
            buffer[imageIndex + 2] = (rgb >> 0x08) & 0xFF;
            buffer[imageIndex + 3] = (rgb >> 0x00) & 0xFF;
        }
    }
}

void doReverse(NSURL *url)
{
    NSBitmapImageRep *bitmapImage = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nil pixelsWide:kXKBootLogoWidth pixelsHigh:kXKBootLogoHeight bitsPerSample:8 samplesPerPixel:3 hasAlpha:NO isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:(kXKBootLogoWidth * 4) bitsPerPixel:32];

    reverseTransform([bitmapImage bitmapData]);

    NSData *pngData = [bitmapImage representationUsingType:NSPNGFileType properties:@{}];
    [pngData writeToURL:url atomically:YES];
}

#else

void doReverse(NSURL *url)
{
    printf("This functionality is not compiled into this binary.\n");
}

#endif
