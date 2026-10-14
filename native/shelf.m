#import <AppKit/AppKit.h>
#import <ImageIO/ImageIO.h>
#import <ServiceManagement/ServiceManagement.h>
#import <fcntl.h>
#import <unistd.h>

extern int rs_scan(void);
extern void rs_action(int action);
extern void rs_tick(void);
extern void rs_restore(void);
extern void rs_save_folder(const char *path);

@interface ShelfPreview : NSImageView <NSDraggingSource>
@property(copy) NSString *path;
@property(strong) NSURL *dragURL;
@end

@interface ShelfDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate>
@property(strong) NSPanel *panel;
@property(strong) ShelfPreview *preview;
@property(strong) NSTextField *counter;
@property(strong) NSTextField *hint;
@property(strong) NSButton *previous;
@property(strong) NSButton *next;
@property(strong) NSStatusItem *statusItem;
@property(strong) NSTimer *expiryTimer;
@property(strong) dispatch_source_t watcher;
@property(copy) NSString *capture;
@property(copy) NSString *save;
@property BOOL scanScheduled;
@end

static ShelfDelegate *app;

@implementation ShelfPreview
- (BOOL)mouseDownCanMoveWindow { return NO; }
- (void)mouseDown:(NSEvent *)event {
    (void)event;
    rs_action(7);
}
- (void)mouseDragged:(NSEvent *)event {
    if (!self.path || self.dragURL) return;
    self.dragURL = [NSURL fileURLWithPath:self.path];
    NSDraggingItem *item = [[NSDraggingItem alloc] initWithPasteboardWriter:self.dragURL];
    [item setDraggingFrame:self.bounds contents:self.image];
    rs_action(4);
    NSDraggingSession *session = [self beginDraggingSessionWithItems:@[item] event:event source:self];
    session.animatesToStartingPositionsOnCancelOrFail = YES;
}
- (NSDragOperation)draggingSession:(NSDraggingSession *)session sourceOperationMaskForDraggingContext:(NSDraggingContext)context {
    (void)session; (void)context;
    return NSDragOperationCopy;
}
- (void)draggingSession:(NSDraggingSession *)session endedAtPoint:(NSPoint)point operation:(NSDragOperation)operation {
    (void)session; (void)point;
    rs_action(operation == NSDragOperationNone ? 5 : 6);
    self.dragURL = nil;
}
@end

static NSButton *button(NSString *title, NSString *symbol, NSRect frame, id target, SEL action) {
    NSButton *result = [NSButton buttonWithTitle:title target:target action:action];
    result.frame = frame;
    result.bezelStyle = NSBezelStyleRegularSquare;
    result.bordered = NO;
    result.image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:title];
    result.imagePosition = NSImageOnly;
    result.toolTip = title;
    [result setAccessibilityLabel:title];
    return result;
}

@implementation ShelfDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    [self createPanel];
    [self createMenu];
    int descriptor = open(self.capture.fileSystemRepresentation, O_EVTONLY);
    if (descriptor < 0) {
        extern void shelf_error(const char *);
        shelf_error("Cannot watch the capture folder. Quit and reopen the app.");
        return;
    }
    self.watcher = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, descriptor,
        DISPATCH_VNODE_WRITE | DISPATCH_VNODE_RENAME | DISPATCH_VNODE_DELETE, dispatch_get_main_queue());
    __weak ShelfDelegate *weakSelf = self;
    dispatch_source_set_event_handler(self.watcher, ^{
        unsigned long flags = dispatch_source_get_data(weakSelf.watcher);
        if (flags & (DISPATCH_VNODE_RENAME | DISPATCH_VNODE_DELETE)) {
            extern void shelf_error(const char *);
            shelf_error("The capture folder was moved or deleted. Restore it and reopen the app.");
            return;
        }
        [weakSelf scheduleScan];
    });
    dispatch_source_set_cancel_handler(self.watcher, ^{ close(descriptor); });
    dispatch_resume(self.watcher);
    rs_restore();
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"setupComplete"]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf setup:nil]; });
    }
}
- (void)createPanel {
    self.panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 286, 226)
        styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
        backing:NSBackingStoreBuffered defer:NO];
    self.panel.level = NSFloatingWindowLevel;
    self.panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
        NSWindowCollectionBehaviorFullScreenAuxiliary;
    self.panel.hidesOnDeactivate = NO;
    self.panel.opaque = NO;
    self.panel.backgroundColor = NSColor.clearColor;
    self.panel.hasShadow = YES;
    self.panel.movableByWindowBackground = YES;
    self.panel.releasedWhenClosed = NO;
    NSGlassEffectView *glass = [[NSGlassEffectView alloc] initWithFrame:NSMakeRect(0, 0, 286, 226)];
    glass.style = NSGlassEffectViewStyleRegular;
    glass.cornerRadius = 24;
    NSView *content = [[NSView alloc] initWithFrame:glass.bounds];
    glass.contentView = content;
    self.panel.contentView = glass;
    self.preview = [[ShelfPreview alloc] initWithFrame:NSMakeRect(14, 60, 258, 150)];
    self.preview.imageScaling = NSImageScaleProportionallyUpOrDown;
    self.preview.wantsLayer = YES;
    self.preview.layer.cornerRadius = 13;
    self.preview.layer.masksToBounds = YES;
    [self.preview setAccessibilityLabel:@"Screenshot preview. Drag to another app."];
    [content addSubview:self.preview];
    self.previous = button(@"Previous screenshot", @"chevron.left", NSMakeRect(12, 20, 26, 30), self, @selector(previousImage:));
    self.next = button(@"Next screenshot", @"chevron.right", NSMakeRect(92, 20, 26, 30), self, @selector(nextImage:));
    self.counter = [NSTextField labelWithString:@""];
    self.counter.frame = NSMakeRect(38, 27, 54, 16);
    self.counter.alignment = NSTextAlignmentCenter;
    self.counter.font = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightMedium];
    NSButton *discard = button(@"Delete screenshot", @"xmark", NSMakeRect(137, 18, 34, 34), self, @selector(discard:));
    NSButton *save = button(@"Save screenshot", @"checkmark.circle.fill", NSMakeRect(211, 11, 50, 50), self, @selector(saveImage:));
    save.contentTintColor = NSColor.systemGreenColor;
    save.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:38 weight:NSFontWeightMedium];
    self.hint = [NSTextField labelWithString:@"Drag to use · ✓ to keep"];
    self.hint.frame = NSMakeRect(18, 3, 186, 12);
    self.hint.font = [NSFont systemFontOfSize:10];
    self.hint.textColor = NSColor.secondaryLabelColor;
    for (NSView *view in @[self.previous, self.next, self.counter, discard, save, self.hint]) [content addSubview:view];
    NSRect screen = NSScreen.mainScreen.visibleFrame;
    [self.panel setFrameOrigin:NSMakePoint(NSMaxX(screen) - 306, NSMinY(screen) + 20)];
    [self.panel setFrameAutosaveName:@"ScreenshotShelfPosition"];
    [self.panel setFrameUsingName:@"ScreenshotShelfPosition"];
    self.panel.delegate = self;
}
- (void)createMenu {
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
    self.statusItem.button.image = [NSImage imageWithSystemSymbolName:@"square.stack.3d.up" accessibilityDescription:@"Screenshot Shelf"];
    NSMenu *menu = [[NSMenu alloc] init];
    NSArray *items = @[
        @[@"Setup…", NSStringFromSelector(@selector(setup:))],
        @[@"Choose save folder…", NSStringFromSelector(@selector(chooseSave:))],
        @[@"Open capture folder", NSStringFromSelector(@selector(openCapture:))],
        @[@"Open save folder", NSStringFromSelector(@selector(openSave:))],
        @[@"Start at login", NSStringFromSelector(@selector(toggleLogin:))],
        @[@"Quit Screenshot Shelf", NSStringFromSelector(@selector(quit:))]
    ];
    for (NSArray *pair in items) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:pair[0] action:NSSelectorFromString(pair[1]) keyEquivalent:@""];
        item.target = self;
        [menu addItem:item];
    }
    self.statusItem.menu = menu;
}
- (void)scheduleScan {
    if (self.scanScheduled) return;
    self.scanScheduled = YES;
    __weak ShelfDelegate *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        weakSelf.scanScheduled = NO;
        if (rs_scan()) [weakSelf scheduleScan];
    });
}
- (void)tick:(NSTimer *)timer { (void)timer; rs_tick(); }
- (void)windowDidMove:(NSNotification *)notification { (void)notification; rs_action(7); }
- (void)previousImage:(id)sender { (void)sender; rs_action(2); }
- (void)nextImage:(id)sender { (void)sender; rs_action(3); }
- (void)discard:(id)sender { (void)sender; rs_action(0); }
- (void)saveImage:(id)sender { (void)sender; rs_action(1); }
- (void)openCapture:(id)sender { (void)sender; [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:self.capture]]; }
- (void)openSave:(id)sender { (void)sender; [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:self.save]]; }
- (void)chooseSave:(id)sender {
    (void)sender;
    [NSApp activateIgnoringOtherApps:YES];
    NSOpenPanel *picker = [NSOpenPanel openPanel];
    picker.canChooseFiles = NO;
    picker.canChooseDirectories = YES;
    picker.canCreateDirectories = YES;
    picker.allowsMultipleSelection = NO;
    picker.message = @"Choose where to keep saved screenshots.";
    picker.directoryURL = [NSURL fileURLWithPath:self.save];
    if ([picker runModal] == NSModalResponseOK) {
        rs_save_folder(picker.URL.path.fileSystemRepresentation);
        // Read the persisted choice so a rejected folder cannot change the UI.
        NSString *config = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Screenshot Shelf/save-folder"];
        NSString *saved = [NSString stringWithContentsOfFile:config encoding:NSUTF8StringEncoding error:NULL];
        if (saved) self.save = saved;
    }
}
- (void)setup:(id)sender {
    (void)sender;
    [NSApp activateIgnoringOtherApps:YES];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Set up Screenshot Shelf";
    alert.informativeText = [NSString stringWithFormat:
        @"1. Choose a save folder.\n2. Press Shift–Command–5. Under Options → Other Location, select:\n%@\n3. Turn off Show Floating Thumbnail for faster capture.\n\nThe app watches only this capture folder. Existing files are ignored. Clipboard-only captures are not supported.\n\nA drop or × deletes the image immediately. After 10 minutes without widget action, all pending images are deleted. There is no recovery copy.", self.capture];
    [alert addButtonWithTitle:@"Choose save folder"];
    [alert addButtonWithTitle:@"Later"];
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        [self chooseSave:nil];
        NSString *config = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Screenshot Shelf/save-folder"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:config]) [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"setupComplete"];
    }
}
- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if (item.action == @selector(toggleLogin:)) item.state = SMAppService.mainAppService.status == SMAppServiceStatusEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    return YES;
}
- (void)toggleLogin:(id)sender {
    (void)sender;
    NSError *error = nil;
    SMAppService *service = SMAppService.mainAppService;
    if (service.status == SMAppServiceStatusEnabled) [service unregisterAndReturnError:&error];
    else [service registerAndReturnError:&error];
    if (error) {
        extern void shelf_error(const char *);
        shelf_error(error.localizedDescription.UTF8String);
    } else if (service.status == SMAppServiceStatusRequiresApproval) {
        [SMAppService openSystemSettingsLoginItems];
    }
}
- (void)quit:(id)sender { (void)sender; [NSApp terminate:nil]; }
@end

void shelf_error(const char *message) {
    NSString *text = [NSString stringWithUTF8String:message] ?: @"Unknown error";
    // Show errors outside a Rust callback to prevent state re-entry through a modal loop.
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSApp activateIgnoringOtherApps:YES];
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Screenshot Shelf";
        alert.informativeText = text;
        [alert runModal];
    });
}

void shelf_render(const char *path, size_t index, size_t count, uint64_t bytes) {
    if (!app.panel) return;
    if (!path || count == 0) {
        [app.panel orderOut:nil];
        app.preview.image = nil;
        app.preview.path = nil;
        [app.expiryTimer invalidate];
        app.expiryTimer = nil;
        return;
    }
    NSString *file = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:path length:strlen(path)];
    if (![app.preview.path isEqualToString:file]) {
        app.preview.path = file;
        NSURL *url = [NSURL fileURLWithPath:file];
        CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, (__bridge CFDictionaryRef)@{(__bridge NSString *)kCGImageSourceShouldCache: @NO});
        if (source) {
            NSDictionary *options = @{
                (__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
                (__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize: @600,
                (__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform: @YES,
                (__bridge NSString *)kCGImageSourceShouldCacheImmediately: @YES
            };
            CGImageRef thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
            app.preview.image = thumbnail ? [[NSImage alloc] initWithCGImage:thumbnail size:NSZeroSize] : nil;
            if (thumbnail) CGImageRelease(thumbnail);
            CFRelease(source);
        } else app.preview.image = nil;
    }
    app.counter.stringValue = [NSString stringWithFormat:@"%zu of %zu", index + 1, count];
    app.previous.enabled = index > 0;
    app.next.enabled = index + 1 < count;
    app.hint.stringValue = bytes > 1000000000 ? @"Storage above 1 GB · drag or save" : @"Drag to use · ✓ to keep";
    [app.panel orderFrontRegardless];
    if (!app.expiryTimer) {
        app.expiryTimer = [NSTimer timerWithTimeInterval:1 target:app selector:@selector(tick:) userInfo:nil repeats:YES];
        app.expiryTimer.tolerance = 0.25;
        [[NSRunLoop mainRunLoop] addTimer:app.expiryTimer forMode:NSRunLoopCommonModes];
    }
}

void shelf_run(const char *capture, const char *save) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
        if (bundleID && [NSRunningApplication runningApplicationsWithBundleIdentifier:bundleID].count > 1) return;
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        app = [[ShelfDelegate alloc] init];
        app.capture = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:capture length:strlen(capture)];
        app.save = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:save length:strlen(save)];
        NSApp.delegate = app;
        [NSApp run];
    }
}
