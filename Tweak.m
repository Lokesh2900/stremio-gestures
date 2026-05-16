#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <AVFoundation/AVFoundation.h>

@interface GestureOverlayView : UIView
@property (nonatomic, assign) CGFloat startBrightness;
@property (nonatomic, assign) CGFloat startVolume;
@property (nonatomic, assign) BOOL isLongPressing;
@property (nonatomic, strong) UILabel *hudLabel;
@property (nonatomic, strong) NSTimer *hudTimer;
@end

@implementation GestureOverlayView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = YES;
        _hudLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 180, 55)];
        _hudLabel.textColor = [UIColor whiteColor];
        _hudLabel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.65];
        _hudLabel.textAlignment = NSTextAlignmentCenter;
        _hudLabel.font = [UIFont boldSystemFontOfSize:17];
        _hudLabel.layer.cornerRadius = 12;
        _hudLabel.clipsToBounds = YES;
        _hudLabel.alpha = 0;
        _hudLabel.numberOfLines = 2;
        [self addSubview:_hudLabel];
        [self setupGestures];
    }
    return self;
}

- (void)setupGestures {
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(handlePan:)];
    pan.minimumNumberOfTouches = 1;
    pan.maximumNumberOfTouches = 1;
    [self addGestureRecognizer:pan];

    UITapGestureRecognizer *doubleTapLeft = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(handleDoubleTapLeft:)];
    doubleTapLeft.numberOfTapsRequired = 2;
    [self addGestureRecognizer:doubleTapLeft];

    UITapGestureRecognizer *doubleTapRight = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(handleDoubleTapRight:)];
    doubleTapRight.numberOfTapsRequired = 2;
    [self addGestureRecognizer:doubleTapRight];

    UITapGestureRecognizer *singleTap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(handleSingleTap:)];
    singleTap.numberOfTapsRequired = 1;
    [singleTap requireGestureRecognizerToFail:doubleTapLeft];
    [singleTap requireGestureRecognizerToFail:doubleTapRight];
    [self addGestureRecognizer:singleTap];

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc]
        initWithTarget:self action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = 0.6;
    [self addGestureRecognizer:longPress];

    UIPinchGestureRecognizer *pinch = [[UIPinchGestureRecognizer alloc]
        initWithTarget:self action:@selector(handlePinch:)];
    [self addGestureRecognizer:pinch];
}

- (void)showHUD:(NSString *)text {
    _hudLabel.text = text;
    _hudLabel.center = CGPointMake(self.bounds.size.width / 2,
                                   self.bounds.size.height / 2);
    [UIView animateWithDuration:0.15 animations:^{
        self->_hudLabel.alpha = 1;
    }];
    [_hudTimer invalidate];
    _hudTimer = [NSTimer scheduledTimerWithTimeInterval:1.5
                                                 target:self
                                               selector:@selector(hideHUD)
                                               userInfo:nil
                                                repeats:NO];
}

- (void)showHUDPersistent:(NSString *)text {
    [_hudTimer invalidate];
    _hudLabel.text = text;
    _hudLabel.center = CGPointMake(self.bounds.size.width / 2,
                                   self.bounds.size.height / 2);
    [UIView animateWithDuration:0.15 animations:^{
        self->_hudLabel.alpha = 1;
    }];
}

- (void)hideHUD {
    [UIView animateWithDuration:0.3 animations:^{
        self->_hudLabel.alpha = 0;
    }];
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:self];
    CGPoint velocity = [gesture velocityInView:self];
    CGPoint location = [gesture locationInView:self];
    CGFloat screenWidth = self.bounds.size.width;
    CGFloat screenHeight = self.bounds.size.height;
    BOOL isHorizontal = fabs(velocity.x) > fabs(velocity.y);

    if (gesture.state == UIGestureRecognizerStateBegan) {
        _startBrightness = [UIScreen mainScreen].brightness;
        AVAudioSession *session = [AVAudioSession sharedInstance];
        _startVolume = session.outputVolume;
    }

    if (isHorizontal) {
        CGFloat seconds = translation.x / 3.0;
        NSString *dir = seconds > 0 ? @"⏩" : @"⏪";
        if (gesture.state == UIGestureRecognizerStateEnded) {
            [[NSNotificationCenter defaultCenter]
                postNotificationName:@"StremioGestureSeek"
                              object:@(seconds)];
            [self showHUD:[NSString stringWithFormat:@"%@ %.0f sec",
                          dir, fabs(seconds)]];
        } else {
            [self showHUDPersistent:[NSString stringWithFormat:@"%@ %.0f sec",
                                    dir, fabs(seconds)]];
        }
    } else {
        CGFloat delta = -(translation.y / screenHeight);
        if (location.x < screenWidth / 2) {
            CGFloat newBrightness = MAX(0.0, MIN(1.0, _startBrightness + delta));
            [UIScreen mainScreen].brightness = newBrightness;
            NSString *icon = newBrightness > 0.5 ? @"🔆" : @"🔅";
            [self showHUDPersistent:[NSString stringWithFormat:@"%@ %.0f%%",
                                    icon, newBrightness * 100]];
        } else {
            CGFloat newVolume = MAX(0.0, MIN(1.0, _startVolume + delta));
            [[NSNotificationCenter defaultCenter]
                postNotificationName:@"StremioGestureVolume"
                              object:@(newVolume)];
            NSString *icon = newVolume > 0.5 ? @"🔊" : @"🔉";
            [self showHUDPersistent:[NSString stringWithFormat:@"%@ %.0f%%",
                                    icon, newVolume * 100]];
        }
        if (gesture.state == UIGestureRecognizerStateEnded) {
            [self showHUD:_hudLabel.text];
        }
    }
}

- (void)handleSingleTap:(UITapGestureRecognizer *)gesture {
    [[NSNotificationCenter defaultCenter]
        postNotificationName:@"StremioGesturePlayPause" object:nil];
    [self showHUD:@"⏯️ Play / Pause"];
}

- (void)handleDoubleTapLeft:(UITapGestureRecognizer *)gesture {
    CGPoint location = [gesture locationInView:self];
    if (location.x < self.bounds.size.width / 2) {
        [[NSNotificationCenter defaultCenter]
            postNotificationName:@"StremioGestureSeek" object:@(-10.0)];
        [self showHUD:@"⏪ -10 sec"];
    }
}

- (void)handleDoubleTapRight:(UITapGestureRecognizer *)gesture {
    CGPoint location = [gesture locationInView:self];
    if (location.x >= self.bounds.size.width / 2) {
        [[NSNotificationCenter defaultCenter]
            postNotificationName:@"StremioGestureSeek" object:@(10.0)];
        [self showHUD:@"⏩ +10 sec"];
    }
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        _isLongPressing = YES;
        [[NSNotificationCenter defaultCenter]
            postNotificationName:@"StremioGestureSpeed" object:@(2.0)];
        [self showHUDPersistent:@"⚡️ 2x Speed"];
    } else if (gesture.state == UIGestureRecognizerStateEnded ||
               gesture.state == UIGestureRecognizerStateCancelled) {
        _isLongPressing = NO;
        [[NSNotificationCenter defaultCenter]
            postNotificationName:@"StremioGestureSpeed" object:@(1.0)];
        [self showHUD:@"▶️ 1x Speed"];
    }
}

- (void)handlePinch:(UIPinchGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateChanged) {
        self.superview.transform = CGAffineTransformScale(
            self.superview.transform, gesture.scale, gesture.scale);
        gesture.scale = 1.0;
    }
    if (gesture.state == UIGestureRecognizerStateEnded) {
        [self showHUD:@"🔍 Zoom"];
    }
}

// Override hitTest to pass taps through to controls underneath
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    // Always handle the touch ourselves
    return self;
}

@end

static IMP original_viewDidAppear;

static void swizzled_viewDidAppear(UIViewController *self,
                                    SEL _cmd, BOOL animated) {
    ((void(*)(id,SEL,BOOL))original_viewDidAppear)(self, _cmd, animated);

    UIWindow *window = self.view.window;
    if (!window) return;

    for (UIView *sub in window.subviews) {
        if ([sub isKindOfClass:[GestureOverlayView class]]) return;
    }

    GestureOverlayView *overlay = [[GestureOverlayView alloc]
                                    initWithFrame:window.bounds];
    overlay.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [window addSubview:overlay];
}

__attribute__((constructor))
static void initialize() {
    Class playerVC = NSClassFromString(
        @"_TtC7Stremio20PlayerViewController");
    if (playerVC) {
        Method m = class_getInstanceMethod(playerVC,
                                           @selector(viewDidAppear:));
        if (m) {
            original_viewDidAppear = method_getImplementation(m);
            method_setImplementation(m, (IMP)swizzled_viewDidAppear);
        }
    }
}
