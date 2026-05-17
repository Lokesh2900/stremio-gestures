#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <AVFoundation/AVFoundation.h>

@interface GestureOverlayView : UIView
@property (nonatomic, strong) UILabel *hudLabel;
@property (nonatomic, strong) NSTimer *hudTimer;
@end

@implementation GestureOverlayView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;

        _hudLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 180, 55)];
        _hudLabel.textColor = [UIColor whiteColor];
        _hudLabel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.65];
        _hudLabel.textAlignment = NSTextAlignmentCenter;
        _hudLabel.font = [UIFont boldSystemFontOfSize:17];
        _hudLabel.layer.cornerRadius = 12;
        _hudLabel.clipsToBounds = YES;
        _hudLabel.alpha = 0;
        _hudLabel.numberOfLines = 2;
        _hudLabel.userInteractionEnabled = NO;
        [self addSubview:_hudLabel];
    }
    return self;
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

@end

@interface StremioGestureHandler : NSObject
@property (nonatomic, assign) CGFloat startBrightness;
@property (nonatomic, assign) CGFloat startVolume;
@property (nonatomic, assign) BOOL isLongPressing;
@property (nonatomic, strong) GestureOverlayView *overlay;
@end

@implementation StremioGestureHandler

// Find and set AVPlayer rate by walking up responder chain
- (void)setPlayerRate:(float)rate fromView:(UIView *)view {
    @try {
        UIResponder *responder = view;
        while (responder) {
            if ([responder isKindOfClass:[UIViewController class]]) {
                UIViewController *vc = (UIViewController *)responder;

                // Try playerManager ivar
                Ivar managerIvar = class_getInstanceVariable(
                    [vc class], "playerManager");
                if (managerIvar) {
                    id manager = (__bridge id)object_getIvar(vc, managerIvar);
                    if (manager) {
                        // Try player ivar inside manager
                        Ivar playerIvar = class_getInstanceVariable(
                            [manager class], "player");
                        if (playerIvar) {
                            id player = (__bridge id)object_getIvar(
                                manager, playerIvar);
                            if (player &&
                                [player respondsToSelector:@selector(setRate:)]) {
                                [player setValue:@(rate) forKey:@"rate"];
                                return;
                            }
                        }
                    }
                }
                break;
            }
            responder = responder.nextResponder;
        }
    } @catch (NSException *e) {}
}

// Find and set system volume using private API safely
- (void)setSystemVolume:(float)volume {
    @try {
        // Use MPVolumeView's slider - safest way on non-jailbroken
        Class mpVolumeView = NSClassFromString(@"MPVolumeView");
        if (mpVolumeView) {
            id volumeView = [[mpVolumeView alloc] init];
            for (UIView *view in [volumeView subviews]) {
                if ([view isKindOfClass:[UISlider class]]) {
                    UISlider *slider = (UISlider *)view;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        slider.value = volume;
                    });
                    return;
                }
            }
        }
    } @catch (NSException *e) {}
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    @try {
        CGPoint translation = [gesture translationInView:gesture.view];
        CGPoint velocity = [gesture velocityInView:gesture.view];
        CGPoint location = [gesture locationInView:gesture.view];
        CGFloat screenWidth = gesture.view.bounds.size.width;
        CGFloat screenHeight = gesture.view.bounds.size.height;
        BOOL isHorizontal = fabs(velocity.x) > fabs(velocity.y);

        if (gesture.state == UIGestureRecognizerStateBegan) {
            _startBrightness = [UIScreen mainScreen].brightness;
            @try {
                AVAudioSession *session = [AVAudioSession sharedInstance];
                [session setActive:YES error:nil];
                _startVolume = session.outputVolume;
            } @catch (NSException *e) {
                _startVolume = 0.5;
            }
        }

        if (isHorizontal) {
            CGFloat seconds = translation.x / 3.0;
            NSString *dir = seconds > 0 ? @"⏩" : @"⏪";
            if (gesture.state == UIGestureRecognizerStateEnded) {
                [[NSNotificationCenter defaultCenter]
                    postNotificationName:@"StremioGestureSeek"
                                  object:@(seconds)];
                [self.overlay showHUD:[NSString stringWithFormat:@"%@ %.0f sec",
                                      dir, fabs(seconds)]];
            } else {
                [self.overlay showHUDPersistent:
                    [NSString stringWithFormat:@"%@ %.0f sec",
                     dir, fabs(seconds)]];
            }
        } else {
            CGFloat delta = -(translation.y / screenHeight);
            if (location.x < screenWidth / 2) {
                // LEFT - Brightness
                CGFloat newBrightness = MAX(0.0, MIN(1.0,
                    _startBrightness + delta));
                [UIScreen mainScreen].brightness = newBrightness;
                NSString *icon = newBrightness > 0.5 ? @"🔆" : @"🔅";
                [self.overlay showHUDPersistent:
                    [NSString stringWithFormat:@"%@ %.0f%%",
                     icon, newBrightness * 100]];
            } else {
                // RIGHT - Volume
                CGFloat newVolume = MAX(0.0, MIN(1.0,
                    _startVolume + delta));
                [self setSystemVolume:newVolume];
                NSString *icon = newVolume > 0.5 ? @"🔊" : @"🔉";
                [self.overlay showHUDPersistent:
                    [NSString stringWithFormat:@"%@ %.0f%%",
                     icon, newVolume * 100]];
            }
            if (gesture.state == UIGestureRecognizerStateEnded) {
                [self.overlay showHUD:self.overlay.hudLabel.text];
            }
        }
    } @catch (NSException *e) {}
}

- (void)handleDoubleTapLeft:(UITapGestureRecognizer *)gesture {
    @try {
        CGPoint location = [gesture locationInView:gesture.view];
        if (location.x < gesture.view.bounds.size.width / 2) {
            [[NSNotificationCenter defaultCenter]
                postNotificationName:@"StremioGestureSeek"
                              object:@(-10.0)];
            [self.overlay showHUD:@"⏪ -10 sec"];
        }
    } @catch (NSException *e) {}
}

- (void)handleDoubleTapRight:(UITapGestureRecognizer *)gesture {
    @try {
        CGPoint location = [gesture locationInView:gesture.view];
        if (location.x >= gesture.view.bounds.size.width / 2) {
            [[NSNotificationCenter defaultCenter]
                postNotificationName:@"StremioGestureSeek"
                              object:@(10.0)];
            [self.overlay showHUD:@"⏩ +10 sec"];
        }
    } @catch (NSException *e) {}
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    @try {
        if (gesture.state == UIGestureRecognizerStateBegan) {
            _isLongPressing = YES;
            [self setPlayerRate:2.0 fromView:gesture.view];
            [self.overlay showHUDPersistent:@"⚡️ 2x Speed"];
        } else if (gesture.state == UIGestureRecognizerStateEnded ||
                   gesture.state == UIGestureRecognizerStateCancelled) {
            _isLongPressing = NO;
            [self setPlayerRate:1.0 fromView:gesture.view];
            [self.overlay showHUD:@"▶️ 1x Speed"];
        }
    } @catch (NSException *e) {}
}

- (void)handlePinch:(UIPinchGestureRecognizer *)gesture {
    @try {
        if (gesture.state == UIGestureRecognizerStateChanged) {
            gesture.view.transform = CGAffineTransformScale(
                gesture.view.transform, gesture.scale, gesture.scale);
            gesture.scale = 1.0;
        }
        if (gesture.state == UIGestureRecognizerStateEnded) {
            [self.overlay showHUD:@"🔍 Zoom"];
        }
    } @catch (NSException *e) {}
}

@end

static char kHandlerKey;
static IMP original_viewDidAppear;

static void swizzled_viewDidAppear(UIViewController *self,
                                    SEL _cmd, BOOL animated) {
    ((void(*)(id,SEL,BOOL))original_viewDidAppear)(self, _cmd, animated);

    if (objc_getAssociatedObject(self, &kHandlerKey)) return;

    UIView *playerView = self.view;

    GestureOverlayView *overlay = [[GestureOverlayView alloc]
                                    initWithFrame:playerView.bounds];
    overlay.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [playerView addSubview:overlay];

    StremioGestureHandler *handler = [[StremioGestureHandler alloc] init];
    handler.overlay = overlay;

    objc_setAssociatedObject(self, &kHandlerKey, handler,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:handler action:@selector(handlePan:)];
    pan.cancelsTouchesInView = NO;
    pan.minimumNumberOfTouches = 1;
    pan.maximumNumberOfTouches = 1;
    [playerView addGestureRecognizer:pan];

    UITapGestureRecognizer *doubleTapLeft = [[UITapGestureRecognizer alloc]
        initWithTarget:handler action:@selector(handleDoubleTapLeft:)];
    doubleTapLeft.numberOfTapsRequired = 2;
    doubleTapLeft.cancelsTouchesInView = NO;
    [playerView addGestureRecognizer:doubleTapLeft];

    UITapGestureRecognizer *doubleTapRight = [[UITapGestureRecognizer alloc]
        initWithTarget:handler action:@selector(handleDoubleTapRight:)];
    doubleTapRight.numberOfTapsRequired = 2;
    doubleTapRight.cancelsTouchesInView = NO;
    [playerView addGestureRecognizer:doubleTapRight];

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc]
        initWithTarget:handler action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = 0.6;
    longPress.cancelsTouchesInView = NO;
    [playerView addGestureRecognizer:longPress];

    UIPinchGestureRecognizer *pinch = [[UIPinchGestureRecognizer alloc]
        initWithTarget:handler action:@selector(handlePinch:)];
    pinch.cancelsTouchesInView = NO;
    [playerView addGestureRecognizer:pinch];
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
