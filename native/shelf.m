#import <AppKit/AppKit.h>

@interface ShelfDelegate : NSObject <NSApplicationDelegate>
@property(strong) NSStatusItem *statusItem;
@end

@implementation ShelfDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
    self.statusItem.button.image = [NSImage imageWithSystemSymbolName:@"square.stack.3d.up" accessibilityDescription:@"Screenshot Shelf"];
    NSMenu *menu = [[NSMenu alloc] init];
    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Quit Screenshot Shelf" action:@selector(terminate:) keyEquivalent:@""];
    quit.target = NSApp;
    [menu addItem:quit];
    self.statusItem.menu = menu;
}
@end

void shelf_run(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        ShelfDelegate *delegate = [[ShelfDelegate alloc] init];
        NSApp.delegate = delegate;
        [NSApp run];
    }
}
