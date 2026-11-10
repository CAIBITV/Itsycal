#import <Cocoa/Cocoa.h>

@interface TimeZonePickerVC : NSViewController

- (instancetype)initWithSelection:(NSString *)identifier
                         onSelect:(void (^)(NSString *identifier))onSelect;
+ (NSString *)displayNameForTimeZone:(NSTimeZone *)timeZone;

@end
