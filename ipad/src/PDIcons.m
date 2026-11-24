#import "PDIcons.h"
#import "PDKeys.h"
#include <math.h>

// Paths are drawn on a 24 x 24 grid and scaled to the requested size.

static void fillTriangle(CGContextRef c, CGPoint a, CGPoint b, CGPoint d) {
    CGContextMoveToPoint(c, a.x, a.y);
    CGContextAddLineToPoint(c, b.x, b.y);
    CGContextAddLineToPoint(c, d.x, d.y);
    CGContextClosePath(c);
    CGContextFillPath(c);
}

static void roundedBar(CGContextRef c, CGRect r) {
    UIBezierPath *p = [UIBezierPath bezierPathWithRoundedRect:r cornerRadius:MIN(r.size.width, r.size.height) / 3];
    CGContextAddPath(c, p.CGPath);
    CGContextFillPath(c);
}

static void speaker(CGContextRef c) {
    CGContextMoveToPoint(c, 2.5, 9);
    CGContextAddLineToPoint(c, 6.5, 9);
    CGContextAddLineToPoint(c, 11.5, 4.5);
    CGContextAddLineToPoint(c, 11.5, 19.5);
    CGContextAddLineToPoint(c, 6.5, 15);
    CGContextAddLineToPoint(c, 2.5, 15);
    CGContextClosePath(c);
    CGContextFillPath(c);
}

static void wave(CGContextRef c, CGFloat radius) {
    CGContextAddArc(c, 11.5, 12, radius, -M_PI / 3.6, M_PI / 3.6, 0);
    CGContextStrokePath(c);
}

static void sun(CGContextRef c, BOOL big) {
    CGFloat core = big ? 4.2 : 3.4, from = big ? 7.2 : 6.2, to = big ? 10.6 : 8.2;
    CGContextAddEllipseInRect(c, CGRectMake(12 - core, 12 - core, core * 2, core * 2));
    CGContextFillPath(c);
    for (int i = 0; i < 8; i++) {
        CGFloat a = i * M_PI / 4;
        CGContextMoveToPoint(c, 12 + cos(a) * from, 12 + sin(a) * from);
        CGContextAddLineToPoint(c, 12 + cos(a) * to, 12 + sin(a) * to);
    }
    CGContextStrokePath(c);
}

UIImage *PDMediaIcon(int media, CGFloat side) {
    if (side < 4) side = 4;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGContextScaleCTM(c, side / 24.0, side / 24.0);
    [[UIColor blackColor] set];
    CGContextSetLineWidth(c, 2);
    CGContextSetLineCap(c, kCGLineCapRound);
    CGContextSetLineJoin(c, kCGLineJoinRound);

    switch (media) {
        case PDMediaPlay:          // ▶ ❚❚
            fillTriangle(c, CGPointMake(2.5, 5), CGPointMake(2.5, 19), CGPointMake(12, 12));
            roundedBar(c, CGRectMake(14, 5, 3, 14));
            roundedBar(c, CGRectMake(19, 5, 3, 14));
            break;
        case PDMediaPrev:          // ◀◀
            fillTriangle(c, CGPointMake(11.5, 5), CGPointMake(11.5, 19), CGPointMake(2.5, 12));
            fillTriangle(c, CGPointMake(21.5, 5), CGPointMake(21.5, 19), CGPointMake(12.5, 12));
            break;
        case PDMediaNext:          // ▶▶
            fillTriangle(c, CGPointMake(2.5, 5), CGPointMake(2.5, 19), CGPointMake(11.5, 12));
            fillTriangle(c, CGPointMake(12.5, 5), CGPointMake(12.5, 19), CGPointMake(21.5, 12));
            break;
        case PDMediaMute:          // speaker + ×
            speaker(c);
            CGContextMoveToPoint(c, 15, 9);  CGContextAddLineToPoint(c, 21, 15);
            CGContextMoveToPoint(c, 21, 9);  CGContextAddLineToPoint(c, 15, 15);
            CGContextStrokePath(c);
            break;
        case PDMediaVolDown:       // speaker + one wave
            speaker(c);
            wave(c, 4.5);
            break;
        case PDMediaVolUp:         // speaker + three waves
            speaker(c);
            wave(c, 4.5);
            wave(c, 7.8);
            wave(c, 11);
            break;
        case PDMediaBrightDown:    // small sun
            sun(c, NO);
            break;
        case PDMediaBrightUp:      // big sun
            sun(c, YES);
            break;
        default:
            break;
    }

    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}
