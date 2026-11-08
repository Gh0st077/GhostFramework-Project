// UnityTraceLab v0.2 • compact overlay for developer-authorized IL2CPP research
// MIT © 2026 UnityTraceLab contributors
#import <UIKit/UIKit.h>
#import "TraceCore.h"

@interface UTLOverlay : UIViewController <UITextFieldDelegate>
@property(nonatomic,strong) UIWindow *host;
@property(nonatomic,strong) UIView *panel;
@property(nonatomic,strong) UITextField *filter;
@property(nonatomic,strong) UITextView *status;
@property(nonatomic,assign) BOOL expanded;
@property(nonatomic,assign) BOOL busy;
@end

@implementation UTLOverlay
- (void)loadView {
    UIView *root=[[UIView alloc] initWithFrame:CGRectMake(0,0,58,58)];
    root.backgroundColor=UIColor.clearColor;
    root.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    self.view=root;
    UIButton *orb=[UIButton buttonWithType:UIButtonTypeSystem];
    orb.frame=CGRectMake(0,0,58,58);orb.autoresizingMask=UIViewAutoresizingFlexibleRightMargin|UIViewAutoresizingFlexibleBottomMargin;
    orb.backgroundColor=[UIColor colorWithRed:.33 green:.29 blue:.75 alpha:1];
    orb.layer.cornerRadius=29;
    [orb setTitle:@"UT" forState:UIControlStateNormal];
    [orb setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    orb.titleLabel.font=[UIFont boldSystemFontOfSize:16];
    [orb addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:orb];

    UIView *panel=[[UIView alloc] initWithFrame:CGRectMake(0,0,344,582)];
    panel.backgroundColor=[UIColor colorWithRed:.07 green:.09 blue:.15 alpha:.985];
    panel.layer.cornerRadius=16;panel.clipsToBounds=YES;panel.hidden=YES;
    panel.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [root addSubview:panel];self.panel=panel;

    UILabel *title=[[UILabel alloc] initWithFrame:CGRectMake(13,8,282,29)];
    title.font=[UIFont boldSystemFontOfSize:19];title.textColor=UIColor.whiteColor;
    title.text=@"UnityTraceLab  v0.2";
    [panel addSubview:title];
    UIButton *close=[UIButton buttonWithType:UIButtonTypeSystem];
    close.frame=CGRectMake(306,5,36,34);[close setTitle:@"×" forState:UIControlStateNormal];
    [close setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    close.titleLabel.font=[UIFont systemFontOfSize:27];
    close.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin;
    [close addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:close];

    UILabel *sub=[[UILabel alloc] initWithFrame:CGRectMake(13,39,322,41)];
    sub.text=@"Choose exact methods, opt in to tracing, compare BASELINE vs TARGET intervals. No anti-cheat bypass.";
    sub.numberOfLines=3;sub.textColor=[UIColor colorWithWhite:.76 alpha:1];
    sub.font=[UIFont systemFontOfSize:10.5];
    sub.autoresizingMask=UIViewAutoresizingFlexibleWidth;
    [panel addSubview:sub];

    UITextField *input=[[UITextField alloc] initWithFrame:CGRectMake(12,83,320,37)];
    input.placeholder=@"Class::Method or keyword (narrow filter)";
    input.textColor=UIColor.blackColor;input.backgroundColor=UIColor.whiteColor;
    input.layer.cornerRadius=8;input.font=[UIFont systemFontOfSize:13];
    input.autocapitalizationType=UITextAutocapitalizationTypeNone;
    input.autocorrectionType=UITextAutocorrectionTypeNo;
    input.returnKeyType=UIReturnKeyDone;input.delegate=self;
    input.autoresizingMask=UIViewAutoresizingFlexibleWidth;
    [panel addSubview:input];self.filter=input;

    UIScrollView *scroll=[[UIScrollView alloc] initWithFrame:CGRectMake(9,129,326,322)];
    scroll.backgroundColor=UIColor.clearColor;
    scroll.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [panel addSubview:scroll];
    NSArray<NSArray *> *items=@[
        @[@"1. Index methods + RVA",NSStringFromSelector(@selector(indexAction))],
        @[@"2. Arm exact matching trace (1–8)",NSStringFromSelector(@selector(armAction))],
        @[@"3. Start BASELINE",NSStringFromSelector(@selector(baselineAction))],
        @[@"4. Start TARGET event",NSStringFromSelector(@selector(targetAction))],
        @[@"5. End interval",NSStringFromSelector(@selector(endAction))],
        @[@"6. Compare + rank functions",NSStringFromSelector(@selector(compareAction))],
        @[@"7. Export machine-code samples",NSStringFromSelector(@selector(codeAction))],
        @[@"8. Export logs / Share",NSStringFromSelector(@selector(shareAction))],
        @[@"9. DISARM + restore hooks",NSStringFromSelector(@selector(disarmAction))]
    ];
    CGFloat y=0;
    for(NSArray *item in items) {
        UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];
        button.frame=CGRectMake(1,y,322,39);
        [button setTitle:item[0] forState:UIControlStateNormal];
        button.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeft;
        button.contentEdgeInsets=UIEdgeInsetsMake(0,12,0,0);
        button.layer.cornerRadius=8;
        button.backgroundColor=[UIColor colorWithRed:.18 green:.22 blue:.34 alpha:1];
        [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        button.titleLabel.font=[UIFont boldSystemFontOfSize:12];
        [button addTarget:self action:NSSelectorFromString(item[1]) forControlEvents:UIControlEventTouchUpInside];
        [scroll addSubview:button]; y+=44;
    }
    scroll.contentSize=CGSizeMake(323,y+5);
    UILabel *label=[[UILabel alloc] initWithFrame:CGRectMake(12,458,310,18)];
    label.text=@"DIAGNOSTICS / LAST RESULT";label.font=[UIFont boldSystemFontOfSize:11];
    label.textColor=[UIColor colorWithRed:.54 green:.9 blue:.77 alpha:1];
    [panel addSubview:label];
    UITextView *status=[[UITextView alloc] initWithFrame:CGRectMake(11,478,322,91)];
    status.editable=NO;status.selectable=YES;
    status.backgroundColor=[UIColor colorWithRed:.035 green:.045 blue:.09 alpha:1];
    status.textColor=[UIColor colorWithWhite:.88 alpha:1];
    status.font=[UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    status.layer.cornerRadius=8;
    status.text=@"Ready. Tracing is OFF by default. First index, then enter a narrow filter.";
    status.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [panel addSubview:status];self.status=status;
}
- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];return YES;
}
- (void)toggle {
    self.expanded=!self.expanded;
    self.panel.hidden=!self.expanded;
    UIWindowScene *scene=self.host.windowScene;
    CGRect rect=scene?scene.coordinateSpace.bounds:UIScreen.mainScreen.bounds;
    CGFloat width=self.expanded?MIN(344,rect.size.width-16):58;
    CGFloat height=self.expanded?MIN(582,rect.size.height-65):58;
    CGRect prior=self.host.frame;
    CGFloat x=MIN(MAX(prior.origin.x,8),MAX(8,rect.size.width-width-8));
    CGFloat y=MIN(MAX(prior.origin.y,18),MAX(18,rect.size.height-height-18));
    self.host.frame=CGRectMake(x,y,width,height);
    self.view.frame=self.host.bounds;
    self.panel.frame=CGRectMake(0,0,width,height);
    UIScrollView *scroll=nil;
    for(UIView *view in self.panel.subviews)if([view isKindOfClass:UIScrollView.class]){scroll=(UIScrollView *)view;break;}
    if(scroll) scroll.frame=CGRectMake(9,129,width-18,MAX(160,height-260));
    self.status.frame=CGRectMake(11,MAX(280,height-104),width-22,91);
}
- (void)show:(NSString *)text {
    dispatch_async(dispatch_get_main_queue(),^{self.status.text=text ?: @"";});
}
- (void)run:(NSString *)name job:(NSDictionary *(^)(void))job {
    if(self.busy) { [self show:@"Operation already running."];return; }
    self.busy=YES;[self.filter resignFirstResponder];
    [self show:[NSString stringWithFormat:@"%@…",name]];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        NSDictionary *res=nil;
        @try {res=job();}
        @catch (NSException *e) {res=@{@"ok":@NO,@"error":e.reason ?: @"Unexpected exception"};}
        NSData *json=[NSJSONSerialization dataWithJSONObject:res ?: @{} options:NSJSONWritingPrettyPrinted error:nil];
        NSString *str=json?[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]:[res description];
        dispatch_async(dispatch_get_main_queue(),^{
            self.busy=NO;
            self.status.text=[NSString stringWithFormat:@"%@\n%@",name,str ?: @"(no result)"];
        });
    });
}
- (void)indexAction {
    NSString *query=self.filter.text ?: @"";
    [self run:@"Index methods" job:^NSDictionary *{return [[UTLRuntime shared] indexMethods:query];}];
}
- (void)armAction {
    NSString *query=self.filter.text ?: @"";
    [self run:@"Arm trace" job:^NSDictionary *{return [[UTLRuntime shared] armTrace:query];}];
}
- (void)baselineAction {
    [self run:@"Start baseline" job:^NSDictionary *{return [[UTLRuntime shared] beginPhase:@"baseline"];}];
}
- (void)targetAction {
    [self run:@"Start target" job:^NSDictionary *{return [[UTLRuntime shared] beginPhase:@"target"];}];
}
- (void)endAction {
    [self run:@"End interval" job:^NSDictionary *{return [[UTLRuntime shared] endPhase];}];
}
- (void)compareAction {
    [self run:@"Compare intervals" job:^NSDictionary *{
        NSDictionary *full=[[UTLRuntime shared] comparePhases];
        if(![full[@"ok"] boolValue])return full;
        NSArray *rows=full[@"ranked"];
        return @{@"ok":@YES,@"candidate_count":@(rows.count),@"top":rows.count?[rows subarrayWithRange:NSMakeRange(0,MIN(rows.count,3))]:@[]};
    }];
}
- (void)codeAction {
    [self run:@"Code samples" job:^NSDictionary *{return [[UTLRuntime shared] exportCodeSamples];}];
}
- (void)disarmAction {
    [self run:@"Disarm" job:^NSDictionary *{return [[UTLRuntime shared] disarmTrace];}];
}
- (void)shareAction {
    if(self.busy)return;
    [self show:@"Preparing bounded trace samples for export…"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        NSArray<NSURL *> *paths=[[UTLRuntime shared] exportURLs];
        dispatch_async(dispatch_get_main_queue(),^{
            if(!paths.count){[self show:@"No data. Index or trace methods first."];return;}
            UIActivityViewController *share=[[UIActivityViewController alloc] initWithActivityItems:paths applicationActivities:nil];
            share.popoverPresentationController.sourceView=self.panel;
            share.popoverPresentationController.sourceRect=CGRectMake(9,390,300,42);
            [self presentViewController:share animated:YES completion:nil];
            [self show:[NSString stringWithFormat:@"Prepared %lu log / code files.",(unsigned long)paths.count]];
        });
    });
}
@end

static void UTLInstall(void) {
    static UIWindow *overlayWindow=nil;
    if(overlayWindow)return;
    UIApplication *app=UIApplication.sharedApplication;
    UIWindowScene *scene=nil;
    for(UIScene *candidate in app.connectedScenes) {
        if([candidate isKindOfClass:UIWindowScene.class] && candidate.activationState==UISceneActivationStateForegroundActive) {
            scene=(UIWindowScene *)candidate; break;
        }
    }
    if(!scene)return;
    UIWindow *window=[[UIWindow alloc] initWithWindowScene:scene];
    window.frame=CGRectMake(16,110,58,58);
    window.backgroundColor=UIColor.clearColor;
    window.windowLevel=UIWindowLevelAlert+3;
    UTLOverlay *controller=[UTLOverlay new];
    controller.host=window;window.rootViewController=controller;
    window.hidden=NO;
    overlayWindow=window;
}
__attribute__((constructor)) static void UTLBootstrap(void) {
    @autoreleasepool {
        dispatch_async(dispatch_get_main_queue(),^{
            [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *n){UTLInstall();}];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),
                dispatch_get_main_queue(),^{UTLInstall();});
        });
    }
}
