/*
 * Copyright 2012 ZXing authors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import "ZXBarcodeFormat.h"
#import "ZXBinaryBitmap.h"
#import "ZXBitMatrix.h"
#import "ZXDecodeHints.h"
#import "ZXDecoderResult.h"
#import "ZXDetectorResult.h"
#import "ZXErrors.h"
#import "ZXQRCodeDecoder.h"
#import "ZXQRCodeDetector.h"
#import "ZXQRCodeReader.h"
#import "ZXResult.h"

@interface ZXQRCodeReader ()

@property (nonatomic, retain) ZXQRCodeDecoder * decoder;

- (ZXBitMatrix *)extractPureBits:(ZXBitMatrix *)image;
- (int)moduleSize:(NSArray *)leftTopBlack image:(ZXBitMatrix *)image;

@end

@implementation ZXQRCodeReader

@synthesize decoder;

- (id)init {
  if (self = [super init]) {
    self.decoder = [[[ZXQRCodeDecoder alloc] init] autorelease];
  }

  return self;
}

- (void)dealloc {
  [decoder release];

  [super dealloc];
}

/**
 * Locates and decodes a QR code in an image.
 */
- (ZXResult *)decode:(ZXBinaryBitmap *)image error:(NSError **)error {
  return [self decode:image hints:nil error:error];
}

- (ZXResult *)decode:(ZXBinaryBitmap *)image hints:(ZXDecodeHints *)hints error:(NSError **)error {
  ZXDecoderResult * decoderResult;
  NSArray * points;
  ZXBitMatrix * matrix = [image blackMatrixWithError:error];
  if (!matrix) {
    return nil;
  }
  if (hints != nil && hints.pureBarcode) {
    ZXBitMatrix * bits = [self extractPureBits:matrix];
    if (!bits) {
      if (error) *error = NotFoundErrorInstance();
      return nil;
    }
    decoderResult = [decoder decodeMatrix:bits hints:hints error:error];
    if (!decoderResult) {
      return nil;
    }
    points = [NSArray array];
  } else {
    ZXDetectorResult * detectorResult = [[[[ZXQRCodeDetector alloc] initWithImage:matrix] autorelease] detect:hints error:error];
    if (!detectorResult) {
      return nil;
    }
    decoderResult = [decoder decodeMatrix:[detectorResult bits] hints:hints error:error];
    if (!decoderResult) {
      return nil;
    }
    points = [detectorResult points];
  }

  ZXResult * result = [ZXResult resultWithText:decoderResult.text
                                      rawBytes:decoderResult.rawBytes
                                        length:decoderResult.length
                                  resultPoints:points
                                        format:kBarcodeFormatQRCode];
  NSMutableArray* byteSegments = decoderResult.byteSegments;
  if (byteSegments != nil) {
    [result putMetadata:kResultMetadataTypeByteSegments value:byteSegments];
  }
  NSString* ecLevel = decoderResult.ecLevel;
  if (ecLevel != nil) {
    [result putMetadata:kResultMetadataTypeErrorCorrectionLevel value:ecLevel];
  }
  return result;
}

- (void)reset {
  // do nothing
}


/**
 * This method detects a code in a "pure" image -- that is, pure monochrome image
 * which contains only an unrotated, unskewed, image of a code, with some white border
 * around it. This is a specialized method that works exceptionally fast in this special
 * case.
 */
- (ZXBitMatrix *)extractPureBits:(ZXBitMatrix *)image {
  NSArray * leftTopBlack = image.topLeftOnBit;
  NSArray * rightBottomBlack = image.bottomRightOnBit;
  if (leftTopBlack == nil || rightBottomBlack == nil) {
    return nil;
  }

  int moduleSize = [self moduleSize:leftTopBlack image:image];
  if (moduleSize == -1) {
    return nil;
  }

  int top = [[leftTopBlack objectAtIndex:1] intValue];
  int bottom = [[rightBottomBlack objectAtIndex:1] intValue];
  int left = [[leftTopBlack objectAtIndex:0] intValue];
  int right = [[rightBottomBlack objectAtIndex:0] intValue];

  if (bottom - top != right - left) {
    // Special case, where bottom-right module wasn't black so we found something else in the last row
    // Assume it's a square, so use height as the width
    right = left + (bottom - top);
  }

  int matrixWidth = (right - left + 1) / moduleSize;
  int matrixHeight = (bottom - top + 1) / moduleSize;
  if (matrixWidth <= 0 || matrixHeight <= 0) {
    return nil;
  }
  if (matrixHeight != matrixWidth) {
    return nil;
  }

  int nudge = moduleSize >> 1;
  top += nudge;
  left += nudge;

  ZXBitMatrix * bits = [[[ZXBitMatrix alloc] initWithWidth:matrixWidth height:matrixHeight] autorelease];
  for (int y = 0; y < matrixHeight; y++) {
    int iOffset = top + y * moduleSize;
    for (int x = 0; x < matrixWidth; x++) {
      if ([image getX:left + x * moduleSize y:iOffset]) {
        [bits setX:x y:y];
      }
    }
  }
  return bits;
}

- (int)moduleSize:(NSArray *)leftTopBlack image:(ZXBitMatrix *)image {
  int height = image.height;
  int width = image.width;
  int x = [[leftTopBlack objectAtIndex:0] intValue];
  int y = [[leftTopBlack objectAtIndex:1] intValue];
  while (x < width && y < height && [image getX:x y:y]) {
    x++;
    y++;
  }
  if (x == width || y == height) {
    return -1;
  }

  int moduleSize = x - [[leftTopBlack objectAtIndex:0] intValue];
  if (moduleSize == 0) {
    return -1;
  }
  return moduleSize;
}

@end
