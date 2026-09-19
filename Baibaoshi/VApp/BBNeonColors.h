// BBNeonColors.h - 深色主题霓虹颜色常量（NO OUTER BRACKETS!）
#pragma once

#import <UIKit/UIKit.h>

// Background  
#define BB_BG_COLOR [UIColor colorWithRed:0.04 green:0.06 blue:0.10 alpha:1]

// Text colors
#define BB_WHITE_TEXT [UIColor whiteColor]

// Status colors – NEON variants
// NOTE: NO outer [ ] so macros expand correctly as sub-expressions
#define BB_NEON_RED \
    [UIColor colorWithRed:1.00 green:0.25 blue:0.30 alpha:1]
#define BB_NEON_ORANGE \
    [UIColor colorWithRed:1.00 green:0.60 blue:0.10 alpha:1]
#define BB_NEON_GREEN \
    [UIColor colorWithRed:0.25 green:0.90 blue:0.50 alpha:1]
#define BB_NEON_BLUE \
    [UIColor colorWithRed:0.40 green:0.75 blue:1.00 alpha:1]

// Gray text for dark bg
#define BB_DARK_GRAY \
    [UIColor colorWithRed:0.55 green:0.65 blue:0.75 alpha:1]

// UI labels adapted for dark background
#define BB_LABEL_LIGHT \
    [UIColor colorWithRed:0.55 green:0.65 blue:0.80 alpha:1]
#define BB_LABEL_SUBTITLE \
    [UIColor colorWithRed:0.45 green:0.55 blue:0.70 alpha:1]
#define BB_HEADER_TEXT \
    [UIColor colorWithRed:0.60 green:0.72 blue:0.85 alpha:1]
#define BB_TRACK_COLOR \
    [UIColor colorWithRed:0.10 green:0.14 blue:0.20 alpha:1]
