//
//  HBViewController.m
//  Heisenberg
//
//  Created by Dan Spinosa on 1/11/14.
//  Copyright (c) 2014 Dan Spinosa. All rights reserved.
//

#import "HBWelcomeViewController.h"

@interface HBWelcomeViewController ()
@property (weak, nonatomic) IBOutlet UIImageView *hat;
@property (weak, nonatomic) IBOutlet UIImageView *glasses;
@property (weak, nonatomic) IBOutlet UIImageView *goatee;

@property (strong, nonatomic) UIDynamicAnimator *animator;
@end

@implementation HBWelcomeViewController {
    CGPoint _hatOriginalCenter;
    UISnapBehavior *_hatSnap;
    UIAttachmentBehavior *_hatAttachment;
    
    NSUInteger panAttempts;
    
    NSTimer *_shakeTheHatTimer;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    panAttempts = 0;
    
    self.animator = [[UIDynamicAnimator alloc] initWithReferenceView:self.view];
    self.animator.delegate = self;
    _hatOriginalCenter = self.hat.center;
    _hatSnap = [[UISnapBehavior alloc] initWithItem:self.hat snapToPoint:self.hat.center];
}

- (void)viewWillAppear:(BOOL)animated
{
    [self.navigationController setNavigationBarHidden:YES animated:animated];
}

- (void)viewDidAppear:(BOOL)animated
{
    self.hat.center = CGPointMake(self.view.bounds.size.width, 0);
    [self.animator addBehavior:_hatSnap];
    
    _shakeTheHatTimer = [NSTimer scheduledTimerWithTimeInterval:4.0 target:self selector:@selector(shakeTheHat) userInfo:nil repeats:YES];
}

- (BOOL)prefersStatusBarHidden
{
    return YES;
}

- (BOOL)shouldAutorotate
{
    return NO;
}

- (IBAction)hatDidPan:(UIPanGestureRecognizer *)panner {
    CGPoint translation = [panner translationInView:self.view];
    CGPoint velocity = [panner velocityInView:self.view];
    
    if (panner.state == UIGestureRecognizerStateBegan) {
        [_shakeTheHatTimer invalidate];
        panAttempts++;
        [self.animator removeBehavior:_hatSnap];
        
        //get the offset within the hat view of the touch to adjust the attachment's anchor point
        CGPoint touchOffset = [panner locationInView:self.hat];
        UIOffset attachmentOffset = UIOffsetMake(touchOffset.x - self.hat.bounds.size.width/2.0,
                                                 touchOffset.y - self.hat.bounds.size.height/2.0);
        _hatAttachment = [[UIAttachmentBehavior alloc] initWithItem:self.hat
                                                   offsetFromCenter:attachmentOffset
                                                   attachedToAnchor:_hatOriginalCenter];
        [self.animator addBehavior:_hatAttachment];
        
    } else if (panner.state == UIGestureRecognizerStateChanged) {
        [self.animator removeBehavior:_hatSnap];
        
        _hatAttachment.anchorPoint = CGPointMake(_hatOriginalCenter.x + translation.x, _hatOriginalCenter.y + translation.y);
        
    } else if (panner.state == UIGestureRecognizerStateEnded) {
        [self.animator removeBehavior:_hatAttachment];
        
        if (panAttempts > 3 || abs(translation.x) + abs(translation.y) > 300) {
            //DONE AND DONE
            panner.enabled = NO;
            //drop goatee and glasses
            [self.animator addBehavior:[[UIGravityBehavior alloc] initWithItems:@[self.glasses, self.goatee]]];
            //continue hat on it's trajectory
            UIPushBehavior *hatPush = [[UIPushBehavior alloc] initWithItems:@[self.hat] mode:UIPushBehaviorModeInstantaneous];
            hatPush.pushDirection = CGVectorMake(velocity.x/fabsf(velocity.x+velocity.y),
                                                 velocity.y/fabsf(velocity.x+velocity.y));
            hatPush.magnitude = MAX((velocity.x + velocity.y)/1000.f, 50);
            [self.animator addBehavior:hatPush];
            //fade to black while dynamics operate
            [UIView animateWithDuration:1.0 animations:^{
                self.view.backgroundColor = [UIColor blackColor];
            } completion:^(BOOL finished) {
                [self performSegueWithIdentifier:@"proceedSegue" sender:self];
                [self.animator removeAllBehaviors];
            }];
            
        } else {
            [self.animator addBehavior:_hatSnap];
            [self.animator updateItemUsingCurrentState:panner.view];
        }
    }
}

- (void)shakeTheHat
{
    //snap is still engaged, just need to push it a bit
    UIPushBehavior *hatPush = [[UIPushBehavior alloc] initWithItems:@[self.hat] mode:UIPushBehaviorModeInstantaneous];
    hatPush.pushDirection = CGVectorMake(arc4random_uniform(3.0)-1.0, arc4random_uniform(3.0)-1.0);
    hatPush.magnitude = 75.0;
    [self.animator addBehavior:hatPush];
}

@end
