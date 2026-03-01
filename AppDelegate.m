#import "AppDelegate.h"
#import <CoreAudio/CoreAudio.h>
#import <ServiceManagement/ServiceManagement.h>

#define CLAMP(x, lo, hi) MAX((lo), MIN((hi), (x)))

// Forward-declare private AppDelegate methods needed by SliderRow and the C callback
@interface AppDelegate (Private)
- (void)setMute:(UInt32)mute forDeviceID:(AudioDeviceID)devID;
- (void)setVolume:(float)scalar forDeviceID:(AudioDeviceID)devID;
- (void)rescanDevices;
- (void)applySettingsForUID:(NSString *)uid retries:(int)remaining;
@end

// ---------------------------------------------------------------------------
// SidetoneDevice — lightweight model for one qualifying CoreAudio device
// ---------------------------------------------------------------------------

@interface SidetoneDevice : NSObject
@property (nonatomic, assign) AudioDeviceID deviceID;
@property (nonatomic, copy)   NSString *uid;
@property (nonatomic, copy)   NSString *name;
@end

@implementation SidetoneDevice
@end

// ---------------------------------------------------------------------------
// SidetoneSlider — custom slider drawn independently of window key state.
//
// NSSlider checks [window isKeyWindow] when painting its knob; since menu
// panels are never the key window the stock control always looks inactive.
// This view draws its own track and knob using semantic system colors so it
// always presents in the "active" style and adapts to light / dark mode.
// ---------------------------------------------------------------------------

@interface SidetoneSlider : NSView
@property (nonatomic, assign) float  minValue;   // default 0.0
@property (nonatomic, assign) float  maxValue;   // default 1.0
@property (nonatomic, assign) float  floatValue;
@property (nonatomic, weak)   id     target;
@property (nonatomic, assign) SEL    action;
@end

@implementation SidetoneSlider

static const CGFloat kTrackH  = 3.0;   // track height
static const CGFloat kKnobR   = 6.0;   // knob radius
static const CGFloat kMargin  = 7.0;   // horizontal inset so knob stays in bounds

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _minValue  = 0.0f;
        _maxValue  = 1.0f;
        _floatValue = 0.0f;
    }
    return self;
}

- (void)setFloatValue:(float)v {
    _floatValue = CLAMP(v, _minValue, _maxValue);
    [self setNeedsDisplay:YES];
}

- (CGFloat)_xForValue:(float)value {
    CGFloat travel = NSWidth(self.bounds) - 2.0 * kMargin;
    CGFloat t = (value - _minValue) / (_maxValue - _minValue);
    return kMargin + CLAMP(t, 0.0, 1.0) * travel;
}

- (float)_valueForX:(CGFloat)x {
    CGFloat travel = NSWidth(self.bounds) - 2.0 * kMargin;
    CGFloat t = (x - kMargin) / travel;
    return _minValue + (float)CLAMP(t, 0.0, 1.0) * (_maxValue - _minValue);
}

- (void)drawRect:(NSRect)dirtyRect {
    CGFloat cy    = NSMidY(self.bounds);
    CGFloat knobX = [self _xForValue:_floatValue];

    // Unfilled track
    NSRect trackRect = NSMakeRect(kMargin, cy - kTrackH / 2.0,
                                  NSWidth(self.bounds) - 2.0 * kMargin, kTrackH);
    NSBezierPath *track = [NSBezierPath bezierPathWithRoundedRect:trackRect
                                                          xRadius:kTrackH / 2.0
                                                          yRadius:kTrackH / 2.0];
    [NSColor.separatorColor setFill];
    [track fill];

    // Filled track — accent color left of the knob
    CGFloat filledW = knobX - kMargin;
    if (filledW > 0) {
        NSRect filledRect = NSMakeRect(kMargin, cy - kTrackH / 2.0, filledW, kTrackH);
        NSBezierPath *filled = [NSBezierPath bezierPathWithRoundedRect:filledRect
                                                               xRadius:kTrackH / 2.0
                                                               yRadius:kTrackH / 2.0];
        [NSColor.controlAccentColor setFill];
        [filled fill];
    }

    // Knob — white circle with a soft drop shadow and hairline border
    NSRect knobRect = NSMakeRect(knobX - kKnobR, cy - kKnobR, 2 * kKnobR, 2 * kKnobR);

    [NSGraphicsContext saveGraphicsState];
    NSShadow *shadow     = [[NSShadow alloc] init];
    shadow.shadowColor   = [NSColor colorWithWhite:0.0 alpha:0.20];
    shadow.shadowBlurRadius = 2.5;
    shadow.shadowOffset  = NSMakeSize(0, -1);
    [shadow set];

    NSBezierPath *knob = [NSBezierPath bezierPathWithOvalInRect:knobRect];
    [[NSColor colorWithWhite:1.0 alpha:1.0] setFill];
    [knob fill];
    [NSGraphicsContext restoreGraphicsState];

    [[NSColor colorWithWhite:0.0 alpha:0.12] setStroke];
    knob.lineWidth = 0.5;
    [knob stroke];
}

- (void)_handleEvent:(NSEvent *)event {
    CGFloat x = [self convertPoint:event.locationInWindow fromView:nil].x;
    self.floatValue = [self _valueForX:x];
    if (_target && _action) {
        [NSApp sendAction:_action to:_target from:self];
    }
}

- (void)mouseDown:(NSEvent *)event    { [self _handleEvent:event]; }
- (void)mouseDragged:(NSEvent *)event { [self _handleEvent:event]; }
- (void)mouseUp:(NSEvent *)event      { }

- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
- (BOOL)acceptsFirstResponder              { return YES; }

@end

// ---------------------------------------------------------------------------
// SliderRow — NSView containing a SidetoneSlider and a dB readout
// ---------------------------------------------------------------------------

@interface SliderRow : NSView
@property (nonatomic, strong) SidetoneSlider *slider;
@property (nonatomic, strong) NSTextField    *dbLabel;
@property (nonatomic, weak)   AppDelegate    *delegate;
@property (nonatomic, copy)   NSString       *deviceUID;
@property (nonatomic, assign) AudioDeviceID   deviceID;
- (instancetype)initWithDevice:(SidetoneDevice *)dev delegate:(id)delegate;
@end

@implementation SliderRow

- (instancetype)initWithDevice:(SidetoneDevice *)dev delegate:(id)del {
    self = [super initWithFrame:NSMakeRect(0, 0, 260, 30)];
    if (!self) return nil;

    self.delegate  = del;
    self.deviceUID = dev.uid;
    self.deviceID  = dev.deviceID;

    SidetoneSlider *s = [[SidetoneSlider alloc] initWithFrame:NSMakeRect(14, 7, 180, 16)];
    s.minValue = 0.0f;
    s.maxValue = 1.0f;
    s.target   = self;
    s.action   = @selector(sliderChanged:);
    self.slider = s;
    [self addSubview:s];

    NSTextField *lbl = [[NSTextField alloc] initWithFrame:NSMakeRect(200, 7, 56, 16)];
    lbl.editable        = NO;
    lbl.bordered        = NO;
    lbl.drawsBackground = NO;
    lbl.font            = [NSFont monospacedDigitSystemFontOfSize:11.0 weight:NSFontWeightRegular];
    lbl.alignment       = NSTextAlignmentRight;
    self.dbLabel        = lbl;
    [self addSubview:lbl];

    NSString *key = [NSString stringWithFormat:@"sidetone_volume_%@", dev.uid];
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    // Default to 0.0 (silent) for devices we have never seen before
    float savedScalar = [ud objectForKey:key] ? (float)[ud floatForKey:key] : 0.0f;
    s.floatValue = savedScalar;
    [self updateLabel];

    return self;
}

- (void)sliderChanged:(SidetoneSlider *)sender {
    float scalar = sender.floatValue;
    // mute=1 enables the sidetone path (play-through mute is inverted on this device)
    [self.delegate setMute:1 forDeviceID:self.deviceID];
    [self.delegate setVolume:scalar forDeviceID:self.deviceID];
    NSString *key = [NSString stringWithFormat:@"sidetone_volume_%@", self.deviceUID];
    [[NSUserDefaults standardUserDefaults] setFloat:scalar forKey:key];
    [self updateLabel];
}

- (void)updateLabel {
    Float32 db = 0.0f;
    UInt32 sz = sizeof(db);
    AudioObjectPropertyAddress va = {
        kAudioDevicePropertyVolumeDecibels,
        kAudioDevicePropertyScopePlayThrough,
        1
    };
    OSStatus err = AudioObjectGetPropertyData(self.deviceID, &va, 0, NULL, &sz, &db);
    self.dbLabel.stringValue = (err == noErr)
        ? [NSString stringWithFormat:@"%.0f dB", db]
        : @"-- dB";
}

- (BOOL)acceptsFirstResponder { return YES; }

@end

// ---------------------------------------------------------------------------
// AppDelegate
// ---------------------------------------------------------------------------

@interface AppDelegate () <NSMenuDelegate>
@property (nonatomic, strong) NSStatusItem                     *statusItem;
@property (nonatomic, strong) NSMenu                           *menu;
@property (nonatomic, strong) NSMutableArray<SidetoneDevice *> *devices;
@property (nonatomic, assign) BOOL                              menuIsOpen;
@end

// CoreAudio notifies us on the audio thread; dispatch to main for all UI/state work.
static OSStatus devicesChangedCallback(AudioObjectID                     inObjectID,
                                       UInt32                            inNumberAddresses,
                                       const AudioObjectPropertyAddress *inAddresses,
                                       void                             *inClientData) {
    AppDelegate *delegate = (__bridge AppDelegate *)inClientData;
    dispatch_async(dispatch_get_main_queue(), ^{ [delegate rescanDevices]; });
    return noErr;
}

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    self.devices = [NSMutableArray array];

    self.statusItem = [[NSStatusBar systemStatusBar]
                       statusItemWithLength:NSVariableStatusItemLength];
    NSImage *icon = [NSImage imageWithSystemSymbolName:@"ear"
                                accessibilityDescription:@"Sidetone"];
    [icon setTemplate:YES];
    self.statusItem.button.image = icon;

    self.menu = [[NSMenu alloc] init];
    self.menu.autoenablesItems = NO;
    self.menu.delegate = self;
    self.statusItem.menu = self.menu;

    AudioObjectPropertyAddress addr = {
        kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    AudioObjectAddPropertyListener(kAudioObjectSystemObject, &addr,
                                   devicesChangedCallback, (__bridge void *)self);

    [self rescanDevices];
}

// ---------------------------------------------------------------------------
// Device scanning
// ---------------------------------------------------------------------------

- (void)rescanDevices {
    AudioObjectPropertyAddress listAddr = {
        kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    UInt32 dataSize = 0;
    AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &listAddr, 0, NULL, &dataSize);
    if (dataSize == 0) {
        self.devices = [NSMutableArray array];
        if (!self.menuIsOpen) [self rebuildMenu];
        return;
    }

    UInt32 count = dataSize / sizeof(AudioDeviceID);
    AudioDeviceID *allDevices = (AudioDeviceID *)malloc(dataSize);
    AudioObjectGetPropertyData(kAudioObjectSystemObject, &listAddr, 0, NULL, &dataSize, allDevices);

    NSMutableSet<NSString *> *previousUIDs = [NSMutableSet set];
    for (SidetoneDevice *d in self.devices) [previousUIDs addObject:d.uid];

    NSMutableArray<SidetoneDevice *> *found   = [NSMutableArray array];
    NSMutableArray<NSString *>       *newUIDs = [NSMutableArray array];

    for (UInt32 i = 0; i < count; i++) {
        AudioDeviceID devID = allDevices[i];
        if (![self deviceQualifies:devID]) continue;

        SidetoneDevice *dev = [[SidetoneDevice alloc] init];
        dev.deviceID = devID;
        dev.uid      = [self uidForDevice:devID];
        dev.name     = [self nameForDevice:devID];
        [found addObject:dev];

        if (![previousUIDs containsObject:dev.uid]) {
            [newUIDs addObject:dev.uid];
        }
    }

    free(allDevices);
    self.devices = found;

    // Apply settings before rebuilding the menu: the menu's updateLabel reads driver
    // properties, and on some USB audio drivers that read resets internal play-through
    // state, interfering with the subsequent write.
    for (NSString *uid in newUIDs) {
        [self applySettingsForUID:uid retries:20];
    }

    // Never mutate a visible NSMenu — removeAllItems on an open menu leaves orphaned
    // separators. menuWillOpen: handles rebuilding with fresh state on next open.
    if (!self.menuIsOpen) {
        [self rebuildMenu];
    }
}

// ---------------------------------------------------------------------------
// NSMenuDelegate — rebuild right before display, never while visible
// ---------------------------------------------------------------------------

- (void)menuWillOpen:(NSMenu *)menu {
    self.menuIsOpen = YES;
    [self rebuildMenu];
}

- (void)menuDidClose:(NSMenu *)menu {
    self.menuIsOpen = NO;
}

// ---------------------------------------------------------------------------
// Device qualification
// ---------------------------------------------------------------------------

// A device qualifies if it has both input and output streams, and its
// play-through mute control is settable (indicating hardware sidetone support).
- (BOOL)deviceQualifies:(AudioDeviceID)devID {
    AudioObjectPropertyAddress addr = {
        kAudioDevicePropertyStreams,
        kAudioDevicePropertyScopeInput,
        kAudioObjectPropertyElementMain
    };
    UInt32 sz = 0;
    if (AudioObjectGetPropertyDataSize(devID, &addr, 0, NULL, &sz) != noErr || sz == 0)
        return NO;

    addr.mScope = kAudioDevicePropertyScopeOutput;
    sz = 0;
    if (AudioObjectGetPropertyDataSize(devID, &addr, 0, NULL, &sz) != noErr || sz == 0)
        return NO;

    AudioObjectPropertyAddress muteAddr = {
        kAudioDevicePropertyMute,
        kAudioDevicePropertyScopePlayThrough,
        0
    };
    Boolean settable = NO;
    if (AudioObjectIsPropertySettable(devID, &muteAddr, &settable) != noErr || !settable)
        return NO;

    return YES;
}

- (NSString *)uidForDevice:(AudioDeviceID)devID {
    AudioObjectPropertyAddress addr = {
        kAudioDevicePropertyDeviceUID,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    CFStringRef uid = NULL;
    UInt32 sz = sizeof(uid);
    AudioObjectGetPropertyData(devID, &addr, 0, NULL, &sz, &uid);
    return (__bridge_transfer NSString *)uid ?: @"";
}

- (NSString *)nameForDevice:(AudioDeviceID)devID {
    AudioObjectPropertyAddress addr = {
        kAudioObjectPropertyName,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    CFStringRef name = NULL;
    UInt32 sz = sizeof(name);
    AudioObjectGetPropertyData(devID, &addr, 0, NULL, &sz, &name);
    return (__bridge_transfer NSString *)name ?: @"Unknown Device";
}

// ---------------------------------------------------------------------------
// Auto-apply on connect
//
// Looks up the device by UID at each attempt so a stale AudioDeviceID from
// an earlier kAudioHardwarePropertyDevices notification is never used.
// Retries up to `remaining` times (every 0.25 s) in case the driver isn't
// ready to accept property writes immediately after the device appears.
// ---------------------------------------------------------------------------

- (void)applySettingsForUID:(NSString *)uid retries:(int)remaining {
    SidetoneDevice *current = nil;
    for (SidetoneDevice *d in self.devices) {
        if ([d.uid isEqualToString:uid]) { current = d; break; }
    }
    if (!current) return; // device disconnected before we could apply

    AudioObjectPropertyAddress muteAddr = {
        kAudioDevicePropertyMute,
        kAudioDevicePropertyScopePlayThrough,
        0
    };

    // mute=1 enables the sidetone path (play-through mute is inverted on this device)
    UInt32 mute = 1;
    OSStatus err = AudioObjectSetPropertyData(current.deviceID, &muteAddr,
                                              0, NULL, sizeof(mute), &mute);
    if (err != noErr && remaining > 1) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self applySettingsForUID:uid retries:remaining - 1];
        });
        return;
    }

    // Default to 0.0 (silent) for devices we have never seen before
    NSString *key = [NSString stringWithFormat:@"sidetone_volume_%@", uid];
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    float scalar = [ud objectForKey:key] ? (float)[ud floatForKey:key] : 0.0f;
    [self setVolume:scalar forDeviceID:current.deviceID];
}

// ---------------------------------------------------------------------------
// CoreAudio setters
// ---------------------------------------------------------------------------

- (void)setMute:(UInt32)mute forDeviceID:(AudioDeviceID)devID {
    AudioObjectPropertyAddress addr = {
        kAudioDevicePropertyMute,
        kAudioDevicePropertyScopePlayThrough,
        0
    };
    AudioObjectSetPropertyData(devID, &addr, 0, NULL, sizeof(mute), &mute);
}

- (void)setVolume:(float)scalar forDeviceID:(AudioDeviceID)devID {
    Float32 v = scalar;
    AudioObjectPropertyAddress addr = {
        kAudioDevicePropertyVolumeScalar,
        kAudioDevicePropertyScopePlayThrough,
        1
    };
    AudioObjectSetPropertyData(devID, &addr, 0, NULL, sizeof(v), &v);
}

// ---------------------------------------------------------------------------
// Launch at login
// ---------------------------------------------------------------------------

- (BOOL)launchAtLoginEnabled {
    return [SMAppService mainAppService].status == SMAppServiceStatusEnabled;
}

- (void)toggleLaunchAtLogin:(id)sender {
    NSError *error = nil;
    SMAppService *service = [SMAppService mainAppService];
    if (service.status == SMAppServiceStatusEnabled) {
        [service unregisterAndReturnError:&error];
    } else {
        [service registerAndReturnError:&error];
    }
}

// ---------------------------------------------------------------------------
// Menu
// ---------------------------------------------------------------------------

- (void)rebuildMenu {
    [self.menu removeAllItems];

    if (self.devices.count == 0) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"No compatible device connected"
                                                      action:nil
                                               keyEquivalent:@""];
        item.enabled = NO;
        [self.menu addItem:item];
    } else {
        for (NSUInteger i = 0; i < self.devices.count; i++) {
            SidetoneDevice *dev = self.devices[i];

            if (i > 0) [self.menu addItem:[NSMenuItem separatorItem]];

            NSMenuItem *title = [[NSMenuItem alloc] initWithTitle:dev.name
                                                           action:nil
                                                    keyEquivalent:@""];
            title.enabled = NO;
            [self.menu addItem:title];

            SliderRow *row = [[SliderRow alloc] initWithDevice:dev delegate:self];
            NSMenuItem *sliderItem = [[NSMenuItem alloc] init];
            sliderItem.view    = row;
            sliderItem.enabled = YES;
            [self.menu addItem:sliderItem];
        }
    }

    [self.menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *loginItem = [[NSMenuItem alloc] initWithTitle:@"Launch at Login"
                                                       action:@selector(toggleLaunchAtLogin:)
                                                keyEquivalent:@""];
    loginItem.target = self;
    loginItem.state  = [self launchAtLoginEnabled] ? NSControlStateValueOn : NSControlStateValueOff;
    [self.menu addItem:loginItem];

    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Quit"
                                                  action:@selector(terminate:)
                                           keyEquivalent:@"q"];
    quit.target = NSApp;
    [self.menu addItem:quit];
}

@end
