//
//  Created by Sanjay Madan on 1/11/17.
//  Copyright © 2017 mowglii.com. All rights reserved.
//

#import "PrefsGeneralVC.h"
#import "Itsycal.h"
#import "MoLoginItem.h"
#import "MoPopover.h"
#import "MoVFLHelper.h"
#import "TimeZonePickerVC.h"
#import "MASShortcut/Shortcut.h"
#import "Sparkle/SUUpdater.h"

@implementation PrefsGeneralVC
{
    NSButton *_login;
    NSButton *_timeZoneButton;
    NSPopover *_timeZonePopover;
}

#pragma mark -
#pragma mark View lifecycle

- (void)loadView
{
    // View controller content view
    NSView *v = [NSView new];

    // Convenience function for making labels.
    NSTextField* (^label)(NSString*) = ^NSTextField* (NSString *stringValue) {
        NSTextField *txt = [NSTextField labelWithString:stringValue];
        [v addSubview:txt];
        return txt;
    };

    // Convenience function for making checkboxes.
    NSButton* (^chkbx)(NSString *) = ^NSButton* (NSString *title) {
        NSButton *chkbx = [NSButton checkboxWithTitle:title target:self action:nil];
        [v addSubview:chkbx];
        return chkbx;
    };

    // Checkboxes
    _login = chkbx(NSLocalizedString(@"Launch at login", @""));
    _login.action = @selector(launchAtLogin:);
    NSButton *checkUpdates = chkbx(NSLocalizedString(@"Automatically check for updates", @""));
    checkUpdates.hidden = !ItsycalHasUpdateFeed();
    NSButton *beepBeep = chkbx(NSLocalizedString(@"Beep beep on the hour", @""));

    // Shortcut label
    NSTextField *shortcutLabel = label(NSLocalizedString(@"Keyboard shortcut", @""));

    // Shortcut view
    MASShortcutView *shortcutView = [MASShortcutView new];
    [shortcutView setAssociatedUserDefaultsKey:kKeyboardShortcut withTransformerName:MASDictionaryTransformerName];
    [v addSubview:shortcutView];

    // Window position label
    NSTextField *positionLabel = label(NSLocalizedString(@"Window position:", @""));

    // Window position popup
    NSPopUpButton *positionPopup = [NSPopUpButton new];
    [positionPopup addItemsWithTitles:@[NSLocalizedString(@"Below menu bar icon", @""),
                                        NSLocalizedString(@"Top right of screen", @"")]];
    // The tags will be used to bind the selected window
    // position preference to NSUserDefaults.
    [positionPopup itemAtIndex:0].tag = WindowPositionBelowMenuBarIcon;
    [positionPopup itemAtIndex:1].tag = WindowPositionTopRightOfScreen;
    [positionPopup.cell setAccessibilityTitleUIElement:positionLabel.cell];
    [v addSubview:positionPopup];

    NSTextField *timeZoneLabel = label(NSLocalizedString(@"Time zone:", @""));
    NSImage *chevron = [NSImage imageWithSystemSymbolName:@"chevron.down" accessibilityDescription:nil];
    _timeZoneButton = [NSButton buttonWithTitle:@"" image:chevron target:self action:@selector(showTimeZonePicker:)];
    _timeZoneButton.imagePosition = NSImageTrailing;
    _timeZoneButton.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [_timeZoneButton.cell setAccessibilityTitleUIElement:timeZoneLabel.cell];
    [self updateTimeZoneButton];
    [v addSubview:_timeZoneButton];

    MoVFLHelper *vfl = [[MoVFLHelper alloc] initWithSuperview:v metrics:@{@"m": @20} views:NSDictionaryOfVariableBindings(_login, checkUpdates, beepBeep, shortcutLabel, shortcutView, positionLabel, positionPopup, timeZoneLabel, _timeZoneButton)];
    if (checkUpdates.hidden) {
        [vfl :@"V:|-m-[_login]-[beepBeep]"];
    } else {
        [vfl :@"V:|-m-[_login]-[checkUpdates]-[beepBeep]"];
        [vfl :@"H:|-m-[checkUpdates]-(>=m)-|"];
    }
    [vfl :@"V:[beepBeep]-m-[shortcutLabel]-3-[shortcutView(25)]-30-[positionPopup]-[_timeZoneButton]-m-|"];
    [vfl :@"H:|-m-[_login]-(>=m)-|"];
    [vfl :@"H:|-m-[beepBeep]-(>=m)-|"];
    [vfl :@"H:|-(>=m)-[shortcutLabel]-(>=m)-|"];
    [vfl :@"H:|-m-[shortcutView(>=220)]-m-|"];
    [vfl :@"H:|-m-[positionLabel]-[positionPopup]-(>=m)-|" :NSLayoutFormatAlignAllFirstBaseline];

    [vfl :@"H:|-m-[timeZoneLabel]-[_timeZoneButton(<=180)]-(>=m)-|" :NSLayoutFormatAlignAllFirstBaseline];

    // Center shortcutLabel
    [v addConstraint:[NSLayoutConstraint constraintWithItem:shortcutLabel attribute:NSLayoutAttributeCenterX relatedBy:NSLayoutRelationEqual toItem:v attribute:NSLayoutAttributeCenterX multiplier:1 constant:0]];

    // Binding for Sparkle automatic update checks
    if (!checkUpdates.hidden) {
        [checkUpdates bind:@"value" toObject:[SUUpdater sharedUpdater] withKeyPath:@"automaticallyChecksForUpdates" options:@{NSContinuouslyUpdatesValueBindingOption: @(YES)}];
    }

    // Binding for hourly beep
    [beepBeep bind:@"value" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:[@"values." stringByAppendingString:kBeepBeepOnTheHour] options:@{NSContinuouslyUpdatesValueBindingOption: @(YES)}];

    // Bindings for window position
    [positionPopup bind:@"selectedTag" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:[@"values." stringByAppendingString:kWindowPosition] options:@{NSContinuouslyUpdatesValueBindingOption: @(YES)}];

    self.view = v;
}

- (void)viewWillAppear
{
    [super viewWillAppear];

    [self updateTimeZoneButton];

    // The API used to check the login item's state (LSSharedFileList) causes
    // errors for users who have network drives but are not connected to their
    // network (github.com/sfsam/Itsycal/issues/15). Give them an option to
    // disable this check.
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kDoNotCheckLoginItemStatus] == NO) {
        _login.hidden = NO;
        _login.state = MOIsLoginItemEnabled() ? NSControlStateValueOn : NSControlStateValueOff;
    }
    else {
        _login.hidden = YES;
    }
}

#pragma mark -
#pragma mark General settings

- (void)updateTimeZoneButton
{
    NSString *identifier = [NSUserDefaults.standardUserDefaults stringForKey:kTimeZoneIdentifier];
    NSTimeZone *timeZone = identifier.length ? [NSTimeZone timeZoneWithName:identifier] : nil;
    _timeZoneButton.title = [TimeZonePickerVC displayNameForTimeZone:timeZone];
    _timeZoneButton.toolTip = timeZone.name;
}

- (void)showTimeZonePicker:(NSButton *)sender
{
    if (_timeZonePopover.isShown) {
        [_timeZonePopover close];
        return;
    }
    NSString *selected = [NSUserDefaults.standardUserDefaults stringForKey:kTimeZoneIdentifier];
    __weak typeof(self) weakSelf = self;
    TimeZonePickerVC *picker = [[TimeZonePickerVC alloc] initWithSelection:selected onSelect:^(NSString *identifier) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        [NSUserDefaults.standardUserDefaults setObject:identifier forKey:kTimeZoneIdentifier];
        [strongSelf updateTimeZoneButton];
        [strongSelf->_timeZonePopover close];
    }];
    _timeZonePopover = [MoPopover new];
    _timeZonePopover.behavior = NSPopoverBehaviorTransient;
    _timeZonePopover.contentViewController = picker;
    _timeZonePopover.contentSize = picker.view.frame.size;
    [_timeZonePopover showRelativeToRect:sender.bounds ofView:sender preferredEdge:NSRectEdgeMinY];
}

- (void)launchAtLogin:(NSButton *)login
{
    MOEnableLoginItem(login.state == NSControlStateValueOn);
}

@end
