#import "TimeZonePickerVC.h"
#import "MoVFLHelper.h"

static NSDateFormatter *CityFormatter(NSString *language)
{
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = language ? [NSLocale localeWithLocaleIdentifier:language] : NSLocale.currentLocale;
    // VVV 是 Unicode 日期格式中的本地化时区城市名。
    formatter.dateFormat = @"VVV";
    return formatter;
}

static NSString *CityName(NSTimeZone *timeZone, NSDateFormatter *formatter, NSDateFormatter *englishFormatter,
                          NSDate *date, NSString *unknownCity)
{
    formatter.timeZone = timeZone;
    NSString *city = [formatter stringFromDate:date];
    if (!city.length || [city isEqualToString:unknownCity]) return timeZone.name;

    // 同一时区的旧标识符可能沿用同一个本地化城市名。保留旧标识符自己的地名。
    englishFormatter.timeZone = timeZone;
    NSString *englishCity = [englishFormatter stringFromDate:date];
    NSString *cityComponent = [englishCity stringByReplacingOccurrencesOfString:@" " withString:@"_"];
    NSString *name = timeZone.name;
    if (cityComponent.length && ![name.lastPathComponent isEqualToString:cityComponent]) {
        NSString *relatedName = [name.stringByDeletingLastPathComponent stringByAppendingPathComponent:cityComponent];
        NSTimeZone *relatedZone = [NSTimeZone timeZoneWithName:relatedName];
        if ([timeZone.data isEqualToData:relatedZone.data]) {
            return [name.lastPathComponent stringByReplacingOccurrencesOfString:@"_" withString:@" "];
        }
    }
    return city;
}

static NSString *UTCOffset(NSTimeZone *timeZone, NSDate *date)
{
    NSInteger minutes = [timeZone secondsFromGMTForDate:date] / 60;
    NSInteger magnitude = labs(minutes);
    return [NSString stringWithFormat:@"UTC%c%02ld:%02ld", minutes < 0 ? '-' : '+',
                                      (long)(magnitude / 60), (long)(magnitude % 60)];
}

@interface TimeZoneOption : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *city;
@property (nonatomic, copy) NSString *offset;
@end

@implementation TimeZoneOption
@end

@interface TimeZonePickerVC () <NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate>
@end

@implementation TimeZonePickerVC
{
    NSString *_selectedIdentifier;
    void (^_onSelect)(NSString *);
    NSArray<TimeZoneOption *> *_options;
    NSArray<TimeZoneOption *> *_results;
    NSSearchField *_search;
    NSTableView *_table;
    NSTextField *_emptyLabel;
}

- (instancetype)initWithSelection:(NSString *)identifier onSelect:(void (^)(NSString *))onSelect
{
    self = [super init];
    if (self) {
        _selectedIdentifier = [identifier copy];
        _onSelect = [onSelect copy];

        NSMutableSet<NSString *> *identifiers = [NSMutableSet setWithArray:NSTimeZone.knownTimeZoneNames];
        [identifiers addObject:@"UTC"];
        if (identifier.length && [NSTimeZone timeZoneWithName:identifier]) {
            [identifiers addObject:identifier];
        }
        NSDate *now = [NSDate date];
        NSDateFormatter *formatter = CityFormatter(NSBundle.mainBundle.preferredLocalizations.firstObject);
        formatter.timeZone = [NSTimeZone timeZoneWithName:@"UTC"];
        NSString *unknownCity = [formatter stringFromDate:now];
        NSDateFormatter *englishFormatter = CityFormatter(@"en");
        NSMutableArray<TimeZoneOption *> *options = [NSMutableArray new];
        for (NSString *name in identifiers) {
            NSTimeZone *timeZone = [NSTimeZone timeZoneWithName:name];
            TimeZoneOption *option = [TimeZoneOption new];
            option.identifier = name;
            option.city = CityName(timeZone, formatter, englishFormatter, now, unknownCity);
            option.offset = UTCOffset(timeZone, now);
            [options addObject:option];
        }
        _options = [options sortedArrayUsingComparator:^NSComparisonResult(TimeZoneOption *a, TimeZoneOption *b) {
            NSComparisonResult order = [a.city localizedStandardCompare:b.city];
            return order == NSOrderedSame ? [a.identifier compare:b.identifier] : order;
        }];
        _results = _options;
    }
    return self;
}

+ (NSString *)displayNameForTimeZone:(NSTimeZone *)timeZone
{
    if (!timeZone) return NSLocalizedString(@"Follow System", @"Time zone preference");
    NSDateFormatter *formatter = CityFormatter(NSBundle.mainBundle.preferredLocalizations.firstObject);
    NSDate *now = [NSDate date];
    formatter.timeZone = [NSTimeZone timeZoneWithName:@"UTC"];
    return CityName(timeZone, formatter, CityFormatter(@"en"), now, [formatter stringFromDate:now]);
}

- (void)loadView
{
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 320, 270)];
    _search = [NSSearchField new];
    _search.placeholderString = NSLocalizedString(@"Search city or time zone", @"Time zone picker");
    [_search setAccessibilityLabel:_search.placeholderString];
    _search.delegate = self;
    [view addSubview:_search];

    _table = [NSTableView new];
    _table.headerView = nil;
    _table.style = NSTableViewStyleInset;
    _table.rowHeight = 36;
    _table.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;
    _table.dataSource = self;
    _table.delegate = self;
    _table.target = self;
    _table.action = @selector(chooseClickedTimeZone:);
    [_table addTableColumn:[[NSTableColumn alloc] initWithIdentifier:@"TimeZone"]];

    NSScrollView *scroll = [NSScrollView new];
    scroll.hasVerticalScroller = YES;
    scroll.drawsBackground = NO;
    scroll.documentView = _table;
    [view addSubview:scroll];

    _emptyLabel = [NSTextField labelWithString:NSLocalizedString(@"No matching time zones", @"Time zone picker")];
    _emptyLabel.textColor = NSColor.secondaryLabelColor;
    _emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _emptyLabel.hidden = YES;
    [view addSubview:_emptyLabel];

    NSBox *separator = [NSBox new];
    separator.boxType = NSBoxSeparator;
    [view addSubview:separator];
    NSButton *followSystem = [NSButton buttonWithTitle:NSLocalizedString(@"Follow System", @"Time zone preference")
                                               target:self action:@selector(followSystem:)];
    [view addSubview:followSystem];

    MoVFLHelper *vfl = [[MoVFLHelper alloc] initWithSuperview:view metrics:nil
                                                      views:NSDictionaryOfVariableBindings(_search, scroll, separator, followSystem)];
    [vfl :@"V:|-12-[_search]-6-[scroll]-4-[separator]-6-[followSystem]-10-|"];
    [vfl :@"H:|-12-[_search]-12-|"];
    [vfl :@"H:|[scroll]|"];
    [vfl :@"H:|-12-[separator]-12-|"];
    [vfl :@"H:|-12-[followSystem]-(>=12)-|"];
    [NSLayoutConstraint activateConstraints:@[
        [_emptyLabel.centerXAnchor constraintEqualToAnchor:scroll.centerXAnchor],
        [_emptyLabel.centerYAnchor constraintEqualToAnchor:scroll.centerYAnchor]
    ]];

    self.view = view;
}

- (void)viewDidAppear
{
    [super viewDidAppear];
    [self.view.window makeFirstResponder:_search];
    NSUInteger selected = [_results indexOfObjectPassingTest:^BOOL(TimeZoneOption *option, NSUInteger idx, BOOL *stop) {
        return [option.identifier isEqualToString:self->_selectedIdentifier];
    }];
    if (selected != NSNotFound) [self selectRow:selected];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return _results.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
    TimeZoneOption *option = _results[row];
    NSTextField *city = [NSTextField labelWithString:option.city];
    city.lineBreakMode = NSLineBreakByTruncatingTail;
    NSTextField *identifier = [NSTextField labelWithString:option.identifier];
    identifier.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    identifier.textColor = NSColor.secondaryLabelColor;
    identifier.lineBreakMode = NSLineBreakByTruncatingMiddle;
    NSTextField *offset = [NSTextField labelWithString:option.offset];
    offset.font = [NSFont monospacedDigitSystemFontOfSize:NSFont.smallSystemFontSize weight:NSFontWeightRegular];
    offset.textColor = NSColor.secondaryLabelColor;

    NSView *view = [NSView new];
    [view addSubview:city];
    [view addSubview:identifier];
    [view addSubview:offset];
    MoVFLHelper *vfl = [[MoVFLHelper alloc] initWithSuperview:view metrics:nil
                                                      views:NSDictionaryOfVariableBindings(city, identifier, offset)];
    [vfl :@"H:|-8-[city]-(>=8)-[offset]-8-|" :NSLayoutFormatAlignAllFirstBaseline];
    [vfl :@"H:|-8-[identifier]-8-|"];
    [vfl :@"V:|-3-[city][identifier]-(>=0)-|"];
    return view;
}

- (void)controlTextDidChange:(NSNotification *)notification
{
    NSString *query = [_search.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    _results = query.length ? [_options filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(TimeZoneOption *option, NSDictionary *bindings) {
        NSString *name = [option.identifier stringByReplacingOccurrencesOfString:@"_" withString:@" "];
        return [option.city localizedStandardContainsString:query] ||
               [option.identifier localizedStandardContainsString:query] ||
               [name localizedStandardContainsString:query] ||
               [option.offset localizedStandardContainsString:query];
    }]] : _options;
    [_table reloadData];
    [_table deselectAll:nil];
    _emptyLabel.hidden = _results.count > 0;
    if (_results.count) [self selectRow:0];
}

- (void)selectRow:(NSInteger)row
{
    [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    [_table scrollRowToVisible:row];
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)command
{
    if (command == @selector(insertNewline:)) {
        if (_table.selectedRow >= 0) _onSelect(_results[_table.selectedRow].identifier);
        return YES;
    }
    if (command == @selector(moveDown:) || command == @selector(moveUp:)) {
        if (_results.count) {
            NSInteger delta = command == @selector(moveDown:) ? 1 : -1;
            NSInteger row = MAX(0, MIN(_table.selectedRow + delta, (NSInteger)_results.count - 1));
            [self selectRow:row];
        }
        return YES;
    }
    return NO;
}

- (void)chooseClickedTimeZone:(NSTableView *)sender
{
    if (sender.clickedRow >= 0) _onSelect(_results[sender.clickedRow].identifier);
}

- (void)followSystem:(NSButton *)sender
{
    _onSelect(nil);
}

@end
