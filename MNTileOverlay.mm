//
//  MNTileOverlay.mm
//
//  Created by Dennis Oberhoff on 08/12/13.
//  Copyright (c) 2013 Dennis Oberhoff. All rights reserved.
//

#import "MNTileOverlay.h"
#include <math.h>

#include <mapnik/map.hpp>
#include <mapnik/graphics.hpp>
#include <mapnik/color.hpp>
#include <mapnik/image_util.hpp>
#include <mapnik/agg_renderer.hpp>
#include <mapnik/load_map.hpp>
#include <mapnik/datasource_cache.hpp>
#include <mapnik/datasource.hpp>

#define degreesToRadians(x)    (x * M_PI / 180)
#define radiansToDegrees(x)    (x * 180 / M_PI)

using namespace mapnik;

@interface MNTileOverlay()

@property (nonatomic, strong) dispatch_queue_t renderQueue;

@end

@implementation MNTileOverlay

-(id)init
{
    
    self = [super init];
    
    if (self) {
        self.canReplaceMapContent = YES;
        self.geometryFlipped = NO;
        self.maximumZ = 20;
        self.minimumZ = 4;
    }
    
    return self;
    
}

-(id)initWithStyle: (NSURL*)styleFile
{
    
    self = [self init];
    if (self) {
        
        NSError *error;
        NSString *styleContent = [NSString stringWithContentsOfURL:styleFile encoding:NSUTF8StringEncoding error:&error];
        self.style = [styleContent stringByReplacingOccurrencesOfString:@"RESOURCE_PATH" withString:[NSBundle mainBundle].resourcePath];
        
    }
    
    return self;
    
}

- (void)loadTileAtPath:(MKTileOverlayPath)path result:(void (^)(NSData *tileData, NSError *error))result
{

    if (!_renderQueue) _renderQueue = dispatch_queue_create("renderQueue", DISPATCH_QUEUE_CONCURRENT);
    dispatch_async(_renderQueue, ^{
        NSData *image = [self renderTileForPath:path];
        result(image, NULL);
    });
    
}

-(NSData*)renderTileForPath: (MKTileOverlayPath)path;{

    image_32 im(self.tileSize.width, self.tileSize.height);
    Map m(im.width(),im.height());
    load_map_string(m, std::string(self.style.UTF8String));
    
    m.zoom_to_box([self convertPathTo2dBox:path]);

    agg_renderer<mapnik::image_32> ren(m,im);
    ren.apply();
    
    size_t im_size = im.width() * im.height();
    size_t bitsPerComponent = 8;
    size_t bitsPerPixel = 32;
    size_t bytesPerRow = 4 * im.width();
    
    CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, im.raw_data(), im_size, NULL);
    CGColorSpaceRef colorSpaceRef = CGColorSpaceCreateDeviceRGB();
    CGBitmapInfo bitmapInfo = kCGBitmapByteOrderDefault | kCGImageAlphaPremultipliedLast;
    CGColorRenderingIntent renderingIntent = kCGRenderingIntentDefault;
    
    CGImageRef iref = CGImageCreate(im.width(), im.height(), bitsPerComponent, bitsPerPixel, bytesPerRow, colorSpaceRef, bitmapInfo, provider,
                                    NULL, YES, renderingIntent);
    
    CGContextRef context = CGBitmapContextCreate(im.raw_data(), im.width(), im.height(),
                                                 bitsPerComponent, bytesPerRow, colorSpaceRef, bitmapInfo);
    
    CGContextDrawImage(context, CGRectMake(0.0f, 0.0f, im.width(), im.height()), iref);
   
    CGImageRef imageRef = CGBitmapContextCreateImage(context);
    UIImage *image = [UIImage imageWithCGImage:imageRef scale:path.contentScaleFactor orientation:UIDeviceOrientationPortrait];
    
    CGImageRelease(imageRef);
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpaceRef);
    CGImageRelease(iref);
    CGDataProviderRelease(provider);
    
    return  UIImagePNGRepresentation(image);
}


-(box2d<double>)convertPathTo2dBox:(MKTileOverlayPath)path{
  
    CLLocationDegrees topLatitude = convertTileYPathToLatitude(path.y, path.z);
    CLLocationDegrees belowLatitude = convertTileYPathToLatitude(path.y + 1, path.z);
    
    CLLocationDegrees westLongitude = convertTileXPathToLongitude(path.x, path.z);
    CLLocationDegrees rightLongitude = convertTileXPathToLongitude(path.x + 1, path.z);
    
    return box2d<double>(westLongitude, belowLatitude, rightLongitude, topLatitude);
    
}


static CGPoint getPixelFromLatitudeLongitude(CLLocationCoordinate2D coord) {
    
    CGFloat y = (((-1 * coord.latitude) + 90) * (256 / 180));
    CGFloat x = (180.0 + coord.longitude) * (256 / 360.0);
    return CGPointMake(x, y);
    
}

static CLLocationCoordinate2D getLatitudeLongitudeForPath(MKTileOverlayPath path) {

    CGFloat n = M_PI - 2 * M_PI * path.y / pow(2,path.z);
    CGFloat centerLongitude = path.x / pow(2, path.z) * 360 - 180;
    CGFloat centerLatitude = 180 / M_PI * atan(0.5 * (exp(n) - exp(-n)));
    return CLLocationCoordinate2DMake(centerLatitude, centerLongitude);

}

static CLLocationDegrees convertTileXPathToLongitude(NSInteger xPath, NSInteger zPath)
{
    return (xPath / pow(2.0, zPath) * 360.0 - 180.0);
}

static CLLocationDegrees convertTileYPathToLatitude(NSInteger yPath, NSInteger zPath)
{
    return radiansToDegrees(atan(sinh(M_PI - (2.0 * M_PI * yPath) / pow(2.0, zPath))));
}

@end
