#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

typedef struct {
    uint8_t red;
    uint8_t green;
    uint8_t blue;
} pixel;

// Palette:
//   byte  - ID
//   dword - color value

// Given 2 palettes - RGB and BGR

// Image encoded as a set of palette information, each pixel = 2 bytes
// Image additionally encoded as a set of alpha components (1 byte each)
// Actually, we removed the alpha buffer, as I deemed it useless.

NSString *sectionAttribute = @"__attribute__((section(\"__DATA,__bootlogo\"))) ";
NSMutableString *header;

void write_data(NSData *data, NSURL *location)
{
    NSError *error;
    BOOL created = [data writeToURL:location options:NSDataWritingAtomic error:&error];

    if (!created)
    {
        printf("Error: Could not write to '%s'. (Error: %s)\n", [[location absoluteString] UTF8String], [[error localizedDescription] UTF8String]);
        exit(EXIT_FAILURE);
    }
}

uint16_t palette_lookup(uint32_t palette[1 << 16], uint16_t filled, uint32_t rgb)
{
    for (uint16_t i = 0; i < filled; i++)
    {
        if (palette[i] == rgb)
            return i;
    }

    if (filled == 0xFFF)
    {
        printf("Error: Image may only have 4095 unique colors!\n");
        exit(EXIT_FAILURE);
    }

    palette[filled] = rgb;
    return filled;
}

NSString *encode_palette_once(uint32_t palette[1 << 16], uint16_t filled, BOOL rgb)
{
    NSString *variableName = @"const static UInt32 kXKBootLogoPalette";
    NSMutableString *paletteString = [NSMutableString string];

    [paletteString appendString:sectionAttribute];
    [paletteString appendString:[NSString stringWithFormat:@"%@%@[%hu] = {\n", variableName, (rgb ? @"RGB" : @"BGR"), filled]];

    for (uint16_t i = 0; i < filled; i++)
    {
        uint32_t entry = palette[i];

        if (!rgb)
        {
            entry = ((entry >> 16) & 0x0000FF) |
                    ((entry << 00) & 0x00FF00) |
                    ((entry << 16) & 0xFF0000);
        }

        [paletteString appendString:[NSString stringWithFormat:@"\t0x%06X", entry]];

        if (i == (filled - 1))   [paletteString appendString:@"\n};\n\n"];
        else if (!((i + 1) % 4)) [paletteString appendString:@",\n"];
        else                     [paletteString appendString:@", "];
    }

    return [paletteString copy];
}

NSString *encode_palette(uint32_t palette[1 << 16], uint16_t filled)
{
    NSMutableString *paletteString = [NSMutableString string];

    [paletteString appendString:encode_palette_once(palette, filled, YES)];
    [paletteString appendString:encode_palette_once(palette, filled,  NO)];

    return [paletteString copy];
}

NSString *encode_image(uint16_t *paletteBuffer, NSInteger imageHeight, NSInteger imageWidth)
{
    NSString *variableName = @"const static UInt16 kXKBootLogoData";
    NSMutableString *imageString = [NSMutableString string];
    NSInteger imageSize = imageHeight * imageWidth;

    [imageString appendString:sectionAttribute];
    [imageString appendString:[NSString stringWithFormat:@"%@[%ld] = {\n", variableName, imageSize]];
    [imageString appendString:@"\t"];

    for (NSInteger i = 0; i < imageSize; i++)
    {
        [imageString appendString:[NSString stringWithFormat:@"0x%03X", paletteBuffer[i]]];

        if (i == (imageSize - 1))         [imageString appendString:@"\n};\n\n"];
        else if (!((i + 1) % 16))         [imageString appendString:@",\n\t"];
        else                              [imageString appendString:@", "];
    }

    return [imageString copy];
}

void process_image(NSData *data, NSURL *writeLocation)
{
    NSBitmapImageRep *image = [[NSBitmapImageRep alloc] initWithData:data];
    NSInteger imageHeight = [image pixelsHigh];
    NSInteger imageWidth  = [image pixelsWide];

    if ((imageHeight & 1) || (imageWidth & 1))
    {
        printf("Error: Image must have an even height and width! (Found %zux%zu)\n", imageWidth, imageHeight);
        exit(EXIT_FAILURE);
    }

    [header appendString:[NSString stringWithFormat:@"%@const static OSSize kXKBootLogoHeight = %zu;\n",   sectionAttribute, imageHeight]];
    [header appendString:[NSString stringWithFormat:@"%@const static OSSize kXKBootLogoWidth  = %zu;\n\n", sectionAttribute, imageWidth]];

    size_t bufferSize = imageHeight * imageWidth * sizeof(uint16_t);
    uint16_t *paletteBuffer = malloc(bufferSize);
    uint8_t *alphaBuffer = malloc(bufferSize);
    uint32_t palette[1 << 16];
    uint16_t filled = 0;

    if (!(paletteBuffer && alphaBuffer))
    {
        printf("Error: Out of memory.\n");
        exit(EXIT_FAILURE);
    }

    for (size_t y = 0; y < imageHeight; y++)
    {
        for (size_t x = 0; x < imageWidth; x++)
        {
            NSUInteger pixelData[4];
            [image getPixel:pixelData atX:x y:y];

            uint32_t rgb = ((((uint32_t)pixelData[0]) << 0x10) & 0xFF0000) |
                           ((((uint32_t)pixelData[1]) << 0x08) & 0x00FF00) |
                           ((((uint32_t)pixelData[2]) << 0x00) & 0x0000FF);

            uint16_t entry = palette_lookup(palette, filled, rgb);
            alphaBuffer[(y * imageWidth) + x] = pixelData[3];
            paletteBuffer[(y * imageWidth) + x] = entry;

            if (entry == filled)
                filled++;
        }
    }

    // Yay we have the buffers now :3
    [header appendString:encode_palette(palette, filled)];
    [header appendString:encode_image(paletteBuffer, imageHeight, imageWidth)];

    free(paletteBuffer);
    free(alphaBuffer);

    write_data([NSData dataWithBytes:[header UTF8String] length:[header length]], writeLocation);
}

extern void doReverse(NSURL *url);

int main(int argc, const char *const *argv)
{
    @autoreleasepool
    {
        NSMutableArray *args = [[NSMutableArray alloc] initWithCapacity:argc];
        header = [NSMutableString string];

        [header appendString:@"/*****************************************************************************************/\n"
                              "/* +-+ WARNING: Autogenerated header file! Make changes to 'build-bootlogo' instead. +-+ */\n"
                              "/*****************************************************************************************/\n\n"];

        for (NSInteger i = 0; i < argc; i++)
            [args addObject:[NSString stringWithUTF8String:argv[i]]];

        if ([args count] < 3)
        {
            printf("Error: Not enough arguments!\n");
            exit(EXIT_FAILURE);
        }

        if ([[NSFileManager defaultManager] fileExistsAtPath:[args objectAtIndex:2]])
            printf("Warning: Output file '%s' already exists!\n", [[args objectAtIndex:2] UTF8String]);

        NSData *imageData = [NSData dataWithContentsOfFile:[args objectAtIndex:1]];

        if (!imageData)
        {
            printf("Error: Input image '%s' does not exist!\n", [[args objectAtIndex:1] UTF8String]);
            exit(EXIT_FAILURE);
        }

        process_image(imageData, [NSURL fileURLWithPath:[args objectAtIndex:2]]);

        if ([args count] > 3)
            doReverse([NSURL fileURLWithPath:[args objectAtIndex:3]]);
    }

    return EXIT_SUCCESS;
}
